#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
output="${1:-${root}/build/packages}"
app_dir="$(find "${root}/build/ios/iphoneos" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "${app_dir}" && -d "${app_dir}" ]] || { echo 'No iOS app found. Run flutter build ios --release --no-codesign first.' >&2; exit 1; }
if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --timestamp=none --sign - "$app_dir"
  codesign --verify --deep --strict "$app_dir"
fi
rm -rf "$output/iospayload" "$output/OldChatForAllPlatformiosadhoc.ipa"
mkdir -p "$output/iospayload/Payload"
cp -a "$app_dir" "$output/iospayload/Payload/"
(cd "$output/iospayload" && zip -qry "../OldChatForAllPlatformiosadhoc.ipa" Payload)
rm -rf "$output/iospayload"
echo "$output/OldChatForAllPlatformiosadhoc.ipa"
