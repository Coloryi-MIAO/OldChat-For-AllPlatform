#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo 'Apple signing must run on macOS with Xcode.' >&2
  exit 2
fi
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
signing_dir="${root}/signing"
keychain_password="${OLDCHAT_APPLE_KEYCHAIN_PASSWORD:-oldchatlocalbuild}"
identity="${OLDCHAT_APPLE_SIGNING_IDENTITY:-OldChat For AllPlatform Offline Development}"
mkdir -p "$signing_dir"
key="$signing_dir/oldchat-apple.key"
cert="$signing_dir/oldchat-apple.crt"
csr="$signing_dir/oldchat-apple.csr"
rm -f "$key" "$cert" "$csr"
openssl genrsa -traditional -out "$key" 2048
openssl req -new -sha256 -key "$key" -out "$csr" \
  -subj "/C=CN/O=Coloryi-MIAO/OU=OldChat For AllPlatform/CN=$identity"
extensions="$signing_dir/oldchat-apple.extensions"
cat > "$extensions" <<'EXTENSIONS'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
EXTENSIONS
openssl x509 -req -sha256 -days 36500 \
  -in "$csr" -signkey "$key" \
  -out "$cert" -extfile "$extensions"
rm -f "$extensions" "$csr"
chmod 600 "$key"
chmod 644 "$cert"

keychain="$signing_dir/oldchat-offline.keychain-db"
security delete-keychain "$keychain" 2>/dev/null || true
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$key" -k "$keychain" -f pemseq -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security import "$cert" -k "$keychain" -f x509 -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security add-trusted-cert -d -r trustRoot -k "$keychain" "$cert" >/dev/null 2>&1 || true
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
security default-keychain -s "$keychain"
security list-keychains -d user -s "$keychain"
if ! security find-identity -v -p codesigning "$keychain" 2>/dev/null | grep -Fq "$identity"; then
  security find-identity -v -p codesigning "$keychain" >&2 || true
  echo "Offline Apple signing identity was not installed: $identity" >&2
  exit 1
fi
printf '%s\n' "$identity"
