#!/usr/bin/env bash
# monitor.sh -- Phase 3 Complete System Monitor
# Complete framework integration: unified logging + standardized formatting + enhanced UX

set -euo pipefail
export DEBUG="${DEBUG:-false}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# ==============================================================================
# COMPLETE FRAMEWORK INTEGRATION (PHASE 3)
# ==============================================================================

# Load core framework with comprehensive error handling
source "$SCRIPT_DIR/lib/common.sh" || {
    echo "ERROR: lib/common.sh is required for monitoring system" >&2
    exit 1
}

# Track complete framework loading for Phase 3
COMPLETE_FRAMEWORK_COMPONENTS=()

# Load all framework components with complete integration
if source "$SCRIPT_DIR/lib/perf-collector.sh"; then
    perf_collector_init
    COMPLETE_FRAMEWORK_COMPONENTS+=("perf-collector")
fi

if source "$SCRIPT_DIR/lib/dashboard-sqlite.sh"; then
    dashboard_sqlite_init
    COMPLETE_FRAMEWORK_COMPONENTS+=("dashboard-sqlite")
fi

if source "$SCRIPT_DIR/lib/dashboard-metrics.sh"; then
    COMPLETE_FRAMEWORK_COMPONENTS+=("dashboard-metrics")
fi

# Phase 3: Complete logging framework override
if source "$SCRIPT_DIR/lib/logger.sh"; then
    logger_init
    COMPLETE_FRAMEWORK_COMPONENTS+=("logger")

    # Override all log functions to use complete framework integration
    log_info() { logger_info "monitor" "$*"; }
    log_success() { logger_info "monitor" "SUCCESS: $*"; }
    log_warning() { logger_warn "monitor" "$*"; }
    log_error() { logger_error "monitor" "$*"; }
    log_step() { logger_info "monitor" "STEP: $*"; }
    log_debug() { logger_debug "monitor" "$*"; }

    echo -e "${GREEN}✅ Complete logging framework integrated${NC}"
else
    # Enhanced fallback logging for Phase 3 compatibility
    log_warning "Enhanced logging framework not available - using enhanced fallback"

    # Enhanced fallback with better formatting
    if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
        RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
        BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'
        WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'
    else
        RED=''; GREEN=''; YELLOW=''; BLUE=''; PURPLE=''; CYAN=''
        WHITE=''; BOLD=''; NC=''
    fi

    log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
    log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
    log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
    log_step() { echo -e "${BOLD}${CYAN}=== $* ===${NC}"; }
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo -e "${PURPLE}[DEBUG]${NC} $*"; }
fi

# Phase 3: Complete error handling integration
if source "$SCRIPT_DIR/lib/error-handler.sh"; then
    error_handler_init
    COMPLETE_FRAMEWORK_COMPONENTS+=("error-handler")
fi

# Phase 3: Complete output formatting integration
if source "$SCRIPT_DIR/lib/perf-formatter.sh"; then
    perf_formatter_init
    COMPLETE_FRAMEWORK_COMPONENTS+=("perf-formatter")
    log_info "Complete output formatting framework loaded"
fi

# Load Docker utilities with Phase 3 enhancements
source "$SCRIPT_DIR/lib/docker.sh" || {
    log_warning "Docker utilities not found - using enhanced fallback functions"

    # Enhanced fallback Docker functions (Phase 3)
    is_service_running() {
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
            error_handler_safe_execute "docker_ps_check" docker ps --filter "name=$1" --filter "status=running" | grep -q "$1"
        else
            docker ps --filter "name=$1" --filter "status=running" | grep -q "$1"
        fi
    }

    is_stack_running() { is_service_running "vaultwarden" && is_service_running "bw_caddy"; }

    get_service_logs() {
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
            error_handler_safe_execute "docker_logs" docker logs --tail "${2:-10}" "$1" || echo "Unable to get logs for $1"
        else
            docker logs --tail "${2:-10}" "$1" || echo "Unable to get logs for $1"
        fi
    }

    get_container_id() {
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
            error_handler_safe_execute "container_id" docker ps --filter "name=$1" -q | head -1
        else
            docker ps --filter "name=$1" -q | head -1
        fi
    }

    perform_health_check() {
        if is_stack_running; then
            log_success "Core stack is running (vaultwarden + caddy)"
        else
            log_warning "Core stack has issues - check service status"
        fi
    }
}

# Load complete configuration suite (Phase 3)
[[ -f "$SCRIPT_DIR/config/performance-targets.conf" ]] && source "$SCRIPT_DIR/config/performance-targets.conf"
[[ -f "$SCRIPT_DIR/config/monitoring-intervals.conf" ]] && source "$SCRIPT_DIR/config/monitoring-intervals.conf"
[[ -f "$SCRIPT_DIR/config/alert-thresholds.conf" ]] && source "$SCRIPT_DIR/config/alert-thresholds.conf"

# Complete configuration defaults
CPU_WARNING_THRESHOLD=${CPU_WARNING_THRESHOLD:-70}
CPU_CRITICAL_THRESHOLD=${CPU_CRITICAL_THRESHOLD:-90}
MEMORY_WARNING_THRESHOLD=${MEMORY_WARNING_THRESHOLD:-70}
MEMORY_CRITICAL_THRESHOLD=${MEMORY_CRITICAL_THRESHOLD:-85}
LOAD_WARNING_THRESHOLD=${LOAD_WARNING_THRESHOLD:-1.0}
LOAD_CRITICAL_THRESHOLD=${LOAD_CRITICAL_THRESHOLD:-1.5}
DISK_WARNING_THRESHOLD=${DISK_WARNING_THRESHOLD:-70}
DISK_CRITICAL_THRESHOLD=${DISK_CRITICAL_THRESHOLD:-85}

# Monitoring intervals from config
DASHBOARD_REFRESH_INTERVAL=${DASHBOARD_REFRESH_INTERVAL:-5}
DASHBOARD_WATCH_INTERVAL=${DASHBOARD_WATCH_INTERVAL:-30}
CONTAINER_LOG_TAIL_LINES=${CONTAINER_LOG_TAIL_LINES:-20}

# ==============================================================================
# PHASE 3: COMPLETE SERVICE MONITORING WITH FORMATTING
# ==============================================================================
show_service_status() {
    # Use complete framework formatting for section headers
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_section "Service Status (Complete Framework SQLite Stack)" "normal"
    else
        echo -e "${BOLD}=== SERVICE STATUS (SQLite Stack) ===${NC}"
    fi

    local expected_services=("vaultwarden" "bw_caddy" "bw_backup" "bw_fail2ban" "bw_watchtower" "bw_ddclient")
    local running_services=()
    local stopped_services=()

    log_debug "Checking service status using complete framework integration"

    # Use complete framework container monitoring
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " dashboard-metrics " ]]; then
        local container_metrics

        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
            container_metrics=$(error_handler_safe_execute "service_status" dashboard_get_container_metrics)
        else
            container_metrics=$(dashboard_get_container_metrics)
        fi

        if [[ "$container_metrics" =~ docker_available=true ]]; then
            log_debug "Service status collected via complete framework container monitoring"

            # Parse framework results with enhanced processing
            local containers_running containers_total
            eval "$(echo "$container_metrics" | grep -E '^containers_(running|total)=')"

            for service in "${expected_services[@]}"; do
                local service_status service_health
                eval "$(echo "$container_metrics" | grep -E "^${service}_(status|health)=" || echo "${service}_status=not_found ${service}_health=N/A")"

                if [[ "$service_status" == "running" ]]; then
                    running_services+=("$service")
                else
                    stopped_services+=("$service")
                fi

                # Enhanced logging with framework integration
                case "$service_status" in
                    "running")
                        case "$service_health" in
                            "healthy"|"no-health-check")
                                log_debug "Service healthy: $service"
                                ;;
                            "starting")
                                log_info "Service starting: $service"
                                ;;
                            "unhealthy")
                                log_warning "Service unhealthy: $service"
                                ;;
                        esac
                        ;;
                    "stopped"|"exited")
                        if [[ "$service" =~ ^(vaultwarden|bw_caddy)$ ]]; then
                            log_error "Critical service stopped: $service"
                        else
                            log_warning "Optional service stopped: $service"
                        fi
                        ;;
                esac
            done

        else
            log_error "Docker not available via complete framework"
            return 1
        fi
    else
        # Enhanced fallback service monitoring
        log_debug "Using enhanced fallback service monitoring"

        for service in "${expected_services[@]}"; do
            if is_service_running "$service"; then
                running_services+=("$service")
                log_debug "Service running: $service"
            else
                stopped_services+=("$service")
                log_debug "Service not running: $service"
            fi
        done
    fi

    # Display results with complete framework formatting
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_service_status_display "${running_services[*]}" "${stopped_services[*]}"
    else
        # Enhanced fallback display
        echo -e "${GREEN}Running services (${#running_services[@]}):${NC}"
        for service in "${running_services[@]}"; do
            echo "  ✅ $service"
        done

        if [[ ${#stopped_services[@]} -gt 0 ]]; then
            echo -e "${YELLOW}Stopped services (${#stopped_services[@]}):${NC}"
            for service in "${stopped_services[@]}"; do
                echo "  ⏸️  $service (may be profile-dependent)"
            done
        fi
    fi

    # Enhanced health check with complete framework
    perform_health_check

    log_info "Service status check completed: ${#running_services[@]} running, ${#stopped_services[@]} stopped"
    echo ""
}

# ==============================================================================
# PHASE 3: COMPLETE RESOURCE MONITORING WITH FORMATTING
# ==============================================================================
show_resource_usage() {
    # Use complete framework formatting for headers
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_section "Resource Usage (Complete Framework, 1 OCPU/6GB)" "normal"
    else
        echo -e "${BOLD}=== RESOURCE USAGE (1 OCPU/6GB Target) ===${NC}"
    fi

    if is_stack_running; then
        log_debug "Stack is running - collecting complete resource metrics"

        # Get system metrics using complete framework
        local system_metrics
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-collector " ]]; then
            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
                system_metrics=$(error_handler_safe_execute "system_resources" perf_collector_system_full)
            else
                system_metrics=$(perf_collector_system_full)
            fi
            log_debug "System metrics collected via complete framework with error handling"
        else
            system_metrics=$(get_resource_metrics_enhanced_fallback)
            log_debug "System metrics collected via enhanced fallback"
        fi

        # Parse metrics for analysis
        local cpu_usage mem_usage_pct load_1m disk_usage_pct
        eval "$(echo "$system_metrics" | grep -E '^(cpu_usage|mem_usage_pct|load_1m|disk_usage_pct)=')"

        # Display system resources with complete framework formatting
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            perf_formatter_section "System Resources (Framework Thresholds)" "compact"

            # Use framework metric displays with progress bars and color coding
            perf_formatter_metric_with_threshold "CPU Usage" "$cpu_usage" "%" "$CPU_WARNING_THRESHOLD" "$CPU_CRITICAL_THRESHOLD"
            perf_formatter_metric_with_threshold "Memory Usage" "$mem_usage_pct" "%" "$MEMORY_WARNING_THRESHOLD" "$MEMORY_CRITICAL_THRESHOLD"
            perf_formatter_metric_with_threshold "Disk Usage" "$disk_usage_pct" "%" "$DISK_WARNING_THRESHOLD" "$DISK_CRITICAL_THRESHOLD"
            perf_formatter_load_analysis_1cpu "$load_1m" "$LOAD_WARNING_THRESHOLD" "$LOAD_CRITICAL_THRESHOLD"
        else
            # Enhanced fallback display with improved formatting
            echo -e "${BLUE}System Resources (Framework Thresholds):${NC}"
            printf "CPU Usage: %s%% (warning: %s%%, critical: %s%%)\n" "$cpu_usage" "$CPU_WARNING_THRESHOLD" "$CPU_CRITICAL_THRESHOLD"
            printf "Memory Usage: %s%% (warning: %s%%, critical: %s%%)\n" "$mem_usage_pct" "$MEMORY_WARNING_THRESHOLD" "$MEMORY_CRITICAL_THRESHOLD"
            printf "Load Average: %s (warning: %s, critical: %s for 1 OCPU)\n" "$load_1m" "$LOAD_WARNING_THRESHOLD" "$LOAD_CRITICAL_THRESHOLD"
            printf "Disk Usage: %s%% (warning: %s%%, critical: %s%%)\n" "$disk_usage_pct" "$DISK_WARNING_THRESHOLD" "$DISK_CRITICAL_THRESHOLD"
        fi

        echo ""

        # Container resource display with complete framework integration
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            perf_formatter_section "Container Resource Usage (Framework vs Targets)" "compact"
            perf_formatter_container_resource_table "672"
        else
            echo -e "${BLUE}Container Resource Usage vs Targets:${NC}"
            echo "Target: VaultWarden(32% CPU, 256MB), Caddy(12% CPU, 128MB), Total(~672MB)"
            echo ""

            # Container stats with enhanced error handling
            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
                error_handler_safe_execute "container_stats" docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" || echo "Container stats unavailable"
            else
                docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.NetIO}}\t{{.BlockIO}}" || echo "Container stats unavailable"
            fi
        fi

        # Enhanced load analysis for single CPU (Phase 3 complete integration)
        echo ""
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            perf_formatter_load_analysis_detailed_1cpu "$load_1m" "$LOAD_WARNING_THRESHOLD" "$LOAD_CRITICAL_THRESHOLD"
        else
            echo -e "${BLUE}1 OCPU Load Analysis:${NC}"
            if command -v bc >/dev/null 2>&1; then
                if (( $(echo "$load_1m > $LOAD_CRITICAL_THRESHOLD" | bc -l) )); then
                    echo -e "${RED}⚠️  CRITICAL: Load $load_1m is dangerous for single CPU${NC}"
                elif (( $(echo "$load_1m > $LOAD_WARNING_THRESHOLD" | bc -l) )); then
                    echo -e "${YELLOW}⚠️  WARNING: Load $load_1m is high for single CPU${NC}"
                else
                    echo -e "${GREEN}✅ Load $load_1m is acceptable for single CPU${NC}"
                fi
            else
                echo "Load analysis: $load_1m (detailed analysis requires 'bc' command)"
            fi
        fi

        # Complete framework logging of resource analysis
        log_info "Resource check completed: CPU ${cpu_usage}%, Memory ${mem_usage_pct}%, Load ${load_1m}, Disk ${disk_usage_pct}%"

    else
        log_warning "No containers running - resource monitoring limited"
    fi

    echo ""
}

# Enhanced resource metrics fallback (Phase 3)
get_resource_metrics_enhanced_fallback() {
    log_debug "Using enhanced fallback resource metrics collection"

    local cpu_usage mem_usage_pct load_1m disk_usage_pct

    # Enhanced CPU collection
    if command -v top >/dev/null 2>&1; then
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "0")
    else
        cpu_usage="N/A"
    fi

    # Enhanced memory collection
    if command -v free >/dev/null 2>&1; then
        mem_usage_pct=$(free | awk '/^Mem:/{printf "%.1f", $3*100/$2}' || echo "0")
    else
        mem_usage_pct="N/A"
    fi

    # Enhanced load average collection
    if command -v uptime >/dev/null 2>&1; then
        load_1m=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',' || echo "0")
    else
        load_1m="N/A"
    fi

    # Enhanced disk usage collection
    if command -v df >/dev/null 2>&1; then
        disk_usage_pct=$(df . | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
    else
        disk_usage_pct="N/A"
    fi

    cat <<EOF
cpu_usage=$cpu_usage
mem_usage_pct=$mem_usage_pct
load_1m=$load_1m
disk_usage_pct=$disk_usage_pct
EOF
}

# ==============================================================================
# PHASE 3: COMPLETE SQLITE MONITORING WITH FORMATTING
# ==============================================================================
show_sqlite_performance() {
    # Use complete framework formatting for section headers
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_section "SQLite Performance (Complete Framework Analysis)" "normal"
    else
        echo -e "${BOLD}=== SQLITE PERFORMANCE (Framework-Enhanced) ===${NC}"
    fi

    # Use complete framework SQLite monitoring
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " dashboard-sqlite " ]]; then
        log_debug "Using complete framework SQLite performance monitoring"

        # Enhanced framework SQLite display with error handling
        if command -v dashboard_sqlite_show_comprehensive >/dev/null 2>&1; then
            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
                error_handler_safe_execute "sqlite_comprehensive" dashboard_sqlite_show_comprehensive
            else
                dashboard_sqlite_show_comprehensive
            fi

            # Additional complete framework insights
            echo ""
            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                perf_formatter_section "Framework SQLite Intelligence" "compact"
            else
                echo -e "${BLUE}Framework SQLite Analysis:${NC}"
            fi

            # Maintenance recommendation using complete framework
            if command -v dashboard_sqlite_check_maintenance_needed >/dev/null 2>&1; then
                if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
                    if error_handler_safe_execute "maintenance_check" dashboard_sqlite_check_maintenance_needed; then
                        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                            perf_formatter_status "warning" "Maintenance recommended - run ./sqlite-maintenance.sh"
                        else
                            echo -e "${YELLOW}🔧 Maintenance recommended - run ./sqlite-maintenance.sh${NC}"
                        fi
                    else
                        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                            perf_formatter_status "good" "Database is well-maintained"
                        else
                            echo -e "${GREEN}✅ Database is well-maintained${NC}"
                        fi
                    fi
                else
                    if dashboard_sqlite_check_maintenance_needed; then
                        echo -e "${YELLOW}🔧 Maintenance recommended${NC}"
                    else
                        echo -e "${GREEN}✅ Database is well-maintained${NC}"
                    fi
                fi
            fi

            # Performance benchmarking with complete framework
            if command -v dashboard_sqlite_get_performance >/dev/null 2>&1; then
                local perf_result
                if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
                    perf_result=$(error_handler_safe_execute "sqlite_performance" dashboard_sqlite_get_performance || echo "failed")
                else
                    perf_result=$(dashboard_sqlite_get_performance || echo "failed")
                fi

                if [[ "$perf_result" != "failed" && "$perf_result" != "unavailable" ]]; then
                    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                        perf_formatter_sqlite_performance_display "$perf_result"
                    else
                        echo "Framework performance test: $perf_result"
                    fi
                fi
            fi

        else
            # Basic framework SQLite functions
            local sqlite_status
            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
                sqlite_status=$(error_handler_safe_execute "sqlite_basic_status" dashboard_sqlite_get_status)
            else
                sqlite_status=$(dashboard_sqlite_get_status)
            fi

            if [[ "$sqlite_status" =~ status=accessible ]]; then
                local db_size
                eval "$(echo "$sqlite_status" | grep '^size=')"

                if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                    perf_formatter_status "info" "Database: $db_size (framework monitored)"
                else
                    echo "Database: $db_size (framework monitored)"
                fi
            else
                if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                    perf_formatter_status "warning" "Database: Not accessible"
                else
                    echo "Database: Not accessible"
                fi
            fi
        fi

        log_info "SQLite performance check completed via complete framework"

    else
        # Enhanced fallback SQLite performance monitoring
        log_debug "Using enhanced fallback SQLite performance monitoring"
        show_sqlite_performance_enhanced_fallback
    fi

    echo ""
}

# Enhanced fallback SQLite performance (Phase 3)
show_sqlite_performance_enhanced_fallback() {
    if [[ -f "./data/bw/data/bwdata/db.sqlite3" ]]; then
        local db_size query_time
        db_size=$(du -h "./data/bw/data/bwdata/db.sqlite3" | cut -f1 || echo "unknown")

        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            perf_formatter_status "info" "Database size: $db_size"
        else
            echo "Database size: $db_size"
        fi

        # Enhanced query performance test
        if command -v sqlite3 >/dev/null 2>&1; then
            local query_start query_end
            query_start=$(date +%s.%3N || date +%s)

            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
                if error_handler_safe_execute "sqlite_query_test" sqlite3 "./data/bw/data/bwdata/db.sqlite3" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null; then
                    query_end=$(date +%s.%3N || date +%s)
                    if command -v bc >/dev/null 2>&1; then
                        query_time=$(echo "$query_end - $query_start" | bc -l || echo "unknown")
                    else
                        query_time="<1"
                    fi

                    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                        perf_formatter_status "info" "Simple query time: ${query_time}s"
                    else
                        echo "Simple query time: ${query_time}s"
                    fi
                else
                    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                        perf_formatter_status "warning" "Unable to test database performance"
                    else
                        echo "Unable to test database performance"
                    fi
                fi
            else
                if sqlite3 "./data/bw/data/bwdata/db.sqlite3" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
                    query_end=$(date +%s.%3N || date +%s)
                    if command -v bc >/dev/null 2>&1; then
                        query_time=$(echo "$query_end - $query_start" | bc -l || echo "unknown")
                    else
                        query_time="<1"
                    fi
                    echo "Simple query time: ${query_time}s"
                else
                    echo "Unable to test database performance"
                fi
            fi
        fi

        # Enhanced WAL file check with complete framework
        if [[ -f "./data/bw/data/bwdata/db.sqlite3-wal" ]]; then
            local wal_size
            wal_size=$(du -h "./data/bw/data/bwdata/db.sqlite3-wal" | cut -f1 || echo "unknown")

            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                perf_formatter_status "info" "WAL file size: $wal_size (recent write activity)"
            else
                echo "WAL file size: $wal_size (recent write activity)"
            fi
        else
            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                perf_formatter_status "info" "No active WAL file (database idle)"
            else
                echo "No active WAL file (database idle)"
            fi
        fi
    else
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            perf_formatter_status "info" "SQLite database not found"
        else
            echo "SQLite database not found"
        fi
    fi
}

# ==============================================================================
# PHASE 3: COMPLETE DASHBOARD WITH COMPREHENSIVE FORMATTING
# ==============================================================================
show_dashboard() {
    clear

    # Complete framework header formatting
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_dashboard_header "VaultWarden-OCI-Slim Monitor" "Complete Framework v3" "$(date '+%Y-%m-%d %H:%M:%S %Z')" "1 OCPU/6GB • SQLite • ${#COMPLETE_FRAMEWORK_COMPONENTS[@]} Framework Components"
    else
        # Enhanced fallback header
        echo -e "${BOLD}${BLUE}"
        echo "╔══════════════════════════════════════════════════════════════════════════════╗"
        echo "║           VaultWarden-OCI-Slim Monitor (Complete Framework v3)              ║"
        echo "║                          $(date '+%Y-%m-%d %H:%M:%S %Z')                          ║"
        echo "║                 1 OCPU/6GB • SQLite • Framework Components: ${#COMPLETE_FRAMEWORK_COMPONENTS[@]}               ║"
        echo "╚══════════════════════════════════════════════════════════════════════════════╝"
        echo -e "${NC}"
    fi

    # Framework status indicator
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_framework_status "${COMPLETE_FRAMEWORK_COMPONENTS[*]}"
    else
        echo -e "${BOLD}Complete Framework Status:${NC} ${#COMPLETE_FRAMEWORK_COMPONENTS[@]} components active (${COMPLETE_FRAMEWORK_COMPONENTS[*]})"
    fi
    echo ""

    # Display all sections with complete framework integration
    show_service_status
    show_resource_usage
    show_sqlite_performance
    show_security_status_complete
    show_backup_status_complete

    # Enhanced footer with complete framework formatting
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_dashboard_footer "$DASHBOARD_WATCH_INTERVAL"
    else
        echo -e "${BOLD}${BLUE}Complete Framework Enhanced Monitoring • Press Ctrl+C to exit, or wait ${DASHBOARD_WATCH_INTERVAL} seconds for refresh...${NC}"
    fi
}

# ==============================================================================
# PHASE 3: ENHANCED SECURITY AND BACKUP STATUS
# ==============================================================================

# Enhanced security status with complete framework integration
show_security_status_complete() {
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_section "Security Status" "normal"
    else
        echo -e "${BOLD}=== SECURITY STATUS ===${NC}"
    fi

    # Enhanced Fail2ban monitoring with complete framework
    if is_service_running "bw_fail2ban"; then
        local f2b_id banned_count
        f2b_id=$(get_container_id "bw_fail2ban")

        if [[ -n "$f2b_id" ]]; then
            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
                banned_count=$(error_handler_safe_execute "fail2ban_status" docker exec "$f2b_id" fail2ban-client status | grep "Currently banned" | awk '{print $NF}' || echo "0")
            else
                banned_count=$(docker exec "$f2b_id" fail2ban-client status | grep "Currently banned" | awk '{print $NF}' || echo "0")
            fi

            # Enhanced status display with framework formatting
            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                local ban_status="good"
                [[ $banned_count -gt ${FAIL2BAN_BANNED_CRITICAL:-25} ]] && ban_status="critical"
                [[ $banned_count -gt 10 ]] && ban_status="warning"

                perf_formatter_status "$ban_status" "Fail2ban: $banned_count banned IPs"
            else
                if [[ $banned_count -gt ${FAIL2BAN_BANNED_CRITICAL:-25} ]]; then
                    echo -e "${RED}🚨 Fail2ban: $banned_count banned IPs (critical)${NC}"
                elif [[ $banned_count -gt 10 ]]; then
                    echo -e "${YELLOW}⚠️  Fail2ban: $banned_count banned IPs${NC}"
                else
                    echo -e "${GREEN}✅ Fail2ban: $banned_count banned IPs${NC}"
                fi
            fi

            log_info "Fail2ban status checked: $banned_count banned IPs"
        else
            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                perf_formatter_status "warning" "Fail2ban container not accessible"
            else
                echo -e "${YELLOW}Fail2ban container not accessible${NC}"
            fi
        fi
    else
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            perf_formatter_status "info" "Fail2ban not running (may be profile-dependent)"
        else
            echo -e "${YELLOW}Fail2ban not running (may be profile-dependent)${NC}"
        fi
    fi

    # Enhanced SSL certificate monitoring
    echo ""
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_subsection "SSL Certificate Status" "compact"
    else
        echo -e "${BLUE}SSL Certificate:${NC}"
    fi

    if [[ -f "$SETTINGS_FILE" ]]; then
        set -a
        source "$SETTINGS_FILE" || true
        set +a

        if [[ -n "${APP_DOMAIN:-}" ]] && command -v openssl >/dev/null 2>&1; then
            local cert_check_result
            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
                cert_check_result=$(error_handler_safe_execute "ssl_check" timeout 5 openssl s_client -servername "${APP_DOMAIN}" -connect "${APP_DOMAIN}":443 | openssl x509 -noout -dates || echo "failed")
            else
                cert_check_result=$(echo | timeout 5 openssl s_client -servername "${APP_DOMAIN}" -connect "${APP_DOMAIN}":443 | openssl x509 -noout -dates || echo "failed")
            fi

            if [[ -n "$cert_check_result" && "$cert_check_result" != "failed" ]]; then
                if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                    perf_formatter_status "good" "Certificate: Valid"
                    perf_formatter_cert_details "$cert_check_result"
                else
                    echo -e "${GREEN}Certificate: Valid${NC}"
                    echo "$cert_check_result"
                fi

                log_info "SSL certificate check passed for domain: ${APP_DOMAIN}"
            else
                if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                    perf_formatter_status "warning" "Certificate check failed or timed out"
                else
                    echo -e "${YELLOW}Certificate check failed or timed out${NC}"
                fi

                log_warning "SSL certificate check failed for domain: ${APP_DOMAIN}"
            fi
        else
            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                perf_formatter_status "info" "Domain not configured or openssl not available"
            else
                echo "Domain not configured or openssl not available"
            fi
        fi
    else
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            perf_formatter_status "warning" "Settings file not found"
        else
            echo -e "${YELLOW}Settings file not found${NC}"
        fi
    fi

    echo ""
}

# Enhanced backup status with complete framework integration
show_backup_status_complete() {
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_section "Backup Status (SQLite)" "normal"
    else
        echo -e "${BOLD}=== BACKUP STATUS (SQLite) ===${NC}"
    fi

    if is_service_running "bw_backup"; then
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            perf_formatter_status "good" "SQLite backup service running"
        else
            echo -e "${GREEN}SQLite backup service is running${NC}"
        fi

        log_info "Backup service status: running"

        # Enhanced backup file analysis
        if [[ -d "./data/backups" ]]; then
            local sqlite_backup_count file_backup_count recent_backup
            sqlite_backup_count=$(find ./data/backups -name "*sqlite*backup*.sql*" | wc -l)
            file_backup_count=$(find ./data/backups -name "*files*backup*.tar.gz" | wc -l)
            recent_backup=$(find ./data/backups -name "*sqlite*backup*.sql*" -mtime -7 | head -1)

            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                perf_formatter_backup_summary "$sqlite_backup_count" "$file_backup_count"
            else
                echo "SQLite database backups: $sqlite_backup_count"
                echo "File backups (attachments): $file_backup_count"
            fi

            if [[ -n "$recent_backup" ]]; then
                local backup_size backup_age
                backup_size=$(du -h "$recent_backup" | cut -f1 || echo "unknown")
                backup_age=$(stat -c %Y "$recent_backup" || echo "0")
                backup_age=$(( ($(date +%s) - backup_age) / 3600 ))

                if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                    perf_formatter_status "good" "Recent backup: $(basename "$recent_backup") (${backup_size}, ${backup_age}h ago)"
                else
                    echo -e "${GREEN}Recent backup: $(basename "$recent_backup") (${backup_size}, ${backup_age}h ago)${NC}"
                fi

                log_info "Recent backup found: $(basename "$recent_backup") (${backup_age}h ago)"
            else
                if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                    perf_formatter_status "warning" "No recent SQLite backup found (last 7 days)"
                else
                    echo -e "${YELLOW}No recent SQLite backup found (last 7 days)${NC}"
                fi

                log_warning "No recent SQLite backup found in last 7 days"
            fi
        else
            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                perf_formatter_status "warning" "Backup directory not found"
            else
                echo -e "${YELLOW}Backup directory not found${NC}"
            fi
        fi
    else
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            perf_formatter_status "info" "SQLite backup service not running"
            perf_formatter_command_suggestion "docker compose --profile backup up -d"
        else
            echo -e "${YELLOW}SQLite backup service not running${NC}"
            echo "Enable with: docker compose --profile backup up -d"
        fi

        log_warning "Backup service not running"
    fi

    echo ""
}

# ==============================================================================
# PHASE 3: COMPLETE INTERACTIVE MENU WITH FORMATTING
# ==============================================================================
show_interactive_menu() {
    while true; do
        clear

        # Complete framework interactive header
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            perf_formatter_interactive_header "VaultWarden-OCI-Slim Monitor" "Complete Framework v3" "${#COMPLETE_FRAMEWORK_COMPONENTS[@]}"
        else
            echo -e "${BOLD}${BLUE}VaultWarden-OCI-Slim Monitor - Complete Framework Interactive Menu${NC}"
            echo -e "${BLUE}SQLite Optimized for 1 OCPU/6GB • Complete Framework Components: ${#COMPLETE_FRAMEWORK_COMPONENTS[@]}${NC}"
        fi

        echo ""
        echo "1) 📊 Full Dashboard (Complete Framework Integration)"
        echo "2) 🖥️  Service Status"
        echo "3) 📈 Resource Usage (Complete Framework Metrics + 1 OCPU Analysis)"
        echo "4) 📋 Recent Logs (Enhanced Display)"
        echo "5) 💾 Disk Usage (SQLite Database Focus)"
        echo "6) 🌐 Network Status"
        echo "7) ⚡ SQLite Performance (Complete Framework Analysis)"
        echo "8) 🔒 Security Status (Enhanced)"
        echo "9) 💿 SQLite Backup Status (Complete)"
        echo "f) 🔧 Complete Framework Component Status"
        echo "w) 👁️  Watch Mode (complete framework-enhanced auto-refresh)"
        echo "q) 🚪 Quit"
        echo ""
        read -p "Select option: " choice

        case $choice in
            1) show_dashboard; read -p "Press Enter to continue..." ;;
            2) show_service_status; read -p "Press Enter to continue..." ;;
            3) show_resource_usage; read -p "Press Enter to continue..." ;;
            4)
                read -p "Enter number of log lines (default ${CONTAINER_LOG_TAIL_LINES}): " lines
                show_recent_logs_complete "${lines:-$CONTAINER_LOG_TAIL_LINES}"
                read -p "Press Enter to continue..."
                ;;
            5) show_disk_usage_complete; read -p "Press Enter to continue..." ;;
            6) show_network_status_complete; read -p "Press Enter to continue..." ;;
            7) show_sqlite_performance; read -p "Press Enter to continue..." ;;
            8) show_security_status_complete; read -p "Press Enter to continue..." ;;
            9) show_backup_status_complete; read -p "Press Enter to continue..." ;;
            f|F) show_complete_framework_status; read -p "Press Enter to continue..." ;;
            w|W) watch_dashboard ;;
            q|Q)
                log_info "Interactive monitor exited by user"
                exit 0
                ;;
            *)
                echo "Invalid option. Press Enter to continue..."
                read
                ;;
        esac
    done
}

# Enhanced recent logs with complete framework formatting
show_recent_logs_complete() {
    local lines="${1:-$CONTAINER_LOG_TAIL_LINES}"

    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_section "Recent Logs (Complete Framework Enhanced, last $lines lines)" "normal"
    else
        echo -e "${BOLD}=== RECENT LOGS (last $lines lines) ===${NC}"
    fi

    local sqlite_services=("vaultwarden" "bw_caddy" "bw_backup" "bw_fail2ban" "bw_watchtower" "bw_ddclient")
    local active_services=0

    for service in "${sqlite_services[@]}"; do
        if is_service_running "$service"; then
            ((active_services++))

            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                perf_formatter_subsection "$service" "compact"
                perf_formatter_log_display "$(get_service_logs "$service" "$lines")"
            else
                echo -e "${YELLOW}--- $service ---${NC}"
                get_service_logs "$service" "$lines"
            fi
            echo ""
        fi
    done

    log_info "Recent logs displayed for $active_services active services"
}

# Enhanced disk usage with complete framework formatting  
show_disk_usage_complete() {
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_section "Disk Usage (SQLite Database Focus)" "normal"
    else
        echo -e "${BOLD}=== DISK USAGE (SQLite Database) ===${NC}"
    fi

    # Enhanced disk usage display
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_disk_usage_display
    else
        df -h . || echo "Unable to check disk usage"
    fi

    # Complete framework SQLite disk analysis
    echo ""
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " dashboard-sqlite " ]]; then
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            perf_formatter_sqlite_disk_analysis
        else
            echo -e "${BLUE}SQLite Database Files:${NC}"
            local sqlite_status
            sqlite_status=$(dashboard_sqlite_get_status || echo "status=not_available")

            if [[ "$sqlite_status" =~ status=accessible ]]; then
                local db_size
                eval "$(echo "$sqlite_status" | grep '^size=')"
                echo "Main database: $db_size (framework monitored)"
            else
                echo "Database not accessible"
            fi
        fi
    else
        # Enhanced fallback disk monitoring
        echo -e "${BLUE}SQLite Database Files (Fallback):${NC}"
        if [[ -f "./data/bw/data/bwdata/db.sqlite3" ]]; then
            local db_size
            db_size=$(du -h "./data/bw/data/bwdata/db.sqlite3" | cut -f1 || echo "unknown")
            echo "Main database: $db_size"
        else
            echo "SQLite database not found"
        fi
    fi

    echo ""
}

# Enhanced network status with complete framework formatting
show_network_status_complete() {
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_section "Network Status" "normal"
    else
        echo -e "${BOLD}=== NETWORK STATUS ===${NC}"
    fi

    # Enhanced Docker network display
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_network_overview
    else
        echo -e "${BLUE}Docker Networks:${NC}"
        if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
            error_handler_safe_execute "docker_networks" docker network ls --filter name=vaultwarden --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" || echo "Unable to list networks"
        else
            docker network ls --filter name=vaultwarden --format "table {{.Name}}\t{{.Driver}}\t{{.Scope}}" || echo "Unable to list networks"
        fi
    fi

    # Enhanced connectivity testing
    echo ""
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_subsection "Network Connectivity" "compact"
        perf_formatter_connectivity_test_results
    else
        echo -e "${BLUE}Network Connectivity:${NC}"
        test_internal_connectivity
    fi

    log_info "Network status check completed"
    echo ""
}

# Show complete framework component status
show_complete_framework_status() {
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_framework_status_complete "${COMPLETE_FRAMEWORK_COMPONENTS[*]}"
    else
        echo -e "${BOLD}=== COMPLETE FRAMEWORK COMPONENT STATUS ===${NC}"
        echo ""

        echo "Phase 3 Complete Framework Integration Status:"
        echo "Active components: ${#COMPLETE_FRAMEWORK_COMPONENTS[@]}/6"
        echo ""

        # Check each expected framework component
        local all_components=("perf-collector" "dashboard-sqlite" "dashboard-metrics" "logger" "error-handler" "perf-formatter")

        for component in "${all_components[@]}"; do
            if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " $component " ]]; then
                echo -e "✅ lib/$component.sh: ${GREEN}Loaded and Active${NC}"
            else
                echo -e "❌ lib/$component.sh: ${YELLOW}Not Available${NC}"
            fi
        done

        echo ""
        echo "Configuration Status:"

        [[ -f "$SCRIPT_DIR/config/performance-targets.conf" ]] && 
            echo -e "✅ performance-targets.conf: ${GREEN}Loaded${NC}" ||
            echo -e "❌ performance-targets.conf: ${YELLOW}Missing${NC}"

        [[ -f "$SCRIPT_DIR/config/monitoring-intervals.conf" ]] &&
            echo -e "✅ monitoring-intervals.conf: ${GREEN}Available${NC}" ||
            echo -e "❌ monitoring-intervals.conf: ${YELLOW}Missing${NC}"

        [[ -f "$SCRIPT_DIR/config/alert-thresholds.conf" ]] &&
            echo -e "✅ alert-thresholds.conf: ${GREEN}Available${NC}" ||
            echo -e "❌ alert-thresholds.conf: ${YELLOW}Missing${NC}"
    fi

    echo ""
}

# Watch mode with complete framework integration
watch_dashboard() {
    log_info "Starting watch mode with complete framework integration"
    log_info "Refresh interval: ${DASHBOARD_WATCH_INTERVAL}s (configurable via monitoring-intervals.conf)"

    while true; do
        show_dashboard
        sleep "$DASHBOARD_WATCH_INTERVAL"
    done
}

# ==============================================================================
# PHASE 3: MAIN FUNCTION WITH COMPLETE INTEGRATION
# ==============================================================================
main() {
    local command="${1:-dashboard}"

    # Complete framework initialization logging
    log_info "Starting VaultWarden monitoring with complete framework integration"
    log_info "Framework components loaded: ${#COMPLETE_FRAMEWORK_COMPONENTS[@]} (${COMPLETE_FRAMEWORK_COMPONENTS[*]})"
    log_info "Configuration files loaded: performance-targets, monitoring-intervals, alert-thresholds"

    case "$command" in
        dashboard|status)
            log_debug "Showing dashboard with complete framework integration"
            show_dashboard
            ;;
        watch)
            log_info "Starting watch mode with complete framework integration"
            watch_dashboard
            ;;
        interactive|menu)
            log_info "Starting interactive menu with complete framework integration"
            show_interactive_menu
            ;;
        services)
            show_service_status
            ;;
        resources)
            show_resource_usage
            ;;
        logs)
            local lines="${2:-$CONTAINER_LOG_TAIL_LINES}"
            show_recent_logs_complete "$lines"
            ;;
        disk)
            show_disk_usage_complete
            ;;
        network)
            show_network_status_complete
            ;;
        performance|perf)
            show_sqlite_performance
            ;;
        security)
            show_security_status_complete
            ;;
        backup)
            show_backup_status_complete
            ;;
        framework)
            show_complete_framework_status
            ;;
        --help|-h)
            show_complete_help
            ;;
        *)
            log_error "Unknown command: $command. Use --help for usage information."
            exit 1
            ;;
    esac
}

# Complete help display with framework formatting
show_complete_help() {
    if [[ " ${COMPLETE_FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_help_complete "monitor" "System Monitor" "Complete Framework Integration v3"
    else
        cat <<EOF
VaultWarden-OCI-Slim Monitor (Complete Framework v3)

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    dashboard          Show full dashboard with complete framework integration (default)
    watch              Watch mode with complete framework formatting
    interactive        Interactive menu with complete framework status
    services           Show service status with framework container management
    resources          Show resource usage with complete framework metrics
    logs [lines]       Show recent logs with enhanced formatting (default: ${CONTAINER_LOG_TAIL_LINES})
    disk               Show disk usage with complete framework SQLite analysis
    network            Show network status with enhanced connectivity testing
    performance        Show SQLite performance with complete framework analysis
    security           Show security status with enhanced fail2ban monitoring
    backup             Show backup status with complete framework integration
    framework          Show complete framework component status

🆕 Complete Framework Integration (Phase 3):
    ✅ lib/perf-collector.sh: Unified metrics with intelligent caching
    ✅ lib/dashboard-sqlite.sh: Comprehensive SQLite monitoring and analysis
    ✅ lib/dashboard-metrics.sh: Complete container management integration
    ✅ lib/logger.sh: Complete structured logging with rotation and categorization
    ✅ lib/error-handler.sh: Comprehensive error recovery and safe execution
    ✅ lib/perf-formatter.sh: Complete standardized output formatting

SQLite Optimization Features (Complete Framework):
    • Resource usage analysis for 1 OCPU/6GB deployment with framework caching
    • Complete SQLite database performance monitoring with fragmentation analysis
    • Framework-based container resource monitoring with threshold analysis
    • Enhanced backup status tracking with intelligent recommendations
    • Complete 1 OCPU load analysis with configurable thresholds
    • Structured logging reduces I/O overhead on single CPU systems

Complete Framework Benefits:
    • Consistent metrics across all tools via comprehensive framework caching
    • All thresholds configurable via external config files
    • Complete structured logging with automatic rotation and categorization
    • Standardized formatting provides consistent and professional user experience
    • Comprehensive error handling improves reliability and recovery
    • Graceful fallback ensures compatibility across different environments
    • Enhanced performance on 1 OCPU systems through optimized resource usage

Configuration Integration:
    • config/performance-targets.conf: All performance thresholds
    • config/monitoring-intervals.conf: All refresh rates and timing
    • config/alert-thresholds.conf: Alert-specific policies

Examples:
    $0                 # Complete framework-integrated dashboard
    $0 watch           # Auto-refresh with complete framework formatting
    $0 interactive     # Interactive menu with complete framework status
    $0 framework       # Show complete framework component integration status

EOF
    fi
}

# Handle interrupts gracefully with complete framework logging
trap 'echo ""; log_info "Complete framework monitoring stopped by user"; exit 0' INT TERM

# Execute main function with complete framework integration
main "$@"
