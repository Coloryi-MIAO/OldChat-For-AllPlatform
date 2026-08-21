#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'Apple signing must run on macOS with Xcode.' >&2
  exit 2
fi

mode="${OLDCHAT_APPLE_SIGNING_MODE:-adhoc}"
if [[ "$mode" != "adhoc" ]]; then
  echo 'Only Apple ad hoc signing is supported for offline CI builds.' >&2
  echo 'A self-signed OpenSSL certificate is not a valid Apple iOS development identity.' >&2
  exit 2
fi

if ! command -v codesign >/dev/null 2>&1; then
  echo 'codesign is required for offline Apple signing.' >&2
  exit 2
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
signing_dir="${root}/signing"
mkdir -p "$signing_dir"

cat > "$signing_dir/apple-signing-mode.txt" <<MODE
mode=adhoc
certificate=none
network=offline
identity=-
MODE
chmod 644 "$signing_dir/apple-signing-mode.txt"
printf 'Apple offline signing mode: ad hoc\n'
printf 'Apple signing identity: -\n'
printf 'No keychain, certificate import, password, or network access is required.\n'
