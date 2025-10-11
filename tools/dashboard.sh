#!/usr/bin/env bash
# dashboard.sh -- Refactored Interactive Dashboard for VaultWarden-OCI-Slim

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
# FIX: Correct path to parent directory's lib folder
LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# Load core modules (order matters) - FIXED PATHS
source "$LIB_DIR/common.sh"
source "$LIB_DIR/dashboard-config.sh"
source "$LIB_DIR/dashboard-ui.sh"  
source "$LIB_DIR/dashboard-metrics.sh"
source "$LIB_DIR/dashboard-sqlite.sh"
source "$LIB_DIR/dashboard-core.sh"
source "$LIB_DIR/dashboard-maintenance.sh"

# Initialize dashboard configuration
dashboard_config_init

# Main function - simplified orchestration
main() {
    local mode="interactive"
    local refresh_interval="${DASHBOARD_REFRESH_INTERVAL:-5}"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --static|--once)
                mode="static"
                shift
                ;;
            --refresh)
                refresh_interval="$2"
                shift 2
                ;;
            --help|-h)
                dashboard_show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done

    # Check terminal capability for interactive mode
    if [[ "$mode" == "interactive" && ! -t 0 ]]; then
        mode="static"
    fi

    # Execute appropriate mode
    case "$mode" in
        "interactive")
            dashboard_interactive_mode "$refresh_interval"
            ;;
        "static")
            dashboard_static_mode
            ;;
    esac
}

# Execute main function with all arguments
main "$@"
