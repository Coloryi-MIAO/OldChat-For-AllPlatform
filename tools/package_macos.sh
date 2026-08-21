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
export MACOSX_DEPLOYMENT_TARGET="10.15"
if [[ "$arch" == "arm64" ]]; then
  [[ "$(uname -m)" == "arm64" ]] || { echo 'macOS arm64 packaging requires an Apple Silicon runner.' >&2; exit 2; }
else
  [[ "$(uname -m)" == "x86_64" ]] || { echo 'macOS x64 packaging requires an Intel runner.' >&2; exit 2; }
fi
chmod +x tools/sign_apple_offline.sh
tools/sign_apple_offline.sh
flutter build macos --release
app="build/macos/Build/Products/Release/OldChatForAllPlatform.app"
[[ -d "$app" ]] || { echo "Flutter did not produce $app" >&2; exit 1; }
identity="${OLDCHAT_APPLE_SIGNING_IDENTITY:-OldChat For AllPlatform Offline Development}"
keychain="$root/signing/oldchat-offline.keychain-db"
security find-identity -v -p codesigning "$keychain" | grep -Fq "$identity" || {
  echo "Offline Apple signing identity not found: $identity" >&2
  exit 1
}
codesign --force --deep --timestamp=none --keychain "$keychain" --sign "$identity" "$app"
codesign --verify --deep --strict --verbose=2 "$app"
mkdir -p "$out"
codesign --display --verbose=2 "$app" > "$out/OldChatForAllPlatformmacos$arch.signing.txt" 2>&1
hdiutil create -volname 'OldChat For AllPlatform' -srcfolder "$app" -ov -format UDZO "$out/OldChatForAllPlatformmacos$arch.dmg"
printf 'macOS DMG: %s\n' "$out/OldChatForAllPlatformmacos$arch.dmg"
