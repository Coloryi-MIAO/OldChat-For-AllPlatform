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
  if openssl pkcs12 -help 2>&1 | grep -q -- '-legacy'; then
    openssl pkcs12 -export -inkey "$key" -in "$cert" -out "$p12" \
      -name "$identity" -passout "pass:$password" -legacy
  else
    openssl pkcs12 -export -inkey "$key" -in "$cert" -out "$p12" \
      -name "$identity" -passout "pass:$password"
  fi
  chmod 600 "$key" "$p12"
  chmod 644 "$cert"
fi
keychain="$signing_dir/oldchat-offline.keychain-db"
security create-keychain -p "$password" "$keychain" 2>/dev/null || true
security unlock-keychain -p "$password" "$keychain"
security import "$p12" -k "$keychain" -P "$password" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$password" "$keychain" >/dev/null
security default-keychain -s "$keychain"
security list-keychains -d user -s "$keychain"
printf '%s\n' "$identity"
