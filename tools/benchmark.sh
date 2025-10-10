#!/usr/bin/env bash
# benchmark.sh - VaultWarden SQLite benchmark/health script (fail-fast, no fallbacks)
# Purpose:
# - Validate SQLite DB presence and basic health
# - Report size, WAL size, freelist/fragmentation
# - Enforce thresholds via env/settings.env
# Exits non-zero when thresholds are breached or required inputs are missing.

set -euo pipefail
IFS=$'\n\t'

# -------------- Logging --------------
log_info()  { echo "[INFO] $*"; }
log_warn()  { echo "[WARN] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
die()       { log_error "$*"; exit 1; }

# -------------- Defaults and env --------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

SETTINGS_FILE="${SETTINGS_FILE:-$REPO_ROOT/settings.env}"

# Load settings.env if present (fail-fast only if explicitly requested)
if [[ -f "$SETTINGS_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$SETTINGS_FILE"
  set +a
fi

# Default paths (can be overridden by flags or env)
DEFAULT_DB_PATH="$REPO_ROOT/data/bwdata/db.sqlite3"
DEFAULT_DATA_DIR="$REPO_ROOT/data/bwdata"

SQLITE_DB_PATH="${SQLITE_DB_PATH:-$DEFAULT_DB_PATH}"
VAULTWARDEN_DATA_DIR="${VAULTWARDEN_DATA_DIR:-$DEFAULT_DATA_DIR}"

# Thresholds (align with monitoring env; safe defaults)
SQLITE_SIZE_ALERT_MB="${SQLITE_SIZE_ALERT_MB:-100}"
WAL_SIZE_ALERT_MB="${WAL_SIZE_ALERT_MB:-10}"
FRAGMENTATION_ALERT_RATIO="${FRAGMENTATION_ALERT_RATIO:-1.5}"
FREELIST_ALERT_THRESHOLD="${FREELIST_ALERT_THRESHOLD:-15}"  # percent

# -------------- CLI parsing --------------
JSON_OUTPUT=false
QUICK=false
DB_OVERRIDE=""
DATA_DIR_OVERRIDE=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --db PATH           Path to SQLite DB (default: $SQLITE_DB_PATH)
  --data-dir PATH     Vaultwarden data dir (default: $VAULTWARDEN_DATA_DIR)
  --json              Output JSON
  --quick             Skip intensive checks (pragma optimize, integrity)
  -h, --help          Show this help

Env/Settings respected if set:
  SQLITE_DB_PATH, VAULTWARDEN_DATA_DIR
  SQLITE_SIZE_ALERT_MB, WAL_SIZE_ALERT_MB, FRAGMENTATION_ALERT_RATIO, FREELIST_ALERT_THRESHOLD
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --db) DB_OVERRIDE="${2:-}"; shift 2 ;;
    --data-dir) DATA_DIR_OVERRIDE="${2:-}"; shift 2 ;;
    --json) JSON_OUTPUT=true; shift ;;
    --quick) QUICK=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown option: $1. Use --help";;
  esac
done

if [[ -n "$DB_OVERRIDE" ]]; then
  SQLITE_DB_PATH="$DB_OVERRIDE"
fi
if [[ -n "$DATA_DIR_OVERRIDE" ]]; then
  VAULTWARDEN_DATA_DIR="$DATA_DIR_OVERRIDE"
fi

# Derive WAL path (SQLite WAL is dbfile-wal)
WAL_PATH="${SQLITE_DB_PATH}-wal"

# -------------- Preconditions (fail-fast) --------------
command -v sqlite3 >/dev/null 2>&1 || die "sqlite3 is required but not found in PATH"

[[ -f "$SQLITE_DB_PATH" ]] || die "SQLite DB not found at: $SQLITE_DB_PATH"
[[ -d "$VAULTWARDEN_DATA_DIR" ]] || log_warn "Data dir not found: $VAULTWARDEN_DATA_DIR (continuing)"

# -------------- Helpers --------------
bytes_to_mb() {
  # usage: bytes_to_mb <bytes>
  awk 'BEGIN { printf "%.2f", '"${1}"' / 1024 / 1024 }'
}

json_escape() {
  # naive escaper for simple strings
  echo -n "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))'
}

# -------------- Collect metrics --------------
DB_SIZE_BYTES=$(stat -c%s "$SQLITE_DB_PATH")
DB_SIZE_MB=$(bytes_to_mb "$DB_SIZE_BYTES")

WAL_EXISTS=false
WAL_SIZE_BYTES=0
WAL_SIZE_MB=0.00
if [[ -f "$WAL_PATH" ]]; then
  WAL_EXISTS=true
  WAL_SIZE_BYTES=$(stat -c%s "$WAL_PATH")
  WAL_SIZE_MB=$(bytes_to_mb "$WAL_SIZE_BYTES")
fi

# Get page stats from sqlite
# Outputs: page_count|freelist_count|page_size
PRAGMA_OUT=$(sqlite3 "$SQLITE_DB_PATH" "SELECT (SELECT pragma_page_count()), (SELECT pragma_freelist_count()), (SELECT pragma_page_size());")
# The output may be "page_count|freelist|page_size"
IFS='|' read -r PAGE_COUNT FREE_COUNT PAGE_SIZE <<< "$PRAGMA_OUT"

# Fallback sanity if empty (shouldn't happen with a valid DB)
[[ -n "${PAGE_COUNT:-}" && -n "${FREE_COUNT:-}" && -n "${PAGE_SIZE:-}" ]] || die "Failed to read PRAGMA stats from DB"

# Compute ratios
FRAG_RATIO="0.00"
FREE_PCT="0.00"
if [[ "$PAGE_COUNT" -gt 0 ]]; then
  FRAG_RATIO=$(awk 'BEGIN { printf "%.2f", '"$FREE_COUNT"' / '"$PAGE_COUNT"' }')
  FREE_PCT=$(awk 'BEGIN { printf "%.2f", (('"$FREE_COUNT"' / '"$PAGE_COUNT"') * 100) }')
fi

# Optional deeper checks unless --quick
INTEGRITY_RESULT="skipped"
ANALYZE_SUGGESTED=false

if [[ "$QUICK" == "false" ]]; then
  # Lightweight integrity check
  INTEGRITY_RESULT=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA quick_check;" | head -n1)
  # Heuristic: suggest ANALYZE/REINDEX if fragmentation high
  awk -v r="$FRAG_RATIO" 'BEGIN { exit (r > 1.0 ? 0 : 1) }' && ANALYZE_SUGGESTED=true || ANALYZE_SUGGESTED=false
fi

# -------------- Threshold evaluation --------------
VIOLATIONS=()

# DB size
awk -v sz="$DB_SIZE_MB" -v th="$SQLITE_SIZE_ALERT_MB" 'BEGIN { exit (sz > th ? 0 : 1) }' \
  && VIOLATIONS+=("Database size ${DB_SIZE_MB}MB exceeds threshold ${SQLITE_SIZE_ALERT_MB}MB")

# WAL size (only if WAL exists)
if [[ "$WAL_EXISTS" == "true" ]]; then
  awk -v sz="$WAL_SIZE_MB" -v th="$WAL_SIZE_ALERT_MB" 'BEGIN { exit (sz > th ? 0 : 1) }' \
    && VIOLATIONS+=("WAL size ${WAL_SIZE_MB}MB exceeds threshold ${WAL_SIZE_ALERT_MB}MB")
fi

# Fragmentation ratio
awk -v r="$FRAG_RATIO" -v th="$FRAGMENTATION_ALERT_RATIO" 'BEGIN { exit (r > th ? 0 : 1) }' \
  && VIOLATIONS+=("Fragmentation ratio ${FRAG_RATIO} exceeds ${FRAGMENTATION_ALERT_RATIO}")

# Free list percent
awk -v p="$FREE_PCT" -v th="$FREELIST_ALERT_THRESHOLD" 'BEGIN { exit (p > th ? 0 : 1) }' \
  && VIOLATIONS+=("Freelist percent ${FREE_PCT}% exceeds ${FREELIST_ALERT_THRESHOLD}%")

STATUS="ok"
EXIT_CODE=0
if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
  STATUS="alert"
  EXIT_CODE=2
fi

# -------------- Output --------------
if [[ "$JSON_OUTPUT" == "true" ]]; then
  # Build minimal JSON
  echo -n '{'
  echo -n "\"db_path\":$(json_escape "$SQLITE_DB_PATH"),"
  echo -n "\"db_size_mb\":$DB_SIZE_MB,"
  echo -n "\"wal_path\":$(json_escape "$WAL_PATH"),"
  echo -n "\"wal_exists\":$([[ "$WAL_EXISTS" == "true" ]] && echo -n true || echo -n false),"
  echo -n "\"wal_size_mb\":$WAL_SIZE_MB,"
  echo -n "\"page_count\":$PAGE_COUNT,"
  echo -n "\"freelist_count\":$FREE_COUNT,"
  echo -n "\"page_size\":$PAGE_SIZE,"
  echo -n "\"fragmentation_ratio\":$FRAG_RATIO,"
  echo -n "\"freelist_percent\":$FREE_PCT,"
  echo -n "\"integrity\":$(json_escape "$INTEGRITY_RESULT"),"
  echo -n "\"thresholds\":{"
  echo -n "\"SQLITE_SIZE_ALERT_MB\":$SQLITE_SIZE_ALERT_MB,"
  echo -n "\"WAL_SIZE_ALERT_MB\":$WAL_SIZE_ALERT_MB,"
  echo -n "\"FRAGMENTATION_ALERT_RATIO\":$FRAGMENTATION_ALERT_RATIO,"
  echo -n "\"FREELIST_ALERT_THRESHOLD\":$FREELIST_ALERT_THRESHOLD"
  echo -n "},"
  echo -n "\"status\":$(json_escape "$STATUS"),"
  printf '"violations":['
  if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    for i in "${!VIOLATIONS[@]}"; do
      printf '%s' "$(json_escape "${VIOLATIONS[$i]}")"
      [[ $i -lt $((${#VIOLATIONS[@]} - 1)) ]] && printf ','
    done
  fi
  echo ']}'
else
  echo "SQLite Health Report"
  echo "--------------------"
  echo "DB:           $SQLITE_DB_PATH"
  echo "Size (MB):    $DB_SIZE_MB (threshold: ${SQLITE_SIZE_ALERT_MB}MB)"
  echo "WAL:          $WAL_PATH (exists: $WAL_EXISTS)"
  echo "WAL size (MB): $WAL_SIZE_MB (threshold: ${WAL_SIZE_ALERT_MB}MB)"
  echo "Pages:        $PAGE_COUNT (size: ${PAGE_SIZE} bytes)"
  echo "Freelist:     $FREE_COUNT (${FREE_PCT}%)"
  echo "Fragmentation ratio: $FRAG_RATIO (threshold: ${FRAGMENTATION_ALERT_RATIO})"
  echo "Integrity:    $INTEGRITY_RESULT"
  $ANALYZE_SUGGESTED && echo "Suggestion:   Consider VACUUM/ANALYZE if fragmentation is persistently high."
  if [[ ${#VIOLATIONS[@]} -gt 0 ]]; then
    echo ""
    echo "ALERTS:"
    for v in "${VIOLATIONS[@]}"; do
      echo " - $v"
    done
  fi
  echo ""
  echo "Status: $STATUS"
fi

exit "$EXIT_CODE"
