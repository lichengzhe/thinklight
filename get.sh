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

# Default tracks only, filed where `thinklight unmute` looks for them. Anything
# already playing, and whether sound is on at all, is left exactly as it was —
# re-running this script to update never changes either.
if [ -d "$tmp/assets" ]; then
  mkdir -p ~/.local/share/thinklight/defaults
  for track in "$tmp"/assets/loop.* "$tmp"/assets/done.*; do
    if [ -f "$track" ]; then
      install -m 644 "$track" ~/.local/share/thinklight/defaults/
    fi
  done
fi

mkdir -p ~/.local/state/thinklight
# A prebuilt install has no git checkout: 'thinklight update' and update
# checks are off. Updating means running this script again.
rm -f ~/.local/state/thinklight/source ~/.local/state/thinklight/revision
# Recording the version is what lets the Claude Code plugin notice later that
# these programs have fallen behind it, since this install path has no manifest.
if [ -f "$tmp/VERSION" ]; then
  install -m 644 "$tmp/VERSION" ~/.local/state/thinklight/version
else
  rm -f ~/.local/state/thinklight/version
fi
~/.local/bin/thinklight _sync </dev/null

echo "installed: thinklight thinklight-daemon thinklight-check -> ~/.local/bin"
echo "next: ~/.local/bin/thinklight blink 3   # macOS will ask for camera access; the LED then lights for 3s"
