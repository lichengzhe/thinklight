#!/bin/bash
# Build and install thinklight to ~/.local/bin
set -euo pipefail
cd "$(dirname "$0")/src"

mkdir -p ~/.local/bin
swiftc -O thinklight-daemon.swift -o ~/.local/bin/thinklight-daemon
swiftc -O thinklight-check.swift -o ~/.local/bin/thinklight-check
install -m 755 thinklight ~/.local/bin/thinklight

echo "installed: thinklight thinklight-daemon thinklight-check -> ~/.local/bin"
echo "try: ~/.local/bin/thinklight blink 3 && ~/.local/bin/thinklight check"
