#!/bin/bash
# Runs at SessionStart, and decides one thing: whether the programs the other
# hooks call are the ones this plugin expects.
#
# Those programs cannot ship inside the plugin. Claude Code copies a plugin into
# a per-version cache directory, so a daemon run from there would sit at a new
# path after every update — and macOS ties camera access to the path, so it would
# ask again each time. A fixed ~/.local/bin keeps that grant for good. What the
# plugin can do is put them there: installing the plugin and then finding hooks
# that call a program nobody installed is the whole reason this exists.
#
# Silent on stdout by design: SessionStart stdout becomes Claude's context, and a
# maintenance notice does not belong there. Notifications carry it instead.
set -uo pipefail

root=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
bin_dir="${THINKLIGHT_BIN_DIR:-$HOME/.local/bin}"
cli="$bin_dir/thinklight"
state="${THINKLIGHT_STATE_DIR:-$HOME/.local/state/thinklight}"
share="${THINKLIGHT_SHARE_DIR:-$HOME/.local/share/thinklight}"

# Read with sed rather than plutil: this hook also runs on the machine holding
# the agent, which is often not a Mac and has no plutil. The manifest's version is
# a flat string field, so the quoted-key capture the CLI uses on hook payloads
# reads it exactly as well.
version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$root/.claude-plugin/plugin.json" 2>/dev/null | head -n1)
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 0

# The programs live outside either host's plugin cache, so Claude and Codex can
# briefly see different plugin versions while their marketplaces update. An
# older plugin must remain compatible with newer programs instead of pinning the
# shared install backwards and starting an upgrade/downgrade loop.
installed=$(cat "$state/version" 2>/dev/null)
if [[ -x "$cli" ]]; then
  [[ "$installed" == "$version" ]] && exit 0
  if [[ "$installed" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] &&
    [[ "$(printf '%s\n%s\n' "$installed" "$version" | sort -V | tail -1)" == "$installed" ]]; then
    exit 0
  fi
fi

# Reporting the gap is what this hook did before it could close one, and it is
# still the right answer whenever installing is not ours to do.
notify_only() {
  [[ -x "$cli" ]] || exit 0
  exec "$cli" _version_notify "$version"
}

# A source checkout owns this install: `thinklight update` is its way forward,
# and dropping prebuilt binaries on top would take that command away.
[[ -f "$state/source" ]] && notify_only
# Off means off. The switch is a file rather than a CLI question because it has
# to be answerable before anything is installed; the env var covers a machine
# that has never run thinklight at all.
[[ "${THINKLIGHT_NO_BOOTSTRAP:-}" == "1" || -f "$share/bootstrap-off" ]] && notify_only

# Getting here means the programs are behind, and one attempt every six hours is
# as often as that is worth acting on. Starting a session says nothing new about a
# download that already ran; the one thing that does change the answer is a
# release being published, which lands minutes after the version bump that made
# the plugin ask for it. A hard failure withdraws its own attempt, so being
# offline right now costs nothing more than the next session.
mkdir -p "$state" 2>/dev/null || notify_only
attempt=$(cat "$state/bootstrap-attempt" 2>/dev/null)
attempt_stamp=${attempt##* }
[[ "$attempt_stamp" =~ ^[0-9]+$ ]] || attempt_stamp=0
now=$(date +%s)
if [[ "${attempt%% *}" == "$version" ]] && (( now - attempt_stamp < 21600 )); then
  notify_only
fi
printf '%s %s\n' "$version" "$now" > "$state/bootstrap-attempt" || notify_only

# Detached: a 5s hook timeout is not a download budget. This session's light may
# come on a turn late, which is a far smaller cost than a session that waits.
nohup "$root/scripts/install-programs.sh" "$version" </dev/null >/dev/null 2>&1 &
exit 0
