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
extensions="$signing_dir/oldchat-apple.extensions"
keychain="$signing_dir/oldchat-offline.keychain-db"

run_security() {
  local seconds="$1"
  shift
  "$@" &
  local pid=$!
  local elapsed=0
  while kill -0 "$pid" 2>/dev/null; do
    if (( elapsed >= seconds )); then
      kill -TERM "$pid" 2>/dev/null || true
      sleep 1
      kill -KILL "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      echo "Timed out after ${seconds}s: $*" >&2
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid"
}

rm -f "$key" "$cert" "$csr" "$extensions" "$signing_dir/identities.txt"
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:4096 -out "$key"
openssl pkey -in "$key" -passin pass: -noout
openssl req -new -sha256 -key "$key" -passin pass: -out "$csr" \
  -subj "/C=CN/O=Coloryi-MIAO/OU=OldChat For AllPlatform/CN=$identity"
cat > "$extensions" <<'EXTENSIONS'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
EXTENSIONS
openssl x509 -req -sha256 -days 36500 \
  -in "$csr" -signkey "$key" -passin pass: \
  -out "$cert" -extfile "$extensions"
rm -f "$csr" "$extensions"
chmod 600 "$key"
chmod 644 "$cert"

run_security 10 security delete-keychain "$keychain" >/dev/null 2>&1 || true
run_security 10 security create-keychain -p "$keychain_password" "$keychain"
run_security 10 security set-keychain-settings -lut 21600 "$keychain"
run_security 10 security unlock-keychain -p "$keychain_password" "$keychain"

if ! run_security 15 security import "$key" -k "$keychain" -f pem -t priv -A >/dev/null 2>&1; then
  echo 'Private-key import failed.' >&2
  exit 1
fi
if ! run_security 15 security import "$cert" -k "$keychain" -f pem -t cert -A >/dev/null 2>&1; then
  echo 'Certificate import failed.' >&2
  exit 1
fi

run_security 10 security add-trusted-cert -d -r trustRoot -k "$keychain" "$cert" >/dev/null 2>&1 || true
run_security 10 security default-keychain -s "$keychain" >/dev/null 2>&1
run_security 10 security list-keychains -d user -s "$keychain" >/dev/null 2>&1

if ! run_security 15 security find-identity -v -p codesigning "$keychain" > "$signing_dir/identities.txt" 2>/dev/null; then
  echo 'Could not query the offline Apple signing identity.' >&2
  exit 1
fi
if ! grep -Fq "$identity" "$signing_dir/identities.txt"; then
  cat "$signing_dir/identities.txt" >&2 || true
  echo "Offline Apple signing identity was not installed: $identity" >&2
  exit 1
fi
rm -f "$signing_dir/identities.txt"
printf '%s\n' "$identity"
