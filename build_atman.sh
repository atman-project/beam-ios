#!/bin/bash
#
# Build atman as a static library for iOS and copy the header + .a into
# ios/atman/ so the Xcode project can link against it. Mirrors the pattern
# from atman-project/sky-is-the-limit-ios.
#
# Usage:
#   ./build_atman.sh                  # both arm64 (device) and x86_64 (sim)
#   ./build_atman.sh --release        # release profile
#   ./build_atman.sh --arm64          # device only
#   ./build_atman.sh --x86_64         # simulator only

set -uexo pipefail

IOS_DIR="$(cd "$(dirname "$0")" && pwd)"
ATMAN_DIR="$(cd "$IOS_DIR/submodules/atman" && pwd)"

cd "$ATMAN_DIR/atman"
bash ./build_bindings.sh --features blobs "$@"

MODE="debug"
if [[ "$*" == *"--release"* ]]; then
  MODE="release"
fi

ARM64=false
X86_64=false
if [[ "$*" == *"--arm64"* ]]; then ARM64=true; fi
if [[ "$*" == *"--x86_64"* ]]; then X86_64=true; fi
if ! $ARM64 && ! $X86_64; then
  ARM64=true
  X86_64=true
fi

cp "$ATMAN_DIR/target/atman.h" "$IOS_DIR/atman/atman.h"
if $ARM64 && $X86_64; then
  cp "$ATMAN_DIR/target/$MODE/libatman.a" "$IOS_DIR/atman/libatman.a"
elif $ARM64; then
  cp "$ATMAN_DIR/target/aarch64-apple-ios/$MODE/libatman.a" "$IOS_DIR/atman/libatman.a"
else
  cp "$ATMAN_DIR/target/x86_64-apple-ios/$MODE/libatman.a" "$IOS_DIR/atman/libatman.a"
fi

ls -lh "$IOS_DIR/atman/atman.h" "$IOS_DIR/atman/libatman.a"
