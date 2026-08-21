#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-${root}/build/packages}"
app_dir="$(find "${root}/build/ios/iphoneos" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "${app_dir}" && -d "${app_dir}" ]] || { echo 'No iOS app found. Run flutter build ios --release --no-codesign first.' >&2; exit 1; }
identity="${OLDCHAT_APPLE_SIGNING_IDENTITY:-OldChat For AllPlatform Offline Development}"
rm -rf "$output/iospayload" "$output/OldChatForAllPlatformiosdevelopment.ipa" "$output/OldChatForAllPlatformiosdevelopment.signing.txt"
mkdir -p "$output/iospayload/Payload"
if command -v codesign >/dev/null 2>&1; then
  security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$identity\"" || {
    echo "Offline Apple signing identity not found: $identity" >&2
    exit 1
  }
  codesign --force --deep --timestamp=none --sign "$identity" "$app_dir"
  codesign --verify --deep --strict --verbose=2 "$app_dir"
  codesign --display --verbose=2 "$app_dir" > "$output/OldChatForAllPlatformiosdevelopment.signing.txt" 2>&1
else
  echo 'codesign is required to produce a signed iOS IPA.' >&2
  exit 2
fi
cp -a "$app_dir" "$output/iospayload/Payload/"
(cd "$output/iospayload" && zip -qry "../OldChatForAllPlatformiosdevelopment.ipa" Payload)
rm -rf "$output/iospayload"
echo "$output/OldChatForAllPlatformiosdevelopment.ipa"
