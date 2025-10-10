#!/usr/bin/env bash
# verify-backup.sh -- SQLite Backup Verification Script for VaultWarden-OCI-Slim (Enhanced with HTML notifications)
# Optimized for 1 OCPU/6GB deployment

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load settings if available
if [[ -f "${ROOT_DIR}/settings.env" ]]; then
    source "${ROOT_DIR}/settings.env"
fi

BACKUP_DIR="${BACKUP_DIR:-${ROOT_DIR}/data/backups}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/backup_logs}"
EMAIL_RECIPIENT="${BACKUP_EMAIL:-${ALERT_EMAIL:-}}"

# Create necessary directories
mkdir -p "$LOG_DIR"

# Logging setup
LOG_FILE="$LOG_DIR/sqlite-verify-$(date +%Y%m%d_%H%M%S).log"
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*"
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*"
}

# Find backup files
find_backup_files() {
    local pattern="$1"

    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "Backup directory not found: $BACKUP_DIR"
        return 1
    fi

    case "$pattern" in
        "latest")
            find "$BACKUP_DIR" -name "vaultwarden-*backup-*.sql.gz*" -printf "%T@ %p\n" | sort -nr | head -1 | cut -d' ' -f2-
            ;;
        "all")
            find "$BACKUP_DIR" -name "vaultwarden-*backup-*.sql.gz*" | sort -r
            ;;
        *)
            # Specific file or pattern
            if [[ -f "$BACKUP_DIR/$pattern" ]]; then
                echo "$BACKUP_DIR/$pattern"
            elif [[ -f "$pattern" ]]; then
                echo "$pattern"
            else
                find "$BACKUP_DIR" -name "*$pattern*" | sort -r
            fi
            ;;
    esac
}

# Verify file integrity
verify_file_integrity() {
    local backup_file="$1"
    local verification_results=()

    log_info "Verifying file integrity: $(basename "$backup_file")"

    # Check if file exists and is readable
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        return 1
    fi

    if [[ ! -r "$backup_file" ]]; then
        log_error "Backup file not readable: $backup_file"
        return 1
    fi

    local file_size
    file_size=$(du -h "$backup_file" | cut -f1)
    log_info "File size: $file_size"

    # Verify based on file type
    if [[ "$backup_file" == *.gpg ]]; then
        log_info "Verifying encrypted backup..."

        if [[ -z "${BACKUP_PASSPHRASE:-}" ]]; then
            log_error "Cannot verify encrypted backup: BACKUP_PASSPHRASE not set"
            return 1
        fi

        # Test decryption and decompression
        if echo "$BACKUP_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 --decrypt "$backup_file" | gzip -t; then
            log_success "Encrypted backup integrity: PASSED"
            verification_results+=("encryption:PASSED")
        else
            log_error "Encrypted backup integrity: FAILED"
            verification_results+=("encryption:FAILED")
            return 1
        fi

    elif [[ "$backup_file" == *.gz ]]; then
        log_info "Verifying compressed backup..."

        if gzip -t "$backup_file"; then
            log_success "Compressed backup integrity: PASSED"
            verification_results+=("compression:PASSED")
        else
            log_error "Compressed backup integrity: FAILED"
            verification_results+=("compression:FAILED")
            return 1
        fi

    elif [[ "$backup_file" == *.sql ]]; then
        log_info "Verifying SQL backup..."

        # Check if file starts with SQLite pragma
        if head -n 5 "$backup_file" | grep -q "PRAGMA\|BEGIN\|CREATE"; then
            log_success "SQL backup format: VALID"
            verification_results+=("format:VALID")
        else
            log_error "SQL backup format: INVALID"
            verification_results+=("format:INVALID")
            return 1
        fi

    else
        log_warning "Unknown backup file format, skipping format verification"
        verification_results+=("format:UNKNOWN")
    fi

    # Store results for summary
    echo "${verification_results[@]}"
    return 0
}

# Verify backup content
verify_backup_content() {
    local backup_file="$1"
    local temp_dir="$2"

    log_info "Verifying backup content..."

    local sql_file="$temp_dir/verify.sql"
    local test_db="$temp_dir/test.sqlite3"

    # Extract SQL content
    if [[ "$backup_file" == *.gpg ]]; then
        if ! echo "$BACKUP_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 --decrypt "$backup_file" | gzip -dc > "$sql_file"; then
            log_error "Failed to extract encrypted backup content"
            return 1
        fi
    elif [[ "$backup_file" == *.gz ]]; then
        if ! gzip -dc "$backup_file" > "$sql_file"; then
            log_error "Failed to extract compressed backup content"
            return 1
        fi
    elif [[ "$backup_file" == *.sql ]]; then
        if ! cp "$backup_file" "$sql_file"; then
            log_error "Failed to copy SQL backup content"
            return 1
        fi
    else
        log_error "Cannot extract content from unknown backup format"
        return 1
    fi

    log_info "SQL content extracted successfully"

    # Get SQL file statistics
    local sql_size line_count
    sql_size=$(du -h "$sql_file" | cut -f1)
    line_count=$(wc -l < "$sql_file")
    log_info "SQL content: $sql_size, $line_count lines"

    # Test SQL content by creating a test database
    log_info "Testing SQL content by creating test database..."

    if sqlite3 "$test_db" < "$sql_file"; then
        log_success "SQL content is valid (test database created)"

        # Verify database structure
        local table_count
        table_count=$(sqlite3 "$test_db" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" || echo "0")
        log_info "Tables in backup: $table_count"

        # Check for VaultWarden-specific tables
        local vw_tables
        vw_tables=$(sqlite3 "$test_db" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('users', 'organizations', 'ciphers', 'folders');" || echo "0")

        if [[ $vw_tables -gt 0 ]]; then
            log_success "VaultWarden tables detected: $vw_tables/4"

            # Get record counts if possible
            if sqlite3 "$test_db" "SELECT name FROM sqlite_master WHERE type='table' AND name='users';" | grep -q users; then
                local user_count
                user_count=$(sqlite3 "$test_db" "SELECT COUNT(*) FROM users;" || echo "N/A")
                log_info "Users in backup: $user_count"
            fi

            if sqlite3 "$test_db" "SELECT name FROM sqlite_master WHERE type='table' AND name='ciphers';" | grep -q ciphers; then
                local cipher_count
                cipher_count=$(sqlite3 "$test_db" "SELECT COUNT(*) FROM ciphers;" || echo "N/A")
                log_info "Ciphers (passwords) in backup: $cipher_count"
            fi
        else
            log_warning "No VaultWarden tables found in backup (may be empty or corrupted)"
        fi

        # Store stats for email notification
        BACKUP_VERIFICATION_STATS="$table_count tables, $vw_tables VaultWarden tables"

        # Cleanup test database
        rm -f "$test_db"

        return 0
    else
        log_error "SQL content is invalid (failed to create test database)"
        return 1
    fi
}

# Verify backup completeness
verify_backup_completeness() {
    local backup_file="$1"

    log_info "Verifying backup completeness..."

    # Extract timestamp from filename
    local timestamp
    timestamp=$(basename "$backup_file" | grep -o '[0-9]\{8\}_[0-9]\{6\}' || echo "unknown")

    # Check for corresponding file backup
    local file_backup_pattern="*files-backup-$timestamp*"
    local file_backup_count
    file_backup_count=$(find "$BACKUP_DIR" -name "$file_backup_pattern" | wc -l)

    if [[ $file_backup_count -gt 0 ]]; then
        log_success "Corresponding file backup found ($file_backup_count files)"

        # Verify file backup integrity
        local file_backup
        file_backup=$(find "$BACKUP_DIR" -name "$file_backup_pattern" | head -1)

        if tar -tzf "$file_backup" >/dev/null 2>&1; then
            log_success "File backup integrity: PASSED"
            BACKUP_COMPLETENESS_STATUS="Complete (with file backup)"
        else
            log_warning "File backup integrity: FAILED"
            BACKUP_COMPLETENESS_STATUS="Incomplete (file backup corrupted)"
        fi
    else
        log_info "No corresponding file backup found (database-only backup)"
        BACKUP_COMPLETENESS_STATUS="Database only"
    fi

    return 0
}

# Generate verification report
generate_verification_report() {
    local backup_file="$1"
    local verification_start="$2"
    local verification_end="$3"
    local overall_status="$4"
    shift 4
    local detailed_results=("$@")

    log_info "Generating verification report..."

    local report_file="$LOG_DIR/verification-report-$(date +%Y%m%d_%H%M%S).txt"

    cat > "$report_file" << EOF
VaultWarden SQLite Backup Verification Report
=============================================

Backup File: $(basename "$backup_file")
Full Path: $backup_file
Verification Date: $(date)
Verification Duration: $((verification_end - verification_start)) seconds
Overall Status: $overall_status

File Information:
- Size: $(du -h "$backup_file" | cut -f1)
- Modified: $(stat -c %y "$backup_file" | cut -d. -f1 || date -r "$backup_file" || echo "Unknown")
- Type: $(file -b "$backup_file" || echo "Unknown")

Verification Results:
EOF

    # Add detailed results
    for result in "${detailed_results[@]}"; do
        echo "- $result" >> "$report_file"
    done

    # Add system information
    cat >> "$report_file" << EOF

System Information:
- Hostname: $(hostname)
- Date: $(date)
- User: $(whoami)
- Script Version: VaultWarden-OCI-Slim v1.0
- Database Type: SQLite
- Backup Directory: $BACKUP_DIR

Log File: $LOG_FILE
EOF

    log_success "Verification report generated: $report_file"
    echo "$report_file"
}

# Enhanced HTML verification notification
send_verification_notification() {
    local backup_file="$1"
    local overall_status="$2"
    local report_file="$3"
    local verification_start="$4"
    local verification_end="$5"
    local detailed_results=("${@:6}")

    if [[ -z "$EMAIL_RECIPIENT" ]]; then
        return 0
    fi

    log_info "Sending HTML verification notification..."

    # Status styling
    local status_icon="✅"
    local status_color="#28a745"
    local bar_color="#28a745"
    
    case "$overall_status" in
        "FAILED")
            status_icon="🚨"
            status_color="#dc3545"
            bar_color="#dc3545"
            ;;
        "PARTIAL")
            status_icon="⚠️"
            status_color="#ffc107"
            bar_color="#ffc107"
            ;;
    esac

    local duration=$((verification_end - verification_start))
    local subject="${status_icon} VaultWarden SQLite Backup Verification: ${overall_status}"

    # Generate results HTML
    local results_html=""
    for result in "${detailed_results[@]}"; do
        results_html+="<tr><td>${result}</td></tr>"
    done

    local html_body=$(cat <<EOF
From: VaultWarden Backup <${SMTP_FROM:-noreply@$(hostname -d || echo localdomain)}>
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
  .footer { text-align: center; color: #6c757d; font-size: 12px; padding: 14px 10px 22px 10px; }
</style>
</head>
<body>
  <div class="card">
    <div class="bar"></div>
    <div class="content">
      <h2>${status_icon} SQLite Backup Verification</h2>
      <div class="muted">Result: <span class="status">${overall_status}</span> &nbsp;- &nbsp; Host: <b>$(hostname)</b> &nbsp;- &nbsp; Duration: <b>${duration}s</b></div>

      <h3 class="section-title">📁 Backup Details</h3>
      <table>
        <tr><th>Property</th><th>Value</th></tr>
        <tr><td>📄 File</td><td>$(basename "$backup_file")</td></tr>
        <tr><td>📊 Size</td><td>$(du -h "$backup_file" | cut -f1)</td></tr>
        <tr><td>📅 Modified</td><td>$(stat -c %y "$backup_file" | cut -d. -f1 || date -r "$backup_file" || echo "Unknown")</td></tr>
        <tr><td>🔍 Content</td><td>${BACKUP_VERIFICATION_STATS:-"Verification skipped"}</td></tr>
        <tr><td>📋 Completeness</td><td>${BACKUP_COMPLETENESS_STATUS:-"Not checked"}</td></tr>
        <tr><td>⏱️ Verification Time</td><td>${duration} seconds</td></tr>
      </table>

      <h3 class="section-title">✅ Verification Results</h3>
      <table>
        <tr><th>Check Results</th></tr>
        ${results_html}
      </table>

      <div class="footer">
        Generated by VaultWarden-OCI-Slim SQLite Backup Verification<br>
        Report: $(basename "$report_file") | Log: $(basename "$LOG_FILE")
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
        local plain_body="VaultWarden SQLite backup verification completed.

Backup File: $(basename "$backup_file")
Status: $overall_status
Timestamp: $(date)
Server: $(hostname)

Report: $report_file
Log: $LOG_FILE

$(tail -n 10 "$LOG_FILE")"

        echo "$plain_body" | mail -s "$subject" "$EMAIL_RECIPIENT"
        log_success "Plain text notification sent to $EMAIL_RECIPIENT"
    else
        log_info "No mail command available for notifications"
    fi
}

# Main verification function
main() {
    local backup_pattern="latest"
    local verify_content=true
    local generate_report=true
    local send_notification_flag=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --backup|-b)
                backup_pattern="$2"
                shift 2
                ;;
            --latest)
                backup_pattern="latest"
                shift
                ;;
            --all)
                backup_pattern="all"
                shift
                ;;
            --quick)
                verify_content=false
                shift
                ;;
            --no-report)
                generate_report=false
                shift
                ;;
            --notify)
                send_notification_flag=true
                shift
                ;;
            --help|-h)
                cat <<EOF
VaultWarden SQLite Backup Verification Script (Enhanced with HTML notifications)

Usage: $0 [OPTIONS]

Options:
    --backup, -b FILE   Verify specific backup file or pattern
    --latest            Verify latest backup (default)
    --all               Verify all backup files
    --quick             Quick verification (integrity only, skip content)
    --no-report         Don't generate verification report
    --notify            Send HTML email notification (requires BACKUP_EMAIL/ALERT_EMAIL)
    --help, -h          Show this help message

Environment Variables:
    BACKUP_DIR              Backup storage directory
    BACKUP_PASSPHRASE       GPG decryption passphrase (for encrypted backups)
    BACKUP_EMAIL            Email address for HTML notifications (preferred)
    ALERT_EMAIL             Fallback email address for notifications
    LOG_DIR                 Log directory

Examples:
    $0                      # Verify latest backup
    $0 --all               # Verify all backups
    $0 --backup backup.sql.gz   # Verify specific backup
    $0 --quick --notify    # Quick verification with HTML notification

Verification Process:
    1. File integrity check (compression/encryption)
    2. Content validation (SQL structure)
    3. Database schema verification
    4. Completeness check (file backups)
    5. HTML report generation and email notification

EOF
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done

    log_info "Starting VaultWarden SQLite backup verification..."

    local verification_start
    verification_start=$(date +%s)

    # Find backup files to verify
    local backup_files
    backup_files=$(find_backup_files "$backup_pattern")

    if [[ -z "$backup_files" ]]; then
        log_error "No backup files found matching pattern: $backup_pattern"
        exit 1
    fi

    local overall_status="SUCCESS"
    local detailed_results=()
    local verified_count=0
    local failed_count=0

    # Initialize global variables for email
    BACKUP_VERIFICATION_STATS=""
    BACKUP_COMPLETENESS_STATUS=""

    # Process each backup file
    while IFS= read -r backup_file; do
        [[ -z "$backup_file" ]] && continue

        log_info "=========================================="
        log_info "Verifying backup: $(basename "$backup_file")"
        log_info "=========================================="

        local file_status="SUCCESS"

        # Verify file integrity
        local integrity_results
        if integrity_results=$(verify_file_integrity "$backup_file"); then
            detailed_results+=("$(basename "$backup_file"): Integrity - $integrity_results")
        else
            file_status="FAILED"
            overall_status="FAILED"
            detailed_results+=("$(basename "$backup_file"): Integrity - FAILED")
        fi

        # Verify content if requested and integrity passed
        if [[ "$verify_content" == "true" && "$file_status" == "SUCCESS" ]]; then
            local temp_dir
            temp_dir=$(mktemp -d)

            if verify_backup_content "$backup_file" "$temp_dir"; then
                detailed_results+=("$(basename "$backup_file"): Content - VALID")
            else
                file_status="FAILED"
                overall_status="FAILED"
                detailed_results+=("$(basename "$backup_file"): Content - INVALID")
            fi

            rm -rf "$temp_dir"
        fi

        # Verify completeness
        if verify_backup_completeness "$backup_file"; then
            detailed_results+=("$(basename "$backup_file"): Completeness - CHECKED")
        else
            detailed_results+=("$(basename "$backup_file"): Completeness - ISSUES")
        fi

        if [[ "$file_status" == "SUCCESS" ]]; then
            ((verified_count++))
            log_success "Backup verification completed: $(basename "$backup_file")"
        else
            ((failed_count++))
            log_error "Backup verification failed: $(basename "$backup_file")"
        fi

    done <<< "$backup_files"

    local verification_end
    verification_end=$(date +%s)

    # Generate summary
    log_info "=========================================="
    log_info "VERIFICATION SUMMARY"
    log_info "=========================================="
    log_info "Total backups processed: $((verified_count + failed_count))"
    log_info "Successful verifications: $verified_count"
    log_info "Failed verifications: $failed_count"
    log_info "Overall status: $overall_status"
    log_info "Verification duration: $((verification_end - verification_start)) seconds"

    # Generate report if requested
    local report_file=""
    if [[ "$generate_report" == "true" ]]; then
        # Use the first/primary backup file for report
        local primary_backup
        primary_backup=$(echo "$backup_files" | head -1)
        report_file=$(generate_verification_report "$primary_backup" "$verification_start" "$verification_end" "$overall_status" "${detailed_results[@]}")
    fi

    # Send HTML notification if requested
    if [[ "$send_notification_flag" == "true" ]]; then
        local primary_backup
        primary_backup=$(echo "$backup_files" | head -1)
        send_verification_notification "$primary_backup" "$overall_status" "$report_file" "$verification_start" "$verification_end" "${detailed_results[@]}"
    fi

    log_success "Backup verification process completed"
    log_info "Log file: $LOG_FILE"

    if [[ "$overall_status" == "SUCCESS" ]]; then
        exit 0
    else
        exit 1
    fi
}

# Execute main function
main "$@"
