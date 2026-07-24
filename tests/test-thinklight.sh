#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/thinklight-test.XXXXXX")
BIN_DIR="$TEST_ROOT/bin"
STATE_DIR="$TEST_ROOT/state"
DAEMON="$BIN_DIR/thinklight-daemon"
CLI="$ROOT/src/thinklight"

cleanup() {
  env THINKLIGHT_BIN_DIR="$BIN_DIR" THINKLIGHT_STATE_DIR="$STATE_DIR" \
    "$CLI" off --force </dev/null >/dev/null 2>&1 || true
  pkill -fx "$DAEMON" 2>/dev/null || true
  find "$TEST_ROOT" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 130' HUP INT TERM

fail() {
  echo "not ok - $*" >&2
  exit 1
}

pass() {
  echo "ok - $*"
}

assert_eq() {
  [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'"
}

run_cli() {
  env THINKLIGHT_BIN_DIR="$BIN_DIR" THINKLIGHT_STATE_DIR="$STATE_DIR" \
    "$CLI" "$@"
}

run_hook() {
  local event=$1 session=$2
  shift 2
  printf '{"hook_event_name":"%s","session_id":"%s"}\n' "$event" "$session" \
    | env THINKLIGHT_BIN_DIR="$BIN_DIR" THINKLIGHT_STATE_DIR="$STATE_DIR" \
        "$CLI" "$@"
}

run_codex_hook() {
  local event=$1 session=$2 turn=$3 transcript=$4
  shift 4
  printf '{"hook_event_name":"%s","session_id":"%s","turn_id":"%s","transcript_path":"%s"}\n' \
    "$event" "$session" "$turn" "$transcript" \
    | env THINKLIGHT_BIN_DIR="$BIN_DIR" THINKLIGHT_STATE_DIR="$STATE_DIR" \
        "$CLI" "$@"
}

mkdir -p "$BIN_DIR"
swiftc "$ROOT/tests/fake-daemon.swift" -o "$DAEMON"

assert_eq "$(run_cli status)" "off"
[[ ! -e "$STATE_DIR" ]] || fail "status created state"
pass "status is side-effect free"

mkdir -p "$STATE_DIR"
date +%s > "$STATE_DIR/update-check"

run_hook UserPromptSubmit alpha on
first_pid=$(pgrep -fx "$DAEMON")
assert_eq "$(run_cli status)" "on"
pass "on starts the daemon and records a session"

run_hook UserPromptSubmit beta on
assert_eq "$(pgrep -fx "$DAEMON")" "$first_pid"
run_hook Stop alpha off
assert_eq "$(run_cli status)" "on"
run_hook Stop beta off
assert_eq "$(run_cli status)" "off"
kill -0 "$first_pid" 2>/dev/null || fail "idle daemon exited"
pass "multiple sessions aggregate and the idle daemon stays resident"

run_hook UserPromptSubmit gamma on
assert_eq "$(pgrep -fx "$DAEMON")" "$first_pid"
run_cli _sync </dev/null
second_pid=$(pgrep -fx "$DAEMON")
[[ "$second_pid" != "$first_pid" ]] || fail "_sync did not replace the daemon"
kill -0 "$first_pid" 2>/dev/null && fail "old daemon survived _sync"
assert_eq "$(run_cli status)" "on"
run_hook Stop gamma off
pass "_sync waits for replacement and preserves active sessions"

run_hook UserPromptSubmit upgrading on
[[ -f "$STATE_DIR/sessions/upgrading" ]] || fail "legacy session token was not written"
run_codex_hook Stop upgrading upgrade-turn /dev/null off
[[ ! -e "$STATE_DIR/sessions/upgrading" ]] || fail "new Stop left a pre-upgrade token behind"
assert_eq "$(run_cli status)" "off"
pass "turn-scoped Stop clears tokens written before an upgrade"

FAILED_STATE="$TEST_ROOT/failed-state"
if printf '{"session_id":"failed"}\n' \
  | env THINKLIGHT_STATE_DIR="$FAILED_STATE" THINKLIGHT_BIN_DIR="$TEST_ROOT/missing-bin" \
      "$CLI" on >/dev/null 2>&1; then
  fail "on succeeded without a daemon"
fi
[[ ! -e "$FAILED_STATE/sessions/failed" ]] || fail "failed on left a session token"
pass "on reports daemon failure and rolls back its token"

BAD_STATE="$TEST_ROOT/not-a-directory"
: > "$BAD_STATE"
if printf '{"session_id":"bad-state"}\n' \
  | env THINKLIGHT_STATE_DIR="$BAD_STATE" THINKLIGHT_BIN_DIR="$BIN_DIR" \
      "$CLI" on >/dev/null 2>&1; then
  fail "on succeeded with an unusable state path"
fi
pass "on reports state-write failures"

run_cli off --force </dev/null
assert_eq "$(run_cli status)" "off"
kill -0 "$second_pid" 2>/dev/null && fail "force off left the daemon running"
pass "force off clears state and stops the resident daemon"

# Exercise the production daemon's Codex-interrupt fallback without requesting
# camera permission or opening a camera.
swiftc "$ROOT/src/thinklight-daemon.swift" -o "$DAEMON"
env THINKLIGHT_STATE_DIR="$STATE_DIR" THINKLIGHT_TEST_NO_CAMERA=1 \
  "$DAEMON" >/dev/null 2>&1 &
production_pid=$!
for _ in {1..40}; do
  kill -0 "$production_pid" 2>/dev/null && break
  sleep 0.05
done
kill -0 "$production_pid" 2>/dev/null || fail "production daemon did not start in test mode"

TRANSCRIPT="$TEST_ROOT/codex transcript.jsonl"
TURN_A=turn-a
printf '%s\n' \
  "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"$TURN_A\"}}" \
  > "$TRANSCRIPT"
run_codex_hook UserPromptSubmit interrupted "$TURN_A" "$TRANSCRIPT" on
TOKEN_A="$STATE_DIR/sessions/interrupted.$TURN_A"
[[ -f "$TOKEN_A" ]] || fail "turn-scoped token was not written"
assert_eq "$(sed -n '2p' "$TOKEN_A")" "$TRANSCRIPT"
assert_eq "$(sed -n '3p' "$TOKEN_A")" "$TURN_A"
token_owner=$(sed -n '1p' "$TOKEN_A")
kill -0 "$token_owner" 2>/dev/null || fail "interrupt test owner was not alive"
printf '%s\n' \
  "{\"type\":\"event_msg\",\"payload\":{\"type\":\"turn_aborted\",\"turn_id\":\"$TURN_A\",\"reason\":\"interrupted\"}}" \
  >> "$TRANSCRIPT"
for _ in {1..80}; do
  [[ ! -e "$TOKEN_A" ]] && break
  sleep 0.05
done
[[ ! -e "$TOKEN_A" ]] || fail "interrupted turn token was not reaped"
assert_eq "$(run_cli status)" "off"
kill -0 "$token_owner" 2>/dev/null || fail "test only passed because the owner exited"
pass "Codex Ctrl+C terminal events clear live-process tokens"

TURN_B=turn-b
printf '%s\n' \
  "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"$TURN_B\"}}" \
  >> "$TRANSCRIPT"
run_codex_hook UserPromptSubmit interrupted "$TURN_B" "$TRANSCRIPT" on
TOKEN_B="$STATE_DIR/sessions/interrupted.$TURN_B"
[[ -f "$TOKEN_B" ]] || fail "second turn-scoped token was not written"
printf '%s\n' \
  "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"$TURN_B\"}}" \
  >> "$TRANSCRIPT"
for _ in {1..80}; do
  [[ ! -e "$TOKEN_B" ]] && break
  sleep 0.05
done
[[ ! -e "$TOKEN_B" ]] || fail "completed turn token was not reaped"
assert_eq "$(run_cli status)" "off"
pass "terminal events also recover from a missed normal Stop hook"

TURN_C=turn-c
printf '%s\n' \
  "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"$TURN_C\"}}" \
  >> "$TRANSCRIPT"
run_codex_hook UserPromptSubmit interrupted "$TURN_C" "$TRANSCRIPT" on
TOKEN_C="$STATE_DIR/sessions/interrupted.$TURN_C"
[[ -f "$TOKEN_C" ]] || fail "third turn-scoped token was not written"
run_hook SessionEnd interrupted off
[[ ! -e "$TOKEN_C" ]] || fail "SessionEnd did not clear turn-scoped tokens"
assert_eq "$(run_cli status)" "off"
pass "SessionEnd clears every token for its session"

run_cli off --force </dev/null
kill -0 "$production_pid" 2>/dev/null && fail "test daemon survived final cleanup"
