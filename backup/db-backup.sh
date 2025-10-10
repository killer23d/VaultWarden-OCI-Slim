#!/usr/bin/env bash
# db-backup.sh -- SQLite Backup Script for VaultWarden-OCI-Slim (Enhanced with HTML notifications)
# Optimized for 1 OCPU/6GB deployment with weekly backup schedule

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load settings from settings.env if available
if [[ -f "${ROOT_DIR}/settings.env" ]]; then
    source "${ROOT_DIR}/settings.env"
fi

# Map repository variables to script variables
BACKUP_DIR="${BACKUP_DIR:-${ROOT_DIR}/data/backups}"
LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/backup_logs}"
SQLITE_DB_PATH=/data/bwdata/db.sqlite3
VAULTWARDEN_DATA_DIR="${VAULTWARDEN_DATA_DIR:-${ROOT_DIR}/data/bwdata}"

# Map RCLONE variables to BACKUP variables for compatibility
if [[ -z "${BACKUP_REMOTE:-}" && -n "${RCLONE_REMOTE:-}" ]]; then
    BACKUP_REMOTE="$RCLONE_REMOTE"
fi
if [[ -z "${BACKUP_PATH:-}" && -n "${RCLONE_PATH:-}" ]]; then
    BACKUP_PATH="$RCLONE_PATH"
fi

# Set email recipient with fallbacks
BACKUP_EMAIL="${BACKUP_EMAIL:-${ALERT_EMAIL:-}}"

# Create necessary directories
mkdir -p "$BACKUP_DIR" "$LOG_DIR"

# Logging setup
LOG_FILE="$LOG_DIR/sqlite-backup-$(date +%Y%m%d_%H%M%S).log"
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

# Check if SQLite database exists
check_sqlite_database() {
    log_info "Checking SQLite database..."

    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        log_error "SQLite database not found: $SQLITE_DB_PATH"
        return 1
    fi

    # Check if database is accessible
    if ! sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
        log_error "SQLite database is not accessible or corrupted: $SQLITE_DB_PATH"
        return 1
    fi

    local db_size
    db_size=$(du -h "$SQLITE_DB_PATH" | cut -f1)
    log_success "SQLite database found and accessible ($db_size): $SQLITE_DB_PATH"
    return 0
}

# Create SQLite backup
create_sqlite_backup() {
    local timestamp="$1"
    local backup_name="vaultwarden-sqlite-backup-$timestamp"
    local backup_file="$BACKUP_DIR/$backup_name.sql"
    local compressed_file="$BACKUP_DIR/$backup_name.sql.gz"
    local encrypted_file="$BACKUP_DIR/$backup_name.sql.gz.gpg"

    log_info "Creating SQLite backup..."

    # Create SQL dump using sqlite3
    if sqlite3 "$SQLITE_DB_PATH" ".dump" > "$backup_file"; then
        log_success "SQLite dump created: $backup_file"
    else
        log_error "Failed to create SQLite dump"
        return 1
    fi

    # Compress the backup
    if gzip "$backup_file"; then
        log_success "Backup compressed: $compressed_file"
    else
        log_error "Failed to compress backup"
        return 1
    fi

    # Encrypt if passphrase is provided
    if [[ -n "${BACKUP_PASSPHRASE:-}" ]]; then
        if echo "$BACKUP_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 --symmetric --cipher-algo AES256 --output "$encrypted_file" "$compressed_file"; then
            log_success "Backup encrypted: $encrypted_file"
            rm -f "$compressed_file"
            echo "$encrypted_file"
        else
            log_error "Failed to encrypt backup"
            return 1
        fi
    else
        echo "$compressed_file"
    fi
}

# Create additional file backup (attachments, etc.)
create_file_backup() {
    local timestamp="$1"
    local backup_name="vaultwarden-files-backup-$timestamp"
    local file_backup="$BACKUP_DIR/$backup_name.tar.gz"

    log_info "Creating VaultWarden files backup..."

    # Backup attachments and other data files (excluding database)
    if tar -czf "$file_backup" -C "$(dirname "$VAULTWARDEN_DATA_DIR")" \
        --exclude="$(basename "$VAULTWARDEN_DATA_DIR")/db.sqlite3" \
        --exclude="$(basename "$VAULTWARDEN_DATA_DIR")/db.sqlite3-wal" \
        --exclude="$(basename "$VAULTWARDEN_DATA_DIR")/db.sqlite3-shm" \
        "$(basename "$VAULTWARDEN_DATA_DIR")"; then
        log_success "Files backup created: $file_backup"
        echo "$file_backup"
    else
        log_error "Failed to create files backup"
        return 1
    fi
}

# Verify backup integrity
verify_backup() {
    local backup_file="$1"

    log_info "Verifying backup integrity..."

    if [[ "$backup_file" == *.gpg ]]; then
        # Verify encrypted backup
        if echo "$BACKUP_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 --decrypt "$backup_file" | gzip -t; then
            log_success "Encrypted backup verification passed"
            return 0
        else
            log_error "Encrypted backup verification failed"
            return 1
        fi
    elif [[ "$backup_file" == *.gz ]]; then
        # Verify compressed backup
        if gzip -t "$backup_file"; then
            log_success "Compressed backup verification passed"
            return 0
        else
            log_error "Compressed backup verification failed"
            return 1
        fi
    else
        log_error "Unknown backup format for verification"
        return 1
    fi
}

# Upload backup to remote storage
upload_backup() {
    local backup_file="$1"
    local file_backup="$2"

    if [[ -z "${BACKUP_REMOTE:-}" ]]; then
        log_info "No remote storage configured, skipping upload"
        return 0
    fi

    log_info "Uploading backups to remote storage: $BACKUP_REMOTE"

    # Upload database backup
    if rclone copy "$backup_file" "$BACKUP_REMOTE:${BACKUP_PATH:-vaultwarden-backups}/$(date +%Y/%m)" --progress; then
        log_success "Database backup uploaded successfully"
    else
        log_error "Failed to upload database backup"
        return 1
    fi

    # Upload file backup
    if rclone copy "$file_backup" "$BACKUP_REMOTE:${BACKUP_PATH:-vaultwarden-backups}/$(date +%Y/%m)" --progress; then
        log_success "File backup uploaded successfully"
    else
        log_error "Failed to upload file backup"
        return 1
    fi

    return 0
}

# Cleanup old backups
cleanup_old_backups() {
    local retention_days="${BACKUP_RETENTION_DAYS:-30}"

    log_info "Cleaning up backups older than $retention_days days..."

    # Local cleanup
    find "$BACKUP_DIR" -name "vaultwarden-*backup-*.sql.gz*" -mtime +$retention_days -delete || true
    find "$BACKUP_DIR" -name "vaultwarden-*backup-*.tar.gz" -mtime +$retention_days -delete || true

    # Remote cleanup (if configured)
    if [[ -n "${BACKUP_REMOTE:-}" ]]; then
        # Note: Remote cleanup implementation depends on rclone remote type
        # This is a basic implementation - adjust based on your remote storage
        log_info "Note: Remote cleanup may need manual configuration based on your storage type"
    fi

    log_success "Backup cleanup completed"
}

# Enhanced HTML notification function
send_notification() {
    local status="$1"
    local backup_file="$2"
    local file_backup="$3"
    local start_time="${4:-}"
    local end_time="${5:-}"

    if [[ -z "${BACKUP_EMAIL:-}" ]]; then
        log_info "No BACKUP_EMAIL configured, skipping notification"
        return 0
    fi

    # Calculate duration if timestamps provided
    local duration=""
    if [[ -n "$start_time" && -n "$end_time" ]]; then
        local duration_sec=$((end_time - start_time))
        if (( duration_sec >= 3600 )); then
            duration="$(( duration_sec / 3600 ))h $(( (duration_sec % 3600) / 60 ))m $(( duration_sec % 60 ))s"
        elif (( duration_sec >= 60 )); then
            duration="$(( duration_sec / 60 ))m $(( duration_sec % 60 ))s"
        else
            duration="${duration_sec}s"
        fi
    fi

    # Get file sizes
    local db_backup_size="N/A"
    local file_backup_size="N/A"
    [[ -f "$backup_file" ]] && db_backup_size=$(du -h "$backup_file" | cut -f1)
    [[ -f "$file_backup" ]] && file_backup_size=$(du -h "$file_backup" | cut -f1)

    # Status-specific styling
    local status_icon="✅"
    local status_color="#28a745"
    local bar_color="#28a745"
    
    case "$status" in
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

    local subject="${status_icon} VaultWarden SQLite Backup ${status}"

    # Generate HTML email
    local html_body=$(cat <<EOF
From: VaultWarden Backup <${SMTP_FROM:-noreply@$(hostname -d || echo localdomain)}>
To: $BACKUP_EMAIL
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
  .log { background: #0b1020; color: #dbe2f1; padding: 14px; border-radius: 6px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace; font-size: 12px; line-height: 1.45; overflow-x: auto; max-height: 300px; }
  .footer { text-align: center; color: #6c757d; font-size: 12px; padding: 14px 10px 22px 10px; }
  .status { color: ${status_color}; font-weight: bold; }
</style>
</head>
<body>
  <div class="card">
    <div class="bar"></div>
    <div class="content">
      <h2>${status_icon} VaultWarden SQLite Backup</h2>
      <div class="muted">Status: <span class="status">${status}</span> &nbsp;- &nbsp; Host: <b>$(hostname)</b> &nbsp;- &nbsp; When: <b>$(date)</b></div>

      <h3 class="section-title">📊 Backup Summary</h3>
      <table>
        <tr><th>Component</th><th>Details</th></tr>
        <tr><td>🗄️ Database Backup</td><td>$(basename "$backup_file") (${db_backup_size})</td></tr>
        <tr><td>📁 Files Backup</td><td>$(basename "$file_backup") (${file_backup_size})</td></tr>
        $([[ -n "$duration" ]] && echo "<tr><td>⏱️ Duration</td><td>${duration}</td></tr>")
        $([[ -n "${BACKUP_REMOTE:-}" ]] && echo "<tr><td>☁️ Remote Storage</td><td>${BACKUP_REMOTE}</td></tr>")
        <tr><td>🔐 Encryption</td><td>$([[ -n "${BACKUP_PASSPHRASE:-}" ]] && echo "GPG AES256" || echo "None")</td></tr>
        <tr><td>📅 Retention</td><td>${BACKUP_RETENTION_DAYS:-30} days</td></tr>
      </table>

      <h3 class="section-title">📝 Recent Log Output</h3>
      <div class="log">
        <pre>$(tail -n 15 "$LOG_FILE" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g' || echo "Log not available")</pre>
      </div>

      <div class="footer">
        Generated by VaultWarden-OCI-Slim SQLite Backup System<br>
        Log file: $(basename "$LOG_FILE")
      </div>
    </div>
  </div>
</body>
</html>
EOF
)

    # Send email
    if command -v sendmail >/dev/null 2>&1; then
        echo -e "$html_body" | sendmail -t
        log_success "HTML notification sent to $BACKUP_EMAIL"
    elif command -v mail >/dev/null 2>&1; then
        # Fallback to plain text for basic mail command
        local plain_body="VaultWarden SQLite backup completed with status: $status

Backup Details:
- Database backup: $(basename "$backup_file") ($db_backup_size)
- Files backup: $(basename "$file_backup") ($file_backup_size)
- Duration: ${duration:-N/A}
- Timestamp: $(date)
- Server: $(hostname)
- Remote: ${BACKUP_REMOTE:-Local only}

Log file: $LOG_FILE"
        
        echo "$plain_body" | mail -s "$subject" "$BACKUP_EMAIL"
        log_success "Plain text notification sent to $BACKUP_EMAIL"
    else
        log_info "No mail command available for notifications"
    fi
}

# Main backup function
main() {
    local force_backup=false
    local start_time=$(date +%s)

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                force_backup=true
                shift
                ;;
            --help|-h)
                cat <<EOF
VaultWarden SQLite Backup Script

Usage: $0 [OPTIONS]

Options:
    --force     Force backup even if not scheduled
    --help, -h  Show this help message

Environment Variables:
    SQLITE_DB_PATH          Path to SQLite database
    VAULTWARDEN_DATA_DIR    VaultWarden data directory
    BACKUP_DIR              Backup storage directory
    LOG_DIR                 Log directory
    BACKUP_PASSPHRASE       GPG encryption passphrase
    BACKUP_REMOTE           rclone remote name
    BACKUP_PATH             Remote backup path
    BACKUP_EMAIL            Email for HTML notifications
    BACKUP_RETENTION_DAYS   Backup retention period (default: 30)

Examples:
    $0 --force              # Force immediate backup
    $0                      # Normal scheduled backup

EOF
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done

    log_info "Starting VaultWarden SQLite backup..."

    # Check if database exists and is accessible
    if ! check_sqlite_database; then
        log_error "Database check failed"
        send_notification "FAILED" "" "" "$start_time" "$(date +%s)"
        exit 1
    fi

    # Create timestamp for this backup
    local timestamp
    timestamp=$(date +%Y%m%d_%H%M%S)

    # Create SQLite backup
    local backup_file
    if ! backup_file=$(create_sqlite_backup "$timestamp"); then
        log_error "SQLite backup creation failed"
        send_notification "FAILED" "" "" "$start_time" "$(date +%s)"
        exit 1
    fi

    # Create file backup
    local file_backup
    if ! file_backup=$(create_file_backup "$timestamp"); then
        log_error "File backup creation failed"
        send_notification "FAILED" "$backup_file" "" "$start_time" "$(date +%s)"
        exit 1
    fi

    # Verify backups
    if ! verify_backup "$backup_file"; then
        log_error "Backup verification failed"
        send_notification "FAILED" "$backup_file" "$file_backup" "$start_time" "$(date +%s)"
        exit 1
    fi

    # Upload to remote storage
    local upload_status="SUCCESS"
    if ! upload_backup "$backup_file" "$file_backup"; then
        log_error "Backup upload failed"
        upload_status="PARTIAL"
        # Don't exit here - local backup still succeeded
    fi

    # Cleanup old backups
    cleanup_old_backups

    local end_time=$(date +%s)

    # Send success notification
    send_notification "$upload_status" "$backup_file" "$file_backup" "$start_time" "$end_time"

    log_success "VaultWarden SQLite backup completed successfully!"
    log_info "Database backup: $backup_file"
    log_info "Files backup: $file_backup"
    log_info "Log file: $LOG_FILE"
}

# Execute main function
main "$@"
