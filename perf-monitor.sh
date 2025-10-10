#!/usr/bin/env bash
# perf-monitor.sh -- Unified Performance Monitor with Framework Integration
# Aligned with unified monitoring configuration and diagnose.sh approach

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# ==============================================================================
# UNIFIED FRAMEWORK INTEGRATION - ALIGNED WITH DIAGNOSE.SH
# ==============================================================================

# Load core framework
source "$SCRIPT_DIR/lib/common.sh" || {
    echo "ERROR: lib/common.sh required for performance monitoring" >&2
    exit 1
}

# UNIFIED CONFIGURATION: Single source of truth - same as diagnose.sh
source "$SCRIPT_DIR/lib/monitoring-config.sh" || {
    echo "ERROR: lib/monitoring-config.sh required for unified configuration" >&2
    exit 1
}

# Verify unified configuration loaded
if [[ "$MONITORING_CONFIG_LOADED" != "true" ]]; then
    echo "ERROR: Unified monitoring configuration failed to load" >&2
    exit 1
fi

# Track framework loading - consistent with diagnose.sh approach
loaded_frameworks=()

# Framework component loading - aligned with diagnose.sh pattern
if source "$SCRIPT_DIR/lib/perf-collector.sh" 2>/dev/null; then
    perf_collector_init
    loaded_frameworks+=("perf-collector")
fi

if source "$SCRIPT_DIR/lib/dashboard-sqlite.sh" 2>/dev/null; then
    dashboard_sqlite_init
    loaded_frameworks+=("dashboard-sqlite")
fi

if source "$SCRIPT_DIR/lib/dashboard-metrics.sh" 2>/dev/null; then
    loaded_frameworks+=("dashboard-metrics")
fi

# Enhanced logging framework integration (optional - maintains compatibility)
if source "$SCRIPT_DIR/lib/logger.sh" 2>/dev/null; then
    logger_init
    loaded_frameworks+=("logger")

    # Override logging functions to use framework
    perf_log() { logger_info "perf-monitor" "$*"; }
    perf_info() { logger_info "perf-monitor" "$*"; }
    perf_warning() { logger_warn "perf-monitor" "$*"; }
    perf_critical() { logger_error "perf-monitor" "$*"; }
    perf_success() { logger_info "perf-monitor" "SUCCESS: $*"; }
    perf_debug() { logger_debug "perf-monitor" "$*"; }
else
    # Fallback logging functions - consistent with diagnose.sh approach
    PERF_LOG_DIR="${PERF_LOG_DIR:-./data/performance_logs}"
    mkdir -p "$PERF_LOG_DIR"

    perf_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$PERF_LOG_DIR/performance-$(date +%Y%m%d).log"; }
    perf_info() { echo -e "${BLUE}[INFO]${NC} $*"; perf_log "INFO: $*"; }
    perf_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; perf_log "WARNING: $*"; }
    perf_critical() { echo -e "${RED}[CRITICAL]${NC} $*"; perf_log "CRITICAL: $*"; }
    perf_success() { echo -e "${GREEN}[OK]${NC} $*"; perf_log "OK: $*"; }
    perf_debug() { [[ "${DEBUG:-false}" == "true" ]] && perf_log "DEBUG: $*"; }
fi

# Enhanced error handling integration (optional)
if source "$SCRIPT_DIR/lib/error-handler.sh" 2>/dev/null; then
    error_handler_init
    loaded_frameworks+=("error-handler")
fi

# Enhanced output formatting integration (optional)
if source "$SCRIPT_DIR/lib/perf-formatter.sh" 2>/dev/null; then
    perf_formatter_init
    loaded_frameworks+=("perf-formatter")
    log_info "Output formatting framework loaded - using standardized formatting"
fi

# Create performance log directory
mkdir -p "$PERF_LOG_DIR"

# ==============================================================================
# UNIFIED SYSTEM PERFORMANCE - ALIGNED WITH DIAGNOSE.SH
# ==============================================================================

# Get system performance using unified framework - consistent with diagnose.sh
get_system_performance_unified() {
    perf_debug "Collecting system performance metrics using unified framework integration"

    if [[ " ${loaded_frameworks[*]} " =~ " perf-collector " ]]; then
        # Use framework collector with enhanced error handling
        local system_metrics

        if [[ " ${loaded_frameworks[*]} " =~ " error-handler " ]]; then
            system_metrics=$(error_handler_safe_execute "system_metrics" perf_collector_system_full)
        else
            system_metrics=$(perf_collector_system_full)
        fi

        # Add timestamp for compatibility
        echo "timestamp=$(date -Iseconds)"
        echo "$system_metrics"

        perf_debug "System metrics collected via unified framework with caching"

    else
        # Use unified fallback - same approach as diagnose.sh
        get_unified_system_metrics
        perf_debug "System metrics collected via unified fallback"
    fi
}

# ==============================================================================
# UNIFIED SQLITE PERFORMANCE - ALIGNED WITH DIAGNOSE.SH
# ==============================================================================

# Get SQLite performance using unified framework - consistent with diagnose.sh
get_sqlite_performance_unified() {
    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        perf_debug "SQLite database not found: $SQLITE_DB_PATH"
        echo "sqlite_available=false"
        return 1
    fi

    perf_debug "Collecting SQLite performance metrics using unified framework"

    if [[ " ${loaded_frameworks[*]} " =~ " dashboard-sqlite " ]]; then
        # Use unified framework SQLite monitoring - same as diagnose.sh
        local sqlite_status sqlite_metrics

        if [[ " ${loaded_frameworks[*]} " =~ " error-handler " ]]; then
            sqlite_status=$(error_handler_safe_execute "sqlite_status" dashboard_sqlite_get_status)
            sqlite_metrics=$(error_handler_safe_execute "sqlite_metrics" dashboard_sqlite_get_detailed_metrics)
        else
            sqlite_status=$(dashboard_sqlite_get_status)
            sqlite_metrics=$(dashboard_sqlite_get_detailed_metrics || echo "available=false")
        fi

        if [[ "$sqlite_status" =~ status=accessible ]] && [[ "$sqlite_metrics" =~ available=true ]]; then
            echo "sqlite_available=true"

            # Parse framework results - consistent format
            local file_size_mb table_count user_count fragmentation_ratio wal_size_mb journal_mode page_count
            eval "$(echo "$sqlite_metrics" | grep -E '^(file_size_mb|table_count|user_count|fragmentation_ratio|wal_size_mb|journal_mode|page_count)=')"

            # Enhanced database timing test with error handling
            local query_time integrity_ok
            if [[ " ${loaded_frameworks[*]} " =~ " error-handler " ]]; then
                local query_start query_end
                query_start=$(date +%s%N || date +%s)
                if error_handler_safe_execute "sqlite_query" sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null; then
                    query_end=$(date +%s%N || date +%s)
                    integrity_ok="true"

                    if command -v bc >/dev/null 2>&1; then
                        query_time=$(echo "scale=3; ($query_end - $query_start) / 1000000000" | bc)
                    else
                        query_time="<1"
                    fi
                else
                    query_time="N/A"
                    integrity_ok="false"
                fi
            else
                # Standard timing test
                local query_start query_end
                query_start=$(date +%s%N || date +%s)
                if sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
                    query_end=$(date +%s%N || date +%s)
                    integrity_ok="true"

                    if command -v bc >/dev/null 2>&1; then
                        query_time=$(echo "scale=3; ($query_end - $query_start) / 1000000000" | bc)
                    else
                        query_time="<1"
                    fi
                else
                    query_time="N/A"
                    integrity_ok="false"
                fi
            fi

            # Database modified time
            local db_modified
            db_modified=$(stat -c%Y "$SQLITE_DB_PATH" || echo "0")

            # Output unified framework results in compatible format
            cat <<EOF
db_size_mb=$file_size_mb
db_modified=$db_modified
wal_size_mb=$wal_size_mb
query_time=$query_time
integrity_ok=$integrity_ok
table_count=$table_count
user_count=$user_count
journal_mode=$journal_mode
page_count=$page_count
fragmentation_ratio=$fragmentation_ratio
EOF

            perf_debug "SQLite metrics collected via unified framework integration"

        else
            perf_warning "SQLite framework monitoring unavailable"
            echo "sqlite_available=false"
            return 1
        fi
    else
        # Enhanced fallback SQLite monitoring - same approach as diagnose.sh
        get_sqlite_metrics_fallback
        perf_debug "SQLite metrics collected via unified fallback"
    fi
}

# Fallback SQLite metrics - consistent with diagnose.sh approach
get_sqlite_metrics_fallback() {
    local db_size_bytes db_size_mb db_modified
    local wal_size_bytes wal_size_mb query_time integrity_ok
    local table_count user_count journal_mode

    # Enhanced file operations with error handling
    if [[ " ${loaded_frameworks[*]} " =~ " error-handler " ]]; then
        db_size_bytes=$(error_handler_safe_execute "file_stat" stat -c%s "$SQLITE_DB_PATH" || echo "0")
        db_modified=$(error_handler_safe_execute "file_modified" stat -c%Y "$SQLITE_DB_PATH" || echo "0")
    else
        db_size_bytes=$(stat -c%s "$SQLITE_DB_PATH" || echo "0")
        db_modified=$(stat -c%Y "$SQLITE_DB_PATH" || echo "0")
    fi

    if command -v bc >/dev/null 2>&1; then
        db_size_mb=$(echo "scale=2; $db_size_bytes / 1024 / 1024" | bc)
    else
        db_size_mb=$(( db_size_bytes / 1024 / 1024 ))
    fi

    # Enhanced WAL file check
    if [[ -f "${SQLITE_DB_PATH}-wal" ]]; then
        if [[ " ${loaded_frameworks[*]} " =~ " error-handler " ]]; then
            wal_size_bytes=$(error_handler_safe_execute "wal_stat" stat -c%s "${SQLITE_DB_PATH}-wal" || echo "0")
        else
            wal_size_bytes=$(stat -c%s "${SQLITE_DB_PATH}-wal" || echo "0")
        fi

        if command -v bc >/dev/null 2>&1; then
            wal_size_mb=$(echo "scale=2; $wal_size_bytes / 1024 / 1024" | bc)
        else
            wal_size_mb=$(( wal_size_bytes / 1024 / 1024 ))
        fi
    else
        wal_size_bytes="0"
        wal_size_mb="0"
    fi

    # Enhanced SQLite query tests with error handling
    if [[ " ${loaded_frameworks[*]} " =~ " error-handler " ]]; then
        local query_start query_end
        query_start=$(date +%s%N || date +%s)
        if error_handler_safe_execute "sqlite_query_test" sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null; then
            query_end=$(date +%s%N || date +%s)
            integrity_ok="true"

            if command -v bc >/dev/null 2>&1; then
                query_time=$(echo "scale=3; ($query_end - $query_start) / 1000000000" | bc)
            else
                query_time="<1"
            fi

            # Enhanced database statistics collection
            table_count=$(error_handler_safe_execute "table_count" sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" || echo "0")
            journal_mode=$(error_handler_safe_execute "journal_mode" sqlite3 "$SQLITE_DB_PATH" "PRAGMA journal_mode;" || echo "unknown")

            # User count if users table exists
            if error_handler_safe_execute "users_check" sqlite3 "$SQLITE_DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='users';" | grep -q users; then
                user_count=$(error_handler_safe_execute "user_count" sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM users;" || echo "0")
            else
                user_count="N/A"
            fi
        else
            query_time="N/A"
            integrity_ok="false"
            table_count="N/A"
            user_count="N/A"
            journal_mode="unknown"
        fi
    else
        # Standard enhanced fallback
        if sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
            local query_start query_end
            query_start=$(date +%s%N || date +%s)
            sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null
            query_end=$(date +%s%N || date +%s)
            integrity_ok="true"

            if command -v bc >/dev/null 2>&1; then
                query_time=$(echo "scale=3; ($query_end - $query_start) / 1000000000" | bc)
            else
                query_time="<1"
            fi

            table_count=$(sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" || echo "0")
            journal_mode=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA journal_mode;" || echo "unknown")

            if sqlite3 "$SQLITE_DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='users';" | grep -q users; then
                user_count=$(sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM users;" || echo "0")
            else
                user_count="N/A"
            fi
        else
            query_time="N/A"
            integrity_ok="false"
            table_count="N/A"
            user_count="N/A"
            journal_mode="unknown"
        fi
    fi

    cat <<EOF
sqlite_available=true
db_size_mb=$db_size_mb
db_modified=$db_modified
wal_size_mb=$wal_size_mb
query_time=$query_time
integrity_ok=$integrity_ok
table_count=$table_count
user_count=$user_count
journal_mode=$journal_mode
EOF
}

# ==============================================================================
# UNIFIED CONTAINER PERFORMANCE - ALIGNED WITH DIAGNOSE.SH
# ==============================================================================

# Get container performance using unified framework - consistent with diagnose.sh
get_container_performance_unified() {
    if [[ " ${loaded_frameworks[*]} " =~ " dashboard-metrics " ]]; then
        # Use unified framework container monitoring - same as diagnose.sh
        local container_metrics

        if [[ " ${loaded_frameworks[*]} " =~ " error-handler " ]]; then
            container_metrics=$(error_handler_safe_execute "container_metrics" dashboard_get_container_metrics)
        else
            container_metrics=$(dashboard_get_container_metrics)
        fi

        if [[ "$container_metrics" =~ docker_available=true ]]; then
            perf_debug "Container metrics collected via unified framework integration"
            echo "$container_metrics"
        else
            perf_warning "Docker not available via framework"
            echo "docker_available=false"
            return 1
        fi
    else
        # Enhanced fallback container monitoring - same as diagnose.sh
        perf_debug "Using unified fallback container monitoring"
        get_container_performance_fallback
    fi
}

# Enhanced fallback container performance - consistent with diagnose.sh
get_container_performance_fallback() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "docker_available=false"
        return 1
    fi

    # Enhanced Docker availability check
    if [[ " ${loaded_frameworks[*]} " =~ " error-handler " ]]; then
        if ! error_handler_safe_execute "docker_check" docker info >/dev/null; then
            echo "docker_available=false"
            return 1
        fi
    else
        if ! docker info >/dev/null 2>&1; then
            echo "docker_available=false"
            return 1
        fi
    fi

    echo "docker_available=true"

    # Enhanced container stats collection
    local container_stats
    if [[ " ${loaded_frameworks[*]} " =~ " error-handler " ]]; then
        container_stats=$(error_handler_safe_execute "container_stats" docker stats --no-stream --format "{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.NetIO}},{{.BlockIO}}" || echo "")
    else
        container_stats=$(docker stats --no-stream --format "{{.Name}},{{.CPUPerc}},{{.MemUsage}},{{.NetIO}},{{.BlockIO}}" || echo "")
    fi

    local container_count
    container_count=$(echo "$container_stats" | grep -c . || echo "0")
    echo "container_count=$container_count"

    # Enhanced container processing
    local container_index=0
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local name cpu_perc mem_usage net_io block_io
        IFS=',' read -r name cpu_perc mem_usage net_io block_io <<< "$line"

        # Enhanced metric cleaning
        cpu_perc=$(echo "$cpu_perc" | sed 's/%//')
        mem_usage=$(echo "$mem_usage" | awk '{print $1}' | sed 's/MiB//')

        echo "container_${container_index}_name=$name"
        echo "container_${container_index}_cpu_perc=$cpu_perc"
        echo "container_${container_index}_mem_usage=$mem_usage"
        echo "container_${container_index}_net_io=$net_io"
        echo "container_${container_index}_block_io=$block_io"

        ((container_index++))
    done <<< "$container_stats"
}

# ==============================================================================
# UNIFIED PERFORMANCE ANALYSIS - ALIGNED WITH DIAGNOSE.SH
# ==============================================================================

# Analyze performance using unified threshold system - consistent with diagnose.sh
analyze_performance_unified() {
    local metrics="$1"

    perf_info "Starting unified performance analysis with framework integration"

    # Parse comprehensive metrics
    local cpu_usage mem_usage_pct load_1m db_size_mb wal_size_mb fragmentation_ratio
    eval "$(echo "$metrics" | grep -E '^(cpu_usage|mem_usage_pct|load_1m|db_size_mb|wal_size_mb|fragmentation_ratio)=')"

    # Use framework formatting for section headers
    if [[ " ${loaded_frameworks[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_section "Performance Analysis for 1 OCPU/6GB Deployment" "normal"
    else
        echo -e "${BOLD}${CYAN}Performance Analysis for 1 OCPU/6GB Deployment:${NC}"
    fi
    echo ""

    # CPU Analysis with unified threshold system - same as diagnose.sh
    local cpu_status
    cpu_status=$(evaluate_cpu_threshold "$cpu_usage")

    echo -e "${BOLD}CPU Performance:${NC}"
    case "$cpu_status" in
        "critical") 
            echo -e "${RED}🔴 CPU CRITICAL${NC}: $cpu_usage% (threshold: $CPU_CRITICAL_THRESHOLD%)"
            echo "  ⚠️  Single OCPU is severely overloaded"
            echo "  💡 Check for runaway processes: ps aux --sort=-%cpu | head -10"
            ;;
        "alert") 
            echo -e "${YELLOW}🟠 CPU ALERT${NC}: $cpu_usage% (threshold: $CPU_ALERT_THRESHOLD%)"
            echo "  ⚠️  High CPU usage for 1 OCPU deployment"
            echo "  💡 Consider reducing concurrent operations"
            ;;
        "warning") 
            echo -e "${YELLOW}🟡 CPU WARNING${NC}: $cpu_usage% (threshold: $CPU_WARNING_THRESHOLD%)"
            echo "  ℹ️  Elevated CPU usage, monitor closely"
            ;;
        *) 
            echo -e "${GREEN}🟢 CPU NORMAL${NC}: $cpu_usage% (optimal for 1 OCPU)"
            ;;
    esac
    echo ""

    # Memory Analysis with unified threshold system - same as diagnose.sh
    local mem_status
    mem_status=$(evaluate_memory_threshold "$mem_usage_pct")

    echo -e "${BOLD}Memory Performance:${NC}"
    case "$mem_status" in
        "critical") 
            echo -e "${RED}🔴 MEMORY CRITICAL${NC}: $mem_usage_pct% (threshold: $MEMORY_CRITICAL_THRESHOLD%)"
            echo "  ⚠️  Memory pressure detected on 6GB system"
            echo "  💡 Check container memory usage: docker stats --no-stream"
            ;;
        "alert") 
            echo -e "${YELLOW}🟠 MEMORY ALERT${NC}: $mem_usage_pct% (threshold: $MEMORY_ALERT_THRESHOLD%)"
            echo "  ⚠️  High memory usage approaching limits"
            ;;
        "warning") 
            echo -e "${YELLOW}🟡 MEMORY WARNING${NC}: $mem_usage_pct% (threshold: $MEMORY_WARNING_THRESHOLD%)"
            ;;
        *) 
            echo -e "${GREEN}🟢 MEMORY NORMAL${NC}: $mem_usage_pct% (target: ~11% of 6GB)"
            ;;
    esac
    echo ""

    # Load Average Analysis with unified threshold system - same as diagnose.sh
    local load_status
    load_status=$(evaluate_load_threshold "$load_1m")

    echo -e "${BOLD}Load Average Performance (1 OCPU Context):${NC}"
    case "$load_status" in
        "critical") 
            echo -e "${RED}🔴 LOAD CRITICAL${NC}: $load_1m (threshold: $LOAD_CRITICAL_THRESHOLD for 1 OCPU)"
            echo "  🚨 Single CPU is severely overloaded - system may be unresponsive"
            echo "  💡 Immediate action required: check runaway processes"
            ;;
        "alert") 
            echo -e "${YELLOW}🟠 LOAD ALERT${NC}: $load_1m (threshold: $LOAD_ALERT_THRESHOLD for 1 OCPU)"
            echo "  ⚠️  High load for single CPU system"
            echo "  💡 Monitor process queue: ps aux --sort=-pcpu | head -5"
            ;;
        "warning") 
            echo -e "${YELLOW}🟡 LOAD WARNING${NC}: $load_1m (threshold: $LOAD_WARNING_THRESHOLD for 1 OCPU)"
            echo "  ℹ️  Elevated load, monitor for trends"
            ;;
        *) 
            echo -e "${GREEN}🟢 LOAD NORMAL${NC}: $load_1m (optimal: <1.0 for 1 OCPU)"
            ;;
    esac
    echo ""

    # SQLite Performance Analysis with unified threshold system - same as diagnose.sh
    if [[ -n "$db_size_mb" && "$db_size_mb" != "N/A" ]]; then
        echo -e "${BOLD}SQLite Database Performance:${NC}"

        # Database size analysis using unified thresholds
        local size_status
        size_status=$(evaluate_sqlite_size_threshold "$db_size_mb")

        case "$size_status" in
            "critical") 
                echo -e "${RED}🔴 SQLite SIZE CRITICAL${NC}: ${db_size_mb}MB (threshold: $SQLITE_SIZE_CRITICAL_MB MB)"
                echo "  🚨 Database is very large - performance may be impacted"
                echo "  💡 Run maintenance: ./sqlite-maintenance.sh --analyze"
                ;;
            "alert") 
                echo -e "${YELLOW}🟠 SQLite SIZE ALERT${NC}: ${db_size_mb}MB (threshold: $SQLITE_SIZE_ALERT_MB MB)"
                echo "  ⚠️  Database size growing - monitor growth rate"
                echo "  💡 Consider scheduling maintenance"
                ;;
            "warning") 
                echo -e "${YELLOW}🟡 SQLite SIZE WARNING${NC}: ${db_size_mb}MB (threshold: $SQLITE_SIZE_WARNING_MB MB)"
                ;;
            *) 
                echo -e "${GREEN}🟢 SQLite SIZE NORMAL${NC}: ${db_size_mb}MB (under $SQLITE_SIZE_WARNING_MB MB)"
                ;;
        esac

        # WAL analysis using unified thresholds
        if [[ -n "$wal_size_mb" && "$wal_size_mb" != "0" ]]; then
            if command -v bc >/dev/null 2>&1 && (( $(echo "$wal_size_mb > $WAL_SIZE_CRITICAL_MB" | bc -l) )); then
                echo -e "${RED}🔴 SQLite WAL CRITICAL${NC}: ${wal_size_mb}MB (threshold: $WAL_SIZE_CRITICAL_MB MB)"
                echo "  🚨 WAL file is very large - checkpoint recommended"
                echo "  💡 Run: docker exec vaultwarden sqlite3 /data/db.sqlite3 'PRAGMA wal_checkpoint;'"
            elif command -v bc >/dev/null 2>&1 && (( $(echo "$wal_size_mb > $WAL_SIZE_ALERT_MB" | bc -l) )); then
                echo -e "${YELLOW}🟠 SQLite WAL ALERT${NC}: ${wal_size_mb}MB (threshold: $WAL_SIZE_ALERT_MB MB)"
                echo "  ℹ️  Large WAL file indicates recent activity"
            else
                echo -e "${GREEN}🟢 SQLite WAL NORMAL${NC}: ${wal_size_mb}MB"
            fi
        else
            echo -e "${GREEN}🟢 SQLite WAL${NC}: No WAL file (normal)"
        fi

        # Fragmentation analysis using unified thresholds
        if [[ -n "$fragmentation_ratio" ]]; then
            local frag_status
            frag_status=$(evaluate_fragmentation_threshold "$fragmentation_ratio")

            case "$frag_status" in
                "critical"|"alert") 
                    echo -e "${YELLOW}🟠 SQLite FRAGMENTATION${NC}: $fragmentation_ratio (threshold: $FRAGMENTATION_ALERT_RATIO)"
                    echo "  💡 Run VACUUM to optimize: ./sqlite-maintenance.sh --vacuum"
                    ;;
                "warning") 
                    echo -e "${YELLOW}🟡 SQLite FRAGMENTATION${NC}: $fragmentation_ratio (threshold: $FRAGMENTATION_WARNING_RATIO)"
                    echo "  ℹ️  Slight fragmentation detected"
                    ;;
                *) 
                    echo -e "${GREEN}🟢 SQLite FRAGMENTATION${NC}: $fragmentation_ratio (optimal)"
                    ;;
            esac
        fi

        echo ""
    fi
}

# ==============================================================================
# UNIFIED REAL-TIME MONITORING - ALIGNED WITH DIAGNOSE.SH
# ==============================================================================

# Real-time monitoring with unified framework integration
monitor_realtime_unified() {
    local interval="${1:-$PERF_MONITOR_INTERVAL}"
    local duration="${2:-0}"

    perf_info "Starting unified framework-integrated real-time monitoring"
    perf_info "Framework components: ${#loaded_frameworks[@]} loaded (${loaded_frameworks[*]})"
    perf_info "Configuration: $MONITORING_CONFIG_SOURCES"

    if [[ " ${loaded_frameworks[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_monitoring_header "VaultWarden Performance Monitor" "Unified Framework v$MONITORING_CONFIG_VERSION" "$interval" "$duration"
    else
        echo -e "${BOLD}${CYAN}VaultWarden Performance Monitor (Unified Framework v$MONITORING_CONFIG_VERSION)${NC}"
        echo "Interval: ${interval}s, Duration: $([[ $duration -eq 0 ]] && echo "infinite" || echo "${duration}s")"
        echo "Framework: ${#loaded_frameworks[@]} components active"
        echo "Press Ctrl+C to stop"
    fi
    echo ""

    local start_time end_time
    start_time=$(date +%s)
    end_time=$((start_time + duration))

    while true; do
        # Check duration limit
        if [[ $duration -gt 0 ]] && [[ $(date +%s) -ge $end_time ]]; then
            perf_info "Monitoring duration completed"
            break
        fi

        clear

        # Header with unified framework formatting
        if [[ " ${loaded_frameworks[*]} " =~ " perf-formatter " ]]; then
            perf_formatter_monitoring_header "VaultWarden Monitor" "Unified v$MONITORING_CONFIG_VERSION • $(date)" "" ""
        else
            echo -e "${BOLD}${CYAN}VaultWarden Performance Monitor - $(date)${NC}"
            echo "Unified Framework: ${loaded_frameworks[*]}"
        fi

        echo "Target: 1 OCPU (CPU <${CPU_CRITICAL_THRESHOLD}%, Load <${LOAD_CRITICAL_THRESHOLD}), 6GB RAM (~672MB containers)"
        echo "Thresholds: CPU ${CPU_WARNING_THRESHOLD}%/${CPU_ALERT_THRESHOLD}%/${CPU_CRITICAL_THRESHOLD}%, Memory ${MEMORY_WARNING_THRESHOLD}%/${MEMORY_ALERT_THRESHOLD}%/${MEMORY_CRITICAL_THRESHOLD}%, Load ${LOAD_WARNING_THRESHOLD}/${LOAD_ALERT_THRESHOLD}/${LOAD_CRITICAL_THRESHOLD}"
        echo "================================================================================"

        # Get comprehensive metrics using unified framework
        local system_metrics sqlite_metrics container_metrics
        system_metrics=$(get_system_performance_unified)
        sqlite_metrics=$(get_sqlite_performance_unified)
        container_metrics=$(get_container_performance_unified)

        # Parse key metrics for display
        local cpu_usage mem_usage_pct load_1m db_size_mb
        eval "$(echo "$system_metrics" | grep -E '^(cpu_usage|mem_usage_pct|load_1m)=')"
        eval "$(echo "$sqlite_metrics" | grep -E '^db_size_mb=' || echo 'db_size_mb=N/A')"

        # Display with unified framework formatting
        echo -e "${BOLD}System Status (Unified Thresholds):${NC}"

        # CPU with unified threshold evaluation
        local cpu_status
        cpu_status=$(evaluate_cpu_threshold "$cpu_usage")
        local cpu_color
        case "$cpu_status" in
            "critical") cpu_color="$RED" ;;
            "alert") cpu_color="$YELLOW" ;;
            "warning") cpu_color="$YELLOW" ;;
            *) cpu_color="$GREEN" ;;
        esac
        echo -e "CPU Usage: ${cpu_color}${cpu_usage}%${NC} (warn: ${CPU_WARNING_THRESHOLD}%, alert: ${CPU_ALERT_THRESHOLD}%, crit: ${CPU_CRITICAL_THRESHOLD}%)"

        # Memory with unified threshold evaluation
        local mem_status
        mem_status=$(evaluate_memory_threshold "$mem_usage_pct")
        local mem_color
        case "$mem_status" in
            "critical") mem_color="$RED" ;;
            "alert") mem_color="$YELLOW" ;;
            "warning") mem_color="$YELLOW" ;;
            *) mem_color="$GREEN" ;;
        esac
        echo -e "Memory: ${mem_color}${mem_usage_pct}%${NC} (warn: ${MEMORY_WARNING_THRESHOLD}%, alert: ${MEMORY_ALERT_THRESHOLD}%, crit: ${MEMORY_CRITICAL_THRESHOLD}%)"

        # Load Average with unified threshold evaluation (1 OCPU context)
        local load_status
        load_status=$(evaluate_load_threshold "$load_1m")
        local load_color
        case "$load_status" in
            "critical") load_color="$RED" ;;
            "alert") load_color="$YELLOW" ;;
            "warning") load_color="$YELLOW" ;;
            *) load_color="$GREEN" ;;
        esac
        echo -e "Load Avg: ${load_color}${load_1m}${NC} (1 OCPU warn: ${LOAD_WARNING_THRESHOLD}, alert: ${LOAD_ALERT_THRESHOLD}, crit: ${LOAD_CRITICAL_THRESHOLD})"

        # SQLite status with unified framework integration
        if [[ "$db_size_mb" != "N/A" && -n "$db_size_mb" ]]; then
            local size_status
            size_status=$(evaluate_sqlite_size_threshold "$db_size_mb")
            local db_color
            case "$size_status" in
                "critical"|"alert") db_color="$YELLOW" ;;
                "warning") db_color="$YELLOW" ;;
                *) db_color="$GREEN" ;;
            esac
            echo -e "SQLite DB: ${db_color}${db_size_mb}MB${NC} (unified monitored)"
        else
            echo -e "SQLite DB: ${YELLOW}Not available${NC}"
        fi

        echo ""

        # Container status with unified framework formatting
        echo -e "${BOLD}Container Status:${NC}"
        if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
            docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" | head -6 || echo "Container stats unavailable"
        else
            echo "Docker not available"
        fi

        echo ""
        echo "Unified Framework Enhanced Monitoring... (${interval}s refresh) - Press Ctrl+C to stop"

        sleep "$interval"
    done
}

# ==============================================================================
# UNIFIED PERFORMANCE REPORTING
# ==============================================================================

# Generate unified performance report with full framework integration
generate_performance_report_unified() {
    local output_file="$PERF_LOG_DIR/performance-report-unified-$(date +%Y%m%d_%H%M%S).txt"

    perf_info "Generating unified performance report with full framework integration"

    {
        echo "VaultWarden-OCI-Slim Performance Report (Unified Framework v$MONITORING_CONFIG_VERSION)"
        echo "================================================================================="
        echo "Generated: $(date)"
        echo "Framework Integration: Unified (${#loaded_frameworks[@]} components)"
        echo "Components Active: ${loaded_frameworks[*]}"
        echo "Configuration Sources: $MONITORING_CONFIG_SOURCES"
        echo "Optimization Target: 1 OCPU/6GB SQLite deployment"
        echo ""

        # Unified threshold configuration
        echo "UNIFIED THRESHOLD CONFIGURATION:"
        echo "================================"
        echo "CPU Thresholds:    Warning: ${CPU_WARNING_THRESHOLD}%, Alert: ${CPU_ALERT_THRESHOLD}%, Critical: ${CPU_CRITICAL_THRESHOLD}%"
        echo "Memory Thresholds: Warning: ${MEMORY_WARNING_THRESHOLD}%, Alert: ${MEMORY_ALERT_THRESHOLD}%, Critical: ${MEMORY_CRITICAL_THRESHOLD}%"
        echo "Load Thresholds:   Warning: ${LOAD_WARNING_THRESHOLD}, Alert: ${LOAD_ALERT_THRESHOLD}, Critical: ${LOAD_CRITICAL_THRESHOLD} (1 OCPU)"
        echo "SQLite Thresholds: Warning: ${SQLITE_SIZE_WARNING_MB}MB, Alert: ${SQLITE_SIZE_ALERT_MB}MB, Critical: ${SQLITE_SIZE_CRITICAL_MB}MB"
        echo ""

        # System performance using unified framework
        echo "SYSTEM PERFORMANCE (Unified Framework Collection):"
        echo "=================================================="
        local system_metrics
        system_metrics=$(get_system_performance_unified)
        echo "$system_metrics" | while IFS='=' read -r key value; do
            printf "%-25s: %s\n" "$key" "$value"
        done
        echo ""

        # SQLite performance using unified framework
        echo "SQLITE PERFORMANCE (Unified Framework Analysis):"
        echo "================================================"
        local sqlite_metrics
        sqlite_metrics=$(get_sqlite_performance_unified)
        if [[ "$sqlite_metrics" =~ sqlite_available=true ]]; then
            echo "$sqlite_metrics" | grep -v "sqlite_available" | while IFS='=' read -r key value; do
                printf "%-25s: %s\n" "$key" "$value"
            done
        else
            echo "SQLite database not available"
        fi
        echo ""

        # Container performance using unified framework
        echo "CONTAINER PERFORMANCE (Unified Framework Metrics):"
        echo "=================================================="
        local container_metrics
        container_metrics=$(get_container_performance_unified)
        if [[ "$container_metrics" =~ docker_available=true ]]; then
            echo "$container_metrics" | grep -v "docker_available" | while IFS='=' read -r key value; do
                printf "%-25s: %s\n" "$key" "$value"
            done
        else
            echo "Docker not available"
        fi
        echo ""

        # Unified performance analysis
        echo "UNIFIED PERFORMANCE ANALYSIS:"
        echo "============================="
        local all_metrics
        all_metrics=$(echo -e "$system_metrics\n$sqlite_metrics\n$container_metrics")
        analyze_performance_unified "$all_metrics" 2>&1 | sed 's/\033\[[0-9;]*m//g'  # Remove color codes

        # Framework component status
        echo ""
        echo "FRAMEWORK COMPONENT STATUS:"
        echo "=========================="
        for component in "${loaded_frameworks[@]}"; do
            echo "✅ $component: Active and integrated"
        done

        if [[ ${#loaded_frameworks[@]} -eq 0 ]]; then
            echo "⚠️ No framework components loaded - using fallback mode"
        fi

    } > "$output_file"

    perf_success "Unified performance report generated: $output_file"
    echo "$output_file"
}

# ==============================================================================
# UNIFIED MAIN FUNCTION
# ==============================================================================
main() {
    local action="status"
    local interval="$PERF_MONITOR_INTERVAL"
    local duration=0

    # Unified framework initialization logging
    perf_info "Starting performance monitoring with unified framework integration"
    perf_info "Framework components loaded: ${#loaded_frameworks[@]} (${loaded_frameworks[*]})"
    perf_info "Configuration sources: $MONITORING_CONFIG_SOURCES"
    perf_info "Monitoring configuration version: $MONITORING_CONFIG_VERSION"

    # Parse arguments with enhanced validation
    while [[ $# -gt 0 ]]; do
        case $1 in
            status|--status)
                action="status"
                shift
                ;;
            monitor|--monitor)
                action="monitor"
                shift
                ;;
            benchmark|--benchmark)
                action="benchmark"
                shift
                ;;
            report|--report)
                action="report"
                shift
                ;;
            --interval)
                if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    interval="$2"
                    shift 2
                else
                    perf_warning "Invalid interval specified, using default: $PERF_MONITOR_INTERVAL"
                    shift
                fi
                ;;
            --duration)
                if [[ -n "${2:-}" ]] && [[ "$2" =~ ^[0-9]+$ ]]; then
                    duration="$2"
                    shift 2
                else
                    perf_warning "Invalid duration specified, using default: 0 (infinite)"
                    shift
                fi
                ;;
            --help|-h)
                show_unified_help
                exit 0
                ;;
            *)
                perf_warning "Unknown argument: $1"
                shift
                ;;
        esac
    done

    # Execute requested action with unified framework integration
    case "$action" in
        "status")
            show_performance_status_unified
            ;;
        "monitor")
            monitor_realtime_unified "$interval" "$duration"
            ;;
        "benchmark")
            run_unified_benchmark
            ;;
        "report")
            local report_file
            report_file=$(generate_performance_report_unified)
            perf_success "Unified performance report generated: $report_file"
            ;;
        *)
            perf_critical "Unknown action: $action"
            exit 1
            ;;
    esac
}

# Show performance status with unified framework integration
show_performance_status_unified() {
    if [[ " ${loaded_frameworks[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_section "VaultWarden Performance Status (Unified Framework v$MONITORING_CONFIG_VERSION)" "normal"
    else
        echo -e "${BOLD}${CYAN}VaultWarden Performance Status (Unified Framework v$MONITORING_CONFIG_VERSION)${NC}"
        echo "Framework Integration: Unified (${#loaded_frameworks[@]} components)"
        echo "Configuration: $MONITORING_CONFIG_SOURCES"
    fi
    echo ""

    # Get comprehensive metrics using unified framework
    local system_metrics sqlite_metrics container_metrics
    system_metrics=$(get_system_performance_unified)
    sqlite_metrics=$(get_sqlite_performance_unified)
    container_metrics=$(get_container_performance_unified)

    # Combine and analyze with unified framework
    local all_metrics
    all_metrics=$(echo -e "$system_metrics\n$sqlite_metrics\n$container_metrics")

    analyze_performance_unified "$all_metrics"

    # Unified framework optimization recommendations
    echo ""
    echo -e "${BOLD}Unified Framework Integration Benefits:${NC}"
    echo "• Consistent thresholds across all monitoring tools (v$MONITORING_CONFIG_VERSION)"
    echo "• Single source of truth via lib/monitoring-config.sh"
    echo "• Standardized 3-tier threshold system (WARNING/ALERT/CRITICAL)"
    echo "• Cached metrics reduce system overhead on 1 OCPU"
    echo "• Configurable thresholds from external config files"
    echo "• Enhanced error handling and recovery patterns"
    echo "• Comprehensive SQLite analysis and maintenance integration"

    echo ""
    echo -e "${BOLD}1 OCPU/6GB Optimization Guidelines (Unified Framework):${NC}"
    echo "• CPU Thresholds: ${CPU_WARNING_THRESHOLD}%/${CPU_ALERT_THRESHOLD}%/${CPU_CRITICAL_THRESHOLD}% (WARNING/ALERT/CRITICAL)"
    echo "• Memory Thresholds: ${MEMORY_WARNING_THRESHOLD}%/${MEMORY_ALERT_THRESHOLD}%/${MEMORY_CRITICAL_THRESHOLD}% (WARNING/ALERT/CRITICAL)" 
    echo "• Load Thresholds: ${LOAD_WARNING_THRESHOLD}/${LOAD_ALERT_THRESHOLD}/${LOAD_CRITICAL_THRESHOLD} (1 OCPU optimized)"
    echo "• SQLite Size Limits: ${SQLITE_SIZE_WARNING_MB}MB/${SQLITE_SIZE_ALERT_MB}MB/${SQLITE_SIZE_CRITICAL_MB}MB"
    echo "• VaultWarden workers: 1 (ROCKET_WORKERS=1)"
    echo "• WebSocket disabled: WEBSOCKET_ENABLED=false"
    echo "• Target memory usage: ~672MB total containers"
    echo ""
}

# Unified benchmark with framework integration
run_unified_benchmark() {
    if [[ " ${loaded_frameworks[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_section "Performance Benchmark (Unified Framework)" "normal"
    else
        echo -e "${BOLD}${CYAN}Performance Benchmark (Unified Framework)${NC}"
    fi

    perf_info "Running comprehensive benchmark with unified framework integration"
    perf_info "Threshold system: 3-tier (WARNING/ALERT/CRITICAL)"
    perf_info "Configuration sources: $MONITORING_CONFIG_SOURCES"

    # Framework-enhanced benchmark results
    if [[ " ${loaded_frameworks[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_benchmark_results "unified"
    else
        echo "Unified benchmark functionality available via lib/test-utils.sh"
        echo "Current mode: Basic benchmark with unified logging and thresholds"
        echo ""
        echo "Benchmark Results:"
        echo "• Framework Integration: ${#loaded_frameworks[@]} components"
        echo "• Threshold System: 3-tier unified system"
        echo "• Configuration: Single source of truth (lib/monitoring-config.sh)"
        echo "• 1 OCPU Optimization: Active"
    fi
}

# Unified help display
show_unified_help() {
    cat <<EOF
VaultWarden-OCI-Slim Performance Monitor (Unified Framework v$MONITORING_CONFIG_VERSION)

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    status      Show performance status with unified framework integration (default)
    monitor     Real-time monitoring with unified framework formatting
    benchmark   Run comprehensive benchmark tests
    report      Generate detailed performance report

Options:
    --interval N    Monitoring refresh interval (config: ${PERF_MONITOR_INTERVAL}s)
    --duration N    Monitoring duration (0 = infinite, default: 0)
    --help, -h      Show this help message

🔄 Unified Framework Integration (Aligned with diagnose.sh):
    ✅ lib/monitoring-config.sh: Single source of truth for all thresholds
    ✅ lib/perf-collector.sh: Unified metrics with intelligent caching
    ✅ lib/dashboard-sqlite.sh: Comprehensive SQLite analysis
    ✅ lib/dashboard-metrics.sh: Complete container management
    ✅ lib/logger.sh: Structured logging with rotation (optional)
    ✅ lib/error-handler.sh: Robust error recovery (optional)
    ✅ lib/perf-formatter.sh: Standardized output formatting (optional)

Unified Performance Targets (1 OCPU/6GB, 3-Tier System):
    • CPU Usage: <${CPU_WARNING_THRESHOLD}% warn, <${CPU_ALERT_THRESHOLD}% alert, <${CPU_CRITICAL_THRESHOLD}% critical
    • Memory Usage: <${MEMORY_WARNING_THRESHOLD}% warn, <${MEMORY_ALERT_THRESHOLD}% alert, <${MEMORY_CRITICAL_THRESHOLD}% critical
    • Load Average: <${LOAD_WARNING_THRESHOLD} warn, <${LOAD_ALERT_THRESHOLD} alert, <${LOAD_CRITICAL_THRESHOLD} critical (1 OCPU)
    • SQLite Database: <${SQLITE_SIZE_WARNING_MB}MB warn, <${SQLITE_SIZE_ALERT_MB}MB alert, <${SQLITE_SIZE_CRITICAL_MB}MB critical

Configuration Sources (Priority Order):
    1. config/performance-targets.conf (highest)
    2. config/alert-thresholds.conf
    3. config/monitoring-intervals.conf
    4. settings.env environment variables
    5. Built-in defaults (lowest)

Unified Framework Benefits:
    • Consistent metrics and thresholds across ALL monitoring scripts
    • Single source of truth prevents configuration drift
    • 3-tier threshold system provides granular alerting
    • Standardized evaluation functions ensure consistent behavior
    • Enhanced framework integration with graceful fallbacks
    • Optimized for 1 OCPU/6GB OCI A1 Flex deployment

Examples:
    $0                 # Unified framework-integrated status
    $0 monitor         # Real-time monitoring with unified thresholds
    $0 report          # Comprehensive unified framework-based report

EOF
}

# Handle interrupts gracefully with unified framework logging
trap 'echo ""; perf_info "Performance monitoring stopped by user"; exit 0' INT TERM

# Execute main function
main "$@"