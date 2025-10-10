#!/usr/bin/env bash
set -euo pipefail
DB="${1:-/data/bwdata/db.sqlite3}"
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "sqlite3 not installed" >&2
  exit 2
fi
if [[ ! -f "$DB" ]]; then
  echo "DB not found at $DB" >&2
  exit 1
fi
result=$(sqlite3 "$DB" 'PRAGMA integrity_check;')
echo "integrity_check: $result"
[[ "$result" == "ok" ]]
