#!/usr/bin/env bash
# backup/full-backup/create-full-backup.sh - Complete VaultWarden SQLite system backup for VM migration (Enhanced with HTML notifications)
# This script creates a comprehensive backup of everything needed for disaster recovery

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Configuration - Updated for /backup/full-backup/ directory structure
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BACKUP_DIR="$(dirname "$SCRIPT_DIR")"  # /backup
readonly PROJECT_ROOT="$(dirname "$BACKUP_DIR")"  # project root (two levels up)
readonly TIMESTAMP=$(date +%Y%m%d_%H%M%S)
readonly BACKUP_NAME="vaultwarden_sqlite_full_${TIMESTAMP}"
readonly OUTPUT_DIR="${PROJECT_ROOT}/migration_backups"
readonly TEMP_DIR="/tmp/${BACKUP_NAME}"

# Load settings if available
if [[ -f "${PROJECT_ROOT}/settings.env" ]]; then
    source "${PROJECT_ROOT}/settings.env"
fi

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Enhanced HTML email notification function
send_backup_notification() {
    local status="$1"
    local backup_name="$2"
    local backup_size="${3:-N/A}"
    local start_time="${4:-}"
    local end_time="${5:-}"

    # Check if email is configured
    local email_recipient="${BACKUP_EMAIL:-${ADMIN_EMAIL:-${ALERT_EMAIL:-}}}"
    if [[ -z "$email_recipient" ]]; then
        log_info "No email recipient configured for notifications"
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

    local subject="${status_icon} VaultWarden Full System Backup ${status}"

    # Get backup contents info
    local backup_contents=""
    if [[ -f "$OUTPUT_DIR/${backup_name}_manifest.txt" ]]; then
        backup_contents="<tr><td>📋 Manifest</td><td>Available</td></tr>"
    fi
    
    local sqlite_info="SQLite database included"
    if [[ -f "$PROJECT_ROOT/data/bw/data/bwdata/db.sqlite3" ]]; then
        local db_size
        db_size=$(du -h "$PROJECT_ROOT/data/bw/data/bwdata/db.sqlite3" | cut -f1)
        sqlite_info="SQLite database ($db_size)"
    fi

    # Generate HTML email
    local html_body=$(cat <<EOF
From: VaultWarden Backup <${SMTP_FROM:-noreply@$(hostname -d || echo localdomain)}>
To: $email_recipient
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
  .code { background: #f8f9fa; padding: 15px; border-radius: 4px; font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace; font-size: 12px; line-height: 1.6; }
</style>
</head>
<body>
  <div class="card">
    <div class="bar"></div>
    <div class="content">
      <h2>${status_icon} VaultWarden Full System Backup</h2>
      <div class="muted">Status: <span class="status">${status}</span> &nbsp;- &nbsp; Type: <b>SQLite Migration Backup</b> &nbsp;- &nbsp; Host: <b>$(hostname)</b></div>

      <h3 class="section-title">📦 Backup Summary</h3>
      <table>
        <tr><th>Component</th><th>Details</th></tr>
        <tr><td>🎯 Backup Name</td><td>${backup_name}</td></tr>
        <tr><td>📊 Archive Size</td><td>${backup_size}</td></tr>
        $([[ -n "$duration" ]] && echo "<tr><td>⏱️ Duration</td><td>${duration}</td></tr>")
        <tr><td>🗄️ Database</td><td>${sqlite_info}</td></tr>
        <tr><td>📁 Data Directories</td><td>Complete backup included</td></tr>
        <tr><td>⚙️ Configuration</td><td>All settings and scripts</td></tr>
        <tr><td>🔐 SSL Certificates</td><td>Let's Encrypt certificates</td></tr>
        <tr><td>☁️ Remote Upload</td><td>$([[ -n "${BACKUP_REMOTE:-${RCLONE_REMOTE:-}}" ]] && echo "${BACKUP_REMOTE:-$RCLONE_REMOTE}" || echo "Not configured")</td></tr>
        ${backup_contents}
      </table>

      <h3 class="section-title">🔄 Migration Commands</h3>
      <div class="code">
# Automated VM rebuild:
./backup/full-backup/rebuild-vm.sh ${backup_name}.tar.gz

# Manual restoration:
./backup/full-backup/restore-full-backup.sh ${backup_name}.tar.gz

# Validate backup:
./backup/full-backup/validate-backup.sh ${backup_name}.tar.gz
      </div>

      <div class="footer">
        Generated by VaultWarden-OCI-Slim Full Backup System (SQLite)<br>
        Location: ${OUTPUT_DIR}
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
        log_success "HTML notification sent to $email_recipient"
    elif command -v mail >/dev/null 2>&1; then
        # Fallback to plain text
        local plain_body="VaultWarden full system backup completed with status: $status

Backup Details:
- Name: $backup_name
- Size: $backup_size
- Duration: ${duration:-N/A}
- Type: SQLite Migration Backup
- Location: $OUTPUT_DIR
- Server: $(hostname)

Migration Commands:
- Automated: ./backup/full-backup/rebuild-vm.sh ${backup_name}.tar.gz
- Manual: ./backup/full-backup/restore-full-backup.sh ${backup_name}.tar.gz
- Validate: ./backup/full-backup/validate-backup.sh ${backup_name}.tar.gz"

        echo "$plain_body" | mail -s "$subject" "$email_recipient"
        log_success "Plain text notification sent to $email_recipient"
    else
        log_info "No mail command available for notifications"
    fi
}

# Check if running from correct directory
validate_environment() {
    if [[ ! -f "$PROJECT_ROOT/docker-compose.yml" ]]; then
        log_error "Not running from VaultWarden project directory. PROJECT_ROOT: $PROJECT_ROOT"
    fi

    if [[ ! -d "$PROJECT_ROOT/data" ]]; then
        log_error "Data directory not found. Is VaultWarden initialized?"
    fi

    # Check for SQLite database
    if [[ ! -f "$PROJECT_ROOT/data/bw/data/bwdata/db.sqlite3" ]]; then
        log_warning "SQLite database not found - may not have been created yet"
    fi

    log_success "Environment validation passed"
}

# Create backup directories
setup_directories() {
    log_info "Setting up backup directories..."
    mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"
    chmod 755 "$OUTPUT_DIR"
    log_success "Directories created: $OUTPUT_DIR, $TEMP_DIR"
}

# Create SQLite database backup
backup_sqlite_database() {
    log_info "Step 1/6: Creating SQLite database backup..."

    cd "$PROJECT_ROOT"

    local sqlite_db_path="./data/bw/data/bwdata/db.sqlite3"
    local backup_timestamp=$(date +%Y%m%d_%H%M%S)
    local sql_backup="$TEMP_DIR/vaultwarden-sqlite-backup-${backup_timestamp}.sql"

    # Check if SQLite database exists
    if [[ ! -f "$sqlite_db_path" ]]; then
        log_warning "SQLite database not found at $sqlite_db_path - creating empty backup"
        echo "-- VaultWarden SQLite database backup (empty - database not created yet)" > "$sql_backup"
        echo "-- Created: $(date)" >> "$sql_backup"
        echo "-- This backup is empty because the database has not been initialized yet." >> "$sql_backup"
        log_success "Empty database backup created for uninitialized system"
        return 0
    fi

    # Method 1: Try using backup service if running
    if docker compose ps --services --filter "status=running" | grep -q "bw_backup"; then
        log_info "Using backup service for SQLite database backup..."

        if docker compose exec -T bw_backup /usr/local/bin/db-backup.sh --force; then
            # Find the latest backup created by the service
            local latest_service_backup
            latest_service_backup=$(find "$PROJECT_ROOT/data/backups" -name "*sqlite*backup*.sql*" -type f -exec ls -t {} + | head -1 || echo "")

            if [[ -n "$latest_service_backup" && -f "$latest_service_backup" ]]; then
                cp "$latest_service_backup" "$sql_backup"
                log_success "SQLite database backup via service: $(basename "$latest_service_backup")"
                return 0
            else
                log_warning "Service backup completed but file not found, trying direct method"
            fi
        else
            log_warning "Service backup failed, trying direct method"
        fi
    fi

    # Method 2: Direct SQLite backup using sqlite3 command
    log_info "Creating direct SQLite database backup..."

    # Check if we can access the database directly
    if command -v sqlite3 >/dev/null 2>&1; then
        # Try to create backup directly
        if sqlite3 "$sqlite_db_path" ".dump" > "$sql_backup"; then
            log_success "Direct SQLite backup created successfully"
        else
            log_warning "Direct SQLite access failed, trying container method"

            # Method 3: Use VaultWarden container to create backup
            local vw_container_id
            vw_container_id=$(docker compose ps -q vaultwarden || echo "")

            if [[ -n "$vw_container_id" ]]; then
                log_info "Using VaultWarden container for SQLite backup..."
                if docker exec "$vw_container_id" sqlite3 //data/bwdata/db.sqlite3 ".dump" > "$sql_backup"; then
                    log_success "SQLite backup via VaultWarden container created"
                else
                    log_error "All SQLite backup methods failed"
                fi
            else
                log_error "VaultWarden container not running and direct SQLite access failed"
            fi
        fi
    else
        log_warning "sqlite3 command not available, trying container method"

        # Use container method directly
        local vw_container_id
        vw_container_id=$(docker compose ps -q vaultwarden || echo "")

        if [[ -n "$vw_container_id" ]]; then
            log_info "Using VaultWarden container for SQLite backup..."
            if docker exec "$vw_container_id" sqlite3 //data/bwdata/db.sqlite3 ".dump" > "$sql_backup"; then
                log_success "SQLite backup via VaultWarden container created"
            else
                log_error "Container-based SQLite backup failed"
            fi
        else
            log_error "No method available for SQLite backup (no sqlite3 command and no container)"
        fi
    fi

    # Verify backup was created and has content
    if [[ -f "$sql_backup" && -s "$sql_backup" ]]; then
        local backup_size
        backup_size=$(du -h "$sql_backup" | cut -f1)
        log_success "SQLite database backup completed ($backup_size)"

        # Verify backup contains expected content
        if grep -q "CREATE TABLE" "$sql_backup"; then
            log_success "Backup verification: Contains table structures"
        else
            log_warning "Backup verification: No table structures found (database may be empty)"
        fi

        if grep -q "INSERT INTO" "$sql_backup"; then
            log_success "Backup verification: Contains data"
        else
            log_info "Backup verification: No data inserts found (database may be empty)"
        fi
    else
        log_error "SQLite backup file was not created or is empty"
    fi
}

# Backup data directories
backup_data_directories() {
    log_info "Step 2/6: Backing up data directories..."

    cd "$PROJECT_ROOT"

    # Create comprehensive data backup excluding temporary files
    tar -czf "$TEMP_DIR/data_directories.tar.gz" \
        --exclude="./data/backups" \
        --exclude="./data/backup_logs" \
        --exclude="./data/*/lost+found" \
        --exclude="./data/*/*.tmp" \
        --exclude="./data/*/*.lock" \
        --exclude="./data/bw/data/bwdata/db.sqlite3-wal" \
        --exclude="./data/bw/data/bwdata/db.sqlite3-shm" \
        ./data/

    if [[ -f "$TEMP_DIR/data_directories.tar.gz" ]]; then
        local size
        size=$(du -h "$TEMP_DIR/data_directories.tar.gz" | cut -f1)
        log_success "Data directories backed up ($size)"
    else
        log_error "Failed to create data directories backup"
    fi
}

# Backup configuration files
backup_configurations() {
    log_info "Step 3/6: Backing up configuration files..."

    cd "$PROJECT_ROOT"

    # Backup all configuration files and scripts
    tar -czf "$TEMP_DIR/configuration.tar.gz" \
        --exclude="./migration_backups" \
        --exclude="./.git" \
        --exclude="./data" \
        --exclude="*.backup" \
        --exclude="*~" \
        ./settings.env \
        ./docker-compose.yml \
        ./caddy/ \
        ./fail2ban/ \
        ./config/ \
        ./lib/ \
        ./backup/ \
        ./ddclient/ \
        ./*.sh \
        || true

    if [[ -f "$TEMP_DIR/configuration.tar.gz" ]]; then
        log_success "Configuration files backed up"
    else
        log_warning "Some configuration files may be missing"
        # Create minimal config backup
        tar -czf "$TEMP_DIR/configuration.tar.gz" \
            ./settings.env \
            ./docker-compose.yml \
            || log_error "Critical configuration files missing"
    fi
}

# Backup SSL certificates
backup_ssl_certificates() {
    log_info "Step 4/6: Backing up SSL certificates..."

    if [[ -d "$PROJECT_ROOT/data/caddy_data" ]]; then
        tar -czf "$TEMP_DIR/ssl_certificates.tar.gz" \
            "$PROJECT_ROOT/data/caddy_data/" \
            || true

        if [[ -f "$TEMP_DIR/ssl_certificates.tar.gz" ]]; then
            local size
            size=$(du -h "$TEMP_DIR/ssl_certificates.tar.gz" | cut -f1)
            log_success "SSL certificates backed up ($size)"
        else
            log_warning "No SSL certificates found or backup failed"
        fi
    else
        log_warning "Caddy data directory not found - SSL certificates not backed up"
    fi
}

# Create system information snapshot
backup_system_info() {
    log_info "Step 5/6: Creating system information snapshot..."

    # Create system info file
    cat > "$TEMP_DIR/system_info.txt" << EOF
# VaultWarden SQLite Full System Backup Information
Backup Date: $(date)
Backup Name: ${BACKUP_NAME}
Database Type: SQLite
Hostname: $(hostname)
OS Version: $(lsb_release -d || echo "Unknown")
Architecture: $(uname -m)
Kernel: $(uname -r)
Docker Version: $(docker --version || echo "Not available")
Docker Compose Version: $(docker compose version || echo "Not available")

# Container Status at Backup Time
$(cd "$PROJECT_ROOT" && docker compose ps || echo "Could not get container status")

# Disk Usage
$(df -h "$PROJECT_ROOT" || echo "Could not get disk usage")

# Memory Usage
$(free -h || echo "Could not get memory usage")

# SQLite Database Information
$(if [[ -f "$PROJECT_ROOT/data/bw/data/bwdata/db.sqlite3" ]]; then
    echo "SQLite Database Size: $(du -h "$PROJECT_ROOT/data/bw/data/bwdata/db.sqlite3" | cut -f1)"
    if command -v sqlite3 >/dev/null 2>&1; then
        echo "SQLite Database Tables: $(sqlite3 "$PROJECT_ROOT/data/bw/data/bwdata/db.sqlite3" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" || echo "unknown")"
        echo "SQLite Journal Mode: $(sqlite3 "$PROJECT_ROOT/data/bw/data/bwdata/db.sqlite3" "PRAGMA journal_mode;" || echo "unknown")"
        echo "SQLite Page Size: $(sqlite3 "$PROJECT_ROOT/data/bw/data/bwdata/db.sqlite3" "PRAGMA page_size;" || echo "unknown")"
    fi
else
    echo "SQLite Database: Not found (may not be initialized yet)"
fi)

# VaultWarden Configuration Summary (SQLite Mode)
$(grep -E "^(DOMAIN|APP_DOMAIN|DATABASE_URL|ROCKET_WORKERS|WEBSOCKET_ENABLED|BACKUP_)" "$PROJECT_ROOT/settings.env" || echo "Could not read settings")

# Backup File Sizes
Data Directories: $(du -h "$TEMP_DIR/data_directories.tar.gz" | cut -f1 || echo "N/A")
Configuration: $(du -h "$TEMP_DIR/configuration.tar.gz" | cut -f1 || echo "N/A")
SSL Certificates: $(du -h "$TEMP_DIR/ssl_certificates.tar.gz" | cut -f1 || echo "N/A")
SQLite Database: $(find "$TEMP_DIR" -name "*sqlite*backup*.sql" -exec du -h {} \; | cut -f1 || echo "N/A")
EOF

    log_success "System information snapshot created"
}

# Create final archive
create_final_archive() {
    log_info "Step 6/6: Creating final backup archive..."

    cd "$(dirname "$TEMP_DIR")"

    # Create compressed archive
    if tar -czf "$OUTPUT_DIR/${BACKUP_NAME}.tar.gz" "$(basename "$TEMP_DIR")"; then
        log_success "Archive created: ${BACKUP_NAME}.tar.gz"
    else
        log_error "Failed to create archive"
    fi

    if [[ -f "$OUTPUT_DIR/${BACKUP_NAME}.tar.gz" ]]; then
        # Create checksums
        cd "$OUTPUT_DIR"
        sha256sum "${BACKUP_NAME}.tar.gz" > "${BACKUP_NAME}.sha256"
        md5sum "${BACKUP_NAME}.tar.gz" > "${BACKUP_NAME}.md5"

        # Create backup manifest
        cat > "${BACKUP_NAME}_manifest.txt" << EOF
VaultWarden SQLite Full System Backup Manifest
Backup Name: ${BACKUP_NAME}
Database Type: SQLite
Created: $(date)
Size: $(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
Location: $(pwd)/${BACKUP_NAME}.tar.gz

Contents:
- SQLite database backup (SQL dump)
- Data directories (bwdata, caddy_data, caddy_config, etc.)
- Configuration files (settings.env, docker-compose.yml, scripts)
- SSL certificates (Let's Encrypt)
- System information snapshot

Checksums:
SHA256: $(cut -d' ' -f1 "${BACKUP_NAME}.sha256")
MD5: $(cut -d' ' -f1 "${BACKUP_NAME}.md5")

Restoration Commands:
# Automated disaster recovery:
./backup/full-backup/rebuild-vm.sh ${BACKUP_NAME}.tar.gz

# Manual restoration:
./backup/full-backup/restore-full-backup.sh ${BACKUP_NAME}.tar.gz

# Backup validation:
./backup/full-backup/validate-backup.sh ${BACKUP_NAME}.tar.gz

SQLite-Specific Notes:
- Database file: data/bw/data/bwdata/db.sqlite3
- No external database server required
- Backup includes complete SQL dump for portability
- WAL and SHM files excluded (will be recreated)

Created by: create-full-backup.sh v2.0 (SQLite)
EOF

        log_success "Backup manifest created"
    else
        log_error "Failed to create final archive"
    fi
}

# Upload to remote storage if configured
upload_to_remote() {
    log_info "Checking for remote storage configuration..."

    cd "$PROJECT_ROOT"

    # Check if rclone is configured and remote storage is available
    if [[ -f "$PROJECT_ROOT/backup/config/rclone.conf" ]]; then
        # Map RCLONE variables for compatibility
        local backup_remote="${BACKUP_REMOTE:-${RCLONE_REMOTE:-}}"
        local backup_path="${BACKUP_PATH:-${RCLONE_PATH:-vaultwarden-backups}}"

        if [[ -n "$backup_remote" ]]; then
            log_info "Uploading to remote storage: $backup_remote"

            # Copy the backup file to the backup container's volume first
            cp "$OUTPUT_DIR/${BACKUP_NAME}.tar.gz" "$PROJECT_ROOT/data/backups/" || {
                log_warning "Could not copy to backup container volume, trying direct rclone"
            }
            cp "$OUTPUT_DIR/${BACKUP_NAME}.sha256" "$PROJECT_ROOT/data/backups/" || true
            cp "$OUTPUT_DIR/${BACKUP_NAME}.md5" "$PROJECT_ROOT/data/backups/" || true
            cp "$OUTPUT_DIR/${BACKUP_NAME}_manifest.txt" "$PROJECT_ROOT/data/backups/" || true

            # Upload via rclone from container if backup service is available
            if docker compose ps --services --filter "status=running" | grep -q "bw_backup"; then
                if docker compose exec -T bw_backup rclone copy "/backups/${BACKUP_NAME}.tar.gz" "${backup_remote}:${backup_path}/full/" --config /home/backup/.config/rclone/rclone.conf; then
                    # Also upload checksums and manifest
                    docker compose exec -T bw_backup rclone copy "/backups/${BACKUP_NAME}.sha256" "${backup_remote}:${backup_path}/full/" --config /home/backup/.config/rclone/rclone.conf || true
                    docker compose exec -T bw_backup rclone copy "/backups/${BACKUP_NAME}.md5" "${backup_remote}:${backup_path}/full/" --config /home/backup/.config/rclone/rclone.conf || true
                    docker compose exec -T bw_backup rclone copy "/backups/${BACKUP_NAME}_manifest.txt" "${backup_remote}:${backup_path}/full/" --config /home/backup/.config/rclone/rclone.conf || true

                    log_success "SQLite backup uploaded to remote storage"
                    log_info "Remote location: ${backup_remote}:${backup_path}/full/"
                else
                    log_warning "Remote upload failed - SQLite backup saved locally only"
                fi

                # Clean up temporary copies
                rm -f "$PROJECT_ROOT/data/backups/${BACKUP_NAME}."* || true
            else
                log_info "Backup service not running - skipping remote upload"
            fi
        else
            log_info "No remote storage configured (BACKUP_REMOTE/RCLONE_REMOTE not set)"
        fi
    else
        log_info "rclone not configured - SQLite backup saved locally only"
    fi
}

# Cleanup temporary files
cleanup() {
    log_info "Cleaning up temporary files..."
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_success "Temporary files cleaned up"
    fi
}

# Show backup summary
show_summary() {
    echo ""
    echo "=============================================="
    echo -e "${GREEN}✅ COMPLETE SQLITE BACKUP READY FOR VM MIGRATION${NC}"
    echo "=============================================="
    echo ""
    echo "📁 Backup Location: $OUTPUT_DIR/${BACKUP_NAME}.tar.gz"
    echo "📊 Backup Size: $(du -h "$OUTPUT_DIR/${BACKUP_NAME}.tar.gz" | cut -f1)"
    echo "🔐 SHA256: $(cut -d' ' -f1 "$OUTPUT_DIR/${BACKUP_NAME}.sha256")"
    echo "📋 Manifest: $OUTPUT_DIR/${BACKUP_NAME}_manifest.txt"
    echo ""
    echo -e "${BLUE}📋 SQLite Backup Contents:${NC}"
    echo "✓ SQLite database (complete SQL dump with all user data)"
    echo "✓ Configuration files (settings, scripts, compose file)"  
    echo "✓ SSL certificates (Let's Encrypt)"
    echo "✓ Application data (VaultWarden data directory)"
    echo "✓ User attachments (file uploads)"
    echo "✓ System information (for troubleshooting)"
    echo ""
    echo -e "${BLUE}🔄 To Restore on New VM:${NC}"
    echo ""
    echo "Option A - Automated Recovery:"
    echo "  1. ./init-setup.sh"
    echo "  2. Copy backup file to new VM"
    echo "  3. ./backup/full-backup/rebuild-vm.sh ${BACKUP_NAME}.tar.gz"
    echo ""
    echo "Option B - Manual Recovery:"
    echo "  1. ./init-setup.sh"
    echo "  2. ./backup/full-backup/restore-full-backup.sh ${BACKUP_NAME}.tar.gz"
    echo "  3. Update settings.env for new VM (if needed)"
    echo "  4. ./startup.sh"
    echo ""
    echo -e "${BLUE}🔍 Backup Validation:${NC}"
    echo "  ./backup/full-backup/validate-backup.sh --latest"
    echo "  ./backup/full-backup/validate-backup.sh --deep ${BACKUP_NAME}.tar.gz"
    echo "  ./backup/dr-monthly-test.sh  # SQLite-specific DR test"
    echo ""
    echo -e "${YELLOW}⚠️  SQLITE-SPECIFIC REMINDERS:${NC}"
    echo "• No external database server needed (file-based SQLite)"
    echo "• Backup includes complete SQL dump for maximum portability"
    echo "• Update DNS records when switching to new VM"  
    echo "• Test backup restoration regularly (monthly recommended)"
    echo "• SQLite database will be recreated from SQL dump during restoration"
    echo ""

    # Show storage locations
    echo -e "${BLUE}💾 Storage Locations:${NC}"
    echo "  Local: $OUTPUT_DIR/"
    local backup_remote="${BACKUP_REMOTE:-${RCLONE_REMOTE:-}}"
    if [[ -n "$backup_remote" ]]; then
        echo "  Remote: ${backup_remote}:${BACKUP_PATH:-${RCLONE_PATH:-vaultwarden-backups}}/full/"
    else
        echo "  Remote: Not configured"
    fi

    # Show SQLite-specific info
    echo ""
    echo -e "${BLUE}💽 SQLite Database Info:${NC}"
    if [[ -f "$PROJECT_ROOT/data/bw/data/bwdata/db.sqlite3" ]]; then
        local db_size
        db_size=$(du -h "$PROJECT_ROOT/data/bw/data/bwdata/db.sqlite3" | cut -f1)
        echo "  Database size: $db_size"
        if command -v sqlite3 >/dev/null 2>&1; then
            local table_count
            table_count=$(sqlite3 "$PROJECT_ROOT/data/bw/data/bwdata/db.sqlite3" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" || echo "unknown")
            echo "  Table count: $table_count"
        fi
    else
        echo "  Database: Not yet created (will be initialized on first run)"
    fi
    echo ""
}

# Main execution
main() {
    local start_time=$(date +%s)
    
    echo "=============================================="
    echo "🔄 VaultWarden SQLite Complete System Backup"
    echo "=============================================="
    echo ""

    log_info "Starting SQLite full system backup process..."
    log_info "Script location: $SCRIPT_DIR"
    log_info "Project root: $PROJECT_ROOT"
    log_info "Database type: SQLite"
    echo ""

    # Main backup process
    validate_environment
    setup_directories

    # Create all backup components
    backup_sqlite_database
    backup_data_directories
    backup_configurations
    backup_ssl_certificates
    backup_system_info
    create_final_archive

    # Optional remote upload
    upload_to_remote

    # Cleanup and show results
    cleanup
    show_summary

    local end_time=$(date +%s)
    local backup_size="N/A"
    if [[ -f "$OUTPUT_DIR/${BACKUP_NAME}.tar.gz" ]]; then
        backup_size=$(du -h "$OUTPUT_DIR/${BACKUP_NAME}.tar.gz" | cut -f1)
    fi
    
    # Send backup completion notification
    send_backup_notification "SUCCESS" "$BACKUP_NAME" "$backup_size" "$start_time" "$end_time"

    log_success "SQLite full system backup completed successfully!"
    echo ""
    echo "Next steps:"
    echo "• Validate backup: ./backup/full-backup/validate-backup.sh --latest"
    echo "• Test restoration: Set up test VM and run rebuild-vm.sh"
    echo "• Test DR capability: ./backup/dr-monthly-test.sh"
    echo "• Schedule regular backups: Add to crontab for weekly execution"
    echo ""
}

# Handle errors and send failure notifications
error_handler() {
    local exit_code=$?
    local start_time="${BACKUP_START_TIME:-$(date +%s)}"
    
    if [[ $exit_code -ne 0 ]]; then
        send_backup_notification "FAILED" "${BACKUP_NAME:-backup-failed}" "N/A" "$start_time" "$(date +%s)"
    fi
    
    # Cleanup on any exit
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR" || true
    fi
    
    exit $exit_code
}

# Set up error handling
BACKUP_START_TIME=$(date +%s)
trap error_handler EXIT ERR

# Execute main function
main "$@"
