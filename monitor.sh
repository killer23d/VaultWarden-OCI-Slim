#!/usr/bin/env bash
# monitor.sh -- VaultWarden-OCI Real-time Monitoring Dashboard
# ALIGNED VERSION: Uses settings.env variable names consistently
# Enhanced with Configuration Source Indicator

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

# Source common library if available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
if [[ -f "$SCRIPT_DIR/lib/common.sh" ]]; then
    source "$SCRIPT_DIR/lib/common.sh"
else
    # Fallback logging functions
    log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
    log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
    log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
    log_step() { echo -e "${BOLD}${CYAN}=== $* ===${NC}"; }
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo -e "${PURPLE}[DEBUG]${NC} $*" || true; }
fi

# Configuration defaults (ALIGNED with settings.env and Docker Compose)
# These values match the thresholds used by the bw_monitoring service
CPU_ALERT_THRESHOLD="${CPU_ALERT_THRESHOLD:-80}"
MEMORY_ALERT_THRESHOLD="${MEMORY_ALERT_THRESHOLD:-85}"
DISK_ALERT_THRESHOLD="${DISK_ALERT_THRESHOLD:-85}"
LOAD_ALERT_THRESHOLD="${LOAD_ALERT_THRESHOLD:-2.0}"

# SQLite-specific thresholds (ALIGNED with Docker Compose monitoring service)
SQLITE_SIZE_ALERT_MB="${SQLITE_SIZE_ALERT_MB:-100}"
WAL_SIZE_ALERT_MB="${WAL_SIZE_ALERT_MB:-10}"
FRAGMENTATION_ALERT_RATIO="${FRAGMENTATION_ALERT_RATIO:-1.5}"
FREELIST_ALERT_THRESHOLD="${FREELIST_ALERT_THRESHOLD:-15}"

# Warning thresholds (slightly below alert thresholds)
CPU_WARNING_THRESHOLD="${CPU_WARNING_THRESHOLD:-$((CPU_ALERT_THRESHOLD - 10))}"
MEMORY_WARNING_THRESHOLD="${MEMORY_WARNING_THRESHOLD:-$((MEMORY_ALERT_THRESHOLD - 10))}"
DISK_WARNING_THRESHOLD="${DISK_WARNING_THRESHOLD:-$((DISK_ALERT_THRESHOLD - 10))}"

# Monitoring intervals and behavior
REFRESH_INTERVAL="${REFRESH_INTERVAL:-5}"
MAX_LOG_ENTRIES="${MAX_LOG_ENTRIES:-50}"
SHOW_CONTAINER_STATS="${SHOW_CONTAINER_STATS:-true}"
COMPACT_MODE="${COMPACT_MODE:-false}"

# Paths (ALIGNED with settings.env standards)
SQLITE_DB_PATH="${SQLITE_DB_PATH:-./data/bwdata/db.sqlite3}"
VAULTWARDEN_DATA_DIR="${VAULTWARDEN_DATA_DIR:-./data/bwdata}"
LOG_DIR="${LOG_DIR:-./logs}"
METRICS_LOG="$LOG_DIR/metrics.log"

# Alert configuration (ALIGNED with settings.env)
ALERT_EMAIL="${ALERT_EMAIL:-}"
WEBHOOK_URL="${WEBHOOK_URL:-}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"

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
    local threshold_warn="${2:-70}"
    local threshold_alert="${3:-85}"
    
    if (( $(echo "$value >= $threshold_alert" | bc -l) )); then
        printf "${RED}%5.1f%%${NC}" "$value"
    elif (( $(echo "$value >= $threshold_warn" | bc -l) )); then
        printf "${YELLOW}%5.1f%%${NC}" "$value"
    else
        printf "${GREEN}%5.1f%%${NC}" "$value"
    fi
}

format_load() {
    local load="${1:-0}"
    local cores="${2:-1}"
    local threshold=$(echo "scale=2; $cores * $LOAD_ALERT_THRESHOLD" | bc -l)
    
    if (( $(echo "$load > $threshold" | bc -l) )); then
        printf "${RED}%5.2f${NC}" "$load"
    elif (( $(echo "$load > $threshold * 0.8" | bc -l) )); then
        printf "${YELLOW}%5.2f${NC}" "$load"
    else
        printf "${GREEN}%5.2f${NC}" "$load"
    fi
}

# ================================
# SYSTEM METRICS COLLECTION
# ================================

get_system_metrics() {
    local -A metrics

    # CPU usage (from /proc/stat)
    if [[ -r /proc/stat ]]; then
        local cpu_line prev_cpu_line cpu_usage
        cpu_line=$(head -1 /proc/stat)
        sleep 0.1
        prev_cpu_line=$(head -1 /proc/stat)
        
        local prev_idle prev_total idle total
        prev_idle=$(echo "$cpu_line" | awk '{print $5}')
        prev_total=$(echo "$cpu_line" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')
        idle=$(echo "$prev_cpu_line" | awk '{print $5}')
        total=$(echo "$prev_cpu_line" | awk '{sum=0; for(i=2;i<=NF;i++) sum+=$i; print sum}')
        
        if [[ $total -gt $prev_total ]]; then
            cpu_usage=$(echo "scale=2; (1 - ($idle - $prev_idle) / ($total - $prev_total)) * 100" | bc -l)
        else
            cpu_usage="0.00"
        fi
        metrics[cpu_usage]="$cpu_usage"
    else
        metrics[cpu_usage]="0.00"
    fi

    # Memory usage (from /proc/meminfo)
    if [[ -r /proc/meminfo ]]; then
        local mem_total mem_available mem_used mem_usage
        mem_total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
        mem_available=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
        mem_used=$((mem_total - mem_available))
        mem_usage=$(echo "scale=2; $mem_used * 100 / $mem_total" | bc -l)
        
        metrics[memory_total]="$mem_total"
        metrics[memory_used]="$mem_used"
        metrics[memory_usage]="$mem_usage"
    else
        metrics[memory_usage]="0.00"
        metrics[memory_total]="0"
        metrics[memory_used]="0"
    fi

    # Disk usage (root filesystem)
    local disk_info
    disk_info=$(df / | tail -1)
    local disk_usage
    disk_usage=$(echo "$disk_info" | awk '{gsub(/%/, "", $5); print $5}')
    metrics[disk_usage]="$disk_usage"
    
    local disk_total disk_used
    disk_total=$(echo "$disk_info" | awk '{print $2 * 1024}')  # Convert to bytes
    disk_used=$(echo "$disk_info" | awk '{print $3 * 1024}')   # Convert to bytes
    metrics[disk_total]="$disk_total"
    metrics[disk_used]="$disk_used"

    # Load average
    if [[ -r /proc/loadavg ]]; then
        local load_1min load_5min load_15min
        read -r load_1min load_5min load_15min _ _ < /proc/loadavg
        metrics[load_1min]="$load_1min"
        metrics[load_5min]="$load_5min"
        metrics[load_15min]="$load_15min"
    else
        metrics[load_1min]="0.00"
        metrics[load_5min]="0.00"
        metrics[load_15min]="0.00"
    fi

    # CPU cores
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || echo "1")
    metrics[cpu_cores]="$cpu_cores"

    printf '%s\n' "${metrics[@]/%/}" | while IFS='=' read -r key value; do
        printf 'metrics[%s]="%s"\n' "$key" "$value"
    done
}

# ================================
# SQLITE MONITORING
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
# ALERT SYSTEM (ALIGNED)
# ================================

check_thresholds_and_alert() {
    eval "$1"  # Load metrics array
    local alerts=()

    # CPU threshold check (ALIGNED variable name)
    if (( $(echo "${metrics[cpu_usage]} > $CPU_ALERT_THRESHOLD" | bc -l) )); then
        alerts+=("CPU usage ${metrics[cpu_usage]}% exceeds threshold $CPU_ALERT_THRESHOLD%")
    fi

    # Memory threshold check (ALIGNED variable name)
    if (( $(echo "${metrics[memory_usage]} > $MEMORY_ALERT_THRESHOLD" | bc -l) )); then
        alerts+=("Memory usage ${metrics[memory_usage]}% exceeds threshold $MEMORY_ALERT_THRESHOLD%")
    fi

    # Disk threshold check (ALIGNED variable name)
    if (( $(echo "${metrics[disk_usage]} > $DISK_ALERT_THRESHOLD" | bc -l) )); then
        alerts+=("Disk usage ${metrics[disk_usage]}% exceeds threshold $DISK_ALERT_THRESHOLD%")
    fi

    # Load threshold check (ALIGNED variable name)
    local load_threshold
    load_threshold=$(echo "scale=2; ${metrics[cpu_cores]} * $LOAD_ALERT_THRESHOLD" | bc -l)
    if (( $(echo "${metrics[load_1min]} > $load_threshold" | bc -l) )); then
        alerts+=("Load average ${metrics[load_1min]} exceeds threshold $load_threshold")
    fi

    # SQLite threshold checks (if database monitoring enabled)
    if [[ "${sqlite_metrics[db_exists]}" == "true" ]]; then
        local db_size_mb wal_size_mb
        db_size_mb=$(echo "scale=2; ${sqlite_metrics[db_size]} / 1048576" | bc -l)
        wal_size_mb=$(echo "scale=2; ${sqlite_metrics[wal_size]} / 1048576" | bc -l)

        if (( $(echo "$db_size_mb > $SQLITE_SIZE_ALERT_MB" | bc -l) )); then
            alerts+=("SQLite database size ${db_size_mb}MB exceeds threshold $SQLITE_SIZE_ALERT_MB MB")
        fi

        if (( $(echo "$wal_size_mb > $WAL_SIZE_ALERT_MB" | bc -l) )); then
            alerts+=("SQLite WAL size ${wal_size_mb}MB exceeds threshold $WAL_SIZE_ALERT_MB MB")
        fi

        if (( $(echo "${sqlite_metrics[fragmentation_ratio]} > $FRAGMENTATION_ALERT_RATIO" | bc -l) )); then
            alerts+=("SQLite fragmentation ratio ${sqlite_metrics[fragmentation_ratio]} exceeds threshold $FRAGMENTATION_ALERT_RATIO")
        fi
    fi

    # Send alerts if any thresholds exceeded
    if [[ ${#alerts[@]} -gt 0 && "$ALERT_SENT" == "false" ]]; then
        send_alert "${alerts[@]}"
        ALERT_SENT=true
    elif [[ ${#alerts[@]} -eq 0 ]]; then
        ALERT_SENT=false
    fi
}

send_alert() {
    local alert_message="VaultWarden-OCI Alert: $*"
    
    # Log alert
    echo "$(date): $alert_message" >> "$METRICS_LOG"
    
    # Send email if configured
    if [[ -n "$ALERT_EMAIL" && -n "${SMTP_HOST:-}" ]]; then
        if command -v mail >/dev/null 2>&1; then
            echo "$alert_message" | mail -s "VaultWarden Alert" "$ALERT_EMAIL" || true
        fi
    fi
    
    # Send webhook if configured
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
    printf '║                    VaultWarden-OCI Real-time Monitor                         ║\n'
    printf '║                         %s                           ║\n' "$current_time"
    printf '╚══════════════════════════════════════════════════════════════════════════════╝\n'
    printf "${NC}\n"
}

display_system_metrics() {
    eval "$1"  # Load metrics array
    
    printf "${BOLD}${WHITE}System Metrics:${NC}\n"
    printf "├─ CPU Usage:    %s (cores: %d)\n" \
        "$(format_percentage "${metrics[cpu_usage]}" "$CPU_WARNING_THRESHOLD" "$CPU_ALERT_THRESHOLD")" \
        "${metrics[cpu_cores]}"
    
    printf "├─ Memory Usage: %s (%s / %s)\n" \
        "$(format_percentage "${metrics[memory_usage]}" "$MEMORY_WARNING_THRESHOLD" "$MEMORY_ALERT_THRESHOLD")" \
        "$(format_bytes $((metrics[memory_used] * 1024)))" \
        "$(format_bytes $((metrics[memory_total] * 1024)))"
    
    printf "├─ Disk Usage:   %s (%s / %s)\n" \
        "$(format_percentage "${metrics[disk_usage]}" "$DISK_WARNING_THRESHOLD" "$DISK_ALERT_THRESHOLD")" \
        "$(format_bytes "${metrics[disk_used]}")" \
        "$(format_bytes "${metrics[disk_total]}")"
    
    printf "└─ Load Average: %s / %s / %s (1m/5m/15m)\n" \
        "$(format_load "${metrics[load_1min]}" "${metrics[cpu_cores]}")" \
        "$(format_load "${metrics[load_5min]}" "${metrics[cpu_cores]}")" \
        "$(format_load "${metrics[load_15min]}" "${metrics[cpu_cores]}")"
    printf "\n"
}

display_sqlite_metrics() {
    eval "$1"  # Load sqlite_metrics array
    
    printf "${BOLD}${WHITE}SQLite Database:${NC}\n"
    
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
        
        local frag_color=""
        if (( $(echo "${sqlite_metrics[fragmentation_ratio]} > $FRAGMENTATION_ALERT_RATIO" | bc -l) )); then
            frag_color="$RED"
        elif (( $(echo "${sqlite_metrics[fragmentation_ratio]} > $(echo "scale=2; $FRAGMENTATION_ALERT_RATIO * 0.8" | bc -l)" | bc -l) )); then
            frag_color="$YELLOW"
        else
            frag_color="$GREEN"
        fi
        printf "└─ Fragmentation: %s%s${NC}\n" "$frag_color" "${sqlite_metrics[fragmentation_ratio]}"
    fi
    printf "\n"
}

display_container_status() {
    if [[ "$SHOW_CONTAINER_STATS" != "true" ]] || ! command -v docker >/dev/null 2>&1; then
        return 0
    fi
    
    printf "${BOLD}${WHITE}Container Status:${NC}\n"
    
    local containers=("vaultwarden" "bw_caddy" "bw_backup" "bw_fail2ban" "bw_watchtower" "bw_ddclient" "bw_monitoring")
    
    for container in "${containers[@]}"; do
        local status="${CONTAINER_STATS[$container]:-UNKNOWN}"
        local display_name
        
        case "$container" in
            "vaultwarden") display_name="VaultWarden" ;;
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
            # Parse docker stats output: container cpu% mem_usage net_io block_io
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
# CONFIGURATION SOURCE INDICATOR
# ================================

show_configuration_source() {
    printf "${BOLD}${WHITE}Configuration Source:${NC}\n"
    
    local config_sources=()
    local using_env=false
    
    # Check if key thresholds are set via environment
    if [[ -n "${CPU_ALERT_THRESHOLD:-}" && "${CPU_ALERT_THRESHOLD}" != "80" ]]; then
        using_env=true
    fi
    if [[ -n "${MEMORY_ALERT_THRESHOLD:-}" && "${MEMORY_ALERT_THRESHOLD}" != "85" ]]; then
        using_env=true
    fi
    if [[ -n "${DISK_ALERT_THRESHOLD:-}" && "${DISK_ALERT_THRESHOLD}" != "85" ]]; then
        using_env=true
    fi
    
    if [[ "$using_env" == "true" ]]; then
        printf "├─ ${GREEN}✅ Using thresholds from settings.env/Docker Compose${NC}\n"
        
        # Show which variables are customized
        local customized=()
        [[ "${CPU_ALERT_THRESHOLD}" != "80" ]] && customized+=("CPU=${CPU_ALERT_THRESHOLD}%")
        [[ "${MEMORY_ALERT_THRESHOLD}" != "85" ]] && customized+=("MEM=${MEMORY_ALERT_THRESHOLD}%")
        [[ "${DISK_ALERT_THRESHOLD}" != "85" ]] && customized+=("DISK=${DISK_ALERT_THRESHOLD}%")
        [[ "${LOAD_ALERT_THRESHOLD}" != "2.0" ]] && customized+=("LOAD=${LOAD_ALERT_THRESHOLD}")
        [[ "${SQLITE_SIZE_ALERT_MB}" != "100" ]] && customized+=("DB=${SQLITE_SIZE_ALERT_MB}MB")
        
        if [[ ${#customized[@]} -gt 0 ]]; then
            printf "├─ ${BLUE}Customized:${NC} %s\n" "$(IFS=', '; echo "${customized[*]}")"
        fi
    else
        printf "├─ ${YELLOW}ℹ️  Using default thresholds${NC}\n"
        printf "├─ ${BLUE}💡 Tip:${NC} Configure in settings.env for custom thresholds\n"
    fi
    
    # Check for alert destinations
    local alert_methods=()
    [[ -n "${ALERT_EMAIL:-}" ]] && alert_methods+=("Email")
    [[ -n "${WEBHOOK_URL:-}" ]] && alert_methods+=("Webhook")
    
    if [[ ${#alert_methods[@]} -gt 0 ]]; then
        printf "├─ ${GREEN}🔔 Alerts enabled:${NC} %s\n" "$(IFS=', '; echo "${alert_methods[*]}")"
    else
        printf "├─ ${YELLOW}🔕 Alerts:${NC} Log-only (configure ALERT_EMAIL or WEBHOOK_URL)\n"
    fi
    
    # Show SQLite monitoring status
    if [[ -f "$SQLITE_DB_PATH" ]]; then
        printf "├─ ${GREEN}💾 SQLite monitoring:${NC} Active\n"
    else
        printf "├─ ${YELLOW}💾 SQLite monitoring:${NC} Waiting for database creation\n"
    fi
    
    # Show alignment confirmation
    printf "└─ ${CYAN}🎯 Variable alignment:${NC} settings.env ↔ docker-compose.yml ↔ monitor.sh\n"
    printf "\n"
}

display_thresholds() {
    printf "${BOLD}${WHITE}Alert Thresholds (ALIGNED):${NC}\n"
    printf "├─ CPU Alert:        %d%% (Warning: %d%%)\n" "$CPU_ALERT_THRESHOLD" "$CPU_WARNING_THRESHOLD"
    printf "├─ Memory Alert:     %d%% (Warning: %d%%)\n" "$MEMORY_ALERT_THRESHOLD" "$MEMORY_WARNING_THRESHOLD"
    printf "├─ Disk Alert:       %d%% (Warning: %d%%)\n" "$DISK_ALERT_THRESHOLD" "$DISK_WARNING_THRESHOLD"
    printf "├─ Load Alert:       %.1f per core\n" "$LOAD_ALERT_THRESHOLD"
    printf "├─ DB Size Alert:    %d MB\n" "$SQLITE_SIZE_ALERT_MB"
    printf "├─ WAL Size Alert:   %d MB\n" "$WAL_SIZE_ALERT_MB"
    printf "└─ Fragmentation:    %.2f ratio\n" "$FRAGMENTATION_ALERT_RATIO"
    printf "\n"
}

display_footer() {
    printf "${BOLD}${CYAN}"
    printf '╔══════════════════════════════════════════════════════════════════════════════╗\n'
    printf '║ Press Ctrl+C to exit │ Refresh: %ds │ Logs: %s ║\n' "$REFRESH_INTERVAL" "$METRICS_LOG"
    printf '╚══════════════════════════════════════════════════════════════════════════════╝\n'
    printf "${NC}"
}

# ================================
# MAIN MONITORING LOOP
# ================================

main_monitoring_loop() {
    hide_cursor
    
    # Initialize log directory
    mkdir -p "$LOG_DIR"
    
    while true; do
        clear_screen
        
        # Collect metrics
        local system_metrics_cmd
        system_metrics_cmd=$(get_system_metrics)
        local sqlite_metrics_cmd
        sqlite_metrics_cmd=$(get_sqlite_metrics)
        
        # Get container stats if enabled
        if [[ "$SHOW_CONTAINER_STATS" == "true" ]]; then
            get_container_stats
        fi
        
        # Display dashboard
        display_header
        display_system_metrics "$system_metrics_cmd"
        display_sqlite_metrics "$sqlite_metrics_cmd"
        
        if [[ "$SHOW_CONTAINER_STATS" == "true" ]]; then
            display_container_status
        fi
        
        # Show configuration source
        show_configuration_source
        
        if [[ "$COMPACT_MODE" != "true" ]]; then
            display_thresholds
        fi
        
        display_footer
        
        # Check thresholds and send alerts
        check_thresholds_and_alert "$system_metrics_cmd"
        
        # Log metrics
        local timestamp
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        eval "$system_metrics_cmd"
        printf '%s,%.2f,%.2f,%.2f,%.2f\n' \
            "$timestamp" "${metrics[cpu_usage]}" "${metrics[memory_usage]}" \
            "${metrics[disk_usage]}" "${metrics[load_1min]}" >> "$METRICS_LOG"
        
        # Clean up old log entries
        if [[ -f "$METRICS_LOG" ]]; then
            local line_count
            line_count=$(wc -l < "$METRICS_LOG")
            if [[ $line_count -gt $MAX_LOG_ENTRIES ]]; then
                tail -n "$MAX_LOG_ENTRIES" "$METRICS_LOG" > "$METRICS_LOG.tmp" && 
                mv "$METRICS_LOG.tmp" "$METRICS_LOG"
            fi
        fi
        
        sleep "$REFRESH_INTERVAL"
    done
}

# ================================
# COMMAND LINE INTERFACE
# ================================

show_help() {
    cat <<EOF
VaultWarden-OCI Real-time Monitor (ALIGNED VERSION with Configuration Indicator)

Usage: $0 [command] [options]

Commands:
    monitor, watch    Start real-time monitoring dashboard (default)
    check, status     Run single check and exit
    metrics           Show current metrics in JSON format
    test-alerts       Test alert system
    help              Show this help message

Options:
    --refresh N       Set refresh interval in seconds (default: 5)
    --compact         Compact display mode
    --no-containers   Disable container monitoring
    --debug           Enable debug output

Environment Variables (ALIGNED with settings.env):
    CPU_ALERT_THRESHOLD      CPU usage alert threshold (default: 80%)
    MEMORY_ALERT_THRESHOLD   Memory usage alert threshold (default: 85%)
    DISK_ALERT_THRESHOLD     Disk usage alert threshold (default: 85%)
    LOAD_ALERT_THRESHOLD     Load average alert threshold per core (default: 2.0)
    
    SQLITE_SIZE_ALERT_MB     SQLite database size alert (default: 100MB)
    WAL_SIZE_ALERT_MB        WAL file size alert (default: 10MB)
    FRAGMENTATION_ALERT_RATIO  Fragmentation ratio alert (default: 1.5)
    
    ALERT_EMAIL              Email address for alerts
    WEBHOOK_URL              Webhook URL for alerts
    LOG_RETENTION_DAYS       Log retention period (default: 30)

Examples:
    $0                       # Start monitoring dashboard
    $0 check                 # Single status check
    $0 monitor --refresh 10  # Monitor with 10s refresh
    $0 metrics               # Show JSON metrics
    $0 test-alerts           # Test alert system

Configuration:
    This version uses environment variables aligned with settings.env.
    The Configuration Source indicator shows which variables are active.
    All threshold variables are consistent across the entire stack.

EOF
}

# Parse command line arguments
COMMAND="${1:-monitor}"
shift || true

while [[ $# -gt 0 ]]; do
    case $1 in
        --refresh)
            REFRESH_INTERVAL="${2:-5}"
            shift 2
            ;;
        --compact)
            COMPACT_MODE="true"
            shift
            ;;
        --no-containers)
            SHOW_CONTAINER_STATS="false"
            shift
            ;;
        --debug)
            DEBUG="true"
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
        log_info "Starting VaultWarden-OCI real-time monitor (ALIGNED VERSION with Config Indicator)"
        log_info "Refresh interval: ${REFRESH_INTERVAL}s"
        log_info "Alert thresholds: CPU=${CPU_ALERT_THRESHOLD}% MEM=${MEMORY_ALERT_THRESHOLD}% DISK=${DISK_ALERT_THRESHOLD}%"
        main_monitoring_loop
        ;;
    
    "check"|"status")
        log_step "VaultWarden-OCI Status Check (ALIGNED VERSION with Config Indicator)"
        system_metrics_cmd=$(get_system_metrics)
        sqlite_metrics_cmd=$(get_sqlite_metrics)
        get_container_stats 2>/dev/null || true
        
        eval "$system_metrics_cmd"
        eval "$sqlite_metrics_cmd"
        
        printf "System: CPU=%.1f%% MEM=%.1f%% DISK=%.1f%% LOAD=%.2f\n" \
            "${metrics[cpu_usage]}" "${metrics[memory_usage]}" \
            "${metrics[disk_usage]}" "${metrics[load_1min]}"
        
        if [[ "${sqlite_metrics[db_exists]}" == "true" ]]; then
            local db_mb
            db_mb=$(echo "scale=1; ${sqlite_metrics[db_size]} / 1048576" | bc -l)
            printf "SQLite: Size=%.1fMB Pages=%s Fragmentation=%.2f\n" \
                "$db_mb" "${sqlite_metrics[page_count]}" "${sqlite_metrics[fragmentation_ratio]}"
        else
            printf "SQLite: Database not found\n"
        fi
        
        # Show configuration source check
        echo ""
        show_configuration_source
        
        check_thresholds_and_alert "$system_metrics_cmd"
        ;;
    
    "metrics")
        system_metrics_cmd=$(get_system_metrics)
        sqlite_metrics_cmd=$(get_sqlite_metrics)
        
        eval "$system_metrics_cmd"
        eval "$sqlite_metrics_cmd"
        
        printf '{\n'
        printf '  "timestamp": "%s",\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
        printf '  "system": {\n'
        printf '    "cpu_usage": %.2f,\n' "${metrics[cpu_usage]}"
        printf '    "memory_usage": %.2f,\n' "${metrics[memory_usage]}"
        printf '    "disk_usage": %.2f,\n' "${metrics[disk_usage]}"
        printf '    "load_1min": %.2f\n' "${metrics[load_1min]}"
        printf '  },\n'
        printf '  "sqlite": {\n'
        printf '    "exists": %s,\n' "${sqlite_metrics[db_exists]}"
        printf '    "size_bytes": %s,\n' "${sqlite_metrics[db_size]}"
        printf '    "wal_size_bytes": %s,\n' "${sqlite_metrics[wal_size]}"
        printf '    "fragmentation_ratio": %.2f\n' "${sqlite_metrics[fragmentation_ratio]}"
        printf '  },\n'
        printf '  "thresholds": {\n'
        printf '    "cpu_alert": %d,\n' "$CPU_ALERT_THRESHOLD"
        printf '    "memory_alert": %d,\n' "$MEMORY_ALERT_THRESHOLD"
        printf '    "disk_alert": %d,\n' "$DISK_ALERT_THRESHOLD"
        printf '    "load_alert": %.1f\n' "$LOAD_ALERT_THRESHOLD"
        printf '  },\n'
        printf '  "config_source": {\n'
        printf '    "using_custom_thresholds": %s,\n' "$([[ "$CPU_ALERT_THRESHOLD" != "80" || "$MEMORY_ALERT_THRESHOLD" != "85" ]] && echo "true" || echo "false")"
        printf '    "alerts_configured": %s\n' "$([[ -n "$ALERT_EMAIL" || -n "$WEBHOOK_URL" ]] && echo "true" || echo "false")"
        printf '  }\n'
        printf '}\n'
        ;;
    
    "test-alerts")
        log_info "Testing alert system..."
        send_alert "Test alert from VaultWarden-OCI Monitor (ALIGNED VERSION with Config Indicator)"
        log_success "Test alert sent (check email/webhook if configured)"
        ;;
    
    "help"|"--help"|"-h")
        show_help
        ;;
    
    *)
        log_error "Unknown command: $COMMAND"
        echo "Available commands: monitor, check, metrics, test-alerts, help"
        exit 1
        ;;
esac
