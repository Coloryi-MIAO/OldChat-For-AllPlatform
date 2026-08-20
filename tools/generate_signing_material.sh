#!/usr/bin/env bash
set -euo pipefail

out_dir="${1:-signing}"
password="${OLDCHATSIGNINGPASSWORD:-}"
if [[ -z "$password" ]]; then
  password="oldchatlocalbuild"
fi
mkdir -p "$out_dir"
umask 077
openssl req -x509 -newkey rsa:4096 -sha256 -nodes \
  -keyout "$out_dir/oldchatrelease.key" \
  -out "$out_dir/oldchatrelease.crt" \
  -days 36500 \
  -subj "/C=CN/O=Coloryi-MIAO/OU=OldChat For AllPlatform/CN=OldChat For AllPlatform Release" \
  -addext "basicConstraints=critical,CA:FALSE" \
  -addext "keyUsage=critical,digitalSignature,keyEncipherment" \
  -addext "extendedKeyUsage=codeSigning" \
  -addext "subjectKeyIdentifier=hash"
openssl pkcs12 -export \
  -inkey "$out_dir/oldchatrelease.key" \
  -in "$out_dir/oldchatrelease.crt" \
  -out "$out_dir/oldchatrelease.p12" \
  -name oldchatrelease \
  -passout "pass:$password"
chmod 600 "$out_dir/oldchatrelease.key" "$out_dir/oldchatrelease.p12"
chmod 644 "$out_dir/oldchatrelease.crt"
printf 'Generated Coloryi-MIAO self-signed release material in %s\n' "$out_dir"
openssl x509 -in "$out_dir/oldchatrelease.crt" -noout -subject -dates -fingerprint -sha256
