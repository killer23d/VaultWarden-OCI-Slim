#!/usr/bin/env bash
#
# settings.env.wizard.sh - Interactive Setup Wizard for VaultWarden-OCI-Slim
#
# This script guides users through the most critical configuration steps
# for the settings.env file. It reads existing values, suggests generating
# secure secrets, and safely updates the configuration.

set -euo pipefail

# --- Path and Environment Setup ---
# Robustly determine the repository root, assuming this script is in tools/
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TOOLS_DIR}/.." && pwd)"
readonly SETTINGS_FILE="$REPO_ROOT/settings.env"
readonly SETTINGS_EXAMPLE_FILE="$REPO_ROOT/settings.env.example"

# --- Load Common Library for Color and Logging ---
# This script now requires the common library for a consistent UX.
readonly LIB_COMMON_PATH="$REPO_ROOT/lib/common.sh"
if [[ -f "$LIB_COMMON_PATH" ]]; then
    source "$LIB_COMMON_PATH"
else
    # Provide a clear, actionable error if the library is missing.
    echo "[ERROR] Required library not found at: $LIB_COMMON_PATH" >&2
    echo "This indicates an incomplete repository clone. Please re-clone the project or run 'init-setup.sh'." >&2
    exit 1
fi

# --- Pre-flight Checks ---
pre_flight_check() {
    log_step "Verifying Environment"

    # Check for OpenSSL
    if ! command -v openssl >/dev/null 2>&1; then
        log_error "'openssl' command is required to generate secure secrets but was not found."
    fi

    # Check for settings.env and handle its absence gracefully
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        log_warning "Configuration file not found: $SETTINGS_FILE"
        if [[ -f "$SETTINGS_EXAMPLE_FILE" ]]; then
            read -p "Create it now from the template (settings.env.example)? (Y/n): " create_file
            if [[ "$create_file" =~ ^[Nn]$ ]]; then
                log_error "Setup cannot continue without a settings.env file. Aborting."
            else
                cp "$SETTINGS_EXAMPLE_FILE" "$SETTINGS_FILE"
                chmod 600 "$SETTINGS_FILE"
                log_success "Created '$SETTINGS_FILE' with secure permissions (600)."
            fi
        else
            log_error "The template file 'settings.env.example' is also missing. Please run 'init-setup.sh' or re-clone the repository."
        fi
    fi
    log_success "Environment check passed."
}

# --- Helper Functions ---
get_current_value() {
    local key="$1"
    grep "^${key}=" "$SETTINGS_FILE" | cut -d'=' -f2- || echo ""
}

update_setting() {
    local key="$1"
    local value="$2"
    # Use a temporary file and mv for atomic replacement, which is safer.
    # The '#' delimiter in sed avoids issues with file paths or URLs in values.
    sed "s#^${key}=.*#${key}=${value}#" "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
}

prompt_for_secret_generation() {
    local key_name="$1"
    local description="$2"
    log_info "$description"
    read -p "Generate a new secure ${key_name}? (Recommended) (Y/n): " generate
    if [[ ! "$generate" =~ ^[Nn]$ ]]; then
        local new_secret
        new_secret=$(openssl rand -base64 48)
        update_setting "$key_name" "$new_secret"
        log_success "New ${key_name} generated and saved to settings.env."
    else
        log_warning "Skipped generating a new ${key_name}. Please ensure the existing one is secure."
    fi
}

# --- Wizard Steps ---

configure_domain() {
    log_step "1. Domain Configuration"
    local current_domain_name
    current_domain_name=$(get_current_value "DOMAIN_NAME")

    read -p "Enter your primary domain name (e.g., example.com) [${current_domain_name}]: " domain_name
    domain_name=${domain_name:-$current_domain_name}

    local default_app_domain="vault.${domain_name}"
    local current_app_domain
    current_app_domain=$(get_current_value "APP_DOMAIN")

    read -p "Enter the full domain for Vaultwarden (e.g., vault.example.com) [${default_app_domain}]: " app_domain
    app_domain=${app_domain:-$default_app_domain}

    update_setting "DOMAIN_NAME" "$domain_name"
    update_setting "APP_DOMAIN" "$app_domain"
    update_setting "DOMAIN" "https://${app_domain}"

    log_success "Domain configured: https://${app_domain}"
}

configure_admin() {
    log_step "2. Administrator Configuration"
    local current_admin_email
    current_admin_email=$(get_current_value "ADMIN_EMAIL")
    
    read -p "Enter the administrator's email address [${current_admin_email}]: " admin_email
    admin_email=${admin_email:-$current_admin_email}
    update_setting "ADMIN_EMAIL" "$admin_email"

    prompt_for_secret_generation "ADMIN_TOKEN" "The ADMIN_TOKEN is a secure key for accessing the Vaultwarden admin panel."
}

configure_smtp() {
    log_step "3. SMTP Email Configuration (Optional)"
    log_info "SMTP is required for user invitations, password resets, and alert notifications."
    read -p "Do you want to configure SMTP now? (y/N): " configure_smtp
    if [[ "$configure_smtp" =~ ^[Yy]$ ]]; then
        read -p "Enter SMTP Host (e.g., smtp.mailersend.net): " smtp_host
        read -p "Enter SMTP Port [587]: " smtp_port
        read -p "Enter SMTP Username: " smtp_username
        read -sp "Enter SMTP Password/Token: " smtp_password; echo
        read -p "Enter SMTP From Email Address (e.g., vault@yourdomain.com): " smtp_from

        update_setting "SMTP_HOST" "$smtp_host"
        update_setting "SMTP_PORT" "${smtp_port:-587}"
        update_setting "SMTP_USERNAME" "$smtp_username"
        update_setting "SMTP_PASSWORD" "$smtp_password"
        update_setting "SMTP_FROM" "$smtp_from"
        
        log_success "SMTP settings updated."
    else
        log_warning "SMTP configuration skipped. Email features will be disabled."
    fi
}

configure_backups() {
    log_step "4. Backup Configuration (Optional but Recommended)"
    local current_enable_backup
    current_enable_backup=$(get_current_value "ENABLE_BACKUP")
    read -p "Enable automated remote backups? [${current_enable_backup}]: " enable_backup
    enable_backup=${enable_backup:-$current_enable_backup}

    if [[ "$enable_backup" == "true" ]]; then
        update_setting "ENABLE_BACKUP" "true"
        log_success "Backups enabled."

        read -p "Enter your rclone remote name (e.g., b2-backups): " backup_remote
        update_setting "BACKUP_REMOTE" "$backup_remote"

        prompt_for_secret_generation "BACKUP_PASSPHRASE" "The BACKUP_PASSPHRASE is used to encrypt your database backups."
        
        log_warning "IMPORTANT: You must still configure your rclone remote manually by running:"
        log_warning "  cd ${REPO_ROOT} && docker compose run --rm bw_backup rclone config"
    else
        update_setting "ENABLE_BACKUP" "false"
        log_warning "Automated backups disabled."
    fi
}

# --- Main Execution ---
main() {
    cat << "EOF"

╔════════════════════════════════════════════════════════════════════╗
║      VaultWarden-OCI-Slim - Interactive Configuration Wizard         ║
╚════════════════════════════════════════════════════════════════════╝

EOF
    log_info "This wizard will guide you through the essential settings."
    log_info "Press Enter to accept the default value in brackets []."
    
    pre_flight_check
    configure_domain
    configure_admin
    configure_smtp
    configure_backups

    cat << EOF

$(log_success "Wizard complete! Your 'settings.env' file has been updated.")
$(log_info "You can re-run this wizard at any time to change these settings.")
$(log_info "Next Step: Start the stack by running: cd ${REPO_ROOT} && ./startup.sh")
======================================================================
EOF
}

main "$@"
