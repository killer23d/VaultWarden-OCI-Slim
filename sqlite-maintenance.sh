#!/usr/bin/env bash
# sqlite-maintenance.sh -- Refactored SQLite maintenance script for VaultWarden-OCI-Slim

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Load core modules (order matters)
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/sqlite-metrics.sh"
source "$SCRIPT_DIR/lib/sqlite-analyzer.sh"
source "$SCRIPT_DIR/lib/sqlite-operations.sh"
source "$SCRIPT_DIR/lib/sqlite-scheduler.sh"
source "$SCRIPT_DIR/lib/sqlite-reporter.sh"

# Initialize SQLite maintenance configuration
sqlite_maintenance_init() {
    # Load settings
    if [[ -f "${ROOT_DIR}/settings.env" ]]; then
        source "${ROOT_DIR}/settings.env"
    fi

    # Set defaults
    export SQLITE_DB_PATH="${SQLITE_DB_PATH:-${ROOT_DIR}/data/bw/data/bwdata/db.sqlite3}"
    export LOG_DIR="${LOG_DIR:-${ROOT_DIR}/data/backup_logs}"
    export LOG_FILE="$LOG_DIR/sqlite-maintenance-$(date +%Y%m%d_%H%M%S).log"

    # Create log directory
    mkdir -p "$LOG_DIR"

    # Initialize configuration
    sqlite_analyzer_init
    sqlite_operations_init
    sqlite_scheduler_init
    sqlite_reporter_init
}

# Main function with intelligent auto mode as default
main() {
    local force_comprehensive=false
    local force_vacuum=false
    local analyze_only=false
    local install_schedule=false
    local schedule_time="0 3 * * 0"
    local cron_mode=false
    local operation=""
    local explicit_mode=false

    # Initialize
    sqlite_maintenance_init

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --auto)
                explicit_mode=true
                shift
                ;;
            --cron)
                cron_mode=true
                explicit_mode=true
                shift
                ;;
            --comprehensive)
                force_comprehensive=true
                explicit_mode=true
                shift
                ;;
            --force-vacuum)
                force_vacuum=true
                explicit_mode=true
                shift
                ;;
            --analyze)
                analyze_only=true
                explicit_mode=true
                shift
                ;;
            --operation)
                operation="$2"
                explicit_mode=true
                shift 2
                ;;
            --schedule)
                install_schedule=true
                schedule_time="${2:-0 3 * * 0}"
                shift 2
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1. Use --help for usage information."
                exit 1
                ;;
        esac
    done

    log_info "🤖 SQLite Intelligent Auto Maintenance Starting..."
    log_info "Mode: $([[ "$explicit_mode" == "false" ]] && echo "Auto (Default)" || echo "Explicit")"
    local start_time=$(date +%s)

    # Install schedule if requested
    if [[ "$install_schedule" == "true" ]]; then
        sqlite_scheduler_install "$schedule_time"
        exit 0
    fi

    # Check database accessibility
    if ! sqlite_operations_check_database; then
        log_error "Database check failed"
        [[ "$cron_mode" == "true" ]] && sqlite_reporter_send_notification "FAILED" "Database not accessible"
        exit 1
    fi

    # Handle specific operations
    if [[ -n "$operation" ]]; then
        sqlite_operations_run_single "$operation"
        exit $?
    fi

    # Handle analyze-only mode
    if [[ "$analyze_only" == "true" ]]; then
        sqlite_analyzer_perform_analysis
        if sqlite_analyzer_has_recommendations; then
            echo ""
            echo "💡 Recommended actions to run:"
            echo "   $0                    # Run intelligent auto maintenance"
            echo "   $0 --comprehensive    # Force all operations"
        fi
        exit 0
    fi

    # Handle comprehensive mode
    if [[ "$force_comprehensive" == "true" ]]; then
        log_info "🔧 Running comprehensive maintenance (all operations)..."
        if sqlite_operations_run_comprehensive "$cron_mode"; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            [[ "$cron_mode" == "true" ]] && sqlite_reporter_send_notification "COMPLETED" "All operations completed" "${duration}s"
            exit 0
        else
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            [[ "$cron_mode" == "true" ]] && sqlite_reporter_send_notification "PARTIAL" "Some operations failed" "${duration}s"
            exit 1
        fi
    fi

    # DEFAULT: Intelligent auto maintenance
    log_decision "Using intelligent auto maintenance (analyzes database and performs only needed operations)"

    if sqlite_operations_run_intelligent "$cron_mode"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        local status="COMPLETED"
        if ! sqlite_analyzer_has_executed_operations; then
            status="SKIPPED"
        fi

        # Send notification in cron mode
        if [[ "$cron_mode" == "true" ]]; then
            sqlite_reporter_send_notification "$status" "Intelligent analysis completed" "${duration}s"
        fi

        # Interactive summary
        if [[ "$cron_mode" == "false" ]]; then
            sqlite_reporter_show_summary "$duration"
        fi

        exit 0
    else
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        if [[ "$cron_mode" == "true" ]]; then
            sqlite_reporter_send_notification "PARTIAL" "Some operations failed" "${duration}s"
        fi

        exit 1
    fi
}

# Show help information
show_help() {
    cat <<EOF
🤖 Intelligent SQLite Maintenance Script for VaultWarden-OCI-Slim

DEFAULT MODE: Intelligent Auto Maintenance
- Analyzes database metrics and fragmentation
- Determines optimal operations automatically  
- Performs only needed maintenance operations
- Ideal for cron scheduling and hands-off operation

Usage: $0 [OPTIONS]

🤖 Intelligent Modes (DEFAULT):
    (no args)               Intelligent auto maintenance (DEFAULT)
    --auto                  Explicit intelligent auto mode
    --cron                  Cron mode (skips VACUUM if VaultWarden running)

🔧 Manual Operation Modes:
    --comprehensive         Force all maintenance operations
    --force-vacuum          Force VACUUM regardless of analysis
    --analyze              Analyze database and show recommendations only
    --operation OPERATION   Run specific operation only

📅 Scheduling:
    --schedule TIME        Install cron schedule (default: "0 3 * * 0")

Individual Operations:
    --operation analyze           # ANALYZE only
    --operation vacuum            # VACUUM only  
    --operation checkpoint        # WAL checkpoint only
    --operation optimize          # PRAGMA optimize only
    --operation statistics        # Table statistics only

🧠 Intelligent Decision Matrix:
    ANALYZE:           Missing/stale statistics, sizeable databases
    VACUUM:            High fragmentation (>1.3), significant free space (>10%)
    WAL Checkpoint:    Large WAL files (>10MB) or significant relative size
    PRAGMA Optimize:   Active databases with existing statistics
    Table Statistics:  Multiple tables with outdated statistics

Examples:
    $0                              # Intelligent auto (DEFAULT)
    $0 --cron                       # Cron-safe auto mode
    $0 --analyze                    # Analysis only
    $0 --comprehensive              # Force all operations
    $0 --schedule "0 3 * * 0"       # Schedule intelligent auto maintenance

🎯 Recommended Usage:
    Production: $0 --cron (for crontab)
    Manual:     $0 (interactive intelligent mode)
    Analysis:   $0 --analyze (check what's needed)

EOF
}

# Execute main function
main "$@"
