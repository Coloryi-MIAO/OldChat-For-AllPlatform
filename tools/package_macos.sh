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
flutter build macos --release
app="build/macos/Build/Products/Release/OldChatForAllPlatform.app"
[[ -d "$app" ]] || { echo "Flutter did not produce $app" >&2; exit 1; }
mkdir -p "$out"
hdiutil create -volname 'OldChat For AllPlatform' -srcfolder "$app" -ov -format UDZO "$out/OldChatForAllPlatformmacos$arch.dmg"
printf 'macOS DMG: %s\n' "$out/OldChatForAllPlatformmacos$arch.dmg"
