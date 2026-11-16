#!/usr/bin/env bash
# Build the Rust core for Android (3 ABIs) into app/android/app/src/main/jniLibs/.
# Run from the repo root. Prereqs: rustup targets, NDK (ANDROID_NDK_HOME),
# cargo-ndk, and a prior `flutter create .` inside app/.
set -euo pipefail

cd "$(dirname "$0")/../core"

cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 \
  -o ../app/android/app/src/main/jniLibs build --release

echo "done — jniLibs populated for arm64-v8a, armeabi-v7a, x86_64"
