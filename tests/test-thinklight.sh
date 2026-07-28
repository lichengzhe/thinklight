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
        THINKLIGHT_SHARE_DIR="$SHARE_DIR" "$CLI" "$@"
}

run_codex_hook() {
  local event=$1 session=$2 turn=$3 transcript=$4
  shift 4
  printf '{"hook_event_name":"%s","session_id":"%s","turn_id":"%s","transcript_path":"%s"}\n' \
    "$event" "$session" "$turn" "$transcript" \
    | env THINKLIGHT_BIN_DIR="$BIN_DIR" THINKLIGHT_STATE_DIR="$STATE_DIR" \
        THINKLIGHT_SHARE_DIR="$SHARE_DIR" "$CLI" "$@"
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

# The unattended check reaches the network, so it has to be switchable — and
# switchable in a place installers do not write, or an update would silently
# turn it back on. An explicitly requested check is not covered: the user just
# asked the question out loud.
assert_eq "$(run_cli config | grep '^update-check:')" "update-check: on"
assert_eq "$(run_cli config update-check off | grep '^update-check:')" "update-check: off"
[[ -f "$SHARE_DIR/update-check-off" ]] || fail "the opt-out was not recorded beside the other settings"
CHECK_STAMP="$STATE_DIR/update-check"
# The check compares this install's revision against the remote, so a checkout is
# what makes it answerable in the first place.
printf '%s\n' 0000000000000000000000000000000000000000 > "$STATE_DIR/revision"
rm -f "$CHECK_STAMP"
run_hook UserPromptSubmit optout on
[[ ! -e "$CHECK_STAMP" ]] || fail "an opted-out install still scheduled a check"
run_hook Stop optout off
assert_eq "$(run_cli config update-check on | grep '^update-check:')" "update-check: on"
run_hook UserPromptSubmit optin on
[[ -f "$CHECK_STAMP" ]] || fail "turning the check back on did not schedule it"
run_hook Stop optin off
run_cli config bogus on > /dev/null 2>&1 && fail "an unknown config key was accepted"
pass "the background update check is switchable and off means off"

# A prebuilt install has no revision, but it does have a version, and published
# releases are something it can be compared against — the install path with no
# update signal at all was the one most people use. Latest is injected so the
# check the hook schedules stays off the network.
rm -f "$STATE_DIR/revision" "$CHECK_STAMP"
printf '2.0.0\n' > "$STATE_DIR/version"
THINKLIGHT_LATEST_VERSION=2.0.0 run_hook UserPromptSubmit prebuilt on
[[ -f "$CHECK_STAMP" ]] || fail "a prebuilt install did not schedule a check"
run_hook Stop prebuilt off
pass "the background check covers a prebuilt install too"

# Neither revision nor version: nothing to compare, so nothing to ask.
rm -f "$STATE_DIR/version" "$CHECK_STAMP"
run_hook UserPromptSubmit unknown on
[[ ! -e "$CHECK_STAMP" ]] || fail "an unrecognised install still scheduled a check"
run_hook Stop unknown off
pass "the update check stays out of an install it cannot reason about"

# What "latest" means, and what updating is, follow from how the install was
# made. A prebuilt install compares versions against published releases; the
# release lookup is stood in for so this stays offline.
UPDATE_STATE="$TEST_ROOT/update-state"
mkdir -p "$UPDATE_STATE"
update_check() {
  env THINKLIGHT_STATE_DIR="$UPDATE_STATE" THINKLIGHT_BIN_DIR="$BIN_DIR" \
    THINKLIGHT_SHARE_DIR="$SHARE_DIR" THINKLIGHT_LATEST_VERSION="$1" \
    "$CLI" update --check 2>&1
}
run_cli update --check > /dev/null 2>&1 && fail "a check ran without knowing what is installed"
printf '2.5.0\n' > "$UPDATE_STATE/version"
assert_eq "$(update_check 2.5.0)" "thinklight: up to date (2.5.0)"
assert_eq "$(update_check 2.6.0)" \
  "thinklight: update available (2.5.0 -> 2.6.0); run: thinklight update"
# Version ordering, not string comparison: 2.10.0 is newer than 2.9.0.
printf '2.10.0\n' > "$UPDATE_STATE/version"
assert_eq "$(update_check 2.9.0)" "thinklight: up to date (2.10.0)"
pass "a prebuilt install checks itself against published releases"

# The unattended check names the version so the notice can be acted on, and says
# nothing at all when there is nothing to say.
notify_update() {
  env THINKLIGHT_STATE_DIR="$UPDATE_STATE" THINKLIGHT_BIN_DIR="$BIN_DIR" \
    THINKLIGHT_SHARE_DIR="$SHARE_DIR" THINKLIGHT_LATEST_VERSION="$1" \
    THINKLIGHT_TEST_NO_NOTIFY=1 "$CLI" _check_update_notify
}
assert_eq "$(notify_update 2.9.0)" ""
assert_eq "$(notify_update 2.11.0)" "Run thinklight update to install 2.11.0."
pass "the update notice only fires when a newer release exists"

# Updating a prebuilt install is running get.sh again rather than a second copy
# of what it knows, so the only thing to pin down is that it is what gets run.
cat > "$TEST_ROOT/update-get.sh" <<'FAKE'
#!/bin/bash
printf 'ran %s\n' "$*"
FAKE
assert_eq "$(env THINKLIGHT_STATE_DIR="$UPDATE_STATE" THINKLIGHT_BIN_DIR="$BIN_DIR" \
  THINKLIGHT_SHARE_DIR="$SHARE_DIR" THINKLIGHT_GET_SH="$TEST_ROOT/update-get.sh" \
  "$CLI" update)" "ran "
# A checkout is still the source flavour, which get.sh has no part in.
printf '%s\n' 0000000000000000000000000000000000000000 > "$UPDATE_STATE/revision"
env THINKLIGHT_STATE_DIR="$UPDATE_STATE" THINKLIGHT_BIN_DIR="$BIN_DIR" \
  THINKLIGHT_SHARE_DIR="$SHARE_DIR" THINKLIGHT_GET_SH="$TEST_ROOT/update-get.sh" \
  "$CLI" update > /dev/null 2>&1 && fail "a source install was updated by get.sh"
pass "a prebuilt update runs get.sh, and a source install does not"

# The plugin's own install is switchable the same way and in the same place: the
# hook reads this file directly, because it has to answer the question on a
# machine where the CLI does not exist yet.
assert_eq "$(run_cli config | grep '^bootstrap:')" "bootstrap: on"
assert_eq "$(run_cli config bootstrap off | grep '^bootstrap:')" "bootstrap: off"
[[ -f "$SHARE_DIR/bootstrap-off" ]] || fail "the opt-out was not recorded beside the other settings"
assert_eq "$(run_cli config bootstrap on | grep '^bootstrap:')" "bootstrap: on"
[[ ! -e "$SHARE_DIR/bootstrap-off" ]] || fail "turning bootstrap back on left the switch behind"
pass "the plugin's install is switchable from the CLI"

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

# The plugin updates itself and the programs do not, so the plugin's hook needs
# something to compare against. install.sh records what it installed.
MANIFEST_VERSION=$(/usr/bin/plutil -extract version raw -o - "$ROOT/plugin/.claude-plugin/plugin.json")
assert_eq "$(cat "$INSTALL_HOME/.local/state/thinklight/version")" "$MANIFEST_VERSION"
assert_eq "$(env HOME="$INSTALL_HOME" THINKLIGHT_BIN_DIR="$BIN_DIR" \
  "$INSTALL_HOME/.local/bin/thinklight" version)" "$MANIFEST_VERSION"
pass "install.sh records the manifest version and the CLI reports it"

# Drift is reported once per version, never on stdout: SessionStart stdout
# becomes Claude's context, and the hook must add nothing to it.
NOTIFY_STATE="$TEST_ROOT/notify-state"
mkdir -p "$NOTIFY_STATE"
notify() {
  env THINKLIGHT_STATE_DIR="$NOTIFY_STATE" THINKLIGHT_BIN_DIR="$BIN_DIR" \
    THINKLIGHT_TEST_NO_NOTIFY=1 "$CLI" _version_notify "$@"
}
printf '9.9.9\n' > "$NOTIFY_STATE/version"
assert_eq "$(notify 9.9.9)" ""
[[ ! -e "$NOTIFY_STATE/version-notice" ]] || fail "matching versions still recorded a notice"
assert_eq "$(notify 9.9.10)" ""
assert_eq "$(cat "$NOTIFY_STATE/version-notice")" "9.9.10"
notice_stamp=$(stat -f %m "$NOTIFY_STATE/version-notice")
notify 9.9.10
assert_eq "$(stat -f %m "$NOTIFY_STATE/version-notice")" "$notice_stamp"
assert_eq "$(notify 9.9.11)" ""
assert_eq "$(cat "$NOTIFY_STATE/version-notice")" "9.9.11"
pass "version drift notifies once per version and never writes to stdout"

# An install that predates version recording must not be nagged about a gap it
# cannot even measure.
rm -f "$NOTIFY_STATE/version" "$NOTIFY_STATE/version-notice"
assert_eq "$(notify 9.9.12)" ""
[[ ! -e "$NOTIFY_STATE/version-notice" ]] || fail "notified without knowing the installed version"
pass "an unversioned install is left alone"

# Installing the plugin is meant to be the whole install, so its SessionStart
# hook puts the programs in place itself. The whole decision is exercised here
# without touching the network: a stand-in installer plays get.sh, a stand-in CLI
# records what it was asked to do, and HOME points somewhere disposable.
BOOT_HOME="$TEST_ROOT/bootstrap-home"
BOOT_BIN="$BOOT_HOME/.local/bin"
BOOT_STATE="$BOOT_HOME/.local/state/thinklight"
BOOT_SHARE="$BOOT_HOME/.local/share/thinklight"
INSTALLER_LOG="$BOOT_STATE/installer-log"
CLI_LOG="$BOOT_STATE/cli-log"
mkdir -p "$BOOT_HOME"

cat > "$TEST_ROOT/fake-cli" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" >> "$HOME/.local/state/thinklight/cli-log"
STUB
chmod +x "$TEST_ROOT/fake-cli"

cat > "$TEST_ROOT/fake-get.sh" <<'FAKE'
#!/bin/bash
# Stands in for get.sh: lands a CLI and records the version it was handed.
set -euo pipefail
mkdir -p "$HOME/.local/bin" "$HOME/.local/state/thinklight"
install -m 755 "$FAKE_CLI" "$HOME/.local/bin/thinklight"
printf '%s\n' "${1:-latest}" > "$HOME/.local/state/thinklight/version"
printf '%s\n' "${1:-latest}" >> "$HOME/.local/state/thinklight/installer-log"
FAKE
chmod +x "$TEST_ROOT/fake-get.sh"

# -u so the surrounding test's overrides cannot leak in: this hook resolves
# everything from HOME, exactly as it does in a real session.
session_start() {
  env -u THINKLIGHT_BIN_DIR -u THINKLIGHT_STATE_DIR -u THINKLIGHT_SHARE_DIR \
    HOME="$BOOT_HOME" CLAUDE_PLUGIN_ROOT="$ROOT/plugin" \
    FAKE_CLI="$TEST_ROOT/fake-cli" THINKLIGHT_GET_SH="$TEST_ROOT/fake-get.sh" \
    THINKLIGHT_TEST_NO_NOTIFY=1 "$@" \
    "$ROOT/plugin/scripts/version-check.sh"
}

# The install runs detached, so it is waited for rather than assumed.
await() {
  local path=$1 tries=0
  until [[ -e "$path" ]]; do
    tries=$((tries + 1))
    [[ "$tries" -lt 200 ]] || return 1
    sleep 0.05
  done
}

# Nothing installed: the hook is the installer.
session_start || fail "the hook failed with nothing installed"
await "$BOOT_BIN/thinklight" || fail "the hook did not install the programs"
await "$INSTALLER_LOG" || fail "the installer left no record"
assert_eq "$(cat "$INSTALLER_LOG")" "$MANIFEST_VERSION"
assert_eq "$(cut -d' ' -f1 "$BOOT_STATE/bootstrap-attempt")" "$MANIFEST_VERSION"
pass "a session start installs the programs the other hooks call, pinned to the plugin's version"

# In step, and the hook has to be cheap enough to run on every session start.
rm -f "$INSTALLER_LOG" "$CLI_LOG"
session_start
sleep 0.5
[[ ! -e "$INSTALLER_LOG" ]] || fail "an up-to-date install was reinstalled"
[[ ! -e "$CLI_LOG" ]] || fail "an up-to-date install was still reported as drifted"
pass "matching versions cost nothing"

# A session start is not new information about a download that already ran, so
# drift alone must not restart it.
printf '0.0.1\n' > "$BOOT_STATE/version"
rm -f "$INSTALLER_LOG" "$CLI_LOG"
session_start
sleep 0.5
[[ ! -e "$INSTALLER_LOG" ]] || fail "a fresh attempt tried again straight away"
assert_eq "$(sed -n '1p' "$CLI_LOG")" "_version_notify"
assert_eq "$(sed -n '2p' "$CLI_LOG")" "$MANIFEST_VERSION"
pass "an attempt that already ran is not repeated, and the gap is reported instead"

# The one thing that changes the answer is a release being published, which is why
# the attempt goes stale rather than standing for good. Without this, a plugin that
# updated minutes before its own release built would stay behind until the next one.
printf '%s %s\n' "$MANIFEST_VERSION" "$(( $(date +%s) - 21601 ))" \
  > "$BOOT_STATE/bootstrap-attempt"
session_start
await "$INSTALLER_LOG" || fail "a stale attempt did not retry"
assert_eq "$(cat "$INSTALLER_LOG")" "$MANIFEST_VERSION"
assert_eq "$(cat "$BOOT_STATE/version")" "$MANIFEST_VERSION"
pass "an attempt older than six hours tries again"

# A source checkout owns its install: `thinklight update` is its way forward, and
# prebuilt binaries dropped on top would take that command away.
printf '0.0.1\n' > "$BOOT_STATE/version"
: > "$BOOT_STATE/source"
rm -f "$BOOT_STATE/bootstrap-attempt" "$INSTALLER_LOG" "$CLI_LOG"
session_start
sleep 0.5
[[ ! -e "$INSTALLER_LOG" ]] || fail "the plugin installed over a source checkout"
assert_eq "$(sed -n '1p' "$CLI_LOG")" "_version_notify"
[[ ! -e "$BOOT_STATE/bootstrap-attempt" ]] || fail "a refusal was recorded as an attempt"
rm -f "$BOOT_STATE/source"
pass "a source install is reported, never overwritten"

# Off means off, by either switch, and it still leaves the drift visible.
mkdir -p "$BOOT_SHARE"
: > "$BOOT_SHARE/bootstrap-off"
rm -f "$INSTALLER_LOG" "$CLI_LOG"
session_start
sleep 0.5
[[ ! -e "$INSTALLER_LOG" ]] || fail "bootstrap ran with the switch off"
assert_eq "$(sed -n '1p' "$CLI_LOG")" "_version_notify"
rm -f "$BOOT_SHARE/bootstrap-off" "$CLI_LOG"
session_start THINKLIGHT_NO_BOOTSTRAP=1
sleep 0.5
[[ ! -e "$INSTALLER_LOG" ]] || fail "bootstrap ran with THINKLIGHT_NO_BOOTSTRAP=1"
pass "both bootstrap switches stop the install without hiding the gap"

# The retry rule: a download that fails withdraws its own attempt, so the next
# session tries again instead of the machine staying dark until the next release.
rm -f "$BOOT_STATE/bootstrap-attempt" "$INSTALLER_LOG" "$CLI_LOG"
printf '#!/bin/bash\nexit 1\n' > "$TEST_ROOT/failing-get.sh"
chmod +x "$TEST_ROOT/failing-get.sh"
env -u THINKLIGHT_BIN_DIR -u THINKLIGHT_STATE_DIR -u THINKLIGHT_SHARE_DIR \
  HOME="$BOOT_HOME" CLAUDE_PLUGIN_ROOT="$ROOT/plugin" \
  FAKE_CLI="$TEST_ROOT/fake-cli" THINKLIGHT_GET_SH="$TEST_ROOT/failing-get.sh" \
  THINKLIGHT_TEST_NO_NOTIFY=1 "$ROOT/plugin/scripts/version-check.sh"
await "$BOOT_STATE/bootstrap-notice" || fail "a failed install recorded nothing"
tries=0
while [[ -e "$BOOT_STATE/bootstrap-attempt" ]]; do
  tries=$((tries + 1))
  [[ "$tries" -lt 200 ]] || fail "a failed install kept its attempt, blocking a retry"
  sleep 0.05
done
assert_eq "$(cat "$BOOT_STATE/bootstrap-notice")" "$MANIFEST_VERSION"
pass "a failed install withdraws its attempt and complains once"

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

# --- Sound theme packages ------------------------------------------------------
# A theme package is a loop track plus a done track plus optional metadata.
# Installing one gets its own share directory so these cases do not depend on
# the sound state the earlier tests left behind.
THEME_SHARE="$TEST_ROOT/theme-share"
THEME_WORK="$TEST_ROOT/theme-work"
mkdir -p "$THEME_SHARE/defaults" "$THEME_WORK"
printf 'builtin-loop' > "$THEME_SHARE/defaults/loop.flac"
printf 'builtin-done' > "$THEME_SHARE/defaults/done.flac"

run_theme_cli() {
  env THINKLIGHT_BIN_DIR="$BIN_DIR" THINKLIGHT_STATE_DIR="$STATE_DIR" \
    THINKLIGHT_SHARE_DIR="$THEME_SHARE" "$CLI" "$@"
}

# A track already in place, in a different format, must not survive the
# install — track_for matches by stem, so a leftover loop.flac would keep
# winning over the package's own loop.mp3.
printf 'old-loop' > "$THEME_SHARE/loop.flac"
printf 'old-done' > "$THEME_SHARE/done.flac"

LOFI_PKG="$THEME_WORK/lofi-rain"
mkdir -p "$LOFI_PKG"
cat > "$LOFI_PKG/theme.json" <<'JSON'
{"name":"lofi-rain","title":"Lofi Rain","author":"alice","license":"CC-BY-4.0","source":"https://example.com/themes/lofi-rain","version":1}
JSON
printf 'loop-audio' > "$LOFI_PKG/loop.mp3"
printf 'done-audio' > "$LOFI_PKG/done.mp3"
LOFI_ZIP="$THEME_WORK/lofi-rain.zip"
(cd "$LOFI_PKG" && zip -q -r "$LOFI_ZIP" .)

run_theme_cli theme install "$LOFI_ZIP" > /dev/null \
  || fail "installing a zip theme package failed"
assert_eq "$(run_theme_cli config | grep '^loop track:')" "loop track: loop.mp3"
assert_eq "$(run_theme_cli config | grep '^done track:')" "done track: done.mp3"
[[ ! -e "$THEME_SHARE/loop.flac" ]] || fail "install left the old loop track behind"
[[ ! -e "$THEME_SHARE/done.flac" ]] || fail "install left the old done track behind"
pass "installing a zip theme replaces the previous tracks"

assert_eq "$(run_theme_cli theme current | grep '^name:')" "name: lofi-rain"
assert_eq "$(run_theme_cli theme current | grep '^author:')" "author: alice"
assert_eq "$(run_theme_cli theme current | grep '^license:')" "license: CC-BY-4.0"
pass "theme current reports the installed package's metadata"

FOREST_PKG="$THEME_WORK/forest"
mkdir -p "$FOREST_PKG"
printf '{"name":"forest","author":"bob","license":"CC0","source":"local"}' > "$FOREST_PKG/theme.json"
printf 'forest-loop' > "$FOREST_PKG/loop.wav"
printf 'forest-done' > "$FOREST_PKG/done.wav"
run_theme_cli theme install "$FOREST_PKG" > /dev/null \
  || fail "installing a directory theme package failed"
assert_eq "$(run_theme_cli config | grep '^loop track:')" "loop track: loop.wav"
[[ ! -e "$THEME_SHARE/loop.mp3" ]] || fail "installing a directory package left the previous package's tracks"
pass "installing a directory package works the same as a zip"

BAD_MISSING_DONE="$THEME_WORK/bad-missing-done"
mkdir -p "$BAD_MISSING_DONE"
printf 'x' > "$BAD_MISSING_DONE/loop.mp3"
run_theme_cli theme install "$BAD_MISSING_DONE" > /dev/null 2>&1 \
  && fail "a package missing a done track was accepted"
assert_eq "$(cat "$THEME_SHARE/loop.wav")" "forest-loop"
assert_eq "$(cat "$THEME_SHARE/done.wav")" "forest-done"
[[ ! -e "$THEME_SHARE/loop.mp3" ]] || fail "a rejected package's tracks leaked into place"
pass "a package missing a done track is rejected without touching the installed tracks"

BAD_EXT_PKG="$THEME_WORK/bad-ext"
mkdir -p "$BAD_EXT_PKG"
printf 'x' > "$BAD_EXT_PKG/loop.txt"
printf 'x' > "$BAD_EXT_PKG/done.mp3"
run_theme_cli theme install "$BAD_EXT_PKG" > /dev/null 2>&1 \
  && fail "a track with an unsupported extension was accepted"
[[ ! -e "$THEME_SHARE/loop.txt" ]] || fail "a rejected extension leaked into place"
pass "a track with an unsupported extension is rejected"

NO_META_PKG="$THEME_WORK/no-metadata"
mkdir -p "$NO_META_PKG"
printf 'x' > "$NO_META_PKG/loop.aiff"
printf 'x' > "$NO_META_PKG/done.aiff"
run_theme_cli theme install "$NO_META_PKG" > /dev/null \
  || fail "a package with no theme.json was rejected"
assert_eq "$(run_theme_cli theme current | grep '^name:')" "name: unknown"
pass "a missing theme.json does not block installation, only the metadata"

run_theme_cli theme reset > /dev/null || fail "theme reset failed"
assert_eq "$(run_theme_cli config | grep '^loop track:')" "loop track: loop.flac"
assert_eq "$(cat "$THEME_SHARE/loop.flac")" "builtin-loop"
assert_eq "$(run_theme_cli theme current | grep '^name:')" "name: default"
pass "theme reset restores the bundled default tracks"

run_theme_cli unmute > /dev/null
[[ -f "$THEME_SHARE/sound-on" ]] || fail "unmute did not turn sound on for the reload test"
run_theme_cli theme install "$LOFI_ZIP" > /dev/null \
  || fail "installing a theme while sound is on failed"
assert_eq "$(run_theme_cli config | grep '^loop track:')" "loop track: loop.mp3"
[[ -f "$THEME_SHARE/sound-on" ]] || fail "installing a theme with sound on turned sound off"
pass "installing a theme while sound is on reloads it and leaves sound on"

# Finder's "Compress" on a folder is the most natural way to hand-build a
# package, and it wraps the contents in a top-level directory instead of
# zipping them flat.
NESTED_PKG_DIR="$THEME_WORK/nested-src"
mkdir -p "$NESTED_PKG_DIR/lofi-rain"
printf '{"name":"lofi-rain"}' > "$NESTED_PKG_DIR/lofi-rain/theme.json"
printf 'nested-loop' > "$NESTED_PKG_DIR/lofi-rain/loop.mp3"
printf 'nested-done' > "$NESTED_PKG_DIR/lofi-rain/done.mp3"
NESTED_ZIP="$THEME_WORK/nested.zip"
(cd "$NESTED_PKG_DIR" && zip -q -r "$NESTED_ZIP" lofi-rain)

run_theme_cli theme install "$NESTED_ZIP" > /dev/null \
  || fail "installing a Finder-style nested zip failed"
assert_eq "$(run_theme_cli config | grep '^loop track:')" "loop track: loop.mp3"
assert_eq "$(cat "$THEME_SHARE/loop.mp3")" "nested-loop"
pass "a zip wrapping its contents in one top-level directory installs anyway"

# macOS zip also drops a __MACOSX sibling next to the real content directory;
# that must not be mistaken for a second package root.
MACOSX_PKG_DIR="$THEME_WORK/macosx-src"
mkdir -p "$MACOSX_PKG_DIR/rainy-day" "$MACOSX_PKG_DIR/__MACOSX/rainy-day"
printf '{"name":"rainy-day"}' > "$MACOSX_PKG_DIR/rainy-day/theme.json"
printf 'rainy-loop' > "$MACOSX_PKG_DIR/rainy-day/loop.wav"
printf 'rainy-done' > "$MACOSX_PKG_DIR/rainy-day/done.wav"
printf 'resource-fork' > "$MACOSX_PKG_DIR/__MACOSX/rainy-day/._loop.wav"
MACOSX_ZIP="$THEME_WORK/macosx.zip"
(cd "$MACOSX_PKG_DIR" && zip -q -r "$MACOSX_ZIP" rainy-day __MACOSX)

run_theme_cli theme install "$MACOSX_ZIP" > /dev/null \
  || fail "installing a zip with a __MACOSX sibling directory failed"
assert_eq "$(run_theme_cli config | grep '^loop track:')" "loop track: loop.wav"
assert_eq "$(cat "$THEME_SHARE/loop.wav")" "rainy-loop"
pass "a __MACOSX sibling directory is ignored when finding the package root"

# A directory given directly is used as-is — the user pointed at it on
# purpose, so descending into a subdirectory of it would be a surprise.
WRAPPED_DIR_PKG="$THEME_WORK/wrapped-dir"
mkdir -p "$WRAPPED_DIR_PKG/lofi-rain"
printf '{"name":"lofi-rain"}' > "$WRAPPED_DIR_PKG/lofi-rain/theme.json"
printf 'x' > "$WRAPPED_DIR_PKG/lofi-rain/loop.mp3"
printf 'x' > "$WRAPPED_DIR_PKG/lofi-rain/done.mp3"
run_theme_cli theme install "$WRAPPED_DIR_PKG" > /dev/null 2>&1 \
  && fail "a directory input descended into its own subdirectory"
pass "a directory package is never descended into, only a zip is"
