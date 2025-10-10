#!/usr/bin/env bash
# diagnose.sh -- UNIFIED VERSION: Uses centralized monitoring configuration
# Enhanced diagnostics with unified threshold evaluation

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/lib/common.sh" || { echo "ERROR: lib/common.sh required" >&2; exit 1; }

# UNIFIED CONFIGURATION: Single source of truth
source "$SCRIPT_DIR/lib/monitoring-config.sh" || {
    echo "ERROR: lib/monitoring-config.sh required for unified configuration" >&2
    exit 1
}

# Verify unified configuration loaded
if [[ "$MONITORING_CONFIG_LOADED" != "true" ]]; then
    echo "ERROR: Unified monitoring configuration failed to load" >&2
    exit 1
fi

# Load optional framework components
loaded_frameworks=()
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

# ================================
# UNIFIED DIAGNOSTIC FUNCTIONS
# ================================

# Comprehensive system diagnostics using unified configuration
run_unified_system_diagnostics() {
    log_step "System Diagnostics (Unified Configuration v$MONITORING_CONFIG_VERSION)"

    local system_metrics
    if [[ " ${loaded_frameworks[*]} " =~ " perf-collector " ]]; then
        system_metrics=$(perf_collector_system_full)
        log_info "Using framework perf-collector for system metrics"
    else
        system_metrics=$(get_unified_system_metrics)
        log_info "Using unified fallback system metrics"
    fi

    # Parse metrics
    local cpu_usage mem_usage_pct load_1m disk_usage_pct
    eval "$system_metrics"

    # Evaluate using unified threshold functions
    local cpu_status mem_status load_status disk_status
    cpu_status=$(evaluate_cpu_threshold "$cpu_usage")
    mem_status=$(evaluate_memory_threshold "$mem_usage_pct")
    load_status=$(evaluate_load_threshold "$load_1m")
    disk_status=$(evaluate_disk_threshold "$disk_usage_pct")

    # Display results with unified status indicators
    echo "Configuration: $MONITORING_CONFIG_SOURCES"
    echo ""

    # CPU Analysis
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

    # Memory Analysis
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

    # Load Average Analysis (critical for 1 OCPU)
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

    # Disk Analysis
    case "$disk_status" in
        "critical"|"alert") 
            echo -e "${RED}🔴 DISK ${disk_status^^}${NC}: $disk_usage_pct% (threshold: $DISK_ALERT_THRESHOLD%)"
            echo "  💡 Free up space: docker system prune -af"
            ;;
        "warning") 
            echo -e "${YELLOW}🟡 DISK WARNING${NC}: $disk_usage_pct% (threshold: $DISK_WARNING_THRESHOLD%)"
            ;;
        *) 
            echo -e "${GREEN}🟢 DISK NORMAL${NC}: $disk_usage_pct%"
            ;;
    esac

    echo ""
}

# Unified SQLite diagnostics
run_unified_sqlite_diagnostics() {
    log_step "SQLite Diagnostics (Unified Configuration)"

    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        echo -e "${YELLOW}🟡 SQLite Database:${NC} Not found ($SQLITE_DB_PATH)"
        echo "  ℹ️  Normal for new installations - will be created on first VaultWarden startup"
        return 0
    fi

    local sqlite_metrics
    if [[ " ${loaded_frameworks[*]} " =~ " dashboard-sqlite " ]]; then
        sqlite_metrics=$(dashboard_sqlite_get_detailed_metrics || echo "available=false")
        log_info "Using framework dashboard-sqlite for database analysis"
    else
        sqlite_metrics=$(get_sqlite_metrics_fallback)
        log_info "Using unified fallback SQLite analysis"
    fi

    if [[ "$sqlite_metrics" =~ available=true ]] || [[ "$sqlite_metrics" =~ db_exists=true ]]; then
        # Parse SQLite metrics
        local file_size_mb wal_size_mb fragmentation_ratio table_count user_count journal_mode
        eval "$(echo "$sqlite_metrics" | grep -E '^(file_size_mb|wal_size_mb|fragmentation_ratio|table_count|user_count|journal_mode)=' || echo 'file_size_mb=0 wal_size_mb=0 fragmentation_ratio=1.0')"

        # Database size analysis using unified thresholds
        local size_status
        size_status=$(evaluate_sqlite_size_threshold "$file_size_mb")

        case "$size_status" in
            "critical") 
                echo -e "${RED}🔴 SQLite SIZE CRITICAL${NC}: ${file_size_mb}MB (threshold: $SQLITE_SIZE_CRITICAL_MB MB)"
                echo "  🚨 Database is very large - performance may be impacted"
                echo "  💡 Run maintenance: ./sqlite-maintenance.sh --analyze"
                ;;
            "alert") 
                echo -e "${YELLOW}🟠 SQLite SIZE ALERT${NC}: ${file_size_mb}MB (threshold: $SQLITE_SIZE_ALERT_MB MB)"
                echo "  ⚠️  Database size growing - monitor growth rate"
                echo "  💡 Consider scheduling maintenance"
                ;;
            "warning") 
                echo -e "${YELLOW}🟡 SQLite SIZE WARNING${NC}: ${file_size_mb}MB (threshold: $SQLITE_SIZE_WARNING_MB MB)"
                ;;
            *) 
                echo -e "${GREEN}🟢 SQLite SIZE NORMAL${NC}: ${file_size_mb}MB (under $SQLITE_SIZE_WARNING_MB MB)"
                ;;
        esac

        # WAL file analysis using unified thresholds
        if [[ "$wal_size_mb" != "0" ]] && command -v bc >/dev/null 2>&1; then
            if (( $(echo "$wal_size_mb > $WAL_SIZE_CRITICAL_MB" | bc -l) )); then
                echo -e "${RED}🔴 SQLite WAL CRITICAL${NC}: ${wal_size_mb}MB (threshold: $WAL_SIZE_CRITICAL_MB MB)"
                echo "  🚨 WAL file is very large - checkpoint recommended"
                echo "  💡 Run: docker exec vaultwarden sqlite3 /data/db.sqlite3 'PRAGMA wal_checkpoint;'"
            elif (( $(echo "$wal_size_mb > $WAL_SIZE_ALERT_MB" | bc -l) )); then
                echo -e "${YELLOW}🟠 SQLite WAL ALERT${NC}: ${wal_size_mb}MB (threshold: $WAL_SIZE_ALERT_MB MB)"
                echo "  ℹ️  Large WAL file indicates recent activity"
            else
                echo -e "${GREEN}🟢 SQLite WAL NORMAL${NC}: ${wal_size_mb}MB"
            fi
        else
            echo -e "${GREEN}🟢 SQLite WAL${NC}: No WAL file (normal)"
        fi

        # Fragmentation analysis using unified thresholds
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

        # Additional SQLite information
        echo -e "${BLUE}ℹ️  SQLite Details:${NC} Mode: $journal_mode, Tables: $table_count, Users: $user_count"

    else
        echo -e "${RED}🔴 SQLite Analysis Failed${NC}: Database not accessible"
        echo "  💡 Check if VaultWarden container is running"
    fi

    echo ""
}

# Unified container diagnostics
run_unified_container_diagnostics() {
    log_step "Container Diagnostics (Unified)"

    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${RED}🔴 Docker Not Available${NC}"
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}🔴 Docker Daemon Not Running${NC}"
        return 1
    fi

    local container_metrics
    if [[ " ${loaded_frameworks[*]} " =~ " dashboard-metrics " ]]; then
        container_metrics=$(dashboard_get_container_metrics)
        log_info "Using framework dashboard-metrics for container analysis"
    else
        container_metrics=$(get_container_metrics_fallback)
        log_info "Using unified fallback container analysis"
    fi

    # Parse container information
    if [[ "$container_metrics" =~ docker_available=true ]]; then
        local containers_running containers_total
        eval "$(echo "$container_metrics" | grep -E '^containers_(running|total)=' || echo 'containers_running=0 containers_total=0')"

        echo "Container Status: ${containers_running}/${containers_total} running"

        # Check each expected container
        local expected_containers=("vaultwarden" "bw_caddy" "bw_fail2ban" "bw_backup" "bw_watchtower" "bw_ddclient" "bw_monitoring")
        local critical_issues=0

        for container in "${expected_containers[@]}"; do
            local service_status service_health
            eval "$(echo "$container_metrics" | grep -E "^${container}_(status|health)=" || echo "${container}_status=not_found ${container}_health=N/A")"

            case "$service_status" in
                "running")
                    case "$service_health" in
                        "healthy"|"no-health-check"|"no_healthcheck")
                            echo -e "├─ ${GREEN}✅ $container${NC}: Running, $service_health"
                            ;;
                        "starting")
                            echo -e "├─ ${YELLOW}🔄 $container${NC}: Starting ($service_health)"
                            ;;
                        "unhealthy")
                            echo -e "├─ ${RED}❌ $container${NC}: Running but unhealthy"
                            ((critical_issues++))
                            ;;
                    esac
                    ;;
                "stopped"|"exited")
                    if [[ "$container" =~ ^(vaultwarden|bw_caddy)$ ]]; then
                        echo -e "├─ ${RED}🚨 $container${NC}: CRITICAL SERVICE STOPPED"
                        ((critical_issues++))
                    else
                        echo -e "├─ ${YELLOW}⏸️  $container${NC}: Optional service stopped"
                    fi
                    ;;
                "not_found")
                    echo -e "├─ ${BLUE}➖ $container${NC}: Not configured (normal)"
                    ;;
                *)
                    echo -e "├─ ${PURPLE}❓ $container${NC}: Unknown status ($service_status)"
                    ;;
            esac
        done

        # Summary
        if [[ $critical_issues -gt 0 ]]; then
            echo -e "└─ ${RED}🚨 $critical_issues critical container issues detected${NC}"
            echo "   💡 Run: docker compose logs <service_name> for details"
        else
            echo -e "└─ ${GREEN}✅ All containers healthy${NC}"
        fi

    else
        echo -e "${RED}🔴 Container Analysis Failed${NC}: Docker not available"
        return 1
    fi

    echo ""
}

# Fallback container metrics
get_container_metrics_fallback() {
    local running_count=0
    local total_count=0
    local containers=("vaultwarden" "bw_caddy" "bw_fail2ban" "bw_backup" "bw_watchtower" "bw_ddclient" "bw_monitoring")

    echo "docker_available=true"

    for container in "${containers[@]}"; do
        ((total_count++))

        if docker ps --filter "name=$container" --filter "status=running" --format "{{.Names}}" | grep -q "^$container$"; then
            ((running_count++))
            echo "${container}_status=running"

            # Get health status
            local health
            health=$(docker inspect "$container" --format='{{.State.Health.Status}}' 2>/dev/null || echo "no_healthcheck")
            echo "${container}_health=$health"
        else
            if docker ps -a --filter "name=$container" --format "{{.Names}}" | grep -q "^$container$"; then
                echo "${container}_status=stopped"
            else
                echo "${container}_status=not_found"
            fi
            echo "${container}_health=N/A"
        fi
    done

    echo "containers_running=$running_count"
    echo "containers_total=$total_count"
}

# Fallback SQLite metrics
get_sqlite_metrics_fallback() {
    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        echo "available=false"
        echo "db_exists=false"
        return 1
    fi

    local db_size_bytes wal_size_bytes file_size_mb wal_size_mb

    # File sizes
    db_size_bytes=$(stat -c%s "$SQLITE_DB_PATH" 2>/dev/null || echo "0")
    if [[ -f "${SQLITE_DB_PATH}-wal" ]]; then
        wal_size_bytes=$(stat -c%s "${SQLITE_DB_PATH}-wal" 2>/dev/null || echo "0")
    else
        wal_size_bytes="0"
    fi

    # Convert to MB
    if command -v bc >/dev/null 2>&1; then
        file_size_mb=$(echo "scale=2; $db_size_bytes / 1024 / 1024" | bc)
        wal_size_mb=$(echo "scale=2; $wal_size_bytes / 1024 / 1024" | bc)
    else
        file_size_mb=$(( db_size_bytes / 1024 / 1024 ))
        wal_size_mb=$(( wal_size_bytes / 1024 / 1024 ))
    fi

    # Basic SQLite queries
    local table_count user_count journal_mode fragmentation_ratio
    if command -v sqlite3 >/dev/null 2>&1; then
        table_count=$(sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" 2>/dev/null || echo "0")
        journal_mode=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA journal_mode;" 2>/dev/null || echo "unknown")

        # User count if users table exists
        if sqlite3 "$SQLITE_DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='users';" 2>/dev/null | grep -q users; then
            user_count=$(sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM users;" 2>/dev/null || echo "0")
        else
            user_count="N/A"
        fi

        # Simple fragmentation estimate
        local page_count freelist_count
        page_count=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA page_count;" 2>/dev/null || echo "1")
        freelist_count=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA freelist_count;" 2>/dev/null || echo "0")

        if command -v bc >/dev/null 2>&1 && [[ $page_count -gt 0 ]]; then
            fragmentation_ratio=$(echo "scale=2; $freelist_count / $page_count" | bc)
        else
            fragmentation_ratio="0.00"
        fi
    else
        table_count="N/A"
        user_count="N/A"
        journal_mode="unknown"
        fragmentation_ratio="0.00"
    fi

    cat <<EOF
available=true
db_exists=true
file_size_mb=$file_size_mb
wal_size_mb=$wal_size_mb
table_count=$table_count
user_count=$user_count
journal_mode=$journal_mode
fragmentation_ratio=$fragmentation_ratio
EOF
}

# ================================
# NETWORK CONNECTIVITY DIAGNOSTICS
# ================================

run_network_diagnostics() {
    log_step "Network Connectivity (Unified)"

    # Internal connectivity test
    if curl -sf http://localhost:80/alive >/dev/null 2>&1; then
        echo -e "${GREEN}🟢 Internal Connectivity${NC}: VaultWarden responding on localhost:80"
    else
        echo -e "${RED}🔴 Internal Connectivity${NC}: VaultWarden not responding"
        echo "  💡 Check if vaultwarden container is running"
    fi

    # External connectivity test (if domain configured)
    if [[ -n "${APP_DOMAIN:-}" ]]; then
        local domain_url="${DOMAIN:-https://${APP_DOMAIN}}"

        if curl -sf "${domain_url}/alive" >/dev/null 2>&1; then
            echo -e "${GREEN}🟢 External Connectivity${NC}: $domain_url responding"
        else
            echo -e "${YELLOW}🟡 External Connectivity${NC}: $domain_url not accessible"
            echo "  ℹ️  This may be normal if DNS/firewall not configured"
        fi
    else
        echo -e "${BLUE}ℹ️  External Connectivity${NC}: No domain configured for testing"
    fi

    echo ""
}

# ================================
# CONFIGURATION VALIDATION
# ================================

run_configuration_validation() {
    log_step "Configuration Validation (Unified)"

    # Load settings if available
    local settings_status="Not found"
    if [[ -f "$SCRIPT_DIR/settings.env" ]]; then
        settings_status="Found"
        echo -e "${GREEN}🟢 settings.env${NC}: Configuration file exists"

        # Check critical variables
        local critical_vars=("DOMAIN" "ADMIN_TOKEN" "ADMIN_EMAIL")
        local missing_vars=()

        set -a
        source "$SCRIPT_DIR/settings.env"
        set +a

        for var in "${critical_vars[@]}"; do
            if [[ -z "${!var:-}" ]]; then
                missing_vars+=("$var")
            fi
        done

        if [[ ${#missing_vars[@]} -gt 0 ]]; then
            echo -e "${RED}🔴 Missing Variables${NC}: ${missing_vars[*]}"
            echo "  💡 Configure in settings.env file"
        else
            echo -e "${GREEN}🟢 Core Variables${NC}: All required variables configured"
        fi

        # Check optional features
        local optional_features=()
        [[ -n "${SMTP_HOST:-}" ]] && optional_features+=("SMTP")
        [[ -n "${BACKUP_REMOTE:-}" ]] && optional_features+=("Backup")
        [[ -n "${ALERT_EMAIL:-}" ]] && optional_features+=("Alerts")

        if [[ ${#optional_features[@]} -gt 0 ]]; then
            echo -e "${BLUE}ℹ️  Optional Features${NC}: ${optional_features[*]} configured"
        else
            echo -e "${YELLOW}🟡 Optional Features${NC}: None configured (SMTP, Backup, Alerts)"
        fi

    else
        echo -e "${RED}🔴 settings.env${NC}: Configuration file not found"
        echo "  💡 Copy from settings.env.example and configure"
    fi

    echo ""
}

# ================================
# COMPREHENSIVE HEALTH CHECK
# ================================

run_comprehensive_diagnostics() {
    echo -e "${BOLD}${CYAN}VaultWarden-OCI Comprehensive Diagnostics${NC}"
    echo -e "${BOLD}Unified Configuration v$MONITORING_CONFIG_VERSION${NC}"
    echo "Framework components: ${loaded_frameworks[*]:-none}"
    echo "Configuration sources: $MONITORING_CONFIG_SOURCES"
    echo "======================================================================="
    echo ""

    # Run all diagnostic modules
    run_unified_system_diagnostics
    run_unified_sqlite_diagnostics  
    run_unified_container_diagnostics
    run_network_diagnostics
    run_configuration_validation

    # Overall health summary
    log_step "Overall Health Summary"

    # Use unified metrics for final assessment
    local system_metrics
    system_metrics=$(get_unified_system_metrics)
    eval "$system_metrics"

    local issues=0
    local warnings=0

    # Count issues using unified evaluation
    case "$(evaluate_cpu_threshold "$cpu_usage")" in
        "critical"|"alert") ((issues++)) ;;
        "warning") ((warnings++)) ;;
    esac

    case "$(evaluate_memory_threshold "$mem_usage_pct")" in
        "critical"|"alert") ((issues++)) ;;
        "warning") ((warnings++)) ;;
    esac

    case "$(evaluate_load_threshold "$load_1m")" in
        "critical"|"alert") ((issues++)) ;;
        "warning") ((warnings++)) ;;
    esac

    # Final status
    if [[ $issues -gt 0 ]]; then
        echo -e "${RED}🚨 CRITICAL${NC}: $issues critical issues detected"
        echo "  💡 Immediate attention required"
        exit 1
    elif [[ $warnings -gt 0 ]]; then
        echo -e "${YELLOW}⚠️  WARNINGS${NC}: $warnings warnings detected"
        echo "  💡 Monitor closely, consider optimization"
        exit 1
    else
        echo -e "${GREEN}✅ HEALTHY${NC}: All systems operating within unified thresholds"
        echo "  🎯 Optimized for 1 OCPU/6GB OCI A1 Flex"
        exit 0
    fi
}

# ================================
# MAIN EXECUTION
# ================================

show_help() {
    cat <<EOF
VaultWarden-OCI Unified Diagnostics v$MONITORING_CONFIG_VERSION

Usage: $0 [options]

Options:
    --system        Run system diagnostics only
    --sqlite        Run SQLite diagnostics only  
    --containers    Run container diagnostics only
    --network       Run network connectivity tests only
    --config        Run configuration validation only
    --help, -h      Show this help message
    (no options)    Run comprehensive diagnostics

Features:
    ✅ Unified threshold configuration across all scripts
    ✅ Consistent variable names and evaluation logic
    ✅ Framework integration with graceful fallbacks
    ✅ Optimized for 1 OCPU/6GB OCI A1 Flex deployment
    ✅ Detailed remediation suggestions for each issue

Unified Configuration:
    Sources: $MONITORING_CONFIG_SOURCES
    CPU Thresholds: ${CPU_WARNING_THRESHOLD}%/${CPU_ALERT_THRESHOLD}%/${CPU_CRITICAL_THRESHOLD}%
    Memory Thresholds: ${MEMORY_WARNING_THRESHOLD}%/${MEMORY_ALERT_THRESHOLD}%/${MEMORY_CRITICAL_THRESHOLD}%
    Load Thresholds: ${LOAD_WARNING_THRESHOLD}/${LOAD_ALERT_THRESHOLD}/${LOAD_CRITICAL_THRESHOLD} (1 OCPU)
    SQLite Size Threshold: ${SQLITE_SIZE_ALERT_MB}MB

Examples:
    $0                  # Comprehensive diagnostics
    $0 --system         # System resources only
    $0 --sqlite         # Database analysis only
    $0 --containers     # Container status only

EOF
}

# Parse arguments
case "${1:-}" in
    --system)
        run_unified_system_diagnostics
        ;;
    --sqlite)
        run_unified_sqlite_diagnostics
        ;;
    --containers)
        run_unified_container_diagnostics
        ;;
    --network)
        run_network_diagnostics
        ;;
    --config)
        run_configuration_validation
        ;;
    --help|-h)
        show_help
        exit 0
        ;;
    "")
        run_comprehensive_diagnostics
        ;;
    *)
        echo "Unknown option: $1" >&2
        echo "Use --help for usage information"
        exit 1
        ;;
esac
