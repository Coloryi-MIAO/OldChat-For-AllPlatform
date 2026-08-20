#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
dir="${1:-$root/signing}"
password="${OLDCHATSIGNINGPASSWORD:-oldchatlocalbuild}"
mkdir -p "$dir"
umask 077

if [[ -f "$dir/oldchatrelease.p12" && -f "$dir/oldchatrelease.pfx" && -f "$dir/oldchatrelease.crt" ]]; then
  exit 0
fi

config="$dir/openssl.cnf"
cat > "$config" <<'CONFIG'
[req]
distinguished_name = subject
x509_extensions = extensions
prompt = no
[subject]
C = CN
O = Coloryi-MIAO
OU = OldChat For AllPlatform
CN = OldChat For AllPlatform Offline Release
[extensions]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = codeSigning
CONFIG

openssl req -x509 -newkey rsa:4096 -sha256 -nodes -days 36500 \
  -keyout "$dir/oldchatrelease.key" \
  -out "$dir/oldchatrelease.crt" \
  -config "$config"
openssl pkcs12 -export -legacy \
  -out "$dir/oldchatrelease.p12" \
  -inkey "$dir/oldchatrelease.key" \
  -in "$dir/oldchatrelease.crt" \
  -name oldchatrelease \
  -passout "pass:$password"
cp "$dir/oldchatrelease.p12" "$dir/oldchatrelease.pfx"
chmod 600 "$dir/oldchatrelease.key" "$dir/oldchatrelease.p12" "$dir/oldchatrelease.pfx"
chmod 644 "$dir/oldchatrelease.crt"
rm -f "$config"
printf 'Generated offline self-signed release identity: Coloryi-MIAO / OldChat For AllPlatform Offline Release\n'
