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
