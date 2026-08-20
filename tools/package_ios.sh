#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'iOS IPA packaging must run on a macOS host with Xcode.' >&2
  exit 2
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
out="${1:-build/packages}"
if [[ -n "${IOSEXPORTOPTIONSPLIST:-}" ]]; then
  flutter build ipa --release --export-options-plist "$IOSEXPORTOPTIONSPLIST"
else
  flutter build ios --release --no-codesign
  tools/package_ios_unsigned.sh "$out"
fi
mkdir -p "$out"
find build/ios/ipa -maxdepth 1 -name '*.ipa' -exec cp {} "$out/" \; 2>/dev/null || true
printf 'iOS IPA output: %s\n' "$out"
