#!/bin/bash
# Build and install thinklight to ~/.local/bin
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
cd "$SCRIPT_DIR/src"

mkdir -p ~/.local/bin
swiftc -O thinklight-daemon.swift -o ~/.local/bin/thinklight-daemon
swiftc -O thinklight-check.swift -o ~/.local/bin/thinklight-check
install -m 755 thinklight ~/.local/bin/thinklight
mkdir -p ~/.local/state/thinklight
printf '%s\n' "$SCRIPT_DIR" > ~/.local/state/thinklight/source
git -C "$SCRIPT_DIR" rev-parse HEAD > ~/.local/state/thinklight/revision
~/.local/bin/thinklight _sync </dev/null

echo "installed: thinklight thinklight-daemon thinklight-check -> ~/.local/bin"
echo "try: ~/.local/bin/thinklight blink 3 && ~/.local/bin/thinklight check"
