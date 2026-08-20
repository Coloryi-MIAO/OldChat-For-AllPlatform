#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SIGNING_DIR="${ROOT}/signing"
STORE="${SIGNING_DIR}/oldchatrelease.p12"
PROPS="${SIGNING_DIR}/signing.properties"
PASSWORD="${OLDCHATANDROIDSTOREPASSWORD:-oldchatlocalbuild}"
ALIAS="${OLDCHATANDROIDKEYALIAS:-oldchatrelease}"

mkdir -p "${SIGNING_DIR}"
if ! command -v keytool >/dev/null 2>&1; then
  printf '%s\n' 'keytool is required. Install a JDK 17+ before generating Android signing material.' >&2
  exit 1
fi

if [[ ! -f "${STORE}" ]]; then
  keytool -genkeypair -v \
    -keystore "${STORE}" \
    -storetype PKCS12 \
    -storepass "${PASSWORD}" \
    -keypass "${PASSWORD}" \
    -alias "${ALIAS}" \
    -keyalg RSA \
    -keysize 4096 \
    -validity 36500 \
    -dname 'CN=OldChat For AllPlatform Release, OU=OldChat, O=Coloryi-MIAO, L=Earth, ST=Earth, C=CN'
fi

cat > "${PROPS}" <<PROPERTIES
storeFile=${STORE}
storePassword=${PASSWORD}
keyAlias=${ALIAS}
keyPassword=${PASSWORD}
PROPERTIES
chmod 600 "${STORE}" "${PROPS}"
printf 'Android signing material: %s\n' "${STORE}"
