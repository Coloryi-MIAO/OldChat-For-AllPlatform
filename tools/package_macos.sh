#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'macOS DMG packaging must run on a macOS host with Xcode.' >&2
  exit 2
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
arch="${1:-$(uname -m)}"
out="${2:-build/packages}"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"
case "$arch" in
  x64) [[ "$(uname -m)" == "x86_64" ]] || { echo 'macOS x64 packaging requires an Intel runner.' >&2; exit 2; } ;;
  arm64) [[ "$(uname -m)" == "arm64" ]] || { echo 'macOS arm64 packaging requires an Apple Silicon runner.' >&2; exit 2; } ;;
  *) echo 'Usage: tools/package_macos.sh x64|arm64 [output-directory]' >&2; exit 2 ;;
esac

chmod +x tools/sign_apple_offline.sh
tools/sign_apple_offline.sh
flutter build macos --release
app="build/macos/Build/Products/Release/OldChatForAllPlatform.app"
[[ -d "$app" ]] || { echo "Flutter did not produce $app" >&2; exit 1; }

codesign --remove-signature "$app" >/dev/null 2>&1 || true
codesign --force --deep --timestamp=none --sign - "$app"
codesign --verify --deep --strict --verbose=2 "$app"
codesign --display --verbose=2 "$app" >/dev/null
mkdir -p "$out"
codesign --display --verbose=2 "$app" > "$out/OldChatForAllPlatformmacos$arch.signing.txt" 2>&1
printf 'mode=adhoc\nidentity=-\ncertificate=none\n' >> "$out/OldChatForAllPlatformmacos$arch.signing.txt"
hdiutil create -volname 'OldChat For AllPlatform' -srcfolder "$app" -ov -format UDZO "$out/OldChatForAllPlatformmacos$arch.dmg"
printf 'macOS DMG: %s\n' "$out/OldChatForAllPlatformmacos$arch.dmg"
