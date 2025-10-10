#!/usr/bin/env bash
set -euo pipefail

RED='\033[31m'; YLW='\033[33m'; GRN='\033[32m'; NC='\033[0m'

note() { echo -e "${YLW}WARN:${NC} $*"; }
ok() { echo -e "${GRN}OK:${NC} $*"; }
err() { echo -e "${RED}ERROR:${NC} $*"; }

# Load environment if available
ENV_FILE=""
for f in ./settings.env ./settings.env.example; do
  if [[ -f "$f" ]]; then
    ENV_FILE="$f"
    break
  fi
done

if [[ -n "$ENV_FILE" ]]; then
  set -a
  source "$ENV_FILE"
  set +a
  ok "Loaded environment from $ENV_FILE"
else
  note "No settings.env found"
fi

# Check required commands
for cmd in grep awk sed df; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Missing command: $cmd"
    exit 2
  fi
done

# Domain validation
DOMAIN_CAND="${DOMAIN:-${APP_DOMAIN:-}}"
if [[ -z "$DOMAIN_CAND" ]]; then
  note "DOMAIN/APP_DOMAIN not set"
else
  if [[ "$DOMAIN_CAND" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
    ok "Domain appears valid: $DOMAIN_CAND"
  else
    err "Domain looks invalid: $DOMAIN_CAND"
  fi
fi

# SMTP validation
if [[ -n "${SMTP_HOST:-}" ]]; then
  [[ -n "${SMTP_FROM:-}" ]] || err "SMTP_FROM missing"
  [[ -n "${SMTP_USERNAME:-}" ]] || note "SMTP_USERNAME not set"
  [[ -n "${SMTP_PASSWORD:-}" ]] || note "SMTP_PASSWORD not set"
  ok "SMTP configuration checked"
else
  note "SMTP not configured"
fi

# Disk space checks
check_space() {
  local path="$1" label="$2"
  mkdir -p "$path" || true
  local free_gb
  if command -v df >/dev/null 2>&1; then
    free_gb=$(df -BG "$path" | awk 'NR==2{gsub("G","",$4); print $4}' || echo "unknown")
    if [[ "$free_gb" != "unknown" && "$free_gb" =~ ^[0-9]+$ ]]; then
      if (( free_gb < 2 )); then
        err "$label low free space (${free_gb}G)"
      else
        ok "$label free space: ${free_gb}G"
      fi
    else
      note "Could not determine free space for $path"
    fi
  fi
}

check_space "./data/bwdata" "Data dir"
check_space "./data/backups" "Backup dir"

# Backup validation
if grep -q "backup" docker-compose.yml; then
  if [[ ! -f ./backup/config/rclone.conf ]]; then
    note "backup/config/rclone.conf missing"
  else
    ok "rclone.conf found"
  fi
fi

# Fail2ban validation
if grep -q "fail2ban" docker-compose.yml; then
  [[ -f fail2ban/filter.d/vaultwarden.conf ]] && ok "fail2ban filter OK" || err "fail2ban filter missing"
  [[ -f fail2ban/jail.d/vaultwarden.local ]] && ok "fail2ban jail OK" || err "fail2ban jail missing"
fi

# SQLite validation
if [[ -f "./data/bwdata/db.sqlite3" ]]; then
  ok "Found SQLite DB at ./data/bwdata/db.sqlite3"
else
  note "SQLite DB not found (first run?)"
fi

echo
echo "Validation complete."
