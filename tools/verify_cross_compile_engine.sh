#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
flutter_version="${FLUTTER_VERSION:-3.44.8}"
platform="${1:-all}"
case "$platform" in
  all|android|linux|windows|macos|ios|web) ;;
  *) echo 'Usage: tools/verify_cross_compile_engine.sh all|android|linux|windows|macos|ios|web' >&2; exit 2 ;;
esac
printf 'Flutter cross compile engine: %s\n' "$flutter_version"
printf 'Host: %s / %s\n' "$(uname -s)" "$(uname -m)"
flutter --version | sed -n '1,3p'
flutter pub get
if [[ "$platform" == all || "$platform" == android ]]; then
  flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64,android-x64 --no-pub -Pandroid.compileSdk=36 -Pandroid.targetSdk=36
fi
if [[ "$platform" == all || "$platform" == web ]]; then
  flutter build web --release --no-pub
fi
if [[ "$platform" == all || "$platform" == linux ]]; then
  flutter build linux --release --no-pub
fi
if [[ "$platform" == all || "$platform" == windows ]]; then
  flutter build windows --release --no-pub
fi
if [[ "$platform" == all || "$platform" == macos ]]; then
  [[ "$(uname -s)" == Darwin ]] || { echo 'macOS verification requires a macOS host.' >&2; exit 2; }
  MACOSX_DEPLOYMENT_TARGET=10.15 flutter build macos --release --no-pub
fi
if [[ "$platform" == all || "$platform" == ios ]]; then
  [[ "$(uname -s)" == Darwin ]] || { echo 'iOS verification requires a macOS host.' >&2; exit 2; }
  flutter build ios --release --no-codesign --no-pub
fi
printf 'Cross compile verification passed for %s\n' "$platform"
