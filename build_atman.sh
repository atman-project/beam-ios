#!/bin/bash
#
# Build atman as a static library for iOS and copy the header + .a
# into atman/ so the Xcode project can link against it.
#
# Usage:
#   ./build_atman.sh --release        # release profile
#   ./build_atman.sh --arm64          # device only
#   ./build_atman.sh --sim-arm64      # Apple Silicon simulator only
#   ./build_atman.sh --x86_64         # Intel simulator only
#
# The installed atman/libatman.a is always one slice — pick the one
# matching the destination you're about to build for in Xcode:
#   - simulator on Apple Silicon → run with --sim-arm64
#   - real iPhone / Archive      → run with --arm64
# With no flags the script builds both and installs the sim-arm64 slice
# (most common during dev iteration).

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
SIM_ARM64=false
X86_64=false
if [[ "$*" == *"--arm64"* ]]; then ARM64=true; fi
if [[ "$*" == *"--sim-arm64"* ]]; then SIM_ARM64=true; fi
if [[ "$*" == *"--x86_64"* ]]; then X86_64=true; fi

if ! $ARM64 && ! $SIM_ARM64 && ! $X86_64; then
  echo "build_atman.sh: target must be specified: --arm64 / --sim-arm64 / --x86_64"
  exit 1
fi

rm -f $IOS_DIR/atman/libatman.a $IOS_DIR/atman/atman.swift
rm -rf $IOS_DIR/atman/atmanFFI

# Swift's include-path module discovery wants `module.modulemap` (not
# `atmanFFI.modulemap`), inside a directory named like the module.
cp "$ATMAN_DIR/target/uniffi-bindings/swift/atman.swift" "$IOS_DIR/atman/atman.swift"
mkdir -p "$IOS_DIR/atman/atmanFFI"
cp "$ATMAN_DIR/target/uniffi-bindings/swift/atmanFFI.h" "$IOS_DIR/atman/atmanFFI/atmanFFI.h"
cp "$ATMAN_DIR/target/uniffi-bindings/swift/atmanFFI.modulemap" "$IOS_DIR/atman/atmanFFI/module.modulemap"

if $ARM64 && ! $SIM_ARM64 && ! $X86_64; then
  cp "$ATMAN_DIR/target/aarch64-apple-ios/$MODE/libatman.a" "$IOS_DIR/atman/libatman.a"
elif $SIM_ARM64 && ! $ARM64 && ! $X86_64; then
  cp "$ATMAN_DIR/target/aarch64-apple-ios-sim/$MODE/libatman.a" "$IOS_DIR/atman/libatman.a"
elif $X86_64 && ! $ARM64 && ! $SIM_ARM64; then
  cp "$ATMAN_DIR/target/x86_64-apple-ios/$MODE/libatman.a" "$IOS_DIR/atman/libatman.a"
else
  echo "build_atman.sh: multiple targets specified" >&2
  echo "Re-run with exactly one of --arm64 / --sim-arm64 / --x86_64 to" >&2
  exit 2
fi

ls -lh "$IOS_DIR/atman/libatman.a" "$IOS_DIR/atman/atman.swift" \
  "$IOS_DIR/atman/atmanFFI/atmanFFI.h" "$IOS_DIR/atman/atmanFFI/module.modulemap"
