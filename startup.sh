#!/usr/bin/env bash
# startup.sh -- Enhanced startup script with industry best practices
# VaultWarden-OCI-NG - Production deployment script with strict validation

# BEST PRACTICE: Strict error handling
set -euo pipefail
IFS=$'\n\t'

export DEBUG="${DEBUG:-false}"
export LOG_FILE="/tmp/vaultwarden_startup_$(date +%Y%m%d_%H%M%S).log"

# ================================
# BEST PRACTICE: STRICT ENVIRONMENT VALIDATION (FAIL FAST)
# ================================

validate_environment() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
    local lib_dir="$script_dir/lib"

    # BEST PRACTICE: Fail fast on missing dependencies
    if [[ ! -d "$lib_dir" ]]; then
        echo "❌ FATAL: Required lib/ directory not found at: $lib_dir" >&2
        echo "📋 This suggests an incomplete installation." >&2
        echo "🔧 Solution: Run 'tools/init-setup.sh' or re-clone the repository" >&2
        exit 1
    fi

    # Check required library files
    local required_libs=("common.sh" "config.sh" "docker.sh")
    local missing_libs=()

    for lib in "${required_libs[@]}"; do
        if [[ ! -f "$lib_dir/$lib" ]]; then
            missing_libs+=("$lib")
        fi
    done

    if [[ ${#missing_libs[@]} -gt 0 ]]; then
        echo "❌ FATAL: Required libraries missing from $lib_dir:" >&2
        printf '   - %s\n' "${missing_libs[@]}" >&2
        echo "🔧 Solution: Restore missing files or run 'tools/init-setup.sh'" >&2
        exit 1
    fi
}

# Load libraries without fallbacks (BEST PRACTICE: FAIL FAST, NO MASKING)
load_libraries() {
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

    # FAIL FAST: No fallbacks, require proper installation
    source "$script_dir/lib/common.sh" || {
        echo "❌ FATAL: Required library lib/common.sh not found" >&2
        echo "🔧 Solution: Run 'tools/init-setup.sh' or restore missing files" >&2
        exit 1
    }

    source "$script_dir/lib/config.sh" || {
        echo "❌ FATAL: Required library lib/config.sh not found" >&2
        echo "🔧 Solution: Run 'tools/init-setup.sh' or restore missing files" >&2
        exit 1
    }

    source "$script_dir/lib/docker.sh" || {
        echo "❌ FATAL: Required library lib/docker.sh not found" >&2
        echo "🔧 Solution: Run 'tools/init-setup.sh' or restore missing files" >&2
        exit 1
    }
}

# ================================
# CONFIGURATION VALIDATION FUNCTIONS
# ================================

# BEST PRACTICE: Validate core configuration requirements
validate_core_configuration() {
    log_info "Validating core configuration requirements..."

    local errors=()

    # Required core variables - CORRECTED for domain consolidation
    local required_vars=(
        "VAULTWARDEN_DOMAIN:Domain configuration"
        "ADMIN_TOKEN:VaultWarden admin token"
        "ADMIN_EMAIL:Administrator email"
    )

    for var_spec in "${required_vars[@]}"; do
        local var_name="${var_spec%%:*}"
        local var_desc="${var_spec##*:}"

        if [[ -z "${!var_name:-}" ]]; then
            errors+=("❌ $var_name ($var_desc) is required but not set")
        fi
    done

    # Validate ADMIN_TOKEN format (should be base64-like)
    if [[ -n "${ADMIN_TOKEN:-}" ]] && [[ ! "${ADMIN_TOKEN}" =~ ^[A-Za-z0-9+/=]{40,}$ ]]; then
        errors+=("⚠️  ADMIN_TOKEN should be generated with: openssl rand -base64 32")
    fi

    # Validate VAULTWARDEN_DOMAIN format (should not have a protocol)
    if [[ -n "${VAULTWARDEN_DOMAIN:-}" ]] && [[ "${VAULTWARDEN_DOMAIN}" =~ ^https?:// ]]; then
        errors+=("❌ VAULTWARDEN_DOMAIN should not include http:// or https://")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "Core configuration validation failed:"
        printf '  %s\n' "${errors[@]}"
        echo ""
        echo "🔧 Fix these issues in your settings.env file and try again"
        exit 1
    fi

    log_success "✅ Core configuration validation passed"
}

# BEST PRACTICE: CRITICAL PRE-FLIGHT VALIDATION - Backup configuration
validate_backup_configuration() {
    if [[ "${ENABLE_BACKUP:-false}" != "true" ]]; then
        return 0  # Backup disabled, nothing to validate
    fi

    log_info "Validating backup configuration..."

    local rclone_config="./backup/config/rclone.conf"
    local backup_remote="${BACKUP_REMOTE:-}"
    local backup_passphrase="${BACKUP_PASSPHRASE:-}"
    local errors=()

    # CRITICAL: Check required variables
    if [[ -z "$backup_remote" ]]; then
        errors+=("❌ BACKUP_REMOTE is required when ENABLE_BACKUP=true")
    fi

    if [[ -z "$backup_passphrase" ]]; then
        errors+=("❌ BACKUP_PASSPHRASE is required when ENABLE_BACKUP=true")
        errors+=("   Generate with: openssl rand -base64 32")
    fi

    # CRITICAL: Check if rclone config exists and has content
    if [[ ! -f "$rclone_config" ]] || [[ ! -s "$rclone_config" ]]; then
        errors+=("❌ rclone configuration not found or empty: $rclone_config")
        errors+=("   Configure with: docker compose run --rm bw_backup rclone config")
    elif [[ -n "$backup_remote" ]]; then
        # CRITICAL: Check if specified remote exists in config
        if ! grep -q "^\[$backup_remote\]" "$rclone_config"; then
            errors+=("❌ Backup remote '$backup_remote' not found in rclone.conf")
            local available_remotes
            available_remotes=$(grep "^\[" "$rclone_config" | tr -d '[]' || echo "none")
            errors+=("   Available remotes: $available_remotes")
        fi
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "❌ CRITICAL: Backup configuration errors found:"
        printf '  %s\n' "${errors[@]}"
        log_error "🔧 DISABLING backup profile to prevent silent failures"
        export ENABLE_BACKUP=false
        return 1
    fi

    log_success "✅ Backup configuration validated"
    return 0
}

# BEST PRACTICE: CRITICAL PRE-FLIGHT VALIDATION - DNS configuration
validate_dns_configuration() {
    if [[ "${ENABLE_DNS:-false}" != "true" ]]; then
        return 0  # DNS disabled, nothing to validate
    fi

    log_info "Validating DNS configuration..."

    local errors=()
    local required_dns_vars=("DDCLIENT_HOST" "DDCLIENT_PASSWORD")

    for var in "${required_dns_vars[@]}"; do
        if [[ -z "${!var:-}" ]]; then
            errors+=("❌ $var is required when ENABLE_DNS=true")
        fi
    done

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "❌ CRITICAL: DNS configuration errors found:"
        printf '  %s\n' "${errors[@]}"
        log_error "🔧 DISABLING DNS profile to prevent silent failures"
        export ENABLE_DNS=false
        return 1
    fi

    log_success "✅ DNS configuration validated"
    return 0
}

# BEST PRACTICE: CRITICAL PRE-FLIGHT VALIDATION - Monitoring configuration
validate_monitoring_configuration() {
    if [[ "${ENABLE_MONITORING:-false}" != "true" ]]; then
        return 0  # Monitoring disabled, nothing to validate
    fi

    log_info "Validating monitoring configuration..."

    local has_email_config=false
    local has_webhook_config=false
    local errors=()

    # Check for email alert configuration
    if [[ -n "${SMTP_HOST:-}" && -n "${ALERT_EMAIL:-}" && -n "${SMTP_FROM:-}" ]]; then
        has_email_config=true
        log_info "📧 Email alerts configured"
    fi

    # Check for webhook alert configuration
    if [[ -n "${WEBHOOK_URL:-}" ]]; then
        has_webhook_config=true
        log_info "🔗 Webhook alerts configured"
    fi

    # CRITICAL: Require at least one alert destination
    if [[ "$has_email_config" == "false" && "$has_webhook_config" == "false" ]]; then
        errors+=("❌ Monitoring enabled but no alert destinations configured")
        errors+=("   Required: ALERT_EMAIL + SMTP config OR WEBHOOK_URL")
    fi

    if [[ ${#errors[@]} -gt 0 ]]; then
        log_error "❌ CRITICAL: Monitoring configuration errors found:"
        printf '  %s\n' "${errors[@]}"
        log_error "🔧 DISABLING monitoring profile to prevent silent failures"
        export ENABLE_MONITORING=false
        return 1
    fi

    log_success "✅ Monitoring configuration validated"
    return 0
}

# ================================
# DIRECTORY STRUCTURE CREATION
# ================================

create_directory_structure() {
    log_info "Creating directory structure..."

    # Core data directories
    local directories=(
        "$VAULTWARDEN_DATA_DIR"     # VaultWarden data (SQLite database)
        "./data/caddy_data"         # Caddy data storage
        "./data/caddy_config"       # Caddy configuration
        "./data/caddy_logs"         # Caddy access logs
        "./data/backups"            # Local backup storage
        "./data/backup_logs"        # Backup operation logs
        "./data/fail2ban"           # Fail2ban configuration data

        # Configuration directories
        "./backup/config"           # rclone configuration
        "./backup/templates"        # Backup templates
        "./fail2ban/jail.d"         # Fail2ban jail configurations
        "./fail2ban/filter.d"       # Fail2ban filter configurations
        "./fail2ban/action.d"       # Fail2ban action configurations
        "./ddclient"                # DDClient configuration
        "./caddy"                   # Caddy configuration files

        # Log directories
        "./logs"                    # General log directory
        "./logs/startup"            # Startup script logs
        "./logs/maintenance"        # Maintenance script logs
    )

    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_info "Creating directory: $dir"
            mkdir -p "$dir"

            # Set appropriate permissions
            case "$dir" in
                *"/config"*|*"backup"*|*"fail2ban"*)
                    chmod 700 "$dir"  # Secure permissions for config dirs
                    ;;
                *"/logs"*|*"/data"*)
                    chmod 755 "$dir"  # Standard permissions for data/log dirs
                    ;;
                *)
                    chmod 755 "$dir"  # Default permissions
                    ;;
            esac
        fi
    done

    # Fix ownership for data directories (if running as non-root)
    if [[ -n "${PUID:-}" ]] && [[ -n "${PGID:-}" ]] && [[ "$EUID" -eq 0 ]]; then
        log_info "Setting ownership for data directories..."
        chown -R "${PUID}:${PGID}" ./data/ || log_warning "Failed to set ownership (may be normal)"
    fi

    log_success "Directory structure created successfully"
}

validate_directory_structure() {
    log_info "Validating directory structure..."

    local critical_dirs=(
        "$VAULTWARDEN_DATA_DIR"
        "./data/caddy_logs"
        "./backup/config"
        "./fail2ban/jail.d"
    )

    local errors=0
    for dir in "${critical_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            log_error "Critical directory missing: $dir"
            ((errors++))
        elif [[ ! -w "$dir" ]]; then
            log_error "Directory not writable: $dir"
            ((errors++))
        fi
    done

    if [[ $errors -gt 0 ]]; then
        log_error "Directory structure validation failed with $errors errors"
        return 1
    fi

    log_success "Directory structure validation passed"
    return 0
}

# ================================
# PROFILE MANAGEMENT WITH VALIDATION
# ================================

determine_active_profiles() {
    local -a profiles=()

    log_step "Determining active service profiles with CRITICAL validation..."

    # CRITICAL: Validate and enable backup profile
    if validate_backup_configuration; then
        profiles+=(--profile backup)
        log_success "✅ Backup profile enabled and validated"
        prepare_backup_config
    else
        log_info "ℹ️  Backup profile disabled (configuration errors)"
    fi

    # Security profile (minimal requirements)
    if [[ "${ENABLE_SECURITY:-true}" == "true" ]]; then
        profiles+=(--profile security)
        log_success "✅ Security profile enabled (fail2ban)"
    else
        log_info "ℹ️  Security profile disabled"
    fi

    # CRITICAL: Validate and enable DNS profile
    if validate_dns_configuration; then
        profiles+=(--profile dns)
        log_success "✅ DNS profile enabled and validated (ddclient)"
    else
        log_info "ℹ️  DNS profile disabled (configuration errors)"
    fi

    # Maintenance profile (minimal requirements)
    if [[ "${ENABLE_MAINTENANCE:-true}" == "true" ]]; then
        profiles+=(--profile maintenance)
        log_success "✅ Maintenance profile enabled (watchtower)"
    else
        log_info "ℹ️  Maintenance profile disabled"
    fi

    # CRITICAL: Validate and enable monitoring profile
    if validate_monitoring_configuration; then
        profiles+=(--profile monitoring)
        log_success "✅ Monitoring profile enabled and validated"
    else
        log_info "ℹ️  Monitoring profile disabled (configuration errors)"
    fi

    # Development profile (future)
    if [[ "${ENABLE_DEVELOPMENT:-false}" == "true" ]]; then
        profiles+=(--profile development)
        log_warning "⚠️  Development profile enabled"
    fi

    # Export for use in other functions
    export ACTIVE_PROFILES=("${profiles[@]}")

    if [[ ${#profiles[@]} -eq 0 ]]; then
        log_info "Using core services only (no optional profiles)"
    else
        log_info "Active profiles: ${profiles[*]}"
    fi
}

prepare_backup_config() {
    local config_dir="${RCLONE_CONFIG_DIR:-./backup/config}"
    local config_file="$config_dir/rclone.conf"
    local template_file="./backup/templates/rclone.conf.example"

    log_info "Preparing backup configuration..."

    # Ensure backup directories exist
    mkdir -p "$config_dir"
    mkdir -p "./backup/templates"
    chmod 700 "$config_dir"

    # Create rclone.conf template if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        if [[ -f "$template_file" ]]; then
            log_info "Creating rclone.conf from template"
            cp "$template_file" "$config_file"
        else
            log_info "Creating rclone.conf template"
            cat > "$config_file" << 'EOF'
# rclone configuration file
# Configure your backup destinations here
# 
# Example for Backblaze B2:
# [b2-backup]
# type = b2
# account = your-account-id
# key = your-application-key
# 
# Example for AWS S3:
# [s3-backup]
# type = s3
# provider = AWS
# access_key_id = your-access-key
# secret_access_key = your-secret-key
# region = us-east-1
# 
# Configure interactively with:
# docker compose run --rm bw_backup rclone config
EOF
        fi
        chmod 600 "$config_file"
    fi

    log_info "SQLite database path (host): $SQLITE_DB_PATH"
    log_info "SQLite database path (container): $SQLITE_DB_CONTAINER_PATH"

    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        log_info "SQLite database will be created on first VaultWarden startup"
    fi
}

# ================================
# ENHANCED MAIN FUNCTIONS
# ================================

initialize() {
    log_info "Initializing VaultWarden-OCI startup with CRITICAL validation..."

    # Create directory structure first
    create_directory_structure
    validate_directory_structure

    # Validate system requirements
    validate_system_requirements

    # Validate project structure
    validate_project_structure

    # Load and validate configuration
    if [[ -f "${SETTINGS_FILE:-./settings.env}" ]]; then
        set -a
        source "${SETTINGS_FILE:-./settings.env}"
        set +a
        log_success "Configuration loaded from ${SETTINGS_FILE:-./settings.env}"
    else
        log_error "Configuration file not found: ${SETTINGS_FILE:-./settings.env}"
        echo "🔧 Create settings.env from settings.env.example first"
        exit 1
    fi

    # BEST PRACTICE: Validate core configuration
    validate_core_configuration

    # CRITICAL: Determine active profiles based on validated configuration
    determine_active_profiles

    log_success "Initialization complete"
}

setup_configuration() {
    log_info "Setting up configuration..."

    # Create secure temporary directory for environment file
    local tmpdir
    tmpdir=$(create_secure_tmpdir "startup")
    local env_file="$tmpdir/settings.env"

    # Create secure environment file
    create_secure_env_file "$env_file" "auto"

    # Validate configuration
    validate_configuration "$env_file"

    # Update Cloudflare IPs if needed
    update_cloudflare_ips "${FORCE_IP_UPDATE:-false}"

    # Generate Fail2ban configuration (if security profile enabled)
    if [[ "${ENABLE_SECURITY:-true}" == "true" ]]; then
        generate_fail2ban_config "$env_file"
    fi

    # Export env file path for Docker Compose
    export COMPOSE_ENV_FILE="$env_file"

    log_success "Configuration setup complete"
}

deploy_stack() {
    log_info "Deploying container stack with VALIDATED profiles..."

    # Build Docker Compose command with profiles
    local compose_cmd=(docker compose --env-file "$COMPOSE_ENV_FILE")

    # Add profile arguments
    for profile in "${ACTIVE_PROFILES[@]}"; do
        compose_cmd+=("$profile")
    done

    # Add the up command
    compose_cmd+=(up -d --remove-orphans)

    log_info "Running: ${compose_cmd[*]}"

    # Start the stack
    if "${compose_cmd[@]}"; then
        log_success "Stack started successfully"
    else
        log_error "Failed to start stack"
        return 1
    fi

    # Wait for critical services to be healthy
    local critical_services=("vaultwarden" "bw_caddy")

    for service in "${critical_services[@]}"; do
        if wait_for_service "$service" 120 10; then
            log_success "✅ Service $service is ready"
        else
            log_warning "⚠️  Service $service may not be fully ready"
        fi
    done

    # Wait for profile services if enabled
    wait_for_profile_services

    # Perform comprehensive health check
    if perform_health_check; then
        log_success "✅ All services are healthy"
    else
        log_warning "⚠️  Some services may have issues (check logs)"
    fi

    log_success "Stack deployment complete"
}

wait_for_profile_services() {
    log_info "Checking profile service status..."

    # Check backup service
    if [[ "${ENABLE_BACKUP:-false}" == "true" ]]; then
        if wait_for_service "bw_backup" 60 5; then
            log_success "✅ Backup service is ready"
        else
            log_warning "⚠️  Backup service may not be fully ready"
        fi
    fi

    # Check security service
    if [[ "${ENABLE_SECURITY:-true}" == "true" ]]; then
        if wait_for_service "bw_fail2ban" 90 5; then
            log_success "✅ Security service (fail2ban) is ready"
        else
            log_warning "⚠️  Security service may not be fully ready"
        fi
    fi

    # Check DNS service
    if [[ "${ENABLE_DNS:-false}" == "true" ]]; then
        if wait_for_service "bw_ddclient" 60 5; then
            log_success "✅ DNS service (ddclient) is ready"
        else
            log_warning "⚠️  DNS service may not be fully ready"
        fi
    fi

    # Check monitoring service
    if [[ "${ENABLE_MONITORING:-false}" == "true" ]]; then
        if wait_for_service "bw_monitoring" 60 5; then
            log_success "✅ Monitoring service is ready"
        else
            log_warning "⚠️  Monitoring service may not be fully ready"
        fi
    fi

    # Check maintenance services
    if [[ "${ENABLE_MAINTENANCE:-true}" == "true" ]]; then
        if wait_for_service "bw_watchtower" 30 5; then
            log_success "✅ Watchtower service is ready"
        else
            log_info "ℹ️  Watchtower service status unknown (normal)"
        fi
    fi
}

show_status() {
    log_info "VaultWarden-OCI Status:"
    echo "========================================"

    # Load config for domain info
    if [[ -f "$COMPOSE_ENV_FILE" ]]; then
        set -a
        source "$COMPOSE_ENV_FILE"
        set +a

        echo "🌐 Domain: ${VAULTWARDEN_DOMAIN:-'Not configured'}"
        echo "🔗 URL: https://${VAULTWARDEN_DOMAIN:-'Not configured'}"
        echo "⚙️  Profiles: ${ACTIVE_PROFILES[*]:-'core only'}"
        echo "💾 SQLite DB: $SQLITE_DB_PATH"

        # Show validation status
        echo ""
        echo "📋 Configuration Status:"
        [[ -n "${ADMIN_TOKEN:-}" ]] && echo "  ✅ Admin token configured" || echo "  ❌ Admin token missing"
        [[ -n "${SMTP_HOST:-}" ]] && echo "  ✅ SMTP configured" || echo "  ⚠️  SMTP not configured (optional)"
        [[ "${ENABLE_BACKUP:-false}" == "true" ]] && echo "  ✅ Backups enabled" || echo "  ℹ️  Backups disabled"
        [[ "${ENABLE_MONITORING:-false}" == "true" ]] && echo "  ✅ Monitoring enabled" || echo "  ℹ️  Monitoring disabled"
    fi

    echo ""
    echo "📊 Service Status:"

    # Build status command with same profiles
    local status_cmd=(docker compose --env-file "$COMPOSE_ENV_FILE")
    for profile in "${ACTIVE_PROFILES[@]}"; do
        status_cmd+=("$profile")
    done
    status_cmd+=(ps)

    "${status_cmd[@]}"

    echo "========================================"
    log_info "💡 Management Commands:"
    echo "  ./monitor.sh       - Real-time monitoring dashboard"
    echo "  ./diagnose.sh      - Comprehensive health diagnostics"
    echo "  ./perf-monitor.sh  - Performance monitoring"
    echo "  ./alerts.sh        - Alert management"
    echo ""
    echo "  Configuration Management:"
    echo "  ./oci-setup.sh setup               - Configure OCI Vault integration"
    echo "  docker compose logs <service>      - View service logs"
}

# ================================
# MAIN EXECUTION WITH BEST PRACTICES
# ================================

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force-ip-update)
                export FORCE_IP_UPDATE="true"
                shift
                ;;
            --debug)
                export DEBUG="true"
                shift
                ;;
            --profile)
                export FORCE_PROFILES="$2"
                shift 2
                ;;
            --help|-h)
                cat <<EOF
VaultWarden-OCI Enhanced Startup Script (FAIL-FAST Edition)

Usage: $0 [OPTIONS]

Options:
    --force-ip-update    Force update of Cloudflare IP ranges
    --debug             Enable debug logging
    --profile PROFILES  Force specific profiles (comma-separated)
    --help, -h          Show this help message

Environment Variables:
    OCI_SECRET_OCID     Use OCI Vault for configuration
    DEBUG               Enable debug logging
    LOG_FILE            Custom log file path

    Profile Control (settings.env):
    ENABLE_BACKUP       Enable backup services (requires CRITICAL validation)
    ENABLE_SECURITY     Enable security services (fail2ban)
    ENABLE_DNS          Enable DNS services (requires CRITICAL validation)
    ENABLE_MAINTENANCE  Enable maintenance services (watchtower)
    ENABLE_MONITORING   Enable monitoring services (requires CRITICAL validation)

Examples:
    $0                                    # Start with auto-detected profiles
    $0 --force-ip-update                  # Force IP update during startup
    ENABLE_BACKUP=false $0                # Start without backup services
    OCI_SECRET_OCID=ocid1... $0          # Use OCI Vault configuration
    DEBUG=true $0                         # Debug mode startup

Profile Information:
    core        - Essential services (always enabled)
    backup      - Database backup and restore (CRITICAL validation required)
    security    - fail2ban intrusion protection
    dns         - ddclient dynamic DNS updates (CRITICAL validation required)
    maintenance - watchtower updates
    monitoring  - system monitoring and alerts (CRITICAL validation required)

Best Practices Implemented:
    ✓ FAIL-FAST dependency validation (NO FALLBACKS)
    ✓ CRITICAL pre-flight validation before service start
    ✓ Single source of truth for variables
    ✓ Clear error messages with remediation steps
    ✓ Service disabling for invalid config (prevents silent failures)

EOF
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                ;;
        esac
    done

    # Main execution flow with best practices
    log_info "🚀 Starting VaultWarden-OCI enhanced deployment (FAIL-FAST Edition)..."

    # BEST PRACTICE: Validate environment first (FAIL FAST)
    validate_environment
    load_libraries

    # Override profiles if forced
    if [[ -n "${FORCE_PROFILES:-}" ]]; then
        log_info "🔧 Using forced profiles: $FORCE_PROFILES"
        IFS=',' read -ra FORCED_PROFILE_ARRAY <<< "$FORCE_PROFILES"
        ACTIVE_PROFILES=()
        for profile in "${FORCED_PROFILE_ARRAY[@]}"; do
            ACTIVE_PROFILES+=(--profile "$profile")
        done
    fi

    initialize
    setup_configuration
    deploy_stack
    show_status

    log_success "🎉 VaultWarden-OCI startup completed successfully!"
    log_info "📋 Log file: $LOG_FILE"

    # Show next steps with validation status
    echo ""
    echo "🎯 Next Steps:"
    echo "1. Configure your domain DNS to point to this server"
    if [[ -z "${SMTP_HOST:-}" ]]; then
        echo "2. Configure SMTP settings in settings.env for email notifications"
    fi
    if [[ "${ENABLE_BACKUP:-false}" == "false" ]]; then
        echo "3. Configure backup: Set BACKUP_REMOTE, BACKUP_PASSPHRASE, and run:"
        echo "   docker compose run --rm bw_backup rclone config"
    fi
    echo "4. Access your vault at: https://${VAULTWARDEN_DOMAIN:-vault.yourdomain.com}"
    echo "5. SQLite database location: $SQLITE_DB_PATH"
}

# Execute main function
main "$@"
