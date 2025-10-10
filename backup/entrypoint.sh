#!/bin/bash
# entrypoint.sh -- SQLite Backup Container Entry Point
# VaultWarden-OCI-Slim optimization for 1 OCPU/6GB

set -euo pipefail

# Logging setup
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $*"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $*"
}

# Initialize backup environment
initialize_backup_environment() {
    log_info "Initializing SQLite backup environment..."

    # Create necessary directories
    mkdir -p "${BACKUP_DIR:-/backups}" "${LOG_DIR:-/var/log/backup}"

    # Set proper permissions
    chmod 750 "${BACKUP_DIR:-/backups}"
    chmod 750 "${LOG_DIR:-/var/log/backup}"

    # Create initial log file
    touch "${LOG_DIR:-/var/log/backup}/entrypoint.log"

    log_success "Backup environment initialized"
}

# Validate SQLite database access
validate_sqlite_access() {
    local sqlite_path="${SQLITE_DB_PATH:-/data/bwdata/db.sqlite3}"
    local max_attempts=30
    local attempt=0

    log_info "Validating SQLite database access..."

    while [[ $attempt -lt $max_attempts ]]; do
        if [[ -f "$sqlite_path" ]]; then
            if sqlite3 "$sqlite_path" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
                log_success "SQLite database is accessible: $sqlite_path"
                return 0
            else
                log_info "SQLite database exists but not ready, attempt $((attempt + 1))/$max_attempts"
            fi
        else
            log_info "Waiting for SQLite database to be created, attempt $((attempt + 1))/$max_attempts"
        fi

        sleep 10
        ((attempt++))
    done

    log_error "SQLite database validation failed after $max_attempts attempts"
    return 1
}

# Setup rclone configuration
setup_rclone_config() {
    local rclone_config_dir="/home/backup/.config/rclone"
    local rclone_config_file="$rclone_config_dir/rclone.conf"

    log_info "Setting up rclone configuration..."

    # Create rclone config directory
    mkdir -p "$rclone_config_dir"
    chmod 700 "$rclone_config_dir"

    # Create empty config if it doesn't exist
    if [[ ! -f "$rclone_config_file" ]]; then
        log_info "Creating empty rclone configuration file"
        cat > "$rclone_config_file" << 'EOF'
# rclone configuration file for SQLite backups
# Configure your remote storage here
#
# Example configurations:
#
# [backblaze-b2]
# type = b2
# account = your-account-id
# key = your-application-key
#
# [aws-s3]
# type = s3
# provider = AWS
# access_key_id = your-access-key
# secret_access_key = your-secret-key
# region = us-east-1
#
# Run 'rclone config' to configure interactively
EOF
        chmod 600 "$rclone_config_file"
        log_info "Empty rclone.conf created. Configure your remote before enabling backups."
    else
        log_success "rclone configuration found"
    fi

    # Test rclone if remote is configured
    if [[ -n "${BACKUP_REMOTE:-}" ]]; then
        if rclone listremotes | grep -q "^${BACKUP_REMOTE}:$"; then
            log_success "rclone remote '$BACKUP_REMOTE' is configured"
        else
            log_error "rclone remote '$BACKUP_REMOTE' is not configured"
            return 1
        fi
    else
        log_info "No backup remote configured (BACKUP_REMOTE not set)"
    fi
}

# Setup cron jobs for SQLite backups
setup_cron_jobs() {
    log_info "Setting up cron jobs for SQLite backups..."

    # Create cron file for backup user
    local cron_file="/tmp/backup-cron"

    # Default backup schedule (weekly)
    local backup_schedule="${BACKUP_SCHEDULE:-0 3 * * 1}"

    cat > "$cron_file" << EOF
# VaultWarden SQLite Backup Cron Jobs
# Generated at $(date)

# Main backup job - Weekly on Monday 3 AM
$backup_schedule /usr/local/bin/db-backup.sh >> ${LOG_DIR:-/var/log/backup}/cron.log 2>&1

# Backup verification - Weekly on Sunday 3:30 AM  
${BACKUP_VERIFICATION_SCHEDULE:-30 3 * * 0} /usr/local/bin/verify-backup.sh --latest >> ${LOG_DIR:-/var/log/backup}/verify-cron.log 2>&1

# Log rotation - Daily at 2 AM
0 2 * * * find ${LOG_DIR:-/var/log/backup} -name "*.log" -mtime +${LOG_RETENTION_DAYS:-30} -delete

EOF

    # Install cron jobs
    crontab "$cron_file"
    rm -f "$cron_file"

    log_success "Cron jobs configured:"
    log_info "  Backup: $backup_schedule"
    log_info "  Verification: ${BACKUP_VERIFICATION_SCHEDULE:-30 3 * * 0}"
    log_info "  Log rotation: Daily"
}

# Run initial backup if requested
run_initial_backup() {
    if [[ "${RUN_INITIAL_BACKUP:-false}" == "true" ]]; then
        log_info "Running initial SQLite backup..."
        if /usr/local/bin/db-backup.sh --force; then
            log_success "Initial backup completed"
        else
            log_error "Initial backup failed"
            return 1
        fi
    fi
}

# Display backup status
show_backup_status() {
    log_info "SQLite Backup Container Status:"
    echo "================================"
    echo "Database Type: SQLite"
    echo "Database Path: ${SQLITE_DB_PATH:-/data/bwdata/db.sqlite3}"
    echo "Data Directory: ${VAULTWARDEN_DATA_DIR:-/data/bwdata}"
    echo "Backup Directory: ${BACKUP_DIR:-/backups}"
    echo "Log Directory: ${LOG_DIR:-/var/log/backup}"
    echo "Backup Schedule: ${BACKUP_SCHEDULE:-0 3 * * 1} (Weekly)"
    echo "Backup Remote: ${BACKUP_REMOTE:-Not configured}"
    echo "Retention Days: ${RETENTION_DAYS:-30}"
    echo "Verification: ${BACKUP_VERIFICATION:-true}"
    echo "================================"

    # Show database status
    if [[ -f "${SQLITE_DB_PATH:-/data/bwdata/db.sqlite3}" ]]; then
        local db_size
        db_size=$(du -h "${SQLITE_DB_PATH:-/data/bwdata/db.sqlite3}" | cut -f1)
        echo "Database Status: Available ($db_size)"
    else
        echo "Database Status: Not found (will wait for creation)"
    fi

    # Show recent backups
    if [[ -d "${BACKUP_DIR:-/backups}" ]]; then
        local backup_count
        backup_count=$(find "${BACKUP_DIR:-/backups}" -name "vaultwarden-*backup-*.sql.gz*" | wc -l)
        echo "Local Backups: $backup_count files"

        if [[ $backup_count -gt 0 ]]; then
            echo "Latest Backup:"
            find "${BACKUP_DIR:-/backups}" -name "vaultwarden-*backup-*.sql.gz*" -printf "%T@ %p\n" | sort -nr | head -1 | cut -d' ' -f2- | while read -r file; do
                local file_size
                file_size=$(du -h "$file" | cut -f1)
                echo "  $(basename "$file") ($file_size)"
            done
        fi
    fi
    echo "================================"
}

# Main entrypoint function
main() {
    log_info "Starting VaultWarden SQLite Backup Container..."

    # Initialize environment
    initialize_backup_environment

    # Wait for and validate SQLite database
    if ! validate_sqlite_access; then
        log_error "SQLite database validation failed"
        exit 1
    fi

    # Setup rclone for remote backups
    if ! setup_rclone_config; then
        log_error "rclone configuration failed"
        # Don't exit - local backups can still work
    fi

    # Setup cron jobs
    setup_cron_jobs

    # Run initial backup if requested
    if ! run_initial_backup; then
        log_error "Initial backup failed"
        # Don't exit - container should still start for scheduled backups
    fi

    # Show status
    show_backup_status

    log_success "SQLite backup container initialized successfully"

    # Execute the main command (usually crond)
    exec "$@"
}

# Run main function with all arguments
main "$@"
