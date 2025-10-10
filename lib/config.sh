#!/usr/bin/env bash
# lib/config.sh - Configuration management functions (SQLite Optimized)
# VaultWarden-OCI-Slim - Removed legacy MariaDB/Redis dependencies

set -euo pipefail

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/common.sh"

# ================================
# CONFIGURATION CONSTANTS
# ================================

# Required environment variables (SQLite optimized - no MariaDB/Redis)
declare -ra REQUIRED_VARS=(
    "VAULTWARDEN_DOMAIN"
    "ADMIN_TOKEN"
    "BACKUP_PASSPHRASE"
)

# Optional but recommended variables
declare -ra RECOMMENDED_VARS=(
    "SMTP_HOST"
    "SMTP_USERNAME"
    "SMTP_PASSWORD"
    "PUSH_INSTALLATION_ID"
    "BACKUP_REMOTE"
    "ADMIN_EMAIL"
)

# Configuration file paths
declare -r FAIL2BAN_TEMPLATE="./fail2ban/jail.d/jail.local.template"
declare -r FAIL2BAN_CONFIG="./fail2ban/jail.d/jail.local"
declare -r CLOUDFLARE_IP_SCRIPT="./caddy/update_cloudflare_ips.sh"

# ================================
# ENVIRONMENT MANAGEMENT
# ================================

# Normalize OCI Vault env var (accept both for compatibility)
export OCI_SECRET_OCID="${OCI_SECRET_OCID:-${OCISECRET_OCID:-}}"

# Check if OCI Vault is configured
is_oci_vault_configured() {
    [[ -n "${OCI_SECRET_OCID:-}" ]] && command -v oci >/dev/null 2>&1
}

# Fetch configuration from OCI Vault
fetch_oci_config() {
    local secret_ocid="$1"
    local output_file="$2"

    log_info "Fetching configuration from OCI Vault..."

    if ! command -v oci >/dev/null 2>&1; then
        log_error "OCI CLI not available"
        return 1
    fi

    local secret_content
    if secret_content=$(oci secrets secret-bundle get --secret-id "$secret_ocid" --query "data."secret-bundle-content".content" --raw-output); then
        # Decode base64 content
        echo "$secret_content" | base64 -d > "$output_file"
        chmod 600 "$output_file"
        log_success "OCI Vault configuration retrieved"
        return 0
    else
        log_error "Failed to retrieve OCI Vault secret"
        return 1
    fi
}

# Create secure environment file from OCI Vault or local settings
create_secure_env_file() {
    local output_file="$1"
    local source_type="${2:-auto}" # auto, local, oci

    log_info "Creating secure environment file..."

    case "$source_type" in
        "oci"|"auto")
            if is_oci_vault_configured && [[ -n "${OCI_SECRET_OCID:-}" ]]; then
                fetch_oci_config "${OCI_SECRET_OCID}" "$output_file"
                return 0
            elif [[ "$source_type" == "oci" ]]; then
                log_error "OCI Vault not configured but explicitly requested"
                return 1
            fi
            ;;&  # Fall through to local if auto mode
        "local"|"auto")
            if [[ -f "$SETTINGS_FILE" ]]; then
                log_info "Using local settings file"
                cp "$SETTINGS_FILE" "$output_file"
                chmod 600 "$output_file"
                log_success "Local configuration loaded"
                return 0
            fi
            ;;
        *)
            log_error "Unknown configuration source type: $source_type"
            return 1
            ;;
    esac

    log_error "No configuration source available"
    return 1
}

# Validate configuration variables (SQLite optimized)
validate_configuration() {
    local env_file="$1"

    log_info "Validating SQLite configuration..."

    # Load environment
    set -a
    source "$env_file"
    set +a

    local errors=0
    local warnings=0

    # Check required variables
    for var in "${REQUIRED_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_error "Required variable not set: $var"
            ((errors++))
        else
            # Check password strength for password fields
            if [[ "$var" == *"PASSWORD"* ]] || [[ "$var" == *"TOKEN"* ]] || [[ "$var" == *"PASSPHRASE"* ]]; then
                # Fix: Get the value properly using indirect expansion
                local var_value="${!var:-}"
                if [[ -n "$var_value" ]] && (( ${#var_value} < 16 )); then
                    log_warning "$var is shorter than 16 characters"
                    ((warnings++))
                fi
            fi
        fi
    done

    # Check recommended variables
    for var in "${RECOMMENDED_VARS[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_warning "Recommended variable not set: $var"
            ((warnings++))
        fi
    done

    # Validate domain format - UPDATED for VAULTWARDEN_DOMAIN
    if [[ -n "${VAULTWARDEN_DOMAIN:-}" ]]; then
        if [[ "$VAULTWARDEN_DOMAIN" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]\.[a-zA-Z]{2,}$ ]]; then
            log_success "Domain name format is valid"
        else
            log_warning "Domain name format may be invalid: $VAULTWARDEN_DOMAIN"
            ((warnings++))
        fi
    fi

    # Validate SQLite database configuration
    if [[ -n "${DATABASE_URL:-}" ]]; then
        if [[ "${DATABASE_URL}" == *"sqlite"* ]]; then
            log_success "SQLite database configuration detected"
        else
            log_warning "Non-SQLite DATABASE_URL detected: ${DATABASE_URL} (expected sqlite:////data/bwdata/db.sqlite3)"
            ((warnings++))
        fi
    fi

    # Check for legacy database variables (should not be present)
    local legacy_vars=("MARIADB_ROOT_PASSWORD" "MARIADB_PASSWORD" "REDIS_PASSWORD" "MYSQL_ROOT_PASSWORD")
    for var in "${legacy_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            log_warning "Legacy database variable found: $var (not needed for SQLite deployment)"
            ((warnings++))
        fi
    done

    # Check SQLite optimization settings
    if [[ "${ROCKET_WORKERS:-}" != "1" ]]; then
        log_warning "ROCKET_WORKERS=${ROCKET_WORKERS:-default} (recommended: 1 for SQLite/1 OCPU)"
        ((warnings++))
    fi

    if [[ "${WEBSOCKET_ENABLED:-}" != "false" ]]; then
        log_warning "WEBSOCKET_ENABLED=${WEBSOCKET_ENABLED:-default} (recommended: false for efficiency)"
        ((warnings++))
    fi

    # Summary
    if [[ $errors -gt 0 ]]; then
        log_error "Configuration validation failed with $errors errors"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        log_warning "Configuration validation completed with $warnings warnings"
        return 0
    else
        log_success "Configuration validation passed with no issues"
        return 0
    fi
}

# ================================
# TEMPLATE PROCESSING
# ================================

# Process configuration template
process_template() {
    local template_file="$1"
    local output_file="$2"
    local env_file="${3:-}"

    log_info "Processing template: $template_file"

    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: $template_file"
        return 1
    fi

    # Load environment if provided
    if [[ -n "$env_file" ]]; then
        set -a
        source "$env_file"
        set +a
    fi

    # Process template with envsubst
    if envsubst < "$template_file" > "$output_file"; then
        log_success "Template processed: $output_file"
    else
        log_error "Failed to process template: $template_file"
        return 1
    fi
}

# Generate Fail2ban configuration
generate_fail2ban_config() {
    local env_file="$1"

    log_info "Generating Fail2ban configuration..."

    if [[ ! -f "$FAIL2BAN_TEMPLATE" ]]; then
        log_warning "Fail2ban template not found: $FAIL2BAN_TEMPLATE (skipping)"
        return 0
    fi

    process_template "$FAIL2BAN_TEMPLATE" "$FAIL2BAN_CONFIG" "$env_file"
}

# ================================
# CLOUDFLARE IP MANAGEMENT
# ================================

# Check if Cloudflare IPs need updating
need_cloudflare_ip_update() {
    local max_age_days="${1:-7}"
    local ip_files=("./caddy/cloudflare_ips.caddy" "./caddy/cloudflare_ips.txt")

    for file in "${ip_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_debug "Cloudflare IP file missing: $file"
            return 0  # Need update
        elif [[ $(find "$file" -mtime +$max_age_days) ]]; then
            log_debug "Cloudflare IP file older than $max_age_days days: $file"
            return 0  # Need update
        fi
    done

    return 1  # No update needed
}

# Update Cloudflare IPs
update_cloudflare_ips() {
    local force="${1:-false}"

    log_info "Checking Cloudflare IP configuration..."

    if [[ ! -f "$CLOUDFLARE_IP_SCRIPT" ]]; then
        log_info "Cloudflare IP update script not found, skipping"
        return 0
    fi

    chmod +x "$CLOUDFLARE_IP_SCRIPT"

    if [[ "$force" == "true" ]] || need_cloudflare_ip_update; then
        log_info "Updating Cloudflare IP ranges..."
        if "$CLOUDFLARE_IP_SCRIPT"; then
            log_success "Cloudflare IP ranges updated"
            return 0
        else
            log_warning "Failed to update Cloudflare IP ranges"
            return 1
        fi
    else
        log_info "Cloudflare IP files are current"
        return 0
    fi
}

# ================================
# CONFIGURATION MIGRATION
# ================================

# Migrate old configuration format to new format
migrate_configuration() {
    local old_config="$1"
    local new_config="$2"

    log_info "Migrating configuration format..."

    if [[ ! -f "$old_config" ]]; then
        log_error "Old configuration file not found: $old_config"
        return 1
    fi

    # Create backup
    cp "$old_config" "${old_config}.backup.$(date +%Y%m%d_%H%M%S)"

    # Load old config
    set -a
    source "$old_config"
    set +a

    # Migrate variables (SQLite-specific migrations)
    {
        echo "# Migrated configuration - $(date)"
        echo "# SQLite-optimized VaultWarden deployment"
        echo

        # Domain configuration - UPDATED for consolidation
        echo "# === DOMAIN & SECURITY CONFIGURATION ==="
        echo "VAULTWARDEN_DOMAIN=${VAULTWARDEN_DOMAIN:-${APP_DOMAIN:-${DOMAIN_NAME:-}}}"
        echo

        # SQLite database configuration
        echo "# === DATABASE CONFIGURATION (SQLite) ==="
        echo "DATABASE_URL=sqlite:////data/bwdata/db.sqlite3"
        echo "ROCKET_WORKERS=1"
        echo "WEBSOCKET_ENABLED=false"
        echo

        # Keep other non-database settings
        echo "# === VAULTWARDEN APPLICATION ==="
        echo "ADMIN_TOKEN=${ADMIN_TOKEN:-}"
        echo "SIGNUPS_ALLOWED=${SIGNUPS_ALLOWED:-false}"
        echo "INVITES_ALLOWED=${INVITES_ALLOWED:-true}"
        echo

        # Backup configuration
        echo "# === BACKUP CONFIGURATION ==="
        echo "BACKUP_PASSPHRASE=${BACKUP_PASSPHRASE:-}"
        echo "BACKUP_REMOTE=${BACKUP_REMOTE:-}"
        echo "BACKUP_PATH=${BACKUP_PATH:-vaultwarden-backups}"
        echo "BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-30}"
        echo

        # Note about removed services
        echo "# Legacy MariaDB/Redis variables removed for SQLite deployment"
        echo "# MARIADB_* and REDIS_* variables are no longer needed"

    } > "$new_config"

    chmod 600 "$new_config"
    log_success "Configuration migrated to: $new_config"
}

# ================================
# PASSWORD MANAGEMENT
# ================================

# Generate secure passwords for configuration
generate_secure_config() {
    local output_file="$1"
    local template_file="${2:-$SETTINGS_EXAMPLE}"

    log_info "Generating secure SQLite configuration..."

    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: $template_file"
        return 1
    fi

    # Generate passwords for placeholder values
    local admin_token backup_passphrase
    admin_token=$(generate_password 32)
    backup_passphrase=$(generate_password 32)

    # Process template and replace placeholders (SQLite-specific)
    sed \
        -e "s/generate-with-openssl-rand-base64-32/${admin_token}/g" \
        -e "s/your-very-strong-admin-token-here/${admin_token}/g" \
        -e "s/your-very-strong-backup-passphrase/${backup_passphrase}/g" \
        -e "/MARIADB_/d" \
        -e "/REDIS_/d" \
        "$template_file" > "$output_file"

    chmod 600 "$output_file"
    log_success "Secure SQLite configuration generated: $output_file"
    log_warning "Remember to customize domain and email settings in: $output_file"
}

# ================================
# CONFIGURATION VALIDATION HELPERS
# ================================

# Test SMTP configuration
test_smtp_config() {
    local env_file="$1"

    # Load environment
    set -a
    source "$env_file"
    set +a

    log_info "Testing SMTP configuration..."

    # Check required SMTP variables
    local required_smtp_vars=("SMTP_HOST" "SMTP_PORT" "SMTP_USERNAME" "SMTP_PASSWORD" "SMTP_FROM")
    for var in "${required_smtp_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            log_warning "SMTP variable not set: $var"
            return 1
        fi
    done

    # Test SMTP connectivity (basic check)
    if command_exists nc; then
        if nc -z "${SMTP_HOST}" "${SMTP_PORT}"; then
            log_success "SMTP server is reachable"
        else
            log_warning "SMTP server is not reachable"
        fi
    else
        log_debug "nc command not available, skipping SMTP connectivity test"
    fi

    return 0
}

# Test SQLite database connectivity and health
test_sqlite_config() {
    local env_file="$1"

    # Load environment
    set -a
    source "$env_file"
    set +a

    log_info "Testing SQLite database configuration..."

    local sqlite_path="${SQLITE_DB_PATH:-./data/bw/data/bwdata/db.sqlite3}"

    if [[ -f "$sqlite_path" ]]; then
        # Test database accessibility
        if sqlite3 "$sqlite_path" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
            log_success "SQLite database is accessible"

            # Check database health
            local integrity_result
            integrity_result=$(sqlite3 "$sqlite_path" "PRAGMA integrity_check;")

            if [[ "$integrity_result" == "ok" ]]; then
                log_success "SQLite database integrity check passed"
            else
                log_warning "SQLite database integrity issues detected"
            fi

            # Show database stats
            local db_size table_count journal_mode
            db_size=$(du -h "$sqlite_path" | cut -f1)
            table_count=$(sqlite3 "$sqlite_path" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" || echo "0")
            journal_mode=$(sqlite3 "$sqlite_path" "PRAGMA journal_mode;" || echo "unknown")

            log_info "Database size: $db_size, Tables: $table_count, Journal mode: $journal_mode"

            return 0
        else
            log_error "SQLite database is not accessible"
            return 1
        fi
    else
        log_info "SQLite database not found (will be created on first VaultWarden startup)"
        return 0
    fi
}

# Generate password helper function
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -d "=+/" | cut -c1-"$length" || {
        # Fallback method
        LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length" || echo "fallback$(date +%s)"
    }
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Create secure temporary directory
create_secure_tmpdir() {
    local prefix="${1:-vaultwarden}"
    local tmpdir
    tmpdir=$(mktemp -d "/tmp/${prefix}_$(date +%Y%m%d_%H%M%S)_XXXXXX")
    chmod 700 "$tmpdir"
    echo "$tmpdir"
}
