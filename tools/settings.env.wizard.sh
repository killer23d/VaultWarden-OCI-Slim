#!/usr/bin/env bash
#
# settings.env.wizard.sh - Interactive Setup Wizard for VaultWarden-OCI-Slim
#
# This script guides users through critical and advanced configuration steps,
# orchestrating other scripts as needed for a comprehensive setup.

set -euo pipefail

# --- Path and Environment Setup ---
TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${TOOLS_DIR}/.." && pwd)"
readonly SETTINGS_FILE="$REPO_ROOT/settings.env"
readonly SETTINGS_EXAMPLE_FILE="$REPO_ROOT/settings.env.example"

# --- Load Common Library for Color and Logging ---
readonly LIB_COMMON_PATH="$REPO_ROOT/lib/common.sh"
if [[ -f "$LIB_COMMON_PATH" ]]; then
    source "$LIB_COMMON_PATH"
else
    echo "[ERROR] Required library not found at: $LIB_COMMON_PATH" >&2
    exit 1
fi

# --- Pre-flight Checks ---
pre_flight_check() {
    log_step "Verifying Environment"
    if ! command -v openssl >/dev/null 2>&1; then
        log_error "'openssl' is required but not found."
    fi
    if [[ ! -f "$SETTINGS_FILE" ]]; then
        log_warning "Configuration file not found: $SETTINGS_FILE"
        read -p "Create it now from the template? (Y/n): " create_file
        if [[ "$create_file" =~ ^[Nn]$ ]]; then
            log_error "Aborting. Setup cannot continue without settings.env."
        else
            cp "$SETTINGS_EXAMPLE_FILE" "$SETTINGS_FILE"; chmod 600 "$SETTINGS_FILE"
            log_success "Created '$SETTINGS_FILE' with secure permissions (600)."
        fi
    fi
    log_success "Environment check passed."
}

# --- Helper Functions ---
get_current_value() { grep "^${1}=" "$SETTINGS_FILE" | cut -d'=' -f2- || echo ""; }
update_setting() {
    sed -i "s#^${1}=.*#${1}=${2}#" "$SETTINGS_FILE"
}
prompt_for_secret() {
    log_info "$2"
    read -p "Generate a new secure ${1}? (Recommended) (Y/n): " gen
    if [[ ! "$gen" =~ ^[Nn]$ ]]; then
        update_setting "$1" "$(openssl rand -base64 48)"
        log_success "New ${1} generated and saved."
    else
        log_warning "Skipped ${1} generation. Please ensure it is secure."
    fi
}

# --- Essential Configuration Steps ---
configure_essentials() {
    log_step "1. Domain Configuration"
    local domain; domain=$(get_current_value "VAULTWARDEN_DOMAIN")
    read -p "Enter Vaultwarden FQDN (e.g., vault.example.com) [${domain}]: " d; d=${d:-$domain}
    update_setting "VAULTWARDEN_DOMAIN" "$d"
    log_success "Domain configured: https://${d}"

    log_step "2. Administrator Configuration"
    local email; email=$(get_current_value "ADMIN_EMAIL")
    read -p "Enter admin email [${email}]: " e; e=${e:-$email}
    update_setting "ADMIN_EMAIL" "$e"
    prompt_for_secret "ADMIN_TOKEN" "The ADMIN_TOKEN is for accessing the Vaultwarden admin panel."

    log_step "3. Backup Configuration"
    read -p "Enable automated remote backups? (y/N): " enable_backup
    if [[ "$enable_backup" =~ ^[Yy]$ ]]; then
        update_setting "ENABLE_BACKUP" "true"
        local remote; remote=$(get_current_value "BACKUP_REMOTE")
        read -p "Enter rclone remote name (e.g., b2-backups): " br; br=${br:-$remote}
        update_setting "BACKUP_REMOTE" "$br"
        prompt_for_secret "BACKUP_PASSPHRASE" "The BACKUP_PASSPHRASE encrypts your database backups."
        log_warning "IMPORTANT: Configure rclone manually: cd ${REPO_ROOT} && docker compose run --rm bw_backup rclone config"
    else
        update_setting "ENABLE_BACKUP" "false"
        log_warning "Automated backups disabled."
    fi
}

# --- Advanced Configuration Menu ---
configure_advanced() {
    while true; do
        log_step "Advanced Feature Configuration (Optional)"
        echo "Select a feature to configure:"
        echo "  [1] Admin Page Hardening (Recommended)"
        echo "  [2] OCI Vault Integration"
        echo "  [3] Push Notifications"
        echo "  [4] Cloudflare API Token"
        echo "  [5] SMTP Email Server"
        echo ""
        echo "  [D] Done / Skip"
        read -p "Enter your choice: " choice

        case $choice in
            1) configure_admin_hardening ;;
            2) configure_oci_vault ;;
            3) configure_push_notifications ;;
            4) configure_cloudflare ;;
            5) configure_smtp ;;
            [Dd]|"") break ;;
            *) log_warning "Invalid choice. Please try again." ;;
        esac
    done
}

configure_admin_hardening() {
    log_info "Setting up Basic Auth for the admin panel..."
    read -p "Enter a username for the admin prompt [admin]: " user; user=${user:-admin}
    read -sp "Enter a password for this user (will not be stored): " pass; echo
    if [[ -z "$pass" ]]; then log_error "Password cannot be empty."; return 1; fi

    log_info "Temporarily starting Caddy to generate secure hash..."
    docker compose up -d bw_caddy
    sleep 5
    local hash; hash=$(docker compose exec bw_caddy caddy hash-password --plaintext "$pass" | tr -d '\r')
    docker compose down
    if [[ -z "$hash" ]]; then log_error "Failed to generate hash."; return 1; fi

    grep -q "^BASIC_ADMIN_USER=" "$SETTINGS_FILE" || echo "BASIC_ADMIN_USER=" >> "$SETTINGS_FILE"
    grep -q "^BASIC_ADMIN_HASH=" "$SETTINGS_FILE" || echo "BASIC_ADMIN_HASH=" >> "$SETTINGS_FILE"
    update_setting "BASIC_ADMIN_USER" "$user"; update_setting "BASIC_ADMIN_HASH" "$hash"
    log_success "Secure credentials saved."

    local caddyfile="$REPO_ROOT/caddy/Caddyfile"
    sed -i -e '/# VAULTWARDEN ADMIN HARDENING/,/}/ s/# *\(basicauth\)/  \1/' \
           -e '/# VAULTWARDEN ADMIN HARDENING/,/}/ s/# *\({\|$\)/    \1/' \
           -e '/# VAULTWARDEN ADMIN HARDENING/,/}/ s/# *}/\  }/' "$caddyfile"
    log_success "Admin hardening enabled in Caddyfile."
}

configure_oci_vault() {
    log_info "Configuring OCI Vault integration..."
    if ! command -v oci >/dev/null 2>&1; then
        log_error "OCI CLI ('oci') not found. Please run init-setup.sh to install it."; return 1;
    fi
    if [[ ! -f "$HOME/.oci/config" ]]; then
        log_warning "OCI CLI config not found at ~/.oci/config."
        read -p "Run 'oci setup config' now to create it? (Y/n): " run_setup
        if [[ ! "$run_setup" =~ ^[Nn]$ ]]; then
            /root/bin/oci setup config
        else
            log_warning "Skipping OCI Vault setup."; return 0;
        fi
    fi
    local ocid; ocid=$(get_current_value "OCI_SECRET_OCID")
    read -p "Enter your OCI Secret OCID: " new_ocid; new_ocid=${new_ocid:-$ocid}
    update_setting "OCI_SECRET_OCID" "$new_ocid"
    log_success "OCI Secret OCID saved."
}

configure_push_notifications() {
    log_info "Configuring Push Notifications..."
    log_warning "Get credentials from https://bitwarden.com/host/"
    local id; id=$(get_current_value "PUSH_INSTALLATION_ID")
    read -p "Enter Push Installation ID: " new_id; new_id=${new_id:-$id}
    update_setting "PUSH_INSTALLATION_ID" "$new_id"

    local key; key=$(get_current_value "PUSH_INSTALLATION_KEY")
    read -p "Enter Push Installation Key: " new_key; new_key=${new_key:-$key}
    update_setting "PUSH_INSTALLATION_KEY" "$new_key"
    log_success "Push notification credentials saved."
}

configure_cloudflare() {
    log_info "Configuring Cloudflare API Token..."
    log_warning "This is optional, for helper scripts."
    local token; token=$(get_current_value "CF_API_TOKEN")
    read -p "Enter Cloudflare API Token (optional): " new_token; new_token=${new_token:-$token}
    update_setting "CF_API_TOKEN" "$new_token"
    log_success "Cloudflare API Token saved."
}

configure_smtp() {
    log_info "Configuring SMTP for email notifications..."
    read -p "Enter SMTP Host: " host
    read -p "Enter SMTP Port [587]: " port
    read -p "Enter SMTP Username: " user
    read -sp "Enter SMTP Password/Token: " pass; echo
    read -p "Enter SMTP From Email: " from
    update_setting "SMTP_HOST" "$host"
    update_setting "SMTP_PORT" "${port:-587}"
    update_setting "SMTP_USERNAME" "$user"
    update_setting "SMTP_PASSWORD" "$pass"
    update_setting "SMTP_FROM" "$from"
    log_success "SMTP settings saved."
}

# --- Main Execution ---
main() {
    cat << "EOF"

╔════════════════════════════════════════════════════════════════════╗
║      VaultWarden-OCI-Slim - Comprehensive Configuration Wizard     ║
╚════════════════════════════════════════════════════════════════════╝

This wizard will guide you through all essential and advanced settings.
Press Enter to accept the default value in brackets [].
EOF

    pre_flight_check
    configure_essentials
    configure_advanced

    cat << EOF

$(log_success "Wizard complete! 'settings.env' has been fully configured.")
$(log_info "Next Step: Start the stack by running: cd ${REPO_ROOT} && ./startup.sh")
======================================================================
EOF
}

main "$@"
