#!/usr/bin/env bash
set -euo pipefail
BACKUP_SCHEDULE="${BACKUP_SCHEDULE:-0 3 * * *}"
BACKUP_CMD="${BACKUP_CMD:-/usr/local/bin/db-backup.sh}"
echo "Schedule: ${BACKUP_SCHEDULE} | Command: ${BACKUP_CMD}"

if command -v crontab >/dev/null 2>&1; then
  CRON_LINE="${BACKUP_SCHEDULE} ${BACKUP_CMD}"
  echo "$CRON_LINE" | crontab -
  echo "Crontab installed"
  
  if command -v crond >/dev/null 2>&1; then
    crond -f -l 8
  fi
else
  echo "crontab not found"
fi
