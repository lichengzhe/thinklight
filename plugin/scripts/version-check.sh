#!/bin/bash
# Runs at SessionStart. The plugin updates itself; the programs in ~/.local/bin
# do not, so the two drift — and the drift arrives through an update the user
# never ran, which makes it exactly the kind of breakage nobody can diagnose.
# This only reports it. Installing anything from a session hook would be a
# surprise, and the source it would install from is not always on disk.
#
# Silent on stdout by design: SessionStart stdout becomes Claude's context, and
# a maintenance notice does not belong there. The CLI notifies instead.
set -uo pipefail

root=${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}
cli="${THINKLIGHT_BIN_DIR:-$HOME/.local/bin}/thinklight"

# Not installed at all is the README's problem, not this hook's.
[ -x "$cli" ] || exit 0

version=$(/usr/bin/plutil -extract version raw -o - \
  "$root/.claude-plugin/plugin.json" 2>/dev/null) || exit 0

exec "$cli" _version_notify "$version"
