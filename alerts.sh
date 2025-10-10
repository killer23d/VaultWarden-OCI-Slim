#!/usr/bin/env bash
# alerts.sh -- Phase 3 Complete Consolidated Alert System
# Complete framework integration: unified logging + standardized formatting

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# COMPLETE FRAMEWORK INTEGRATION (PHASE 3)
# ==============================================================================

source "$SCRIPT_DIR/lib/common.sh" || {
    echo "ERROR: lib/common.sh is required for alerts system" >&2
    exit 1
}

# Phase 3: Complete framework loading with comprehensive logging
FRAMEWORK_COMPONENTS=()

# Core performance and data collection
if source "$SCRIPT_DIR/lib/perf-collector.sh"; then
    perf_collector_init
    FRAMEWORK_COMPONENTS+=("perf-collector")
fi

if source "$SCRIPT_DIR/lib/dashboard-sqlite.sh"; then
    dashboard_sqlite_init
    FRAMEWORK_COMPONENTS+=("dashboard-sqlite")
fi

if source "$SCRIPT_DIR/lib/dashboard-metrics.sh"; then
    FRAMEWORK_COMPONENTS+=("dashboard-metrics")
fi

# Phase 3: Complete logging framework integration
if source "$SCRIPT_DIR/lib/logger.sh"; then
    logger_init
    FRAMEWORK_COMPONENTS+=("logger")

    # Override all log functions to use framework
    log_info() { logger_info "alerts" "$*"; }
    log_success() { logger_info "alerts" "SUCCESS: $*"; }
    log_warning() { logger_warn "alerts" "$*"; }
    log_error() { logger_error "alerts" "$*"; }
    log_step() { logger_info "alerts" "STEP: $*"; }
    log_debug() { logger_debug "alerts" "$*"; }
else
    # Maintain fallback logging
    log_warning "Enhanced logging framework not available - using basic logging"
fi

# Phase 3: Complete error handling integration
if source "$SCRIPT_DIR/lib/error-handler.sh"; then
    error_handler_init
    FRAMEWORK_COMPONENTS+=("error-handler")
fi

# Phase 3: Complete output formatting integration
if source "$SCRIPT_DIR/lib/perf-formatter.sh"; then
    perf_formatter_init
    FRAMEWORK_COMPONENTS+=("perf-formatter")
fi

# Load all threshold configurations (Phase 3 complete externalization)
[[ -f "$SCRIPT_DIR/config/performance-targets.conf" ]] && source "$SCRIPT_DIR/config/performance-targets.conf"
[[ -f "$SCRIPT_DIR/config/alert-thresholds.conf" ]] && source "$SCRIPT_DIR/config/alert-thresholds.conf"
[[ -f "$SCRIPT_DIR/config/monitoring-intervals.conf" ]] && source "$SCRIPT_DIR/config/monitoring-intervals.conf"

# Comprehensive defaults (Phase 3 compatibility)
CPU_CRITICAL_THRESHOLD=${CPU_CRITICAL_THRESHOLD:-90}
MEMORY_CRITICAL_THRESHOLD=${MEMORY_CRITICAL_THRESHOLD:-85}
LOAD_CRITICAL_THRESHOLD=${LOAD_CRITICAL_THRESHOLD:-1.5}
DISK_CRITICAL_THRESHOLD=${DISK_CRITICAL_THRESHOLD:-85}
SQLITE_SIZE_CRITICAL_MB=${SQLITE_SIZE_CRITICAL_MB:-500}
SQLITE_WAL_CRITICAL_MB=${SQLITE_WAL_CRITICAL_MB:-50}
SQLITE_FRAGMENTATION_CRITICAL=${SQLITE_FRAGMENTATION_CRITICAL:-1.5}
FAIL2BAN_BANNED_CRITICAL=${FAIL2BAN_BANNED_CRITICAL:-25}
ALERT_MIN_INTERVAL_S=${ALERT_MIN_INTERVAL_S:-1800}

SETTINGS_FILE="${SCRIPT_DIR}/settings.env"
SQLITE_DB_PATH=/data/bwdata/db.sqlite3

# ==============================================================================
# PHASE 3: COMPLETE DEPENDENCY MANAGEMENT
# ==============================================================================
check_dependencies() {
    local missing_deps=()
    local required_deps=("sendmail" "jq")
    local optional_deps=("sqlite3" "bc" "curl")

    log_step "Checking system dependencies"

    # Check required dependencies with framework error handling
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
            error_handler_handle "DEPENDENCY" "Missing required dependencies: ${missing_deps[*]}" "abort"
        else
            log_error "Missing required dependencies: ${missing_deps[*]}"
            log_error "Install with: sudo apt-get install postfix jq"
            exit 1
        fi
    else
        log_success "All required dependencies available"
    fi

    # Check optional dependencies with framework logging
    for dep in "${optional_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            log_debug "Optional dependency available: $dep"
        else
            log_warning "Optional dependency missing: $dep (some features may be limited)"
        fi
    done
}

# ==============================================================================
# PHASE 3: FRAMEWORK-UNIFIED SYSTEM CHECKS
# ==============================================================================
check_system_resources_complete() {
    local alerts=()

    log_debug "Performing system resource checks using complete framework integration"

    # Get system metrics using framework (Phase 3 complete integration)
    local system_metrics
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-collector " ]]; then
        system_metrics=$(perf_collector_system_full)
        log_debug "System metrics collected via framework with caching"
    else
        system_metrics=$(get_system_metrics_basic_fallback)
        log_debug "System metrics collected via fallback method"
    fi

    # Parse metrics for analysis
    local cpu_usage mem_usage_pct load_1m disk_usage_pct
    eval "$(echo "$system_metrics" | grep -E '^(cpu_usage|mem_usage_pct|load_1m|disk_usage_pct)=')"

    # CPU Usage Analysis with framework threshold evaluation
    if command -v bc >/dev/null 2>&1 && (( $(echo "$cpu_usage > $CPU_CRITICAL_THRESHOLD" | bc -l) )); then
        if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            alerts+=("$(perf_formatter_alert_row "⚠️ High CPU Usage" "${cpu_usage}% (threshold: ${CPU_CRITICAL_THRESHOLD}%)" "critical")")
        else
            alerts+=("<tr><td>⚠️ High CPU Usage</td><td style='color:red;'>${cpu_usage}% (threshold: ${CPU_CRITICAL_THRESHOLD}%)</td></tr>")
        fi

        log_error "Critical CPU usage detected: ${cpu_usage}% (threshold: ${CPU_CRITICAL_THRESHOLD}%)"
    else
        log_debug "CPU usage acceptable: ${cpu_usage}%"
    fi

    # Memory Usage Analysis
    if command -v bc >/dev/null 2>&1 && (( $(echo "$mem_usage_pct > $MEMORY_CRITICAL_THRESHOLD" | bc -l) )); then
        if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            alerts+=("$(perf_formatter_alert_row "⚠️ High Memory Usage" "${mem_usage_pct}% (threshold: ${MEMORY_CRITICAL_THRESHOLD}%)" "critical")")
        else
            alerts+=("<tr><td>⚠️ High Memory Usage</td><td style='color:red;'>${mem_usage_pct}% (threshold: ${MEMORY_CRITICAL_THRESHOLD}%)</td></tr>")
        fi

        log_error "Critical memory usage detected: ${mem_usage_pct}% (threshold: ${MEMORY_CRITICAL_THRESHOLD}%)"
    else
        log_debug "Memory usage acceptable: ${mem_usage_pct}%"
    fi

    # Load Average Analysis (critical for 1 OCPU) 
    if command -v bc >/dev/null 2>&1 && (( $(echo "$load_1m > $LOAD_CRITICAL_THRESHOLD" | bc -l) )); then
        if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            alerts+=("$(perf_formatter_alert_row "🔥 High Load Average" "${load_1m} (threshold: ${LOAD_CRITICAL_THRESHOLD} for 1 OCPU)" "critical")")
        else
            alerts+=("<tr><td>🔥 High Load Average</td><td style='color:red;'>${load_1m} (threshold: ${LOAD_CRITICAL_THRESHOLD} for 1 OCPU)</td></tr>")
        fi

        log_error "Critical load average for 1 OCPU: ${load_1m} (threshold: ${LOAD_CRITICAL_THRESHOLD})"
    else
        log_debug "Load average acceptable for 1 OCPU: ${load_1m}"
    fi

    # Disk Usage Analysis
    if [[ ${disk_usage_pct:-0} -gt ${DISK_CRITICAL_THRESHOLD} ]]; then
        if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            alerts+=("$(perf_formatter_alert_row "💾 High Disk Usage" "${disk_usage_pct}% (threshold: ${DISK_CRITICAL_THRESHOLD}%)" "critical")")
        else
            alerts+=("<tr><td>💾 High Disk Usage</td><td style='color:red;'>${disk_usage_pct}% (threshold: ${DISK_CRITICAL_THRESHOLD}%)</td></tr>")
        fi

        log_error "Critical disk usage detected: ${disk_usage_pct}% (threshold: ${DISK_CRITICAL_THRESHOLD}%)"
    else
        log_debug "Disk usage acceptable: ${disk_usage_pct}%"
    fi

    printf '%s\n' "${alerts[@]}"
}

# Basic system metrics fallback
get_system_metrics_basic_fallback() {
    cat <<EOF
cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "0")
mem_usage_pct=$(free | awk '/^Mem:/{printf "%.1f", $3*100/$2}' || echo "0")
load_1m=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',' || echo "0")
disk_usage_pct=$(df . | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
EOF
}

# ==============================================================================
# PHASE 3: COMPLETE SQLITE MONITORING INTEGRATION
# ==============================================================================
check_sqlite_database_complete() {
    local alerts=()

    # Skip if database doesn't exist
    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        log_debug "SQLite database not yet created (normal for new installations)"
        return 0
    fi

    log_debug "Performing SQLite database checks using complete framework integration"

    # Use complete framework SQLite monitoring (Phase 3)
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " dashboard-sqlite " ]]; then
        local sqlite_status sqlite_metrics

        # Enhanced framework execution with error handling
        if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
            sqlite_status=$(error_handler_safe_execute "sqlite_status" dashboard_sqlite_get_status)
            sqlite_metrics=$(error_handler_safe_execute "sqlite_metrics" dashboard_sqlite_get_detailed_metrics)
        else
            sqlite_status=$(dashboard_sqlite_get_status)
            sqlite_metrics=$(dashboard_sqlite_get_detailed_metrics || echo "available=false")
        fi

        if [[ "$sqlite_status" =~ status=accessible ]] && [[ "$sqlite_metrics" =~ available=true ]]; then
            log_debug "SQLite framework analysis completed successfully"

            # Parse comprehensive framework results
            local file_size_mb wal_size_mb fragmentation_ratio health
            eval "$(echo "$sqlite_metrics" | grep -E '^(file_size_mb|wal_size_mb|fragmentation_ratio)=')"
            eval "$(echo "$sqlite_status" | grep -E '^health=')"

            # Database health evaluation
            if [[ "$health" != "healthy" ]]; then
                if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                    alerts+=("$(perf_formatter_alert_row "🚨 SQLite Database Health" "Health check failed: $health" "critical")")
                else
                    alerts+=("<tr><td>🚨 SQLite Database Health</td><td style='color:red;'>Health check failed: $health</td></tr>")
                fi

                log_error "SQLite database health issue detected: $health"
            else
                log_debug "SQLite database health check passed"
            fi

            # Size analysis with framework thresholds
            if command -v bc >/dev/null 2>&1 && (( $(echo "$file_size_mb > $SQLITE_SIZE_CRITICAL_MB" | bc -l) )); then
                if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                    alerts+=("$(perf_formatter_alert_row "📊 Large SQLite Database" "${file_size_mb}MB (threshold: ${SQLITE_SIZE_CRITICAL_MB}MB)" "warning")")
                else
                    alerts+=("<tr><td>📊 Large SQLite Database</td><td style='color:orange;'>${file_size_mb}MB (threshold: ${SQLITE_SIZE_CRITICAL_MB}MB)</td></tr>")
                fi

                log_warning "Large SQLite database detected: ${file_size_mb}MB (threshold: ${SQLITE_SIZE_CRITICAL_MB}MB)"
            else
                log_debug "SQLite database size acceptable: ${file_size_mb}MB"
            fi

            # WAL file analysis
            if command -v bc >/dev/null 2>&1 && (( $(echo "$wal_size_mb > $SQLITE_WAL_CRITICAL_MB" | bc -l) )); then
                if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                    alerts+=("$(perf_formatter_alert_row "📝 Large WAL File" "${wal_size_mb}MB (threshold: ${SQLITE_WAL_CRITICAL_MB}MB)" "warning")")
                else
                    alerts+=("<tr><td>📝 Large WAL File</td><td style='color:orange;'>${wal_size_mb}MB (consider maintenance)</td></tr>")
                fi

                log_warning "Large SQLite WAL file detected: ${wal_size_mb}MB"
            else
                log_debug "SQLite WAL file size acceptable: ${wal_size_mb}MB"
            fi

            # Fragmentation analysis
            if command -v bc >/dev/null 2>&1 && (( $(echo "$fragmentation_ratio > $SQLITE_FRAGMENTATION_CRITICAL" | bc -l) )); then
                if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                    alerts+=("$(perf_formatter_alert_row "🗂️ Database Fragmentation" "Ratio: $fragmentation_ratio (consider VACUUM)" "warning")")
                else
                    alerts+=("<tr><td>🗂️ Database Fragmentation</td><td style='color:orange;'>Ratio: $fragmentation_ratio (consider VACUUM)</td></tr>")
                fi

                log_warning "SQLite fragmentation detected: $fragmentation_ratio"
            else
                log_debug "SQLite fragmentation acceptable: $fragmentation_ratio"
            fi

        else
            log_error "SQLite database is not accessible or framework metrics failed"

            if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                alerts+=("$(perf_formatter_alert_row "🚨 SQLite Database" "Database not accessible" "critical")")
            else
                alerts+=("<tr><td>🚨 SQLite Database</td><td style='color:red;'>Database not accessible</td></tr>")
            fi
        fi

    else
        # Fallback SQLite monitoring (Phase 3 enhanced)
        log_debug "Using fallback SQLite monitoring with enhanced error handling"
        alerts+=($(check_sqlite_database_enhanced_fallback))
    fi

    printf '%s\n' "${alerts[@]}"
}

# Enhanced fallback SQLite checks (Phase 3)
check_sqlite_database_enhanced_fallback() {
    local alerts=()

    # Enhanced database accessibility check
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
        if ! error_handler_safe_execute "sqlite_access" sqlite3 "$SQLITE_DB_PATH" "SELECT 1;" >/dev/null; then
            alerts+=("<tr><td>🚨 SQLite Access</td><td style='color:red;'>Database not accessible</td></tr>")
            return
        fi
    else
        if ! sqlite3 "$SQLITE_DB_PATH" "SELECT 1;" >/dev/null 2>&1; then
            alerts+=("<tr><td>🚨 SQLite Access</td><td style='color:red;'>Database not accessible</td></tr>")
            return
        fi
    fi

    # Enhanced size check
    if command -v bc >/dev/null 2>&1; then
        local db_size_mb
        db_size_mb=$(du -m "$SQLITE_DB_PATH" | cut -f1)
        if (( $(echo "$db_size_mb > $SQLITE_SIZE_CRITICAL_MB" | bc -l) )); then
            alerts+=("<tr><td>📊 Large Database</td><td style='color:orange;'>${db_size_mb}MB > ${SQLITE_SIZE_CRITICAL_MB}MB</td></tr>")
        fi
    fi

    # Enhanced integrity check with framework error handling
    local integrity_result
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
        integrity_result=$(error_handler_safe_execute "sqlite_integrity" sqlite3 "$SQLITE_DB_PATH" "PRAGMA integrity_check;")
    else
        integrity_result=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA integrity_check;" || echo "failed")
    fi

    if [[ "$integrity_result" != "ok" ]]; then
        alerts+=("<tr><td>🚨 SQLite Integrity</td><td style='color:red;'>Check failed</td></tr>")
    fi

    # Enhanced WAL file check
    local wal_file="${SQLITE_DB_PATH}-wal"
    if [[ -f "$wal_file" ]] && command -v bc >/dev/null 2>&1; then
        local wal_size_mb
        wal_size_mb=$(du -m "$wal_file" | cut -f1)
        if (( $(echo "$wal_size_mb > $SQLITE_WAL_CRITICAL_MB" | bc -l) )); then
            alerts+=("<tr><td>📝 Large WAL</td><td style='color:orange;'>${wal_size_mb}MB > ${SQLITE_WAL_CRITICAL_MB}MB</td></tr>")
        fi
    fi

    printf '%s\n' "${alerts[@]}"
}

# ==============================================================================
# PHASE 3: COMPLETE CONTAINER MANAGEMENT INTEGRATION
# ==============================================================================
get_container_status_complete() {
    local container_report=""
    local alert_triggered=false

    log_debug "Performing container status checks using complete framework integration"

    # Container name mapping with framework formatting support
    declare -A container_display_names=(
        ["vaultwarden"]="🔐 VaultWarden Core"
        ["bw_caddy"]="🌐 Caddy Proxy" 
        ["bw_fail2ban"]="🛡️ Fail2Ban Security"
        ["bw_backup"]="💾 Backup Service"
        ["bw_watchtower"]="🔄 Watchtower"
        ["bw_ddclient"]="🌐 DD Client"
    )

    # Use complete framework container monitoring (Phase 3)
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " dashboard-metrics " ]]; then
        local container_metrics

        # Enhanced framework execution with error handling
        if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
            container_metrics=$(error_handler_safe_execute "container_metrics" dashboard_get_container_metrics)
        else
            container_metrics=$(dashboard_get_container_metrics)
        fi

        if [[ "$container_metrics" =~ docker_available=true ]]; then
            log_debug "Container metrics collected via complete framework integration"

            # Parse framework container results
            local containers_running containers_total
            eval "$(echo "$container_metrics" | grep -E '^containers_(running|total)=')"

            log_info "Container status: ${containers_running}/${containers_total} running"

            # Process each expected container with framework formatting
            local expected_containers=("vaultwarden" "bw_caddy" "bw_fail2ban" "bw_backup" "bw_watchtower" "bw_ddclient")

            for container in "${expected_containers[@]}"; do
                local service_status service_health
                eval "$(echo "$container_metrics" | grep -E "^${container}_(status|health)=" || echo "${container}_status=not_found ${container}_health=N/A")"

                # Determine alert status and formatting
                local color="green" 
                local status_icon="✅"
                local needs_alert=false

                case "$service_status" in
                    "running")
                        case "$service_health" in
                            "healthy"|"no-health-check"|"no_healthcheck")
                                color="green"
                                status_icon="✅"
                                log_debug "Container healthy: $container"
                                ;;
                            "starting")
                                color="orange"
                                status_icon="🔄"
                                log_info "Container starting: $container"
                                ;;
                            "unhealthy")
                                color="red"
                                status_icon="❌"
                                needs_alert=true
                                log_error "Container unhealthy: $container"
                                ;;
                        esac
                        ;;
                    "stopped"|"exited")
                        color="red"
                        status_icon="❌"
                        # Only alert for critical services
                        if [[ "$container" =~ ^(vaultwarden|bw_caddy)$ ]]; then
                            needs_alert=true
                            log_error "Critical container stopped: $container"
                        else
                            log_warning "Optional container stopped: $container"
                        fi
                        ;;
                    "not_found")
                        color="gray"
                        status_icon="➖"
                        log_debug "Container not configured: $container"
                        ;;
                esac

                # Generate table row with framework formatting if available
                if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                    container_report+="$(perf_formatter_container_status_row "${container_display_names[$container]:-$container}" "$status_icon $service_status" "$service_health" "$color")"
                else
                    container_report+="<tr><td>${container_display_names[$container]:-$container}</td><td style='color:$color;'>$status_icon $service_status</td><td style='color:$color;'>$service_health</td></tr>"
                fi

                # Track alert status
                if [[ "$needs_alert" == "true" ]]; then
                    alert_triggered=true
                fi
            done

        else
            log_error "Docker system not available via framework"
            if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                container_report="$(perf_formatter_container_status_row "Docker System" "❌ Not Available" "N/A" "red")"
            else
                container_report="<tr><td>Docker System</td><td style='color:red;'>❌ Not Available</td><td>N/A</td></tr>"
            fi
            alert_triggered=true
        fi

    else
        # Enhanced fallback container monitoring (Phase 3)
        log_debug "Using enhanced fallback container monitoring"
        container_report=$(get_container_status_enhanced_fallback)

        # Check for alerts in fallback mode
        if echo "$container_report" | grep -q "❌"; then
            alert_triggered=true
        fi
    fi

    echo "report=$container_report"
    echo "alert_triggered=$alert_triggered"
}

# Enhanced fallback container monitoring (Phase 3)
get_container_status_enhanced_fallback() {
    local containers=("vaultwarden" "bw_caddy" "bw_fail2ban" "bw_backup" "bw_watchtower" "bw_ddclient")
    local container_report=""

    declare -A container_display_names=(
        ["vaultwarden"]="🔐 VaultWarden Core"
        ["bw_caddy"]="🌐 Caddy Proxy" 
        ["bw_fail2ban"]="🛡️ Fail2Ban Security"
        ["bw_backup"]="💾 Backup Service"
        ["bw_watchtower"]="🔄 Watchtower"
        ["bw_ddclient"]="🌐 DD Client"
    )

    for container in "${containers[@]}"; do
        local status_json color="gray" status_icon="➖" service_status="not_found" service_health="N/A"

        if command -v docker >/dev/null 2>&1; then
            # Enhanced error handling for Docker operations
            if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
                status_json=$(error_handler_safe_execute "docker_inspect" docker inspect "$container" || echo "[]")
            else
                status_json=$(docker inspect "$container" || echo "[]")
            fi

            if [[ "$status_json" != "[]" ]] && command -v jq >/dev/null 2>&1; then
                service_status=$(echo "$status_json" | jq -r '.[0].State.Status' || echo "unknown")
                service_health=$(echo "$status_json" | jq -r '.[0].State.Health.Status // "N/A"' || echo "N/A")

                case "$service_status" in
                    "running")
                        case "$service_health" in
                            "healthy"|"N/A")
                                color="green"
                                status_icon="✅"
                                ;;
                            "starting")
                                color="orange" 
                                status_icon="🔄"
                                ;;
                            "unhealthy")
                                color="red"
                                status_icon="❌"
                                ;;
                        esac
                        ;;
                    "stopped"|"exited")
                        color="red"
                        status_icon="❌"
                        ;;
                esac
            fi
        fi

        # Generate formatted row
        if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
            container_report+="$(perf_formatter_container_status_row "${container_display_names[$container]:-$container}" "$status_icon $service_status" "$service_health" "$color")"
        else
            container_report+="<tr><td>${container_display_names[$container]:-$container}</td><td style='color:$color;'>$status_icon $service_status</td><td style='color:$color;'>$service_health</td></tr>"
        fi
    done

    echo "$container_report"
}

# ==============================================================================
# PHASE 3: ENHANCED EMAIL GENERATION WITH COMPLETE FORMATTING
# ==============================================================================
generate_complete_status_email() {
    local test_mode="$1"
    local docker_host_ip
    docker_host_ip=$(hostname -I | awk '{print $1}')

    log_step "Generating complete status email with framework formatting"

    # Collect all status information using complete framework integration
    local container_info system_alerts sqlite_alerts

    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
        container_info=$(error_handler_safe_execute "container_check" get_container_status_complete)
        system_alerts=$(error_handler_safe_execute "system_check" check_system_resources_complete)
        sqlite_alerts=$(error_handler_safe_execute "sqlite_check" check_sqlite_database_complete)
    else
        container_info=$(get_container_status_complete)
        system_alerts=$(check_system_resources_complete) 
        sqlite_alerts=$(check_sqlite_database_complete)
    fi

    # Parse status information
    local container_report alert_triggered
    eval "$(echo "$container_info" | grep -E '^(report|alert_triggered)=')"

    # Get comprehensive system information for display
    local system_metrics
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-collector " ]]; then
        system_metrics=$(perf_collector_system_full)
    else
        system_metrics=$(get_system_metrics_basic_fallback)
    fi

    # Parse display metrics
    local load_avg mem_usage disk_usage
    load_avg=$(uptime | awk -F'load average: ' '{print $2}')
    mem_usage=$(free -m | awk 'NR==2{printf "%.2f%% (%d/%d MB)", $3*100/$2, $3, $2}')
    disk_usage=$(df -h . | awk 'NR==2{print $5 " (" $3 "/" $2 ")"}')

    # Enhanced SQLite information display
    local sqlite_info="🆕 Not initialized"
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " dashboard-sqlite " ]]; then
        local sqlite_status sqlite_metrics
        sqlite_status=$(dashboard_sqlite_get_status || echo "status=not_available")
        sqlite_metrics=$(dashboard_sqlite_get_detailed_metrics || echo "available=false")

        if [[ "$sqlite_status" =~ status=accessible ]] && [[ "$sqlite_metrics" =~ available=true ]]; then
            local file_size_mb journal_mode table_count user_count
            eval "$(echo "$sqlite_metrics" | grep -E '^(file_size_mb|journal_mode|table_count|user_count)=')"

            # Format with framework if available
            if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
                sqlite_info="$(perf_formatter_sqlite_summary "$file_size_mb" "$journal_mode" "$table_count" "$user_count")"
            else
                sqlite_info="📊 ${file_size_mb}MB, Mode: $journal_mode, Tables: $table_count, Users: $user_count"
            fi
        fi
    elif [[ -f "$SQLITE_DB_PATH" ]]; then
        # Enhanced fallback SQLite info
        local db_size journal_mode
        db_size=$(du -h "$SQLITE_DB_PATH" | cut -f1)

        if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
            journal_mode=$(error_handler_safe_execute "sqlite_journal" sqlite3 "$SQLITE_DB_PATH" "PRAGMA journal_mode;" || echo "unknown")
        else
            journal_mode=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA journal_mode;" || echo "unknown")
        fi

        sqlite_info="📊 Size: $db_size, Mode: $journal_mode"
    fi

    # Enhanced security information
    local security_status="🔒 Security checks disabled"
    if docker ps --filter "name=bw_fail2ban" --filter "status=running" | grep -q "bw_fail2ban"; then
        local banned_count
        if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
            banned_count=$(error_handler_safe_execute "fail2ban_status" docker exec bw_fail2ban fail2ban-client status | grep "Currently banned" | awk '{print $NF}' || echo "0")
        else
            banned_count=$(docker exec bw_fail2ban fail2ban-client status | grep "Currently banned" | awk '{print $NF}' || echo "0")
        fi

        if [[ $banned_count -gt ${FAIL2BAN_BANNED_CRITICAL:-25} ]]; then
            security_status="🚨 $banned_count IPs banned (critical: >${FAIL2BAN_BANNED_CRITICAL})"
        elif [[ $banned_count -gt 0 ]]; then
            security_status="🛡️ $banned_count IPs currently banned"
        else
            security_status="✅ No banned IPs"
        fi
    fi

    # Determine overall alert status
    local overall_alert_status=false
    if [[ "$alert_triggered" == "true" ]] || [[ -n "$system_alerts" ]] || [[ -n "$sqlite_alerts" ]]; then
        overall_alert_status=true
        log_warning "Alert conditions detected in status check"
    else
        log_info "All systems reporting healthy status"
    fi

    # Generate enhanced email subject
    local subject
    if [ "$test_mode" = true ]; then
        subject="📧 VaultWarden Test Report (Framework v3) for $docker_host_ip"
        log_info "Generating test email with complete framework integration"
    elif [ "$overall_alert_status" = true ]; then
        subject="🚨 VaultWarden ALERT: Issues Detected on $docker_host_ip"
        log_error "Alert email being generated due to detected issues"
    else
        subject="✅ VaultWarden Status Report for $docker_host_ip"
        log_info "Healthy status report being generated"
    fi

    # Generate enhanced HTML email with complete framework formatting
    local email_body
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        email_body=$(perf_formatter_generate_status_email             "$subject"             "$docker_host_ip"             "$load_avg"             "$mem_usage"             "$disk_usage"             "$sqlite_info"             "$container_report"             "$system_alerts"             "$sqlite_alerts"             "$security_status"             "${FRAMEWORK_COMPONENTS[*]}")
    else
        # Fallback email generation (enhanced HTML template)
        email_body=$(cat <<EOF
From: VaultWarden Monitor <${SMTP_FROM:-noreply@$(hostname -d)}>
To: $ALERT_EMAIL
Subject: $subject
Content-Type: text/html; charset="UTF-8"
MIME-Version: 1.0

<html>
<head>
<style>
  body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; color: #333; background-color: #f8f9fa; }
  .container { background-color: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); max-width: 800px; margin: 0 auto; }
  table { border-collapse: collapse; width: 100%; margin-bottom: 25px; border-radius: 6px; overflow: hidden; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
  th, td { border: none; text-align: left; padding: 12px 15px; }
  th { background-color: #007bff; color: white; font-weight: 600; }
  tr:nth-child(even) { background-color: #f8f9fa; }
  h2 { color: #007bff; border-bottom: 3px solid #007bff; padding-bottom: 10px; }
  h3 { color: #495057; margin-top: 30px; margin-bottom: 15px; }
  .alert-section { background-color: #fff3cd; border-left: 5px solid #ffc107; padding: 20px; margin: 25px 0; border-radius: 4px; }
  .framework-badge { background-color: #28a745; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; }
  .footer { text-align: center; color: #6c757d; font-size: 12px; margin-top: 30px; }
</style>
</head>
<body>
  <div class="container">
    <h2>🔒 VaultWarden Status Report (Phase 3 Complete)</h2>
    <p><strong>SQLite Deployment</strong> <span class="framework-badge">Framework v3</span> | <em>$(date)</em></p>

    <h3>📊 System Information</h3>
    <table>
      <tr><th>Metric</th><th>Value</th></tr>
      <tr><td>🌐 Host IP</td><td>$docker_host_ip</td></tr>
      <tr><td>⚖️ Load Average</td><td>$load_avg</td></tr>
      <tr><td>🧠 Memory Usage</td><td>$mem_usage</td></tr>
      <tr><td>💾 Disk Usage</td><td>$disk_usage</td></tr>
      <tr><td>🗄️ SQLite Database</td><td>$sqlite_info</td></tr>
    </table>

    <h3>🐳 Container Status</h3>
    <table>
      <tr><th>Container</th><th>Status</th><th>Health</th></tr>
      $container_report
    </table>

$(if [[ -n "$system_alerts" ]]; then
    echo "<div class='alert-section'><h3>⚠️ System Resource Alerts</h3><table><tr><th>Type</th><th>Details</th></tr>$system_alerts</table></div>"
fi)

$(if [[ -n "$sqlite_alerts" ]]; then
    echo "<div class='alert-section'><h3>🗄️ SQLite Database Alerts</h3><table><tr><th>Type</th><th>Details</th></tr>$sqlite_alerts</table></div>"
fi)

    <h3>🛡️ Security Status</h3>
    <table>
      <tr><th>Service</th><th>Status</th></tr>
      <tr><td>Protection Status</td><td>$security_status</td></tr>
    </table>

    <hr>
    <div class="footer">
      <p><strong>Framework Components Active:</strong> ${FRAMEWORK_COMPONENTS[*]}<br>
      <strong>Thresholds:</strong> CPU ${CPU_CRITICAL_THRESHOLD}%, Memory ${MEMORY_CRITICAL_THRESHOLD}%, Load ${LOAD_CRITICAL_THRESHOLD}, SQLite ${SQLITE_SIZE_CRITICAL_MB}MB</p>
    </div>
  </div>
</body>
</html>
EOF
        )
    fi

    echo "$overall_alert_status"
}

# ==============================================================================
# MAIN EXECUTION WITH COMPLETE FRAMEWORK INTEGRATION
# ==============================================================================
main() {
    local test_mode=false
    if [[ "${1:-}" == "--test" ]]; then
        test_mode=true
        log_info "Running alert system in test mode with complete framework integration"
    else
        log_info "Starting alert system with complete framework integration"
    fi

    # Log framework status
    log_info "Framework components loaded: ${#FRAMEWORK_COMPONENTS[@]} (${FRAMEWORK_COMPONENTS[*]})"

    # Load configuration with enhanced error handling
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
        if ! error_handler_safe_execute "config_load" load_config; then
            log_error "Configuration loading failed"
            exit 1
        fi
    else
        load_config
    fi

    # Generate and send email with complete framework integration
    local email_content alert_status
    email_content=$(generate_complete_status_email "$test_mode")
    alert_status=$(echo "$email_content" | tail -1)
    email_content=$(echo "$email_content" | head -n -1)

    # Enhanced email sending with framework error handling
    local send_success=false
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " error-handler " ]]; then
        if error_handler_safe_execute "email_send" bash -c "echo '$email_content' | sendmail -t"; then
            send_success=true
            log_info "Email sent successfully using framework error handling"
        else
            log_error "Email sending failed with framework error handling"
        fi
    else
        # Fallback email sending
        if echo "$email_content" | sendmail -t; then
            send_success=true
            log_info "Email sent successfully using fallback method"
        else
            log_error "Email sending failed using fallback method"
        fi
    fi

    # Enhanced result reporting and exit handling
    if [ "$test_mode" = true ]; then
        if [[ "$send_success" == "true" ]]; then
            log_success "Test report sent successfully to $ALERT_EMAIL (complete framework integration verified)"
            exit 0
        else
            log_error "Failed to send test report"
            exit 1
        fi
    elif [ "$alert_status" = true ]; then
        if [[ "$send_success" == "true" ]]; then
            log_warning "Alert triggered! Issues detected and email sent to $ALERT_EMAIL"
        else
            log_error "Alert triggered but email sending failed"
        fi
        exit 1
    else
        if [[ "$send_success" == "true" ]]; then
            log_success "All systems healthy. Status report sent to $ALERT_EMAIL"
        else
            log_error "Systems healthy but email sending failed"
        fi
        exit 0
    fi
}

# ==============================================================================
# ENHANCED HELP WITH COMPLETE FRAMEWORK DOCUMENTATION
# ==============================================================================
show_help() {
    # Use framework formatter for help if available
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-formatter " ]]; then
        perf_formatter_show_help "VaultWarden Alert System" "Phase 3 Complete Framework Integration"             "Comprehensive monitoring with unified logging, standardized formatting, and complete error handling"
    else
        cat <<EOF

🔒 VaultWarden-OCI-Slim Alert System (Phase 3 Complete)
========================================================

Usage: $0 [COMMAND]

Commands:
    --help, -h      Shows this help message and exits
    --test          Sends test alert with complete framework integration
    (no command)    Runs full health check with complete framework

🆕 Phase 3 Complete Framework Integration:
  ✅ lib/perf-collector.sh: Unified system metrics with intelligent caching
  ✅ lib/dashboard-sqlite.sh: Comprehensive SQLite monitoring and analysis
  ✅ lib/dashboard-metrics.sh: Complete container management integration
  ✅ lib/logger.sh: Structured logging with rotation and categorization
  ✅ lib/error-handler.sh: Robust error recovery and safe execution
  ✅ lib/perf-formatter.sh: Standardized output formatting and styling

🔍 Complete Monitoring Features:
  • System Resources: Framework-cached metrics with configurable thresholds
  • Container Status: Unified management via dashboard-metrics integration
  • SQLite Database: Comprehensive analysis including fragmentation detection
  • Security Status: Enhanced Fail2ban monitoring with threshold analysis
  • Email Reports: Framework-formatted HTML with consistent styling

⚙️ Complete Configuration Integration:
  • config/performance-targets.conf: All performance thresholds externalized
  • config/alert-thresholds.conf: Alert-specific policies and intervals
  • config/monitoring-intervals.conf: Timing and refresh rate configuration
  • settings.env: Core deployment configuration (ALERT_EMAIL required)

🎯 1 OCPU/6GB Complete Optimization:
  • Framework component caching minimizes system overhead
  • Single CPU load analysis with critical threshold monitoring
  • Memory targeting ~672MB total containers
  • SQLite performance optimization with intelligent maintenance recommendations
  • Structured logging reduces I/O overhead

📧 Enhanced Email Features:
  • Framework-formatted HTML templates with consistent styling
  • Configurable alert intervals and retry policies
  • Rich diagnostic information with threshold context
  • Mobile-responsive design for on-the-go monitoring

🔄 Complete Backward Compatibility:
  • Graceful fallback when any framework component unavailable
  • Enhanced functionality with full framework, basic functionality without
  • Existing configuration files fully supported
  • Zero breaking changes to existing deployments

Examples:
    $0                 # Complete framework-integrated health check
    $0 --test          # Test all framework components with sample alert
    $0 --help          # Show complete framework documentation

EOF
    fi
}

# Script entry point with complete framework integration
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --test)
        check_dependencies
        log_info "Running complete framework integration test..."
        main "--test"
        ;;
    *)
        check_dependencies
        main
        ;;
esac
