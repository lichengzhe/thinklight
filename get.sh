#!/bin/bash
# Install the latest ThinkLight release binaries to ~/.local/bin.
# Usage: curl -fsSL https://raw.githubusercontent.com/lichengzhe/thinklight/main/get.sh | bash
#        bash get.sh 2.5.0   # that exact release instead of the latest one
# Run it again any time to update. For a source build, use install.sh instead.
#
# On anything that is not a Mac this installs the CLI alone — see below.
set -euo pipefail

REPO=lichengzhe/thinklight
RAW="https://raw.githubusercontent.com/$REPO"
# The plugin passes its own version so a session can only ever install the
# programs that release was built with, never whatever happens to be latest.
VERSION=${1:-}
if [[ -n "$VERSION" ]]; then
  if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "thinklight: invalid version: $VERSION" >&2
    exit 2
  fi
  URL="https://github.com/$REPO/releases/download/v$VERSION/thinklight-$VERSION-macos-universal.tar.gz"
else
  URL="https://github.com/$REPO/releases/latest/download/thinklight-macos-universal.tar.gz"
fi

# Where the redirect lands, which is the same question `thinklight update --check`
# asks and gets the same answer: a tag exists before its release is built, so the
# newest tag is not always something you can download yet.
latest_version() {
  curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/$REPO/releases/latest" 2>/dev/null |
    sed -n 's#.*/releases/tag/v##p'
}

# No camera LED here, and no daemon that could drive one — but an agent on this
# machine can still light the Mac you are sitting at, over the ssh connection you
# opened it with. The CLI is the whole of what that takes: it is a shell script,
# so there are no binaries to match to a platform and no tarball to unpack.
install_cli_only() {
  # tmp is deliberately not local: the EXIT trap below outlives this function,
  # and under `set -u` a trap reaching for a variable that went out of scope with
  # the call fails on the way out of an install that otherwise worked.
  local version=$VERSION ref
  [[ -n "$version" ]] || version=$(latest_version) || true
  # main is the fallback for a version whose tag is not published yet, which is
  # only true between a version bump and its release build.
  ref="main"
  [[ -n "$version" ]] && ref="v$version"
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  echo "downloading $RAW/$ref/src/thinklight"
  curl -fsSL "$RAW/$ref/src/thinklight" -o "$tmp/thinklight" ||
    curl -fsSL "$RAW/main/src/thinklight" -o "$tmp/thinklight"
  mkdir -p ~/.local/bin
  install -m 755 "$tmp/thinklight" ~/.local/bin/".thinklight.$$"
  mv -f ~/.local/bin/".thinklight.$$" ~/.local/bin/thinklight

  mkdir -p ~/.local/state/thinklight
  rm -f ~/.local/state/thinklight/source ~/.local/state/thinklight/revision
  if [[ -n "$version" ]]; then
    printf '%s\n' "$version" > ~/.local/state/thinklight/version
  else
    rm -f ~/.local/state/thinklight/version
  fi

  echo "installed: thinklight -> ~/.local/bin"
  echo "This machine has no light of its own. An agent here lights the Mac you"
  echo "ssh in from, once that Mac has run: thinklight tunnel setup"
  echo "check it from inside an ssh session with: ~/.local/bin/thinklight tunnel status"
}

if [[ "$(uname -s)" != Darwin ]]; then
  install_cli_only
  exit 0
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
