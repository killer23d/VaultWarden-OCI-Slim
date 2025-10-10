#!/usr/bin/env bash
set -euo pipefail
KEY_FILE="${1:-backup/keys/encryption.key}"
mkdir -p "$(dirname "$KEY_FILE")"
if [[ -f "$KEY_FILE" ]]; then
  echo "Key already exists at $KEY_FILE"
  exit 0
fi
umask 077
openssl rand -base64 64 > "$KEY_FILE"
echo "Generated encryption key at $KEY_FILE"
echo "Set BACKUP_ENCRYPT=true and BACKUP_ENCRYPT_KEY_FILE=$KEY_FILE in settings.env"
