#!/usr/bin/env bash
# db-restore.sh -- SQLite Restore Script for VaultWarden-OCI-Slim
# Optimized for 1 OCPU/6GB deployment with SQLite database

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
BACKUP_DIR="${BACKUP_DIR:-/backups}"
LOG_DIR="${LOG_DIR:-/var/log/backup}"
SQLITE_DB_PATH=/data/bwdata/db.sqlite3
VAULTWARDEN_DATA_DIR="${VAULTWARDEN_DATA_DIR:-/data/bwdata}"
BACKUP_PASSPHRASE="${BACKUP_PASSPHRASE:-}"

# Create necessary directories
mkdir -p "$LOG_DIR"

# Logging setup
LOG_FILE="$LOG_DIR/sqlite-restore-$(date +%Y%m%d_%H%M%S).log"
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

# Find available backups
list_available_backups() {
    log_info "Scanning for available SQLite backups..."

    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_error "Backup directory not found: $BACKUP_DIR"
        return 1
    fi

    # Find SQLite backup files
    local sqlite_backups
    sqlite_backups=$(find "$BACKUP_DIR" -name "*sqlite*backup*.sql*" -type f | sort -r)

    if [[ -z "$sqlite_backups" ]]; then
        log_error "No SQLite backup files found in $BACKUP_DIR"
        return 1
    fi

    echo -e "\nAvailable SQLite backups:"
    echo "========================="
    local count=0
    while IFS= read -r backup_file; do
        if [[ -n "$backup_file" ]]; then
            count=$((count + 1))
            local file_size file_date
            file_size=$(du -h "$backup_file" | cut -f1)
            file_date=$(stat -c %y "$backup_file" | cut -d'.' -f1)
            echo "$count) $(basename "$backup_file") - $file_size - $file_date"
        fi
    done <<< "$sqlite_backups"

    echo "$sqlite_backups"
}

# Decrypt backup if encrypted
decrypt_backup() {
    local encrypted_file="$1"
    local output_file="$2"

    if [[ -z "$BACKUP_PASSPHRASE" ]]; then
        log_error "Backup passphrase not provided for encrypted backup"
        return 1
    fi

    log_info "Decrypting backup file..."

    if echo "$BACKUP_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 --decrypt "$encrypted_file" > "$output_file"; then
        log_success "Backup decrypted successfully"
        return 0
    else
        log_error "Failed to decrypt backup"
        return 1
    fi
}

# Decompress backup
decompress_backup() {
    local compressed_file="$1"
    local output_file="$2"

    log_info "Decompressing backup file..."

    if gzip -dc "$compressed_file" > "$output_file"; then
        log_success "Backup decompressed successfully"
        return 0
    else
        log_error "Failed to decompress backup"
        return 1
    fi
}

# Validate backup file
validate_backup() {
    local backup_file="$1"

    log_info "Validating backup file format..."

    # Check if it's a valid SQL dump
    if head -10 "$backup_file" | grep -q "SQLite format\|BEGIN TRANSACTION\|PRAGMA"; then
        log_success "Backup file appears to be a valid SQLite dump"
        return 0
    else
        log_error "Backup file does not appear to be a valid SQLite dump"
        return 1
    fi
}

# Create backup of current database
backup_current_database() {
    local backup_suffix="pre-restore-$(date +%Y%m%d_%H%M%S)"
    local current_backup="$BACKUP_DIR/current-db-backup-$backup_suffix.sql"

    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        log_info "No existing database to backup"
        return 0
    fi

    log_info "Creating backup of current database..."

    if sqlite3 "$SQLITE_DB_PATH" ".dump" > "$current_backup"; then
        log_success "Current database backed up to: $current_backup"
        echo "$current_backup"
        return 0
    else
        log_error "Failed to backup current database"
        return 1
    fi
}

# Stop VaultWarden service
stop_vaultwarden() {
    log_info "Stopping VaultWarden service..."

    if docker compose stop vaultwarden; then
        log_success "VaultWarden stopped"

        # Wait a moment for the service to fully stop
        sleep 5
        return 0
    else
        log_error "Failed to stop VaultWarden"
        return 1
    fi
}

# Start VaultWarden service
start_vaultwarden() {
    log_info "Starting VaultWarden service..."

    if docker compose start vaultwarden; then
        log_success "VaultWarden started"

        # Wait for service to be ready
        log_info "Waiting for VaultWarden to be ready..."
        sleep 10

        # Check if service is healthy
        local max_attempts=30
        local attempt=0

        while [[ $attempt -lt $max_attempts ]]; do
            if docker compose exec vaultwarden curl -f http://localhost:80/alive >/dev/null 2>&1; then
                log_success "VaultWarden is ready"
                return 0
            fi

            sleep 2
            ((attempt++))
        done

        log_warning "VaultWarden started but may not be fully ready"
        return 0
    else
        log_error "Failed to start VaultWarden"
        return 1
    fi
}

# Restore database from backup
restore_database() {
    local backup_file="$1"

    log_info "Restoring SQLite database from backup..."

    # Remove existing database and related files
    if [[ -f "$SQLITE_DB_PATH" ]]; then
        rm -f "$SQLITE_DB_PATH"
        log_info "Removed existing database file"
    fi

    # Remove WAL and SHM files if they exist
    rm -f "${SQLITE_DB_PATH}-wal" "${SQLITE_DB_PATH}-shm"

    # Restore from SQL dump
    if sqlite3 "$SQLITE_DB_PATH" < "$backup_file"; then
        log_success "Database restored from backup"

        # Set proper permissions
        chown "${PUID:-1000}:${PGID:-1000}" "$SQLITE_DB_PATH" || true
        chmod 644 "$SQLITE_DB_PATH"

        # Verify restored database
        if sqlite3 "$SQLITE_DB_PATH" "PRAGMA integrity_check;" >/dev/null 2>&1; then
            log_success "Restored database integrity check passed"
            return 0
        else
            log_error "Restored database failed integrity check"
            return 1
        fi
    else
        log_error "Failed to restore database from backup"
        return 1
    fi
}

# Restore file backup (attachments, etc.)
restore_files() {
    local file_backup="$1"

    if [[ ! -f "$file_backup" ]]; then
        log_info "No file backup specified or file not found"
        return 0
    fi

    log_info "Restoring files from backup..."

    # Create temporary extraction directory
    local temp_dir
    temp_dir=$(mktemp -d)

    # Extract files backup
    if tar -xzf "$file_backup" -C "$temp_dir"; then
        # Copy extracted files to data directory
        if cp -r "$temp_dir"/* "$(dirname "$VAULTWARDEN_DATA_DIR")/"; then
            log_success "Files restored from backup"
            rm -rf "$temp_dir"
            return 0
        else
            log_error "Failed to copy restored files"
            rm -rf "$temp_dir"
            return 1
        fi
    else
        log_error "Failed to extract file backup"
        rm -rf "$temp_dir"
        return 1
    fi
}

# Interactive backup selection
select_backup_interactively() {
    local available_backups
    available_backups=$(list_available_backups)

    if [[ -z "$available_backups" ]]; then
        return 1
    fi

    echo ""
    read -p "Enter backup number to restore (or 'q' to quit): " selection

    if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
        log_info "Restore cancelled by user"
        exit 0
    fi

    # Get selected backup file
    local selected_backup
    selected_backup=$(echo "$available_backups" | sed -n "${selection}p")

    if [[ -z "$selected_backup" || ! -f "$selected_backup" ]]; then
        log_error "Invalid selection or backup file not found"
        return 1
    fi

    echo "$selected_backup"
}

# Main restore function
main() {
    local backup_file=""
    local file_backup=""
    local auto_confirm=false
    local latest_backup=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --backup)
                backup_file="$2"
                shift 2
                ;;
            --file-backup)
                file_backup="$2"
                shift 2
                ;;
            --latest)
                latest_backup=true
                shift
                ;;
            --yes|-y)
                auto_confirm=true
                shift
                ;;
            --help|-h)
                cat <<EOF
VaultWarden SQLite Restore Script

Usage: $0 [OPTIONS]

Options:
    --backup FILE       Specific backup file to restore
    --file-backup FILE  File backup (attachments) to restore
    --latest           Restore from latest backup
    --yes, -y          Auto-confirm without prompts
    --help, -h         Show this help message

Environment Variables:
    SQLITE_DB_PATH          Path to SQLite database (default: /data/bw/data/bwdata/db.sqlite3)
    VAULTWARDEN_DATA_DIR    VaultWarden data directory (default: /data/bwdata)
    BACKUP_DIR              Backup storage directory (default: /backups)
    LOG_DIR                 Log directory (default: /var/log/backup)
    BACKUP_PASSPHRASE       GPG decryption passphrase

Examples:
    $0                                      # Interactive backup selection
    $0 --latest                             # Restore latest backup
    $0 --backup /backups/backup.sql.gz     # Restore specific backup
    $0 --latest --yes                       # Restore latest without prompts

Warning: This will replace your current VaultWarden database!

EOF
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done

    log_info "Starting VaultWarden SQLite database restore..."

    # Find backup file if not specified
    if [[ -z "$backup_file" ]]; then
        if [[ "$latest_backup" == "true" ]]; then
            backup_file=$(find "$BACKUP_DIR" -name "*sqlite*backup*.sql*" -type f | sort -r | head -1)
            if [[ -z "$backup_file" ]]; then
                log_error "No backup files found"
                exit 1
            fi
            log_info "Selected latest backup: $(basename "$backup_file")"
        else
            backup_file=$(select_backup_interactively)
            if [[ -z "$backup_file" ]]; then
                log_error "No backup file selected"
                exit 1
            fi
        fi
    fi

    # Verify backup file exists
    if [[ ! -f "$backup_file" ]]; then
        log_error "Backup file not found: $backup_file"
        exit 1
    fi

    log_info "Selected backup: $(basename "$backup_file")"

    # Prepare backup file for restore
    local restore_file="/tmp/sqlite-restore-$(date +%Y%m%d_%H%M%S).sql"

    if [[ "$backup_file" == *.gpg ]]; then
        # Decrypt encrypted backup
        local decrypted_file="/tmp/sqlite-decrypt-$(date +%Y%m%d_%H%M%S).sql.gz"
        if ! decrypt_backup "$backup_file" "$decrypted_file"; then
            exit 1
        fi
        backup_file="$decrypted_file"
    fi

    if [[ "$backup_file" == *.gz ]]; then
        # Decompress backup
        if ! decompress_backup "$backup_file" "$restore_file"; then
            exit 1
        fi
    else
        # Copy uncompressed backup
        cp "$backup_file" "$restore_file"
    fi

    # Validate backup file
    if ! validate_backup "$restore_file"; then
        exit 1
    fi

    # Confirm restore operation
    if [[ "$auto_confirm" != "true" ]]; then
        echo ""
        echo -e "${RED}WARNING: This will replace your current VaultWarden database!${NC}"
        echo "Current database: $SQLITE_DB_PATH"
        echo "Backup file: $(basename "$backup_file")"
        echo ""
        read -p "Are you sure you want to continue? (yes/no): " confirm

        if [[ "$confirm" != "yes" && "$confirm" != "y" ]]; then
            log_info "Restore cancelled by user"
            rm -f "$restore_file"
            exit 0
        fi
    fi

    # Create backup of current database
    local current_backup
    if current_backup=$(backup_current_database); then
        log_info "Current database backed up to: $current_backup"
    fi

    # Stop VaultWarden service
    if ! stop_vaultwarden; then
        log_error "Failed to stop VaultWarden service"
        exit 1
    fi

    # Restore database
    if ! restore_database "$restore_file"; then
        log_error "Database restore failed"

        # Attempt to start service anyway
        start_vaultwarden
        exit 1
    fi

    # Restore files if specified
    if [[ -n "$file_backup" ]]; then
        if ! restore_files "$file_backup"; then
            log_warning "File restore failed, but database was restored successfully"
        fi
    fi

    # Start VaultWarden service
    if ! start_vaultwarden; then
        log_error "Failed to start VaultWarden service after restore"
        exit 1
    fi

    # Cleanup
    rm -f "$restore_file"
    if [[ -n "${decrypted_file:-}" ]]; then
        rm -f "$decrypted_file"
    fi

    log_success "SQLite database restore completed successfully!"
    log_info "Log file: $LOG_FILE"

    if [[ -n "${current_backup:-}" ]]; then
        log_info "Previous database backed up to: $current_backup"
    fi

    echo ""
    echo "🎉 Restore completed! Your VaultWarden should now be running with the restored data."
    echo "   Access your vault at: https://your-domain.com"
    echo "   Check service status: docker compose ps"
}

# Execute main function
main "$@"
