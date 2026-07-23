#!/bin/bash
# Install the latest ThinkLight release binaries to ~/.local/bin.
# Usage: curl -fsSL https://raw.githubusercontent.com/lichengzhe/thinklight/main/get.sh | bash
# Run it again any time to update. For a source build, use install.sh instead.
set -euo pipefail

REPO=lichengzhe/thinklight
URL="https://github.com/$REPO/releases/latest/download/thinklight-macos-universal.tar.gz"

if [[ "$(uname -s)" != Darwin ]]; then
  echo "thinklight requires macOS" >&2
  exit 1
fi
if (( $(sw_vers -productVersion | cut -d. -f1) < 14 )); then
  echo "thinklight requires macOS 14 or later" >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
echo "downloading $URL"
curl -fsSL "$URL" | tar xz -C "$tmp" --strip-components 1

mkdir -p ~/.local/bin
for f in thinklight thinklight-daemon thinklight-check; do
  # Install to a temp name and mv into place: atomic, and never truncates a
  # binary a running daemon is executing.
  install -m 755 "$tmp/$f" ~/.local/bin/".$f.$$"
  mv -f ~/.local/bin/".$f.$$" ~/.local/bin/"$f"
done

mkdir -p ~/.local/state/thinklight
# A prebuilt install has no git checkout: 'thinklight update' and update
# checks are off. Updating means running this script again.
rm -f ~/.local/state/thinklight/source ~/.local/state/thinklight/revision
~/.local/bin/thinklight _sync </dev/null

echo "installed: thinklight thinklight-daemon thinklight-check -> ~/.local/bin"
echo "next: ~/.local/bin/thinklight blink 3   # macOS will ask for camera access; the LED then lights for 3s"
