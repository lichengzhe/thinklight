#!/bin/bash
# Build the universal macOS release archives.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT_DIR=${1:-"$ROOT/dist"}
MANIFEST="$ROOT/plugin/.claude-plugin/plugin.json"
VERSION=$(/usr/bin/plutil -extract version raw -o - "$MANIFEST")

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "invalid plugin version: $VERSION" >&2
  exit 1
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/thinklight-release.XXXXXX")
cleanup() {
  find "$WORK_DIR" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

BUNDLE="thinklight-$VERSION"
PACKAGE_DIR="$WORK_DIR/$BUNDLE"
VERSIONED_ARCHIVE="$BUNDLE-macos-universal.tar.gz"
LATEST_ARCHIVE="thinklight-macos-universal.tar.gz"
mkdir -p "$PACKAGE_DIR" "$OUT_DIR"

for arch in x86_64 arm64; do
  xcrun swiftc -O -warnings-as-errors \
    -target "$arch-apple-macosx14.0" \
    "$ROOT/src/thinklight-daemon.swift" \
    -o "$WORK_DIR/thinklight-daemon-$arch"
  xcrun swiftc -O -warnings-as-errors \
    -target "$arch-apple-macosx14.0" \
    "$ROOT/src/thinklight-check.swift" \
    -o "$WORK_DIR/thinklight-check-$arch"
done

for binary in thinklight-daemon thinklight-check; do
  lipo -create \
    "$WORK_DIR/$binary-x86_64" \
    "$WORK_DIR/$binary-arm64" \
    -output "$PACKAGE_DIR/$binary"
  codesign --force --sign - "$PACKAGE_DIR/$binary"
  lipo "$PACKAGE_DIR/$binary" -verify_arch x86_64 arm64
  codesign --verify --strict "$PACKAGE_DIR/$binary"
done

install -m 755 "$ROOT/src/thinklight" "$PACKAGE_DIR/thinklight"
install -m 644 "$ROOT/LICENSE" "$PACKAGE_DIR/LICENSE"

COPYFILE_DISABLE=1 tar -czf "$WORK_DIR/$VERSIONED_ARCHIVE" \
  -C "$WORK_DIR" "$BUNDLE"
cp "$WORK_DIR/$VERSIONED_ARCHIVE" "$WORK_DIR/$LATEST_ARCHIVE"
(
  cd "$WORK_DIR"
  shasum -a 256 "$VERSIONED_ARCHIVE" "$LATEST_ARCHIVE" > SHA256SUMS.txt
)

install -m 644 "$WORK_DIR/$VERSIONED_ARCHIVE" "$OUT_DIR/$VERSIONED_ARCHIVE"
install -m 644 "$WORK_DIR/$LATEST_ARCHIVE" "$OUT_DIR/$LATEST_ARCHIVE"
install -m 644 "$WORK_DIR/SHA256SUMS.txt" "$OUT_DIR/SHA256SUMS.txt"

echo "built release assets in $OUT_DIR"
sed -n '1,2p' "$OUT_DIR/SHA256SUMS.txt"
