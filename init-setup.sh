#!/usr/bin/env bash
#
# init-setup.sh - One-Step Setup for VaultWarden-OCI-Slim
#
# This script prepares a minimal OS for the full VaultWarden stack. It combines
# dynamic version detection with a focused, reliable, and maintainable approach,
# and is optimized for cloud environments like OCI.

set -euo pipefail

# Source common library for shared functions and colors
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/lib/common.sh" || {
    # Fallback colors if lib/common.sh isn't available
    if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
        readonly RED='\033[0;31m'; readonly GREEN='\033[0;32m'; readonly YELLOW='\033[1;33m';
        readonly BLUE='\033[0;34m'; readonly BOLD='\033[1m'; readonly NC='\033[0m';
    else
        readonly RED=''; readonly GREEN=''; readonly YELLOW=''; readonly BLUE=''; readonly BOLD=''; readonly NC='';
    fi
}

# --- Configuration & Globals ---
readonly FALLBACK_COMPOSE_VERSION="2.40.0"
readonly FALLBACK_RCLONE_VERSION="1.68.1"
readonly FALLBACK_OCI_CLI_VERSION="3.41.0"
DOCKER_COMPOSE_VERSION=""
RCLONE_VERSION=""
OCI_CLI_VERSION=""

# --- Utility Functions ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; exit "${2:-1}"; }
log_step() { echo -e "\n${BOLD}=== $1 ===${NC}"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }
is_root() { [[ $EUID -eq 0 ]]; }
version_compare() {
    local v1; v1=$(echo "$1" | grep -o -E '^[0-9.]+' || echo "0");
    local v2; v2=$(echo "$2" | grep -o -E '^[0-9.]+' || echo "0");
    if [[ "$(printf '%s\n' "$v1" "$v2" | sort -V | head -n1)" == "$v2" ]]; then return 0; else return 1; fi
}

# --- Dynamic Version Detection ---
get_latest_github_release() {
    local repo="$1"
    local tag
    tag=$(curl -s --connect-timeout 5 "https://api.github.com/repos/${repo}/releases/latest" | grep -o '"tag_name": "[^"]*' | cut -d'"' -f4 | sed 's/^v//')
    echo "$tag"
}

detect_optimal_versions() {
    log_step "Detecting Latest Component Versions"
    DOCKER_COMPOSE_VERSION=$(get_latest_github_release "docker/compose") || true
    RCLONE_VERSION=$(get_latest_github_release "rclone/rclone") || true
    OCI_CLI_VERSION=$(get_latest_github_release "oracle/oci-cli") || true

    : "${DOCKER_COMPOSE_VERSION:=$FALLBACK_COMPOSE_VERSION}"
    : "${RCLONE_VERSION:=$FALLBACK_RCLONE_VERSION}"
    : "${OCI_CLI_VERSION:=$FALLBACK_OCI_CLI_VERSION}"

    log_success "Targeting Docker Compose v${DOCKER_COMPOSE_VERSION}"
    log_success "Targeting rclone v${RCLONE_VERSION}"
    log_success "Targeting OCI CLI v${OCI_CLI_VERSION}"
}

# --- Installation Functions ---

install_system_packages() {
    log_info "Installing required system packages: $*"
    if command_exists apt-get; then
        sudo apt-get update -qq && sudo apt-get install -y --no-install-recommends "$@";
    elif command_exists dnf; then
        sudo dnf install -y "$@";
    else
        log_error "Unsupported package manager. Please install packages manually."
    fi
}

install_docker() {
    log_step "Docker Engine Setup"
    if command_exists docker; then log_success "Docker is already installed."; return 0; fi
    log_info "Installing Docker via official script..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo usermod -aG docker "$USER"
    log_warning "User added to 'docker' group. A logout/login may be required."
}

install_docker_compose() {
    log_step "Docker Compose Setup"
    if command_exists docker && docker compose version >/dev/null 2>&1; then
        local current_version; current_version=$(docker compose version --short)
        if version_compare "$current_version" "$DOCKER_COMPOSE_VERSION"; then
            log_success "Docker Compose v${current_version} is up to date."; return 0;
        fi
    fi
    log_info "Installing Docker Compose v${DOCKER_COMPOSE_VERSION}..."
    local arch; arch=$(uname -m)
    local compose_url="https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${arch}"
    sudo mkdir -p /usr/local/lib/docker/cli-plugins
    sudo curl -L "$compose_url" -o /usr/local/lib/docker/cli-plugins/docker-compose
    sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
}

install_rclone() {
    log_step "rclone Setup"
    if command_exists rclone; then
        local current_version; current_version=$(rclone version | head -n 1 | grep -o -E 'v[0-9.]+')
        if version_compare "${current_version#v}" "$RCLONE_VERSION"; then
            log_success "rclone ${current_version} is up to date."; return 0;
        fi
    fi
    log_info "Installing latest rclone via official script..."
    curl -s https://rclone.org/install.sh | sudo bash
}

install_oci_cli() {
    log_step "OCI CLI Setup"
    if command_exists oci; then
        log_info "OCI CLI is already installed. Skipping."
        return 0
    fi

    local setup_oci
    read -p "Do you want to install the OCI CLI for Vault integration? (y/N): " -n 1 -r setup_oci; echo
    if [[ ! "$setup_oci" =~ ^[Yy]$ ]]; then
        log_info "Skipping OCI CLI installation."
        return 0
    fi
    
    log_info "Installing OCI CLI via official script..."
    curl -sL https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh | bash -s -- --accept-all-defaults --quiet
    log_success "OCI CLI installed. The wizard will help you configure it."
}

# --- Project & Maintenance Configuration ---

setup_project() {
    log_step "Project Initialization"
    if [[ ! -f "settings.env" && -f "settings.env.example" ]]; then
        cp settings.env.example settings.env; chmod 600 settings.env
        log_warning "settings.env created from template. The wizard will now guide you through it."
    fi
}

setup_sqlite_maintenance() {
    log_step "SQLite Maintenance Setup"
    if [[ ! -f "./sqlite-maintenance.sh" ]]; then
        log_warning "sqlite-maintenance.sh not found. Cannot schedule maintenance."; return;
    fi
    local setup_maint; read -p "Setup automatic weekly SQLite maintenance via cron? (y/N): " -n 1 -r setup_maint; echo
    if [[ "$setup_maint" =~ ^[Yy]$ ]]; then
        chmod +x ./sqlite-maintenance.sh
        if ./sqlite-maintenance.sh --schedule "0 3 * * 0"; then
            log_success "SQLite maintenance has been scheduled successfully."
        else
            log_error "Failed to schedule SQLite maintenance."
        fi
    fi
}

show_help() {
    cat <<EOF
${BOLD}VaultWarden-OCI-Slim Definitive Setup Script${NC}
Prepares a minimal OS to run the full VaultWarden stack.

${BOLD}USAGE:${NC}
  $0 [options]

${BOLD}OPTIONS:${NC}
  --offline           Skip version detection and use fallback versions.
  --help, -h          Show this help message.
EOF
}

# --- Main Execution ---

main() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then show_help; exit 0; fi

    cat <<EOF

╔══════════════════════════════════════════════════════════════════════════════╗
║      VaultWarden-OCI-Slim - All-in-One Initial Setup                         ║
╚══════════════════════════════════════════════════════════════════════════════╝

This script will install all system dependencies for the full stack.
EOF

    if is_root; then log_error "Do not run this script as root."; fi

    if ! sudo -n true 2>/dev/null; then
        log_error "Passwordless sudo access is required. Please check your /etc/sudoers.d/ configuration."
    fi
    
    if [[ "${1:-}" == "--offline" ]]; then
        log_warning "Running in offline mode. Using fallback versions."
        DOCKER_COMPOSE_VERSION="$FALLBACK_COMPOSE_VERSION"
        RCLONE_VERSION="$FALLBACK_RCLONE_VERSION"
        OCI_CLI_VERSION="$FALLBACK_OCI_CLI_VERSION"
    else
        detect_optimal_versions
    fi

    log_step "System Prerequisite Installation"
    install_system_packages curl unzip git sudo jq sqlite3 bc gpg python3-pip cron
    
    install_docker
    install_docker_compose
    install_rclone
    install_oci_cli
    
    setup_project
    setup_sqlite_maintenance

    # Automatically run the configuration wizard
    log_step "Launching Interactive Configuration Wizard"
    if [[ -f "$SCRIPT_DIR/tools/settings.env.wizard.sh" ]]; then
        chmod +x "$SCRIPT_DIR/tools/settings.env.wizard.sh"
        "$SCRIPT_DIR/tools/settings.env.wizard.sh"
    else
        log_warning "Configuration wizard not found. Please configure settings.env manually."
    fi
    
    log_step "Setup Complete!"
    log_success "Your system is now ready. Review settings.env and run ./startup.sh"
}

main "$@"
