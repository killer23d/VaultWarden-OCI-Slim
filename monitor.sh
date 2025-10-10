#!/usr/bin/env bash
# monitor.sh -- VaultWarden-OCI Real-time Monitoring Dashboard
# UNIFIED VERSION: Uses centralized monitoring configuration

set -euo pipefail
IFS=$'\n\t'

# Colors and formatting
if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
    readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
    readonly BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m'
    readonly WHITE='\033[1;37m' BOLD='\033[1m' NC='\033[0m'
else
    readonly RED='' GREEN='' YELLOW='' BLUE='' PURPLE='' CYAN=''
    readonly WHITE='' BOLD='' NC=''
fi

# Source common library and UNIFIED monitoring configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/lib/common.sh" || {
    echo "ERROR: lib/common.sh required" >&2
    exit 1
}

# UNIFIED CONFIGURATION: Single source of truth
source "$SCRIPT_DIR/lib/monitoring-config.sh" || {
    echo "ERROR: lib/monitoring-config.sh required for unified configuration" >&2
    exit 1
}

# Verify configuration loaded successfully
if [[ "$MONITORING_CONFIG_LOADED" != "true" ]]; then
    log_error "Monitoring configuration failed to load"
    exit 1
fi

log_info "Using unified monitoring configuration v$MONITORING_CONFIG_VERSION"
log_info "Configuration sources: $MONITORING_CONFIG_SOURCES"

# Internal state
declare -a METRIC_HISTORY=()
declare -A CONTAINER_STATS=()
ALERT_SENT=false

# ================================
# UTILITY FUNCTIONS
# ================================

# Terminal control
clear_screen() { printf '\033[2J\033[H'; }
hide_cursor() { printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }
move_cursor() { printf '\033[%d;%dH' "$1" "$2"; }

# Cleanup on exit
cleanup() {
    show_cursor
    [[ "${1:-}" != "0" ]] && echo -e "\n${RED}Monitoring stopped${NC}"
    exit "${1:-0}"
}
trap 'cleanup $?' EXIT INT TERM

# Formatting helpers
format_bytes() {
    local bytes="${1:-0}"
    if [[ $bytes -ge 1073741824 ]]; then
        printf "%.1fGB" "$(echo "scale=1; $bytes / 1073741824" | bc -l)"
    elif [[ $bytes -ge 1048576 ]]; then
        printf "%.1fMB" "$(echo "scale=1; $bytes / 1048576" | bc -l)"
    elif [[ $bytes -ge 1024 ]]; then
        printf "%.1fKB" "$(echo "scale=1; $bytes / 1024" | bc -l)"
    else
        printf "%dB" "$bytes"
    fi
}

format_percentage() {
    local value="${1:-0}"
    local threshold_warn="${2:-$CPU_WARNING_THRESHOLD}"
    local threshold_alert="${3:-$CPU_ALERT_THRESHOLD}"

    if command -v bc >/dev/null 2>&1 && (( $(echo "$value >= $threshold_alert" | bc -l) )); then
        printf "${RED}%5.1f%%${NC}" "$value"
    elif command -v bc >/dev/null 2>&1 && (( $(echo "$value >= $threshold_warn" | bc -l) )); then
        printf "${YELLOW}%5.1f%%${NC}" "$value"
    else
        printf "${GREEN}%5.1f%%${NC}" "$value"
    fi
}

format_load() {
    local load="${1:-0}"
    local cores="${2:-1}"
    local threshold_critical="${LOAD_CRITICAL_THRESHOLD}"
    local threshold_warning="${LOAD_WARNING_THRESHOLD}"

    if command -v bc >/dev/null 2>&1 && (( $(echo "$load > $threshold_critical" | bc -l) )); then
        printf "${RED}%5.2f${NC}" "$load"
    elif command -v bc >/dev/null 2>&1 && (( $(echo "$load > $threshold_warning" | bc -l) )); then
        printf "${YELLOW}%5.2f${NC}" "$load"
    else
        printf "${GREEN}%5.2f${NC}" "$load"
    fi
}

# ================================
# UNIFIED SYSTEM METRICS COLLECTION
# ================================

get_system_metrics() {
    # Use the unified metrics collection from monitoring-config.sh
    get_unified_system_metrics
}

# ================================
# SQLITE MONITORING (UNIFIED)
# ================================

get_sqlite_metrics() {
    local -A sqlite_metrics

    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        sqlite_metrics[db_exists]="false"
        sqlite_metrics[db_size]="0"
        sqlite_metrics[wal_size]="0"
        sqlite_metrics[page_count]="0"
        sqlite_metrics[freelist_count]="0"
        sqlite_metrics[fragmentation_ratio]="0.00"
        sqlite_metrics[status]="Database not found"
    elif ! command -v sqlite3 >/dev/null 2>&1; then
        sqlite_metrics[db_exists]="true"
        sqlite_metrics[status]="sqlite3 not available"
    else
        sqlite_metrics[db_exists]="true"

        # Database file size
        local db_size
        db_size=$(stat -c%s "$SQLITE_DB_PATH" 2>/dev/null || echo "0")
        sqlite_metrics[db_size]="$db_size"

        # WAL file size
        local wal_path="$SQLITE_DB_PATH-wal"
        local wal_size="0"
        if [[ -f "$wal_path" ]]; then
            wal_size=$(stat -c%s "$wal_path" 2>/dev/null || echo "0")
        fi
        sqlite_metrics[wal_size]="$wal_size"

        # SQLite PRAGMA information
        local pragma_result
        if pragma_result=$(sqlite3 "$SQLITE_DB_PATH" "SELECT pragma_page_count(), pragma_freelist_count(), pragma_page_size();" 2>/dev/null); then
            local page_count freelist_count page_size
            IFS='|' read -r page_count freelist_count page_size <<< "$pragma_result"

            sqlite_metrics[page_count]="${page_count:-0}"
            sqlite_metrics[freelist_count]="${freelist_count:-0}"
            sqlite_metrics[page_size]="${page_size:-4096}"

            # Calculate fragmentation ratio
            local fragmentation_ratio="0.00"
            if [[ ${page_count:-0} -gt 0 ]]; then
                fragmentation_ratio=$(echo "scale=2; ${freelist_count:-0} / ${page_count:-1}" | bc -l)
            fi
            sqlite_metrics[fragmentation_ratio]="$fragmentation_ratio"
            sqlite_metrics[status]="OK"
        else
            sqlite_metrics[status]="Query failed"
            sqlite_metrics[page_count]="0"
            sqlite_metrics[freelist_count]="0"
            sqlite_metrics[fragmentation_ratio]="0.00"
        fi
    fi

    printf '%s\n' "${sqlite_metrics[@]/%/}" | while IFS='=' read -r key value; do
        printf 'sqlite_metrics[%s]="%s"\n' "$key" "$value"
    done
}

# ================================
# CONTAINER MONITORING
# ================================

get_container_stats() {
    if ! command -v docker >/dev/null 2>&1; then
        return 0
    fi

    local containers=("vaultwarden" "bw_caddy" "bw_backup" "bw_fail2ban" "bw_watchtower" "bw_ddclient" "bw_monitoring")

    for container in "${containers[@]}"; do
        if docker ps --filter "name=$container" --filter "status=running" --format "{{.Names}}" | grep -q "^$container$"; then
            local stats
            stats=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" "$container" 2>/dev/null | tail -1)

            if [[ -n "$stats" ]]; then
                CONTAINER_STATS["$container"]="$stats"
            fi
        else
            CONTAINER_STATS["$container"]="STOPPED"
        fi
    done
}

# ================================
# UNIFIED ALERT SYSTEM
# ================================

check_thresholds_and_alert() {
    eval "$1"  # Load metrics array
    local alerts=()

    # Use unified threshold evaluation functions
    case "$(evaluate_cpu_threshold "${metrics[cpu_usage]}")" in
        "critical"|"alert")
            alerts+=("CPU usage ${metrics[cpu_usage]}% exceeds threshold ($(evaluate_cpu_threshold "${metrics[cpu_usage]}"))")
            ;;
    esac

    case "$(evaluate_memory_threshold "${metrics[memory_usage]}")" in
        "critical"|"alert")
            alerts+=("Memory usage ${metrics[memory_usage]}% exceeds threshold ($(evaluate_memory_threshold "${metrics[memory_usage]}"))")
            ;;
    esac

    case "$(evaluate_load_threshold "${metrics[load_1min]}")" in
        "critical"|"alert")
            alerts+=("Load average ${metrics[load_1min]} exceeds threshold ($(evaluate_load_threshold "${metrics[load_1min]}"))")
            ;;
    esac

    case "$(evaluate_disk_threshold "${metrics[disk_usage]}")" in
        "critical"|"alert")
            alerts+=("Disk usage ${metrics[disk_usage]}% exceeds threshold ($(evaluate_disk_threshold "${metrics[disk_usage]}"))")
            ;;
    esac

    # SQLite threshold checks using unified evaluation
    if [[ "${sqlite_metrics[db_exists]}" == "true" ]]; then
        local db_size_mb wal_size_mb
        db_size_mb=$(echo "scale=2; ${sqlite_metrics[db_size]} / 1048576" | bc -l)
        wal_size_mb=$(echo "scale=2; ${sqlite_metrics[wal_size]} / 1048576" | bc -l)

        case "$(evaluate_sqlite_size_threshold "$db_size_mb")" in
            "critical"|"alert")
                alerts+=("SQLite database size ${db_size_mb}MB exceeds threshold ($(evaluate_sqlite_size_threshold "$db_size_mb"))")
                ;;
        esac

        if [[ "$wal_size_mb" != "0" ]]; then
            if command -v bc >/dev/null 2>&1 && (( $(echo "$wal_size_mb > $WAL_SIZE_ALERT_MB" | bc -l) )); then
                alerts+=("SQLite WAL size ${wal_size_mb}MB exceeds threshold $WAL_SIZE_ALERT_MB MB")
            fi
        fi

        case "$(evaluate_fragmentation_threshold "${sqlite_metrics[fragmentation_ratio]}")" in
            "critical"|"alert")
                alerts+=("SQLite fragmentation ratio ${sqlite_metrics[fragmentation_ratio]} exceeds threshold ($(evaluate_fragmentation_threshold "${sqlite_metrics[fragmentation_ratio]}"))")
                ;;
        esac
    fi

    # Send alerts using unified system
    if [[ ${#alerts[@]} -gt 0 && "$ALERT_SENT" == "false" ]]; then
        send_unified_alert "${alerts[@]}"
        ALERT_SENT=true
    elif [[ ${#alerts[@]} -eq 0 ]]; then
        ALERT_SENT=false
    fi
}

send_unified_alert() {
    local alert_message="VaultWarden-OCI Alert: $*"

    # Log alert using unified paths
    echo "$(date): $alert_message" >> "$METRICS_LOG"

    # Send email using unified SMTP configuration
    if [[ -n "$ALERT_EMAIL" && -n "$SMTP_HOST" ]]; then
        if command -v mail >/dev/null 2>&1; then
            echo "$alert_message" | mail -s "VaultWarden Alert" "$ALERT_EMAIL" || true
        fi
    fi

    # Send webhook using unified configuration
    if [[ -n "$WEBHOOK_URL" ]]; then
        if command -v curl >/dev/null 2>&1; then
            curl -X POST -H "Content-Type: application/json" \
                -d "{\"text\":\"$alert_message\"}" \
                "$WEBHOOK_URL" >/dev/null 2>&1 || true
        fi
    fi
}

# ================================
# DISPLAY FUNCTIONS
# ================================

display_header() {
    local current_time
    current_time=$(date '+%Y-%m-%d %H:%M:%S %Z')

    printf "${BOLD}${CYAN}"
    printf '╔══════════════════════════════════════════════════════════════════════════════╗\n'
    printf '║                    VaultWarden-OCI Unified Monitor v3.0                     ║\n'
    printf '║                         %s                           ║\n' "$current_time"
    printf '╚══════════════════════════════════════════════════════════════════════════════╝\n'
    printf "${NC}\n"
}

display_system_metrics() {
    eval "$1"  # Load metrics array

    printf "${BOLD}${WHITE}System Metrics (Unified Thresholds):${NC}\n"
    printf "├─ CPU Usage:    %s (cores: %d)\n" \
        "$(format_percentage "${metrics[cpu_usage]}" "$CPU_WARNING_THRESHOLD" "$CPU_ALERT_THRESHOLD")" \
        "${metrics[cpu_cores]:-1}"

    local mem_total_gb mem_used_gb
    if command -v bc >/dev/null 2>&1; then
        mem_total_gb=$(echo "scale=1; ${metrics[memory_total]:-0} / 1024 / 1024" | bc -l)
        mem_used_gb=$(echo "scale=1; ${metrics[memory_used]:-0} / 1024 / 1024" | bc -l)
    else
        mem_total_gb="N/A"
        mem_used_gb="N/A"
    fi

    printf "├─ Memory Usage: %s (%sGB / %sGB)\n" \
        "$(format_percentage "${metrics[memory_usage]}" "$MEMORY_WARNING_THRESHOLD" "$MEMORY_ALERT_THRESHOLD")" \
        "$mem_used_gb" "$mem_total_gb"

    printf "├─ Disk Usage:   %s (%s / %s)\n" \
        "$(format_percentage "${metrics[disk_usage]}" "$DISK_WARNING_THRESHOLD" "$DISK_ALERT_THRESHOLD")" \
        "$(format_bytes "${metrics[disk_used]}")" \
        "$(format_bytes "${metrics[disk_total]}")"

    printf "└─ Load Average: %s / %s / %s (1m/5m/15m) [1 OCPU]\n" \
        "$(format_load "${metrics[load_1min]}" "1")" \
        "$(format_load "${metrics[load_5min]}" "1")" \
        "$(format_load "${metrics[load_15min]}" "1")"
    printf "\n"
}

display_sqlite_metrics() {
    eval "$1"  # Load sqlite_metrics array

    printf "${BOLD}${WHITE}SQLite Database (Unified Monitoring):${NC}\n"

    if [[ "${sqlite_metrics[db_exists]}" == "false" ]]; then
        printf "├─ Status: ${YELLOW}Database not found${NC} (%s)\n" "$SQLITE_DB_PATH"
        printf "└─ This is normal if VaultWarden hasn't started yet\n"
    elif [[ "${sqlite_metrics[status]}" != "OK" ]]; then
        printf "├─ Status: ${YELLOW}%s${NC}\n" "${sqlite_metrics[status]}"
        printf "└─ Size: %s\n" "$(format_bytes "${sqlite_metrics[db_size]}")"
    else
        local db_size_mb wal_size_mb
        db_size_mb=$(echo "scale=2; ${sqlite_metrics[db_size]} / 1048576" | bc -l)
        wal_size_mb=$(echo "scale=2; ${sqlite_metrics[wal_size]} / 1048576" | bc -l)

        printf "├─ Status: ${GREEN}%s${NC}\n" "${sqlite_metrics[status]}"
        printf "├─ Database: %s (%.1f MB)\n" \
            "$(format_bytes "${sqlite_metrics[db_size]}")" "$db_size_mb"
        printf "├─ WAL File: %s (%.1f MB)\n" \
            "$(format_bytes "${sqlite_metrics[wal_size]}")" "$wal_size_mb"
        printf "├─ Pages: %s (%s bytes each)\n" \
            "${sqlite_metrics[page_count]}" "${sqlite_metrics[page_size]}"
        printf "├─ Free Pages: %s\n" "${sqlite_metrics[freelist_count]}"

        # Use unified fragmentation evaluation
        local frag_status
        frag_status=$(evaluate_fragmentation_threshold "${sqlite_metrics[fragmentation_ratio]}")
        local frag_color
        case "$frag_status" in
            "critical") frag_color="$RED" ;;
            "alert"|"warning") frag_color="$YELLOW" ;;
            *) frag_color="$GREEN" ;;
        esac

        printf "└─ Fragmentation: %s%s${NC} (%s)\n" "$frag_color" "${sqlite_metrics[fragmentation_ratio]}" "$frag_status"
    fi
    printf "\n"
}

display_container_status() {
    local show_containers="${SHOW_CONTAINER_STATS:-true}"
    if [[ "$show_containers" != "true" ]] || ! command -v docker >/dev/null 2>&1; then
        return 0
    fi

    printf "${BOLD}${WHITE}Container Status:${NC}\n"

    local containers=("vaultwarden" "bw_caddy" "bw_backup" "bw_fail2ban" "bw_watchtower" "bw_ddclient" "bw_monitoring")

    for container in "${containers[@]}"; do
        local status="${CONTAINER_STATS[$container]:-UNKNOWN}"
        local display_name

        case "$container" in
            "vaultwarden") display_name="VaultWarden Core" ;;
            "bw_caddy") display_name="Caddy (Proxy)" ;;
            "bw_backup") display_name="Backup Service" ;;
            "bw_fail2ban") display_name="Fail2ban (Security)" ;;
            "bw_watchtower") display_name="Watchtower (Updates)" ;;
            "bw_ddclient") display_name="DDClient (DNS)" ;;
            "bw_monitoring") display_name="Monitoring" ;;
            *) display_name="$container" ;;
        esac

        if [[ "$status" == "STOPPED" ]]; then
            printf "├─ %-20s ${RED}STOPPED${NC}\n" "$display_name:"
        elif [[ "$status" == "UNKNOWN" ]]; then
            printf "├─ %-20s ${YELLOW}UNKNOWN${NC}\n" "$display_name:"
        else
            # Parse docker stats output
            local cpu_pct mem_usage net_io block_io
            read -r _ cpu_pct mem_usage net_io block_io <<< "$status"
            cpu_pct="${cpu_pct%\%}"  # Remove % symbol

            printf "├─ %-20s ${GREEN}RUNNING${NC} (CPU: %5s%%, RAM: %s)\n" \
                "$display_name:" "$cpu_pct" "$mem_usage"
        fi
    done

    printf "└─ ${BLUE}Use 'docker compose ps' for detailed status${NC}\n"
    printf "\n"
}

# ================================
# CONFIGURATION DISPLAY
# ================================

show_configuration_source() {
    printf "${BOLD}${WHITE}Unified Configuration (v$MONITORING_CONFIG_VERSION):${NC}\n"
    printf "├─ ${GREEN}✅ Configuration sources: $MONITORING_CONFIG_SOURCES${NC}\n"

    # Show active thresholds
    printf "├─ ${BLUE}System thresholds:${NC} CPU:${CPU_ALERT_THRESHOLD}%% MEM:${MEMORY_ALERT_THRESHOLD}%% LOAD:${LOAD_ALERT_THRESHOLD}\n"
    printf "├─ ${BLUE}SQLite thresholds:${NC} Size:${SQLITE_SIZE_ALERT_MB}MB WAL:${WAL_SIZE_ALERT_MB}MB Frag:${FRAGMENTATION_ALERT_RATIO}\n"

    # Check for alert destinations
    local alert_methods=()
    [[ -n "$ALERT_EMAIL" ]] && alert_methods+=("Email")
    [[ -n "$WEBHOOK_URL" ]] && alert_methods+=("Webhook")

    if [[ ${#alert_methods[@]} -gt 0 ]]; then
        printf "├─ ${GREEN}🔔 Alerts enabled:${NC} %s\n" "$(IFS=', '; echo "${alert_methods[*]}")"
    else
        printf "├─ ${YELLOW}🔕 Alerts:${NC} Log-only (configure ALERT_EMAIL or WEBHOOK_URL)\n"
    fi

    printf "└─ ${CYAN}🎯 Unified monitoring:${NC} All scripts use same thresholds\n"
    printf "\n"
}

display_footer() {
    printf "${BOLD}${CYAN}"
    printf '╔══════════════════════════════════════════════════════════════════════════════╗\n'
    printf '║ Press Ctrl+C to exit │ Refresh: %ds │ Logs: %s ║\n' "$MONITOR_REFRESH_INTERVAL" "$METRICS_LOG"
    printf '╚══════════════════════════════════════════════════════════════════════════════╝\n'
    printf "${NC}"
}

# ================================
# MAIN MONITORING LOOP
# ================================

main_monitoring_loop() {
    hide_cursor

    # Initialize log directory using unified paths
    mkdir -p "$LOG_DIR"

    while true; do
        clear_screen

        # Collect metrics using unified functions
        local system_metrics_cmd
        system_metrics_cmd=$(get_system_metrics)
        local sqlite_metrics_cmd
        sqlite_metrics_cmd=$(get_sqlite_metrics)

        # Get container stats
        get_container_stats

        # Display dashboard
        display_header
        display_system_metrics "$system_metrics_cmd"
        display_sqlite_metrics "$sqlite_metrics_cmd"
        display_container_status
        show_configuration_source
        display_footer

        # Check thresholds using unified alert system
        check_thresholds_and_alert "$system_metrics_cmd"

        # Log metrics using unified paths
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        eval "$system_metrics_cmd"
        printf '%s,%.2f,%.2f,%.2f,%.2f\n' \
            "$timestamp" "${metrics[cpu_usage]}" "${metrics[mem_usage_pct]}" \
            "${metrics[disk_usage_pct]}" "${metrics[load_1m]}" >> "$METRICS_LOG"

        # Clean up old log entries using unified settings
        if [[ -f "$METRICS_LOG" ]]; then
            local line_count
            line_count=$(wc -l < "$METRICS_LOG")
            if [[ $line_count -gt $MAX_LOG_ENTRIES ]]; then
                tail -n "$MAX_LOG_ENTRIES" "$METRICS_LOG" > "$METRICS_LOG.tmp" && 
                mv "$METRICS_LOG.tmp" "$METRICS_LOG"
            fi
        fi

        sleep "$MONITOR_REFRESH_INTERVAL"
    done
}

# ================================
# COMMAND LINE INTERFACE
# ================================

show_help() {
    cat <<EOF
VaultWarden-OCI Unified Real-time Monitor v$MONITORING_CONFIG_VERSION

Usage: $0 [command] [options]

Commands:
    monitor, watch    Start real-time monitoring dashboard (default)
    check, status     Run single check and exit
    metrics           Show current metrics in JSON format
    config            Show unified configuration
    test-alerts       Test unified alert system
    help              Show this help message

Options:
    --refresh N       Set refresh interval in seconds (default: $MONITOR_REFRESH_INTERVAL)
    --compact         Compact display mode
    --no-containers   Disable container monitoring
    --debug           Enable debug output

Unified Configuration Features:
    ✅ Single source of truth for all thresholds
    ✅ Consistent variable names across all scripts
    ✅ External config file support with priority
    ✅ Automatic threshold validation
    ✅ Standardized metric collection and evaluation

Configuration Sources (priority order):
    1. config/performance-targets.conf
    2. config/alert-thresholds.conf
    3. settings.env environment variables
    4. Built-in defaults

Current Thresholds:
    CPU: Warning: ${CPU_WARNING_THRESHOLD}%, Alert: ${CPU_ALERT_THRESHOLD}%, Critical: ${CPU_CRITICAL_THRESHOLD}%
    Memory: Warning: ${MEMORY_WARNING_THRESHOLD}%, Alert: ${MEMORY_ALERT_THRESHOLD}%, Critical: ${MEMORY_CRITICAL_THRESHOLD}%
    Load: Warning: ${LOAD_WARNING_THRESHOLD}, Alert: ${LOAD_ALERT_THRESHOLD}, Critical: ${LOAD_CRITICAL_THRESHOLD} (1 OCPU)
    SQLite: Size: ${SQLITE_SIZE_ALERT_MB}MB, WAL: ${WAL_SIZE_ALERT_MB}MB, Fragmentation: ${FRAGMENTATION_ALERT_RATIO}

Examples:
    $0                       # Start unified monitoring dashboard
    $0 check                 # Single status check with unified thresholds
    $0 config               # Show unified configuration
    $0 monitor --refresh 10  # Monitor with 10s refresh
    $0 test-alerts           # Test unified alert system

EOF
}

# Parse command line arguments
COMMAND="${1:-monitor}"
shift || true

while [[ $# -gt 0 ]]; do
    case $1 in
        --refresh)
            MONITOR_REFRESH_INTERVAL="${2:-$MONITOR_REFRESH_INTERVAL}"
            shift 2
            ;;
        --compact)
            export COMPACT_MODE="true"
            shift
            ;;
        --no-containers)
            export SHOW_CONTAINER_STATS="false"
            shift
            ;;
        --debug)
            export DEBUG="true"
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Execute command
case "$COMMAND" in
    "monitor"|"watch"|"")
        log_info "Starting VaultWarden-OCI unified monitor v$MONITORING_CONFIG_VERSION"
        log_info "Refresh interval: ${MONITOR_REFRESH_INTERVAL}s"
        log_info "Using unified thresholds from: $MONITORING_CONFIG_SOURCES"
        main_monitoring_loop
        ;;

    "check"|"status")
        log_step "VaultWarden-OCI Status Check (Unified v$MONITORING_CONFIG_VERSION)"
        system_metrics_cmd=$(get_system_metrics)
        sqlite_metrics_cmd=$(get_sqlite_metrics)
        get_container_stats 2>/dev/null || true

        eval "$system_metrics_cmd"
        eval "$sqlite_metrics_cmd"

        printf "System: CPU=%.1f%% MEM=%.1f%% DISK=%.1f%% LOAD=%.2f\n" \
            "${metrics[cpu_usage]}" "${metrics[mem_usage_pct]}" \
            "${metrics[disk_usage_pct]}" "${metrics[load_1m]}"

        if [[ "${sqlite_metrics[db_exists]}" == "true" ]]; then
            local db_mb
            db_mb=$(echo "scale=1; ${sqlite_metrics[db_size]} / 1048576" | bc -l)
            printf "SQLite: Size=%.1fMB Pages=%s Fragmentation=%.2f\n" \
                "$db_mb" "${sqlite_metrics[page_count]}" "${sqlite_metrics[fragmentation_ratio]}"
        else
            printf "SQLite: Database not found\n"
        fi

        echo ""
        show_configuration_source
        check_thresholds_and_alert "$system_metrics_cmd"
        ;;

    "config")
        show_monitoring_configuration
        ;;

    "metrics")
        system_metrics_cmd=$(get_system_metrics)
        sqlite_metrics_cmd=$(get_sqlite_metrics)

        eval "$system_metrics_cmd"
        eval "$sqlite_metrics_cmd"

        printf '{\n'
        printf '  "timestamp": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '  "config_version": "%s",\n' "$MONITORING_CONFIG_VERSION"
        printf '  "system": {\n'
        printf '    "cpu_usage": %.2f,\n' "${metrics[cpu_usage]}"
        printf '    "cpu_status": "%s",\n' "$(evaluate_cpu_threshold "${metrics[cpu_usage]}")"
        printf '    "memory_usage": %.2f,\n' "${metrics[mem_usage_pct]}"
        printf '    "memory_status": "%s",\n' "$(evaluate_memory_threshold "${metrics[mem_usage_pct]}")"
        printf '    "disk_usage": %.2f,\n' "${metrics[disk_usage_pct]}"
        printf '    "load_1min": %.2f,\n' "${metrics[load_1m]}"
        printf '    "load_status": "%s"\n' "$(evaluate_load_threshold "${metrics[load_1m]}")"
        printf '  },\n'
        printf '  "sqlite": {\n'
        printf '    "exists": %s,\n' "${sqlite_metrics[db_exists]}"
        printf '    "size_bytes": %s,\n' "${sqlite_metrics[db_size]}"
        printf '    "wal_size_bytes": %s,\n' "${sqlite_metrics[wal_size]}"
        printf '    "fragmentation_ratio": %.2f\n' "${sqlite_metrics[fragmentation_ratio]}"
        printf '  },\n'
        printf '  "unified_thresholds": {\n'
        printf '    "cpu_alert": %d,\n' "$CPU_ALERT_THRESHOLD"
        printf '    "memory_alert": %d,\n' "$MEMORY_ALERT_THRESHOLD"
        printf '    "disk_alert": %d,\n' "$DISK_ALERT_THRESHOLD"
        printf '    "load_alert": %.1f\n' "$LOAD_ALERT_THRESHOLD"
        printf '  }\n'
        printf '}\n'
        ;;

    "test-alerts")
        log_info "Testing unified alert system..."
        send_unified_alert "Test alert from VaultWarden-OCI Unified Monitor v$MONITORING_CONFIG_VERSION"
        log_success "Test alert sent using unified configuration"
        ;;

    "help"|"--help"|"-h")
        show_help
        ;;

    *)
        log_error "Unknown command: $COMMAND"
        echo "Available commands: monitor, check, config, metrics, test-alerts, help"
        exit 1
        ;;
esac
