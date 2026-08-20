#!/usr/bin/env bash
set -euo pipefail
OUTPUT="${1:?usage: sign_linux.sh <package-dir>}"
GNUPGHOME="${OUTPUT}/gnupg"
export GNUPGHOME
mkdir -m 700 -p "$GNUPGHOME"
cat > "$OUTPUT/gpg-batch" <<KEY
Key-Type: RSA
Key-Length: 4096
Name-Real: OldChat For AllPlatform Release
Name-Email: release@oldchat.local
Expire-Date: 0
Key-Usage: sign
%no-protection
%commit
KEY
gpg --batch --generate-key "$OUTPUT/gpg-batch" >/dev/null
gpg --armor --export 'OldChat For AllPlatform Release' > "$OUTPUT/OldChatForAllPlatform-release-public-key.asc"
find "$OUTPUT" -maxdepth 1 -type f \( -name '*.deb' -o -name '*.rpm' \) -print0 | while IFS= read -r -d '' file; do gpg --batch --yes --armor --detach-sign --local-user 'OldChat For AllPlatform Release' "$file"; done
rm -f "$OUTPUT/gpg-batch"
printf 'Linux package signatures: %s\n' "$OUTPUT"
