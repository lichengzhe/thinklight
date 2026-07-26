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
# The bundled tracks land in defaults/, never beside the ones actually playing.
# Refreshing a default is then safe, while the tracks a user swapped in and the
# flag that turns sound on sit one directory up where no installer writes: an
# update can neither overwrite a chosen track nor change whether a machine
# makes noise. `thinklight unmute` is what copies a default into place.
if [ -d "$SCRIPT_DIR/assets" ]; then
  mkdir -p ~/.local/share/thinklight/defaults
  for track in "$SCRIPT_DIR"/assets/loop.* "$SCRIPT_DIR"/assets/done.*; do
    if [ -f "$track" ]; then
      install -m 644 "$track" ~/.local/share/thinklight/defaults/
    fi
  done
fi
mkdir -p ~/.local/state/thinklight
printf '%s\n' "$SCRIPT_DIR" > ~/.local/state/thinklight/source
# The plugin manifest is the one place a version is declared, and the release
# workflow already keys off it. Recording what got installed is what lets the
# plugin notice later that these programs have fallen behind it.
if version=$(/usr/bin/plutil -extract version raw -o - \
  "$SCRIPT_DIR/plugin/.claude-plugin/plugin.json" 2>/dev/null); then
  printf '%s\n' "$version" > ~/.local/state/thinklight/version
else
  rm -f ~/.local/state/thinklight/version
fi
if ! git -C "$SCRIPT_DIR" rev-parse HEAD > ~/.local/state/thinklight/revision 2>/dev/null; then
  rm -f ~/.local/state/thinklight/revision
  echo "warning: not a git checkout; 'thinklight update' and update checks are disabled" >&2
fi
~/.local/bin/thinklight _sync </dev/null

echo "installed: thinklight thinklight-daemon thinklight-check -> ~/.local/bin"
echo "try: ~/.local/bin/thinklight blink 3 && ~/.local/bin/thinklight check"
