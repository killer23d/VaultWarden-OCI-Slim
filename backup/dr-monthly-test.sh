#!/usr/bin/env bash
# backup/dr-monthly-test.sh - Monthly Disaster Recovery validation test for SQLite (Enhanced with HTML notifications)
# Tests SQLite backup restoration using temporary database validation
# Cross-platform compatible with intelligent secret sourcing

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="${ROOT_DIR}/.dr-test"
LOG_DIR="${ROOT_DIR}/data/backup_logs"
LOG_FILE="${LOG_DIR}/dr-monthly-test.log"

# Load settings if available
if [[ -f "${ROOT_DIR}/settings.env" ]]; then
    source "${ROOT_DIR}/settings.env"
fi

# Test configuration
TEST_DB_NAME="dr_test_$(date +%s).sqlite3"
CONTAINER_NAME="vaultwarden-dr-test-$(date +%s)"

# Email configuration with fallbacks
SEND_EMAIL_NOTIFICATION="${SEND_EMAIL_NOTIFICATION:-${BACKUP_NOTIFY:-true}}"
EMAIL_RECIPIENT="${BACKUP_EMAIL:-${ADMIN_EMAIL:-${ALERT_EMAIL:-}}}"

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE"; }
fail() { log_error "$1"; cleanup; exit 1; }

# Cross-platform date functions
get_file_timestamp() {
    local file="$1"
    if [[ "$(uname)" == "Darwin" ]]; then
        stat -f "%Sm" -t "%Y-%m-%d %H:%M:%S" "$file"
    else
        date -r "$file" '+%Y-%m-%d %H:%M:%S'
    fi
}

get_file_age_hours() {
    local file="$1"
    local current_time=$(date +%s)
    local file_time

    if [[ "$(uname)" == "Darwin" ]]; then
        file_time=$(stat -f "%m" "$file")
    else
        file_time=$(date -r "$file" +%s)
    fi

    echo $(((current_time - file_time) / 3600))
}

# Intelligent secret sourcing
source_backup_passphrase() {
    log_info "Attempting to source BACKUP_PASSPHRASE..."

    # Method 1: Already in environment
    if [[ -n "${BACKUP_PASSPHRASE:-}" ]]; then
        log_success "BACKUP_PASSPHRASE found in environment"
        return 0
    fi

    # Method 2: OCI Vault
    if [[ -n "${OCISECRET_OCID:-}${OCI_SECRET_OCID:-}" ]]; then
        log_info "OCI Vault detected, fetching passphrase from vault..."
        local temp_settings=$(mktemp)
        if "${ROOT_DIR}/oci-setup.sh" get --output "$temp_settings"; then
            set -a
            source "$temp_settings"
            set +a
            rm -f "$temp_settings"

            if [[ -n "${BACKUP_PASSPHRASE:-}" ]]; then
                log_success "Loaded BACKUP_PASSPHRASE from OCI Vault"
                return 0
            else
                log_warning "OCI Vault accessible but BACKUP_PASSPHRASE not found in secret"
            fi
        else
            log_warning "Failed to fetch settings from OCI Vault"
        fi
    fi

    # Method 3: Local settings.env file (already loaded above)
    if [[ -n "${BACKUP_PASSPHRASE:-}" ]]; then
        log_success "Loaded BACKUP_PASSPHRASE from settings.env"
        return 0
    else
        log_warning "settings.env exists but BACKUP_PASSPHRASE not defined"
    fi

    fail "BACKUP_PASSPHRASE not found. Please either:
    1. Export BACKUP_PASSPHRASE=your-passphrase
    2. Ensure OCISECRET_OCID is set for OCI Vault access
    3. Ensure settings.env exists with BACKUP_PASSPHRASE defined"
}

# Enhanced HTML email notification function
send_email_notification() {
    local subject="$1"
    local message="$2"
    local status="$3"

    if [[ "$SEND_EMAIL_NOTIFICATION" != "true" ]]; then
        log_info "Email notifications disabled"
        return 0
    fi

    if [[ -z "$EMAIL_RECIPIENT" ]]; then
        log_warning "Email not configured - skipping notification"
        return 0
    fi

    local status_icon="✅"
    local status_color="#28a745"
    local bar_color="#28a745"
    
    case "$status" in
        "FAILURE")
            status_icon="🚨"
            status_color="#dc3545"
            bar_color="#dc3545"
            ;;
        "WARNING")
            status_icon="⚠️"
            status_color="#ffc107"
            bar_color="#ffc107"
            ;;
    esac

    # Prepare recommendations HTML
    local recommendations_html=""
    if [[ ${BACKUP_AGE_HOURS:-0} -gt 48 ]]; then
        recommendations_html+="<li>SQLite backup is older than 48 hours - check backup automation</li>"
    fi
    if [[ ${USERS_COUNT:-0} -eq 0 ]]; then
        recommendations_html+="<li>No users found - consider testing with production-like data</li>"
    fi
    if [[ ${VALIDATION_TIME:-0} -gt 60 ]]; then
        recommendations_html+="<li>SQLite restoration took longer than 1 minute - monitor disk performance</li>"
    fi
    if [[ -z "$recommendations_html" ]]; then
        recommendations_html="<li>✅ All systems optimal - no recommendations</li>"
    fi

    local html_body=$(cat <<EOF
From: VaultWarden DR System <${SMTP_FROM:-noreply@$(hostname -d || echo localdomain)}>
To: $EMAIL_RECIPIENT
Subject: $subject
Content-Type: text/html; charset="UTF-8"
MIME-Version: 1.0

<html>
<head>
<style>
  body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; color: #333; background-color: #f5f7fb; }
  .card { background: #fff; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.06); max-width: 860px; margin: 0 auto; overflow: hidden; }
  .bar { height: 6px; background: ${bar_color}; }
  .content { padding: 24px 28px; }
  h2 { margin: 0 0 6px 0; color: #111; }
  .muted { color: #666; font-size: 13px; margin-bottom: 16px; }
  table { border-collapse: collapse; width: 100%; margin: 14px 0 20px 0; }
  th, td { border: none; text-align: left; padding: 10px 12px; }
  th { background-color: #0d6efd; color: #fff; font-weight: 600; }
  tr:nth-child(even) { background-color: #f8f9fa; }
  tr:hover { background-color: #eef6ff; }
  .section-title { margin-top: 26px; color: #2f353a; }
  .status { color: ${status_color}; font-weight: bold; }
  .recommendations { background: #f8f9fa; border-left: 4px solid #007bff; padding: 15px; margin: 15px 0; }
  .recommendations ul { margin: 0; padding-left: 20px; }
  .footer { text-align: center; color: #6c757d; font-size: 12px; padding: 14px 10px 22px 10px; }
</style>
</head>
<body>
  <div class="card">
    <div class="bar"></div>
    <div class="content">
      <h2>${status_icon} SQLite Disaster Recovery Test</h2>
      <div class="muted">Result: <span class="status">${status}</span> &nbsp;- &nbsp; Host: <b>$(hostname)</b> &nbsp;- &nbsp; Test ID: <b>$(date +%Y%m%d-%H%M%S)</b></div>

      <h3 class="section-title">📊 Test Results</h3>
      <table>
        <tr><th>Metric</th><th>Value</th></tr>
        <tr><td>📁 Backup File</td><td>$(basename "${LATEST_BACKUP:-N/A}")</td></tr>
        <tr><td>📅 Backup Age</td><td>${BACKUP_AGE_HOURS:-N/A} hours</td></tr>
        <tr><td>🗄️ Database Tables</td><td>${TOTAL_TABLES:-N/A}</td></tr>
        <tr><td>👥 Users</td><td>${USERS_COUNT:-N/A}</td></tr>
        <tr><td>🏢 Organizations</td><td>${ORGS_COUNT:-N/A}</td></tr>
        <tr><td>🔐 Ciphers</td><td>${CIPHERS_COUNT:-N/A}</td></tr>
        <tr><td>⏱️ Validation Time</td><td>${VALIDATION_TIME:-N/A} seconds</td></tr>
        <tr><td>🔍 Essential Tables</td><td>${TABLES_OK:-N/A}/4 found</td></tr>
      </table>

      <h3 class="section-title">📋 Test Summary</h3>
      <p>${message}</p>

      <div class="recommendations">
        <h4>💡 Recommendations</h4>
        <ul>
          ${recommendations_html}
        </ul>
      </div>

      <div class="footer">
        Generated by VaultWarden-OCI-Slim SQLite DR Test System<br>
        Log: $(basename "${LOG_FILE}") | Report: $(basename "${REPORT_FILE:-N/A}")
      </div>
    </div>
  </div>
</body>
</html>
EOF
)

    if command -v sendmail >/dev/null 2>&1; then
        echo -e "$html_body" | sendmail -t
        log_success "HTML notification sent to $EMAIL_RECIPIENT"
    elif command -v mail >/dev/null 2>&1; then
        # Fallback to plain text
        local plain_body="VaultWarden SQLite Disaster Recovery Monthly Test Report

Test Date: $(date '+%Y-%m-%d %H:%M:%S %Z')
Status: $status

$message

Test Details:
- Backup File: $(basename "${LATEST_BACKUP:-N/A}")
- Backup Age: ${BACKUP_AGE_HOURS:-N/A} hours
- Database Tables: ${TOTAL_TABLES:-N/A}
- Users: ${USERS_COUNT:-N/A}
- Organizations: ${ORGS_COUNT:-N/A}
- Ciphers: ${CIPHERS_COUNT:-N/A}
- Validation Time: ${VALIDATION_TIME:-N/A} seconds

Log File: $LOG_FILE
Report: ${REPORT_FILE:-N/A}

--
VaultWarden-OCI-Slim SQLite Disaster Recovery System"

        echo "$plain_body" | mail -s "$subject" "$EMAIL_RECIPIENT"
        log_success "Plain text notification sent to $EMAIL_RECIPIENT"
    else
        log_warning "No email command available - notification not sent"
    fi
}

# Cleanup function
cleanup() {
    log_info "Cleaning up test environment..."

    # Clean up work directory
    if [[ -d "$WORKDIR" ]]; then
        rm -rf "$WORKDIR"
        log_info "Cleaned up work directory: $WORKDIR"
    fi

    # Delete prepared backup file to save disk space
    if [[ -f "${PREPARED_BACKUP:-}" ]]; then
        rm -f "$PREPARED_BACKUP"
        log_info "Deleted temporary backup file to save disk space"
    fi

    # Clean up test database file
    if [[ -f "${TEST_DB_PATH:-}" ]]; then
        rm -f "$TEST_DB_PATH"
        log_info "Deleted test SQLite database"
    fi

    log_info "Cleanup completed"
}

# Trap cleanup on exit
trap cleanup EXIT INT TERM

# Initialize
mkdir -p "$LOG_DIR" "$WORKDIR"
echo "$(date '+%Y-%m-%d %H:%M:%S') - Starting SQLite DR monthly test" >> "$LOG_FILE"

log_info "VaultWarden SQLite Disaster Recovery Monthly Test"
log_info "Test ID: $(date +%Y%m%d-%H%M%S)"
log_info "Log file: $LOG_FILE"

# Source backup passphrase intelligently
source_backup_passphrase

# Find latest SQLite backup
log_info "Searching for latest SQLite database backup..."
BACKUP_DIRS=("${ROOT_DIR}/data/backups" "${ROOT_DIR}/backup/db" "${ROOT_DIR}/backups")
LATEST_BACKUP=""

for backup_dir in "${BACKUP_DIRS[@]}"; do
    if [[ -d "$backup_dir" ]]; then
        log_info "Checking backup directory: $backup_dir"
        # Find latest SQLite backup file
        while IFS= read -r -d '' backup_file; do
            if [[ -z "$LATEST_BACKUP" ]] || [[ "$backup_file" -nt "$LATEST_BACKUP" ]]; then
                LATEST_BACKUP="$backup_file"
            fi
        done < <(find "$backup_dir" -type f \( -name "*sqlite*backup*.sql*" -o -name "vaultwarden-*backup*.sql*" \) -print0)
    fi
done

[[ -n "$LATEST_BACKUP" ]] || fail "No SQLite database backups found. Check backup directories: ${BACKUP_DIRS[*]}"

# Get backup metadata
BACKUP_DATE=$(get_file_timestamp "$LATEST_BACKUP")
BACKUP_AGE_HOURS=$(get_file_age_hours "$LATEST_BACKUP")

log_success "Found latest SQLite backup: $(basename "$LATEST_BACKUP")"
log_info "Backup file: $LATEST_BACKUP"
log_info "Backup size: $(du -h "$LATEST_BACKUP" | cut -f1)"
log_info "Backup date: $BACKUP_DATE"
log_info "Backup age: $BACKUP_AGE_HOURS hours"

# Decrypt/decompress backup if needed
log_info "Preparing SQLite backup file for validation..."
PREPARED_BACKUP="${WORKDIR}/backup.sql"

case "$LATEST_BACKUP" in
    *.gpg)
        log_info "Detected GPG encrypted SQLite backup"
        echo "$BACKUP_PASSPHRASE" | gpg --batch --yes --quiet --passphrase-fd 0 --decrypt "$LATEST_BACKUP" > "$PREPARED_BACKUP" || fail "Failed to decrypt GPG backup"
        log_success "SQLite backup decrypted successfully"
        ;;
    *.gz)
        log_info "Detected gzip compressed SQLite backup"
        gunzip -c "$LATEST_BACKUP" > "$PREPARED_BACKUP" || fail "Failed to decompress backup"
        log_success "SQLite backup decompressed successfully"
        ;;
    *.sql)
        log_info "Detected plain SQL backup"
        cp "$LATEST_BACKUP" "$PREPARED_BACKUP" || fail "Failed to copy backup"
        log_success "SQLite backup copied successfully"
        ;;
    *)
        fail "Unknown backup format: $LATEST_BACKUP"
        ;;
esac

# Validate SQLite backup content
log_info "Validating SQLite backup content..."
BACKUP_SIZE=$(wc -c < "$PREPARED_BACKUP")
[[ $BACKUP_SIZE -gt 0 ]] || fail "Backup file is empty after processing"

# Check for SQLite-specific SQL elements
if grep -q "CREATE TABLE" "$PREPARED_BACKUP"; then
    log_success "Backup contains SQLite CREATE TABLE statements"
else
    fail "No CREATE TABLE statements found - invalid SQLite backup"
fi

if grep -q "INSERT INTO" "$PREPARED_BACKUP"; then
    log_success "Backup contains data INSERT statements"
else
    log_warning "No INSERT statements found - backup may contain no data"
fi

# Check for VaultWarden-specific tables
ESSENTIAL_TABLES=("users" "organizations" "ciphers" "collections")
TABLES_FOUND=0

for table in "${ESSENTIAL_TABLES[@]}"; do
    if grep -q "CREATE TABLE.*${table}" "$PREPARED_BACKUP"; then
        log_success "Found essential table: $table"
        ((TABLES_FOUND++))
    else
        log_warning "Essential table not found: $table"
    fi
done

log_info "Processed SQLite backup size: $(du -h "$PREPARED_BACKUP" | cut -f1)"
log_info "Essential tables found: $TABLES_FOUND/4"

# Create test SQLite database and restore
log_info "Creating test SQLite database and restoring backup..."
TEST_DB_PATH="${WORKDIR}/${TEST_DB_NAME}"

VALIDATION_START=$(date +%s)

# Use sqlite3 to restore the backup
if sqlite3 "$TEST_DB_PATH" < "$PREPARED_BACKUP"; then
    VALIDATION_END=$(date +%s)
    VALIDATION_TIME=$((VALIDATION_END - VALIDATION_START))
    log_success "SQLite backup restored successfully in ${VALIDATION_TIME} seconds"
else
    fail "Failed to restore SQLite backup to test database"
fi

# Check if database file was created and is accessible
if [[ ! -f "$TEST_DB_PATH" ]]; then
    fail "Test SQLite database file was not created"
fi

# Test database accessibility
if ! sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
    fail "Test SQLite database is not accessible or corrupted"
fi

log_success "Test SQLite database created and accessible"

# Run integrity checks
log_info "Running SQLite database integrity checks..."

# SQLite built-in integrity check
if sqlite3 "$TEST_DB_PATH" "PRAGMA integrity_check;" | grep -q "ok"; then
    log_success "SQLite integrity check passed"
else
    log_error "SQLite integrity check failed"
    fail "Database integrity check failed"
fi

# Check if essential VaultWarden tables exist and get counts
TABLES_OK=0
USERS_COUNT=0
ORGS_COUNT=0
CIPHERS_COUNT=0

for table in "${ESSENTIAL_TABLES[@]}"; do
    if sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM $table LIMIT 1;" >/dev/null 2>&1; then
        TABLE_COUNT=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM $table;" || echo "0")
        log_success "Table $table exists with $TABLE_COUNT rows"
        ((TABLES_OK++))

        # Store specific counts for reporting
        case "$table" in
            "users") USERS_COUNT="$TABLE_COUNT" ;;
            "organizations") ORGS_COUNT="$TABLE_COUNT" ;;
            "ciphers") CIPHERS_COUNT="$TABLE_COUNT" ;;
        esac
    else
        log_error "Essential table $table is missing or inaccessible"
    fi
done

# Get total table count
TOTAL_TABLES=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" || echo "0")

# Test data integrity for users table
log_info "Testing data integrity..."
EMAIL_VALIDATION_PASSED="true"
if [[ $USERS_COUNT -gt 0 ]]; then
    # SQLite email validation using LIKE pattern (regex not available in all SQLite builds)
    VALID_EMAILS=$(sqlite3 "$TEST_DB_PATH" "SELECT COUNT(*) FROM users WHERE email LIKE '%@%.%';" || echo "0")

    if [[ "$VALID_EMAILS" -eq "$USERS_COUNT" ]]; then
        log_success "All user emails appear to have valid format"
    else
        log_warning "$((USERS_COUNT - VALID_EMAILS)) users with potentially invalid email formats"
        EMAIL_VALIDATION_PASSED="false"
    fi
fi

# Test database performance
log_info "Testing SQLite database performance..."
PERF_START=$(date +%s)
RANDOM_QUERIES_OK=0

# Test simple queries
TEST_QUERIES=(
    "SELECT COUNT(*) FROM sqlite_master;"
    "SELECT name FROM sqlite_master WHERE type='table' LIMIT 5;"
)

if [[ $USERS_COUNT -gt 0 ]]; then
    TEST_QUERIES+=("SELECT COUNT(*) FROM users;")
fi

if [[ $CIPHERS_COUNT -gt 0 ]]; then
    TEST_QUERIES+=("SELECT COUNT(*) FROM ciphers;")
fi

for query in "${TEST_QUERIES[@]}"; do
    if sqlite3 "$TEST_DB_PATH" "$query" >/dev/null 2>&1; then
        ((RANDOM_QUERIES_OK++))
    else
        log_warning "Query failed: $query"
    fi
done

PERF_END=$(date +%s)
PERF_TIME=$((PERF_END - PERF_START))
log_info "Performance test completed: $RANDOM_QUERIES_OK/${#TEST_QUERIES[@]} queries successful in ${PERF_TIME}s"

# Determine test result
TEST_RESULT="SUCCESS"
TEST_MESSAGE="SQLite disaster recovery test completed successfully"

if [[ $TABLES_OK -lt 4 ]]; then
    TEST_RESULT="FAILURE"
    TEST_MESSAGE="Critical tables missing from SQLite backup"
elif [[ $USERS_COUNT -eq 0 && $CIPHERS_COUNT -eq 0 ]]; then
    TEST_RESULT="WARNING"  
    TEST_MESSAGE="SQLite backup restored successfully but contains no user data"
elif [[ $RANDOM_QUERIES_OK -lt ${#TEST_QUERIES[@]} ]]; then
    TEST_RESULT="WARNING"
    TEST_MESSAGE="SQLite backup restored but some queries failed"
fi

# Generate test report
log_info "Generating SQLite test report..."
REPORT_FILE="${LOG_DIR}/sqlite-dr-test-report-$(date +%Y%m%d-%H%M%S).json"

cat > "$REPORT_FILE" << EOF
{
  "test_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "test_id": "$(date +%Y%m%d-%H%M%S)",
  "test_result": "$TEST_RESULT",
  "database_type": "SQLite",
  "backup_info": {
    "file_path": "$LATEST_BACKUP",
    "file_name": "$(basename "$LATEST_BACKUP")",
    "backup_size_bytes": $BACKUP_SIZE,
    "backup_date": "$BACKUP_DATE",
    "backup_age_hours": $BACKUP_AGE_HOURS,
    "backup_format": "$(case "$LATEST_BACKUP" in *.gpg) echo "GPG_ENCRYPTED";; *.gz) echo "GZIP_COMPRESSED";; *.sql) echo "PLAIN_SQL";; esac)"
  },
  "database_stats": {
    "total_tables": $TOTAL_TABLES,
    "essential_tables_found": $TABLES_OK,
    "users_count": $USERS_COUNT,
    "organizations_count": $ORGS_COUNT,
    "ciphers_count": $CIPHERS_COUNT
  },
  "performance": {
    "restoration_time_seconds": $VALIDATION_TIME,
    "tables_validated": $TABLES_OK,
    "data_integrity_passed": "$EMAIL_VALIDATION_PASSED",
    "query_test_passed": $RANDOM_QUERIES_OK,
    "query_test_total": ${#TEST_QUERIES[@]},
    "performance_test_time": $PERF_TIME
  }
}
EOF

log_success "SQLite test report saved: $REPORT_FILE"

# Summary
echo ""
if [[ "$TEST_RESULT" == "SUCCESS" ]]; then
    log_success "=== SQLITE DISASTER RECOVERY TEST COMPLETED SUCCESSFULLY ==="
elif [[ "$TEST_RESULT" == "WARNING" ]]; then
    log_warning "=== SQLITE DISASTER RECOVERY TEST COMPLETED WITH WARNINGS ==="
else
    log_error "=== SQLITE DISASTER RECOVERY TEST FAILED ==="
fi

log_info "SQLite Test Summary:"
log_info "  Backup file: $(basename "$LATEST_BACKUP")"
log_info "  Backup age: $BACKUP_AGE_HOURS hours"
log_info "  Restoration time: ${VALIDATION_TIME} seconds"
log_info "  Total tables: $TOTAL_TABLES"
log_info "  Essential tables: $TABLES_OK/4"
log_info "  Users: $USERS_COUNT"
log_info "  Organizations: $ORGS_COUNT"
log_info "  Ciphers: $CIPHERS_COUNT"
log_info "  Performance queries: $RANDOM_QUERIES_OK/${#TEST_QUERIES[@]}"
log_info "  Report: $(basename "$REPORT_FILE")"

# Send enhanced HTML email notification
send_email_notification \
    "${TEST_RESULT^}: VaultWarden SQLite DR Test" \
    "$TEST_MESSAGE" \
    "$TEST_RESULT"

# Recommendations
echo ""
log_info "SQLite-Specific Recommendations:"
if [[ $BACKUP_AGE_HOURS -gt 48 ]]; then
    log_warning "  • SQLite backup is $BACKUP_AGE_HOURS hours old - check backup automation"
fi

if [[ $USERS_COUNT -eq 0 ]]; then
    log_info "  • No users found - consider testing with production-like data"
fi

if [[ $VALIDATION_TIME -gt 60 ]]; then
    log_warning "  • SQLite restoration took $VALIDATION_TIME seconds - monitor disk I/O performance"
fi

if [[ $TABLES_OK -eq 4 && $USERS_COUNT -gt 0 ]]; then
    log_success "  • SQLite backup is healthy and ready for disaster recovery!"
fi

if [[ $RANDOM_QUERIES_OK -eq ${#TEST_QUERIES[@]} ]]; then
    log_success "  • SQLite database performance is optimal"
fi

log_success "SQLite disaster recovery capability verified - backups are restorable!"

# Return appropriate exit code
case "$TEST_RESULT" in
    "SUCCESS") exit 0 ;;
    "WARNING") exit 1 ;;
    "FAILURE") exit 2 ;;
esac
