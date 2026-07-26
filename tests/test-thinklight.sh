#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/thinklight-test.XXXXXX")
BIN_DIR="$TEST_ROOT/bin"
STATE_DIR="$TEST_ROOT/state"
SHARE_DIR="$TEST_ROOT/share"
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
    THINKLIGHT_SHARE_DIR="$SHARE_DIR" "$CLI" "$@"
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

assert_eq "$(run_cli config | sed -n '1p')" "sound: off"
[[ ! -e "$SHARE_DIR" ]] || fail "config created the sound directory"
pass "sound is off until asked for, and config reads without writing"

mkdir -p "$SHARE_DIR/defaults"
printf 'default-loop' > "$SHARE_DIR/defaults/loop.flac"
printf 'default-done' > "$SHARE_DIR/defaults/done.flac"
assert_eq "$(run_cli unmute | sed -n '1p')" "sound: on"
[[ -f "$SHARE_DIR/sound-on" ]] || fail "unmute did not record the switch"
assert_eq "$(cat "$SHARE_DIR/loop.flac")" "default-loop"
assert_eq "$(run_cli config | sed -n '3p')" "loop track: loop.flac"
pass "unmute copies the bundled defaults into place and turns sound on"

printf 'chosen' > "$SHARE_DIR/loop.flac"
run_cli mute > /dev/null
assert_eq "$(run_cli config | sed -n '1p')" "sound: off"
[[ -f "$SHARE_DIR/loop.flac" ]] || fail "mute deleted a track"
run_cli unmute > /dev/null
assert_eq "$(cat "$SHARE_DIR/loop.flac")" "chosen"
pass "mute keeps the tracks, and unmute never overwrites a chosen one"

# Tracks are found by stem, so any format macOS can decode works.
rm -f "$SHARE_DIR/done.flac"
printf 'chosen-mp3' > "$SHARE_DIR/done.mp3"
assert_eq "$(run_cli config | sed -n '4p')" "done track: done.mp3"
run_cli unmute > /dev/null
[[ ! -e "$SHARE_DIR/done.flac" ]] || fail "unmute re-added a default over a differently named track"
pass "a track of any extension fills its slot"

# The bug this pins down: an update must not be able to start making noise on a
# quiet machine or replace a track someone chose. install.sh writes defaults/
# and nothing else under share/, so run it against a throwaway HOME and check.
INSTALL_HOME="$TEST_ROOT/home"
INSTALL_SHARE="$INSTALL_HOME/.local/share/thinklight"
mkdir -p "$INSTALL_SHARE"
printf 'chosen' > "$INSTALL_SHARE/loop.flac"
env HOME="$INSTALL_HOME" "$ROOT/install.sh" > /dev/null 2>&1 \
  || fail "install.sh failed against a throwaway HOME"
[[ ! -e "$INSTALL_SHARE/sound-on" ]] || fail "install.sh turned sound on"
assert_eq "$(cat "$INSTALL_SHARE/loop.flac")" "chosen"
[[ -f "$INSTALL_SHARE/defaults/loop.flac" ]] || fail "install.sh did not stage the default tracks"
[[ ! -e "$INSTALL_SHARE/defaults/CREDITS.md" ]] || fail "install.sh copied a non-track asset"
pass "install.sh stages defaults without touching sound state or a chosen track"

# Exercise the production daemon's Codex-interrupt fallback without requesting
# camera permission, opening a camera, or playing anything out loud — the share
# dir has no switch in it, so the daemon stays muted for the whole run.
swiftc "$ROOT/src/thinklight-daemon.swift" -o "$DAEMON"
DAEMON_LOG="$TEST_ROOT/daemon.log"
env THINKLIGHT_STATE_DIR="$STATE_DIR" THINKLIGHT_TEST_NO_CAMERA=1 \
  THINKLIGHT_SHARE_DIR="$TEST_ROOT/muted" \
  "$DAEMON" > /dev/null 2>"$DAEMON_LOG" &
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
assert_eq "$(sed -n '4p' "$TOKEN_A")" "interrupted"
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

# Session ids may contain dots, so "alpha.beta" is a valid session whose name
# also matches the "alpha.*" glob SessionEnd expands.
run_codex_hook UserPromptSubmit alpha turn-x /dev/null on
run_hook UserPromptSubmit alpha.beta on
run_hook SessionEnd alpha off
[[ ! -e "$STATE_DIR/sessions/alpha.turn-x" ]] || fail "SessionEnd left its own turn-scoped token"
[[ -f "$STATE_DIR/sessions/alpha.beta" ]] || fail "SessionEnd for alpha removed session alpha.beta's token"
run_hook SessionEnd alpha.beta off
assert_eq "$(run_cli status)" "off"
pass "SessionEnd only removes tokens recorded for its session key"

# A transcript larger than the 128KB lookback makes the daemon start mid-file
# and discard the partial first line before scanning.
BIG_TRANSCRIPT="$TEST_ROOT/big transcript.jsonl"
TURN_D=turn-d
for _ in {1..2000}; do
  printf '%s\n' \
    "{\"type\":\"event_msg\",\"payload\":{\"type\":\"agent_message\",\"turn_id\":\"$TURN_D\",\"message\":\"padding\"}}"
done > "$BIG_TRANSCRIPT"
printf '%s\n' \
  "{\"type\":\"event_msg\",\"payload\":{\"type\":\"turn_aborted\",\"turn_id\":\"$TURN_D\"}}" \
  >> "$BIG_TRANSCRIPT"
run_codex_hook UserPromptSubmit lookback "$TURN_D" "$BIG_TRANSCRIPT" on
TOKEN_D="$STATE_DIR/sessions/lookback.$TURN_D"
for _ in {1..80}; do
  [[ ! -e "$TOKEN_D" ]] && break
  sleep 0.05
done
[[ ! -e "$TOKEN_D" ]] || fail "lookback did not find a terminal event that predates the token"
assert_eq "$(run_cli status)" "off"
pass "lookback reaps a turn whose terminal event predates its token"

# Two live tokens (a stale turn and the current one) can share one transcript;
# a terminal event must reap only the turn it names.
TURN_E=turn-e
TURN_F=turn-f
printf '%s\n%s\n' \
  "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"$TURN_E\"}}" \
  "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"$TURN_F\"}}" \
  >> "$TRANSCRIPT"
run_codex_hook UserPromptSubmit shared "$TURN_E" "$TRANSCRIPT" on
run_codex_hook UserPromptSubmit shared "$TURN_F" "$TRANSCRIPT" on
TOKEN_E="$STATE_DIR/sessions/shared.$TURN_E"
TOKEN_F="$STATE_DIR/sessions/shared.$TURN_F"
printf '%s\n' \
  "{\"type\":\"event_msg\",\"payload\":{\"type\":\"turn_aborted\",\"turn_id\":\"$TURN_E\"}}" \
  >> "$TRANSCRIPT"
for _ in {1..80}; do
  [[ ! -e "$TOKEN_E" ]] && break
  sleep 0.05
done
[[ ! -e "$TOKEN_E" ]] || fail "aborted turn sharing a transcript was not reaped"
[[ -f "$TOKEN_F" ]] || fail "aborting one turn reaped its sibling token"
assert_eq "$(run_cli status)" "on"
printf '%s\n' \
  "{\"type\":\"event_msg\",\"payload\":{\"type\":\"task_complete\",\"turn_id\":\"$TURN_F\"}}" \
  >> "$TRANSCRIPT"
for _ in {1..80}; do
  [[ ! -e "$TOKEN_F" ]] && break
  sleep 0.05
done
[[ ! -e "$TOKEN_F" ]] || fail "completed turn sharing a transcript was not reaped"
assert_eq "$(run_cli status)" "off"
pass "shared transcripts reap only the turn a terminal event names"

run_cli off --force </dev/null
if kill -0 "$production_pid" 2>/dev/null; then
  fail "test daemon survived final cleanup"
fi
pass "final cleanup stops the production daemon"

# That daemon just ran every session transition in this suite while muted. If
# sound is genuinely opt-in it never went near the audio files.
if grep -q track "$DAEMON_LOG"; then
  fail "a muted daemon looked for tracks: $(cat "$DAEMON_LOG")"
fi
pass "a muted daemon runs the whole suite without touching audio"

# unmute is meant to land while the daemon is already running, not at its next
# start, and sound switched on with no tracks must degrade to the light alone
# rather than refuse to run: the LED is the product, the soundtrack is an extra.
SOUNDLESS_STATE="$TEST_ROOT/soundless-state"
SOUNDLESS_SHARE="$TEST_ROOT/soundless-share"
SOUNDLESS_LOG="$TEST_ROOT/soundless.log"
mkdir -p "$SOUNDLESS_STATE/sessions" "$SOUNDLESS_SHARE"
env THINKLIGHT_STATE_DIR="$SOUNDLESS_STATE" THINKLIGHT_TEST_NO_CAMERA=1 \
  THINKLIGHT_SHARE_DIR="$SOUNDLESS_SHARE" \
  "$DAEMON" > /dev/null 2>"$SOUNDLESS_LOG" &
soundless_pid=$!
sleep 1.5
grep -q track "$SOUNDLESS_LOG" && fail "daemon looked for tracks before unmute"

env THINKLIGHT_BIN_DIR="$BIN_DIR" THINKLIGHT_STATE_DIR="$SOUNDLESS_STATE" \
  THINKLIGHT_SHARE_DIR="$SOUNDLESS_SHARE" "$CLI" unmute > /dev/null 2>&1 \
  || fail "unmute failed with no default tracks to install"
for _ in {1..80}; do
  grep -q "no done track" "$SOUNDLESS_LOG" 2>/dev/null && break
  sleep 0.05
done
kill -0 "$soundless_pid" 2>/dev/null || fail "daemon exited when a track was missing"
grep -q "no loop track" "$SOUNDLESS_LOG" || fail "daemon did not report the missing loop track"
grep -q "no done track" "$SOUNDLESS_LOG" || fail "daemon did not report the missing done track"

# Still watching sessions with nothing to play: a token whose owner is gone
# gets reaped as usual.
bash -c 'exit 0' &
dead_pid=$!
wait "$dead_pid" 2>/dev/null || true
printf '%s\n%s\n%s\n%s\n' "$dead_pid" "" "" "ghost" > "$SOUNDLESS_STATE/sessions/ghost"
for _ in {1..80}; do
  [[ ! -e "$SOUNDLESS_STATE/sessions/ghost" ]] && break
  sleep 0.05
done
[[ ! -e "$SOUNDLESS_STATE/sessions/ghost" ]] || fail "daemon stopped watching sessions once a track was missing"
kill "$soundless_pid" 2>/dev/null || true
wait "$soundless_pid" 2>/dev/null || true
pass "unmute reaches a running daemon, and a missing track costs the cue, not the light"
