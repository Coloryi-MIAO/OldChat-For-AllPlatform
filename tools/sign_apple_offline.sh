#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'Apple signing must run on macOS with Xcode.' >&2
  exit 2
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
signing_dir="${root}/signing"
password="${OLDCHATSIGNINGPASSWORD:-oldchatlocalbuild}"
identity="OldChat For AllPlatform Offline Development"
mkdir -p "$signing_dir"
key="$signing_dir/oldchat-apple.key"
cert="$signing_dir/oldchat-apple.crt"
csr="$signing_dir/oldchat-apple.csr"
p12="$signing_dir/oldchat-apple.p12"
if [[ ! -f "$p12" ]]; then
  openssl req -new -newkey rsa:4096 -nodes -keyout "$key" -out "$csr" \
    -subj "/C=CN/O=Coloryi-MIAO/OU=OldChat For AllPlatform/CN=$identity"
  openssl x509 -req -sha256 -days 36500 -in "$csr" -signkey "$key" -out "$cert" \
    -extfile <(printf 'basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=codeSigning\n')
  openssl pkcs12 -export -inkey "$key" -in "$cert" -out "$p12" \
    -name "$identity" -passout "pass:$password"
  chmod 600 "$key" "$p12"
  chmod 644 "$cert"
fi
security create-keychain -p "$password" oldchat-offline.keychain-db 2>/dev/null || true
security unlock-keychain -p "$password" oldchat-offline.keychain-db
security import "$p12" -k oldchat-offline.keychain-db -P "$password" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" oldchat-offline.keychain-db >/dev/null
security default-keychain -s oldchat-offline.keychain-db
security list-keychains -d user -s oldchat-offline.keychain-db
printf '%s\n' "$identity"
