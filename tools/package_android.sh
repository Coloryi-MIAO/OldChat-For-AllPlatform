#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
out="${1:-dist/android}"
chmod +x tools/create_android_signing.sh
tools/create_android_signing.sh
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64
rm -rf "$out"
mkdir -p "$out"
cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk "$out/OldChatForAllPlatformandroidv7a.apk"
cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$out/OldChatForAllPlatformandroidv8a.apk"
cp build/app/outputs/flutter-apk/app-x86_64-release.apk "$out/OldChatForAllPlatformandroidx64.apk"
printf 'Android APKs: %s\n' "$out"
