#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR="${1:-/backups}"
TMP_DIR=$(mktemp -d)
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

latest=$(ls -1t "$BACKUP_DIR" 2>/dev/null | head -n1 || echo "")
if [[ -z "$latest" ]]; then
  echo "No backups found in $BACKUP_DIR"
  exit 1
fi

path="$BACKUP_DIR/$latest"
echo "Verifying $path"

case "$path" in
  *.sqlite3|*.db)
    sqlite3 "$path" 'PRAGMA integrity_check;' | grep -q "ok"
    ;;
  *.tar.gz|*.tgz)
    tar -tzf "$path" >/dev/null
    tar -xzf "$path" -C "$TMP_DIR"
    db=$(find "$TMP_DIR" -name 'db.sqlite3' | head -n1)
    [[ -f "$db" ]] && sqlite3 "$db" 'PRAGMA integrity_check;' | grep -q "ok"
    ;;
  *)
    echo "Unsupported backup format: $path"
    exit 1
    ;;
esac

echo "Backup verification passed"
