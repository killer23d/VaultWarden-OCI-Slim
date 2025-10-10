#!/usr/bin/env bash
# validate-config.sh - Configuration validation helper
# Best practices implementation for VaultWarden-OCI-Slim

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Configuration file validation
validate_settings_file() {
    local settings_file="${1:-./settings.env}"

    if [[ ! -f "$settings_file" ]]; then
        log_error "Settings file not found: $settings_file"
        echo "Create from template: cp settings.env.example settings.env"
        return 1
    fi

    log_info "Validating configuration file: $settings_file"

    # Source the file for validation
    set -a
    source "$settings_file"
    set +a

    local errors=0
    local warnings=0

    # Required variables validation
    local required_vars=(
        "DOMAIN"
        "ADMIN_TOKEN"
        "ADMIN_EMAIL"
    )

    echo ""
    echo "🔍 Required Configuration:"
    for var in "${required_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            log_success "✅ $var is set"
        else
            log_error "❌ $var is required but not set"
            ((errors++))
        fi
    done

    # Optional but recommended validation
    echo ""
    echo "📧 Email Configuration:"
    if [[ -n "${SMTP_HOST:-}" && -n "${SMTP_FROM:-}" ]]; then
        log_success "✅ SMTP configuration detected"
        # Additional SMTP validation
        local smtp_vars=("SMTP_USERNAME" "SMTP_PASSWORD")
        for var in "${smtp_vars[@]}"; do
            if [[ -n "${!var:-}" ]]; then
                log_success "✅ $var is configured"
            else
                log_warning "⚠️  $var not set (may be required by your SMTP provider)"
                ((warnings++))
            fi
        done
    else
        log_warning "⚠️  SMTP not configured (email features disabled)"
        ((warnings++))
    fi

    # Profile-specific validation
    echo ""
    echo "🔧 Service Profile Configuration:"

    # Backup validation
    if [[ "${ENABLE_BACKUP:-false}" == "true" ]]; then
        local backup_errors=0
        echo "  📦 Backup Profile:"

        if [[ -n "${BACKUP_REMOTE:-}" ]]; then
            log_success "    ✅ BACKUP_REMOTE configured"
        else
            log_error "    ❌ BACKUP_REMOTE required for backups"
            ((backup_errors++))
        fi

        if [[ -n "${BACKUP_PASSPHRASE:-}" ]]; then
            log_success "    ✅ BACKUP_PASSPHRASE configured"
        else
            log_error "    ❌ BACKUP_PASSPHRASE required for backup encryption"
            ((backup_errors++))
        fi

        if [[ -f "./backup/config/rclone.conf" && -s "./backup/config/rclone.conf" ]]; then
            log_success "    ✅ rclone.conf exists and has content"

            # Check if remote exists in config
            if [[ -n "${BACKUP_REMOTE:-}" ]] && grep -q "^\[${BACKUP_REMOTE}\]" "./backup/config/rclone.conf"; then
                log_success "    ✅ Backup remote '$BACKUP_REMOTE' found in rclone.conf"
            elif [[ -n "${BACKUP_REMOTE:-}" ]]; then
                log_error "    ❌ Backup remote '$BACKUP_REMOTE' not found in rclone.conf"
                ((backup_errors++))
            fi
        else
            log_error "    ❌ rclone.conf missing or empty"
            echo "       Configure with: docker compose run --rm bw_backup rclone config"
            ((backup_errors++))
        fi

        if [[ $backup_errors -gt 0 ]]; then
            log_warning "    ⚠️  Backup profile will be disabled due to configuration errors"
            ((warnings++))
        fi
    else
        log_info "  📦 Backup Profile: Disabled"
    fi

    # DNS validation
    if [[ "${ENABLE_DNS:-false}" == "true" ]]; then
        local dns_errors=0
        echo "  🌐 DNS Profile:"

        local required_dns_vars=("DDCLIENT_HOST" "DDCLIENT_PASSWORD")
        for var in "${required_dns_vars[@]}"; do
            if [[ -n "${!var:-}" ]]; then
                log_success "    ✅ $var configured"
            else
                log_error "    ❌ $var required for DNS updates"
                ((dns_errors++))
            fi
        done

        if [[ $dns_errors -gt 0 ]]; then
            log_warning "    ⚠️  DNS profile will be disabled due to configuration errors"
            ((warnings++))
        fi
    else
        log_info "  🌐 DNS Profile: Disabled"
    fi

    # Monitoring validation
    if [[ "${ENABLE_MONITORING:-false}" == "true" ]]; then
        local monitoring_errors=0
        echo "  📊 Monitoring Profile:"

        local has_email_alerts=false
        local has_webhook_alerts=false

        if [[ -n "${ALERT_EMAIL:-}" && -n "${SMTP_HOST:-}" ]]; then
            has_email_alerts=true
            log_success "    ✅ Email alerts configured"
        fi

        if [[ -n "${WEBHOOK_URL:-}" ]]; then
            has_webhook_alerts=true
            log_success "    ✅ Webhook alerts configured"
        fi

        if [[ "$has_email_alerts" == "false" && "$has_webhook_alerts" == "false" ]]; then
            log_error "    ❌ No alert destinations configured"
            echo "       Required: ALERT_EMAIL + SMTP config OR WEBHOOK_URL"
            ((monitoring_errors++))
        fi

        if [[ $monitoring_errors -gt 0 ]]; then
            log_warning "    ⚠️  Monitoring profile will be disabled due to configuration errors"
            ((warnings++))
        fi
    else
        log_info "  📊 Monitoring Profile: Disabled"
    fi

    # Security and maintenance (minimal requirements)
    echo "  🛡️  Security Profile: ${ENABLE_SECURITY:-true} (fail2ban)"
    echo "  🔄 Maintenance Profile: ${ENABLE_MAINTENANCE:-true} (watchtower)"

    # Summary
    echo ""
    echo "📋 Validation Summary:"
    if [[ $errors -eq 0 ]]; then
        log_success "✅ Configuration validation passed"
        if [[ $warnings -gt 0 ]]; then
            log_warning "⚠️  $warnings warning(s) found - some features may be disabled"
        fi
        return 0
    else
        log_error "❌ Configuration validation failed with $errors error(s)"
        echo ""
        echo "🔧 Fix the errors above and run validation again"
        return 1
    fi
}

# Docker Compose validation
validate_compose_config() {
    log_info "Validating Docker Compose configuration..."

    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker not found - install Docker first"
        return 1
    fi

    if ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose not available - install Docker Compose"
        return 1
    fi

    # Check if compose file is valid
    if docker compose config >/dev/null 2>&1; then
        log_success "✅ Docker Compose configuration is valid"
    else
        log_error "❌ Docker Compose configuration has errors:"
        docker compose config
        return 1
    fi

    # Check for required files
    local required_files=(
        "docker-compose.yml"
        "settings.env.example"
    )

    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            log_success "✅ $file exists"
        else
            log_error "❌ Required file missing: $file"
            return 1
        fi
    done

    return 0
}

# System requirements validation
validate_system_requirements() {
    log_info "Validating system requirements..."

    local errors=0

    # Check required commands
    local required_commands=("docker" "curl" "jq" "openssl")
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_success "✅ $cmd is available"
        else
            log_error "❌ Required command missing: $cmd"
            ((errors++))
        fi
    done

    # Check system resources (basic)
    local available_memory
    available_memory=$(free -m | awk '/^Mem:/{print $2}')

    if [[ $available_memory -ge 1024 ]]; then
        log_success "✅ Sufficient memory available: ${available_memory}MB"
    else
        log_warning "⚠️  Low memory detected: ${available_memory}MB (recommended: 2GB+)"
    fi

    # Check disk space
    local available_disk
    available_disk=$(df -BG . | awk 'NR==2{print $4}' | sed 's/G//')

    if [[ $available_disk -ge 5 ]]; then
        log_success "✅ Sufficient disk space: ${available_disk}GB"
    else
        log_warning "⚠️  Low disk space: ${available_disk}GB (recommended: 10GB+)"
    fi

    if [[ $errors -gt 0 ]]; then
        log_error "❌ System requirements validation failed"
        return 1
    else
        log_success "✅ System requirements validation passed"
        return 0
    fi
}

# Main validation function
main() {
    local settings_file="${1:-./settings.env}"
    local exit_code=0

    echo "🔍 VaultWarden-OCI Configuration Validator"
    echo "=========================================="
    echo ""

    # Run all validations
    if ! validate_system_requirements; then
        exit_code=1
    fi

    echo ""
    if ! validate_compose_config; then
        exit_code=1
    fi

    echo ""
    if ! validate_settings_file "$settings_file"; then
        exit_code=1
    fi

    echo ""
    echo "=========================================="
    if [[ $exit_code -eq 0 ]]; then
        log_success "🎉 All validations passed - ready to deploy!"
        echo ""
        echo "Next steps:"
        echo "  1. Review any warnings above"
        echo "  2. Run: ./startup.sh"
    else
        log_error "❌ Validation failed - fix errors before deployment"
        echo ""
        echo "Common fixes:"
        echo "  - Copy settings.env.example to settings.env and edit"
        echo "  - Generate ADMIN_TOKEN: openssl rand -base64 32"
        echo "  - Configure backup: docker compose run --rm bw_backup rclone config"
    fi

    exit $exit_code
}

# Show help
show_help() {
    cat <<EOF
Configuration Validator for VaultWarden-OCI-Slim

Usage: $0 [settings-file]

Arguments:
    settings-file    Path to settings.env file (default: ./settings.env)

Examples:
    $0                      # Validate ./settings.env
    $0 ./custom.env         # Validate custom configuration file

This script validates:
  ✓ System requirements (Docker, commands, resources)
  ✓ Docker Compose configuration
  ✓ Required environment variables
  ✓ Service-specific configuration
  ✓ Profile dependencies

Run this before deployment to catch configuration issues early.
EOF
}

# Handle command line arguments
case "${1:-}" in
    --help|-h|help)
        show_help
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
