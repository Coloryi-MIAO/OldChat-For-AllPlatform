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
p12_password="${OLDCHAT_APPLE_P12_PASSWORD:-oldchatlocalbuild}"
mkdir -p "$signing_dir"
root_key="$signing_dir/oldchat-offline-root.key"
root_cert="$signing_dir/oldchat-offline-root.crt"
root_csr="$signing_dir/oldchat-offline-root.csr"
root_extensions="$signing_dir/oldchat-offline-root.extensions"
key="$signing_dir/oldchat-apple.key"
cert="$signing_dir/oldchat-apple.crt"
csr="$signing_dir/oldchat-apple.csr"
extensions="$signing_dir/oldchat-apple.extensions"
p12="$signing_dir/oldchat-apple.p12"
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

rm -f "$root_key" "$root_cert" "$root_csr" "$root_extensions" "$key" "$cert" "$csr" "$extensions" "$p12" "$signing_dir/identities.txt" "$signing_dir/import-error.txt"
openssl genrsa -out "$root_key" 4096 >/dev/null 2>&1
openssl req -new -sha256 -key "$root_key" -passin pass: -out "$root_csr" \
  -subj "/C=CN/O=Coloryi-MIAO/OU=OldChat For AllPlatform/CN=$identity Offline Root CA"
cat > "$root_extensions" <<'EXTENSIONS'
basicConstraints=critical,CA:TRUE,pathlen:1
keyUsage=critical,keyCertSign,cRLSign
subjectKeyIdentifier=hash
EXTENSIONS
openssl x509 -req -sha256 -days 36500 \
  -in "$root_csr" -signkey "$root_key" -passin pass: \
  -out "$root_cert" -extfile "$root_extensions" >/dev/null
openssl genrsa -out "$key" 4096 >/dev/null 2>&1
openssl rsa -in "$key" -passin pass: -check -noout >/dev/null
openssl req -new -sha256 -key "$key" -passin pass: -out "$csr" \
  -subj "/C=CN/O=Coloryi-MIAO/OU=OldChat For AllPlatform/CN=$identity"
cat > "$extensions" <<'EXTENSIONS'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
subjectKeyIdentifier=hash
authorityKeyIdentifier=keyid,issuer
EXTENSIONS
openssl x509 -req -sha256 -days 36500 \
  -in "$csr" -CA "$root_cert" -CAkey "$root_key" -passin pass: -CAcreateserial \
  -out "$cert" -extfile "$extensions" >/dev/null
openssl verify -CAfile "$root_cert" "$cert" >/dev/null
openssl pkcs12 -export -out "$p12" -inkey "$key" -in "$cert" -certfile "$root_cert" \
  -passout "pass:${p12_password}" \
  -macalg sha1 \
  -keypbe PBE-SHA1-3DES \
  -certpbe PBE-SHA1-3DES \
  -name "$identity" >/dev/null
rm -f "$root_csr" "$root_extensions" "$csr" "$extensions" "$signing_dir/oldchat-offline-root.srl"
chmod 600 "$root_key" "$key" "$p12"
chmod 644 "$root_cert" "$cert"

run_security 60 security delete-keychain "$keychain" >/dev/null 2>&1 || true
run_security 60 security create-keychain -p "$keychain_password" "$keychain"
run_security 60 security set-keychain-settings -lut 21600 "$keychain"
run_security 60 security unlock-keychain -p "$keychain_password" "$keychain"

security import "$root_cert" -k "$keychain" -f pem -A > "$signing_dir/import-error.txt" 2>&1 || true
if ! run_security 60 security import "$p12" -k "$keychain" -f pkcs12 -P "$p12_password" -A > "$signing_dir/import-error.txt" 2>&1; then
  cat "$signing_dir/import-error.txt" >&2 || true
  echo 'Private-key and certificate import failed.' >&2
  exit 1
fi
rm -f "$signing_dir/import-error.txt"

run_security 60 security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$keychain_password" "$keychain" >/dev/null 2>&1 || true
run_security 60 security list-keychains -d user -s "$keychain" login.keychain-db >/dev/null 2>&1 || true
run_security 60 security default-keychain -s "$keychain" >/dev/null 2>&1 || true

if ! run_security 60 security find-identity -v -p codesigning > "$signing_dir/identities.txt" 2>/dev/null; then
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
