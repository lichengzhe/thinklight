#!/bin/bash
# Build and install thinklight to ~/.local/bin
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR/src"

mkdir -p ~/.local/bin
# Build to a temp name and mv into place: atomic, and never truncates a
# binary a running daemon is executing.
swiftc -O thinklight-daemon.swift -o ~/.local/bin/.thinklight-daemon.$$
mv -f ~/.local/bin/.thinklight-daemon.$$ ~/.local/bin/thinklight-daemon
swiftc -O thinklight-check.swift -o ~/.local/bin/.thinklight-check.$$
mv -f ~/.local/bin/.thinklight-check.$$ ~/.local/bin/thinklight-check
install -m 755 thinklight ~/.local/bin/thinklight
# Tracks live in a data dir the daemon reads at startup, so replacing one only
# needs a file copy — no rebuild, no reinstall of the binaries. They are also
# optional: a checkout with no assets (or one whose tracks were deleted to
# silence it) still installs, and the daemon just runs without sound.
if compgen -G "$SCRIPT_DIR/assets/*.flac" > /dev/null; then
  mkdir -p ~/.local/share/thinklight
  install -m 644 "$SCRIPT_DIR"/assets/*.flac ~/.local/share/thinklight/
fi
mkdir -p ~/.local/state/thinklight
printf '%s\n' "$SCRIPT_DIR" > ~/.local/state/thinklight/source
if ! git -C "$SCRIPT_DIR" rev-parse HEAD > ~/.local/state/thinklight/revision 2>/dev/null; then
  rm -f ~/.local/state/thinklight/revision
  echo "warning: not a git checkout; 'thinklight update' and update checks are disabled" >&2
fi
~/.local/bin/thinklight _sync </dev/null

echo "installed: thinklight thinklight-daemon thinklight-check -> ~/.local/bin"
echo "try: ~/.local/bin/thinklight blink 3 && ~/.local/bin/thinklight check"
