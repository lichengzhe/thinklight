#!/bin/bash
# Backgrounded by version-check.sh: fetches the programs the hooks call and puts
# them in ~/.local/bin, then says so out loud once.
#
# The install steps are not reimplemented here. get.sh is the one place that
# knows the layout — which files go where, which of them an update must never
# touch, how to replace a daemon that is currently running — and a second copy of
# that knowledge is a second copy to keep correct. It is fetched pinned to the tag
# matching this plugin, so the installer and the programs it installs both come
# from the release this plugin was built alongside.
#
# Nothing here writes to stdout: the hook that spawns this has already returned,
# and there is nobody left to read it.
set -uo pipefail

REPO=lichengzhe/thinklight
RAW="https://raw.githubusercontent.com/$REPO"

version=${1:-}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 0

bin_dir="${THINKLIGHT_BIN_DIR:-$HOME/.local/bin}"
state="${THINKLIGHT_STATE_DIR:-$HOME/.local/state/thinklight}"
attempt_file="$state/bootstrap-attempt"
notice_file="$state/bootstrap-notice"

mkdir -p "$state" 2>/dev/null || exit 0

# Whether this is a first install or a catch-up changes what every message here
# should say, so it is answered before anything can go wrong.
had_cli=0
[[ -x "$bin_dir/thinklight" ]] && had_cli=1

notify() {
  # Integration tests exercise the bookkeeping without popping banners.
  [[ "${THINKLIGHT_TEST_NO_NOTIFY:-}" == "1" ]] && return 0
  /usr/bin/osascript -e "display notification \"$2\" with title \"$1\"" \
    >/dev/null 2>&1
}

# Failure is worth retrying at the next session rather than in six hours — a
# laptop that was offline for one session start is the likely cause — so the
# attempt is withdrawn outright. The complaint is not repeated, though: once per
# version is enough to act on.
gave_up() {
  local consequence="The light stays off until it can. Installing by hand is one line in the README."
  [[ "$had_cli" == 1 ]] && consequence="The programs you have keep working; this will try again."
  rm -f "$attempt_file"
  [[ "$(cat "$notice_file" 2>/dev/null)" == "$version" ]] && exit 0
  printf '%s\n' "$version" > "$notice_file"
  notify "ThinkLight could not install its programs" "$1 $consequence"
  exit 0
}

# macOS-only, and no version of this is going to change that: the light is a Mac
# camera LED. Nothing to withdraw and nothing to say — the attempt stands so this
# does not run again on every session start.
[[ "$(uname -s)" == Darwin ]] || exit 0
major=$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)
[[ "$major" =~ ^[0-9]+$ ]] && (( major >= 14 )) || exit 0

tmp=$(mktemp -d "${TMPDIR:-/tmp}/thinklight-bootstrap.XXXXXX") || exit 0
trap 'rm -rf "$tmp"' EXIT

# A local installer keeps the tests off the network.
installer=${THINKLIGHT_GET_SH:-}
if [[ -z "$installer" ]]; then
  installer="$tmp/get.sh"
  # main is the fallback for a plugin release whose tag is not published yet,
  # which is only ever true between a version bump and its release build.
  curl -fsSL "$RAW/v$version/get.sh" -o "$installer" \
    || curl -fsSL "$RAW/main/get.sh" -o "$installer" \
    || gave_up "GitHub could not be reached."
fi

# The exact release first; latest covers a plugin newer than any published build,
# where the same programs one version back still beat no programs at all. That
# leaves the version short of the plugin's on purpose — the six-hour retry then
# picks up the real release once it is published.
if ! bash "$installer" "$version" >/dev/null 2>&1; then
  bash "$installer" >/dev/null 2>&1 || gave_up "The download failed."
fi
[[ -x "$bin_dir/thinklight" ]] || gave_up "The download left nothing behind."

installed=$(cat "$state/version" 2>/dev/null)
if [[ -n "$installed" && "$installed" != "$version" ]]; then
  # The release for this plugin version is not published yet. Say what actually
  # landed rather than claiming a match nobody got.
  notify "ThinkLight installed $installed" \
    "The plugin is at $version, whose release is not out yet. It catches up by itself once it is."
elif [[ "$had_cli" == 1 ]]; then
  notify "ThinkLight is up to date" \
    "Programs updated to $version to match the plugin."
else
  notify "ThinkLight is ready" \
    "Programs installed to $bin_dir. macOS asks for camera access the first time the light comes on."
fi
