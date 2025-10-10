#!/usr/bin/env bash
# alerts.sh -- VaultWarden-OCI Alert System (Unified Configuration)
# Uses centralized monitoring configuration from lib/monitoring-config.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# UNIFIED CONFIGURATION LOADING
# ==============================================================================

# Load core framework
source "$SCRIPT_DIR/lib/common.sh" || {
    echo "ERROR: lib/common.sh is required for alerts system" >&2
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

# Framework component tracking
FRAMEWORK_COMPONENTS=()

# Load framework components if available
if source "$SCRIPT_DIR/lib/perf-collector.sh" 2>/dev/null; then
    perf_collector_init
    FRAMEWORK_COMPONENTS+=("perf-collector")
fi

if source "$SCRIPT_DIR/lib/dashboard-sqlite.sh" 2>/dev/null; then
    dashboard_sqlite_init
    FRAMEWORK_COMPONENTS+=("dashboard-sqlite")
fi

if source "$SCRIPT_DIR/lib/dashboard-metrics.sh" 2>/dev/null; then
    FRAMEWORK_COMPONENTS+=("dashboard-metrics")
fi

if source "$SCRIPT_DIR/lib/logger.sh" 2>/dev/null; then
    logger_init
    FRAMEWORK_COMPONENTS+=("logger")

    # Override logging functions to use framework
    log_info() { logger_info "alerts" "$*"; }
    log_success() { logger_info "alerts" "SUCCESS: $*"; }
    log_warning() { logger_warn "alerts" "$*"; }
    log_error() { logger_error "alerts" "$*"; }
    log_step() { logger_info "alerts" "STEP: $*"; }
    log_debug() { logger_debug "alerts" "$*"; }
fi

if source "$SCRIPT_DIR/lib/error-handler.sh" 2>/dev/null; then
    error_handler_init
    FRAMEWORK_COMPONENTS+=("error-handler")
fi

if source "$SCRIPT_DIR/lib/perf-formatter.sh" 2>/dev/null; then
    perf_formatter_init
    FRAMEWORK_COMPONENTS+=("perf-formatter")
fi

# ==============================================================================
# DEPENDENCY MANAGEMENT
# ==============================================================================
check_dependencies() {
    local missing_deps=()
    local required_deps=("sendmail" "jq")
    local optional_deps=("sqlite3" "bc" "curl")

    log_step "Checking system dependencies"

    # Check required dependencies
    for dep in "${required_deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_error "Install with: sudo apt-get install postfix jq"
        exit 1
    else
        log_success "All required dependencies available"
    fi

    # Check optional dependencies
    for dep in "${optional_deps[@]}"; do
        if command -v "$dep" &> /dev/null; then
            log_debug "Optional dependency available: $dep"
        else
            log_warning "Optional dependency missing: $dep (some features may be limited)"
        fi
    done
}

# ==============================================================================
# UNIFIED SYSTEM RESOURCE CHECKS
# ==============================================================================
check_system_resources_unified() {
    local alerts=()

    log_debug "Performing system resource checks using unified configuration"

    # Get system metrics using unified collection
    local system_metrics
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " perf-collector " ]]; then
        system_metrics=$(perf_collector_system_full)
        log_debug "System metrics collected via framework with caching"
    else
        system_metrics=$(get_unified_system_metrics)
        log_debug "System metrics collected via unified fallback method"
    fi

    # Parse metrics for analysis
    local cpu_usage mem_usage_pct load_1m disk_usage_pct
    local cpu_status mem_status load_status disk_status
    eval "$system_metrics"

    # Use unified threshold evaluation functions
    cpu_status=$(evaluate_cpu_threshold "$cpu_usage")
    mem_status=$(evaluate_memory_threshold "$mem_usage_pct")
    load_status=$(evaluate_load_threshold "$load_1m")
    disk_status=$(evaluate_disk_threshold "$disk_usage_pct")

    # Generate alerts based on unified evaluation
    case "$cpu_status" in
        "critical")
            alerts+=("<tr><td>⚠️ Critical CPU Usage</td><td style='color:red;'>${cpu_usage}% (threshold: ${CPU_CRITICAL_THRESHOLD}%)</td></tr>")
            log_error "Critical CPU usage detected: ${cpu_usage}% (threshold: ${CPU_CRITICAL_THRESHOLD}%)"
            ;;
        "alert")
            alerts+=("<tr><td>⚠️ High CPU Usage</td><td style='color:orange;'>${cpu_usage}% (threshold: ${CPU_ALERT_THRESHOLD}%)</td></tr>")
            log_warning "High CPU usage detected: ${cpu_usage}% (threshold: ${CPU_ALERT_THRESHOLD}%)"
            ;;
    esac

    case "$mem_status" in
        "critical")
            alerts+=("<tr><td>⚠️ Critical Memory Usage</td><td style='color:red;'>${mem_usage_pct}% (threshold: ${MEMORY_CRITICAL_THRESHOLD}%)</td></tr>")
            log_error "Critical memory usage detected: ${mem_usage_pct}% (threshold: ${MEMORY_CRITICAL_THRESHOLD}%)"
            ;;
        "alert")
            alerts+=("<tr><td>⚠️ High Memory Usage</td><td style='color:orange;'>${mem_usage_pct}% (threshold: ${MEMORY_ALERT_THRESHOLD}%)</td></tr>")
            log_warning "High memory usage detected: ${mem_usage_pct}% (threshold: ${MEMORY_ALERT_THRESHOLD}%)"
            ;;
    esac

    case "$load_status" in
        "critical")
            alerts+=("<tr><td>🔥 Critical Load Average</td><td style='color:red;'>${load_1m} (threshold: ${LOAD_CRITICAL_THRESHOLD} for 1 OCPU)</td></tr>")
            log_error "Critical load average for 1 OCPU: ${load_1m} (threshold: ${LOAD_CRITICAL_THRESHOLD})"
            ;;
        "alert")
            alerts+=("<tr><td>🔥 High Load Average</td><td style='color:orange;'>${load_1m} (threshold: ${LOAD_ALERT_THRESHOLD} for 1 OCPU)</td></tr>")
            log_warning "High load average for 1 OCPU: ${load_1m} (threshold: ${LOAD_ALERT_THRESHOLD})"
            ;;
    esac

    case "$disk_status" in
        "critical")
            alerts+=("<tr><td>💾 Critical Disk Usage</td><td style='color:red;'>${disk_usage_pct}% (threshold: ${DISK_CRITICAL_THRESHOLD}%)</td></tr>")
            log_error "Critical disk usage detected: ${disk_usage_pct}% (threshold: ${DISK_CRITICAL_THRESHOLD}%)"
            ;;
        "alert")
            alerts+=("<tr><td>💾 High Disk Usage</td><td style='color:orange;'>${disk_usage_pct}% (threshold: ${DISK_ALERT_THRESHOLD}%)</td></tr>")
            log_warning "High disk usage detected: ${disk_usage_pct}% (threshold: ${DISK_ALERT_THRESHOLD}%)"
            ;;
    esac

    printf '%s\n' "${alerts[@]}"
}

# ==============================================================================
# UNIFIED SQLITE MONITORING
# ==============================================================================
check_sqlite_database_unified() {
    local alerts=()

    # Skip if database doesn't exist
    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        log_debug "SQLite database not yet created (normal for new installations)"
        return 0
    fi

    log_debug "Performing SQLite database checks using unified configuration"

    # Use framework SQLite monitoring if available
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " dashboard-sqlite " ]]; then
        local sqlite_status sqlite_metrics
        sqlite_status=$(dashboard_sqlite_get_status)
        sqlite_metrics=$(dashboard_sqlite_get_detailed_metrics || echo "available=false")

        if [[ "$sqlite_status" =~ status=accessible ]] && [[ "$sqlite_metrics" =~ available=true ]]; then
            log_debug "SQLite framework analysis completed successfully")

            # Parse framework results
            local file_size_mb wal_size_mb fragmentation_ratio health
            eval "$(echo "$sqlite_metrics" | grep -E '^(file_size_mb|wal_size_mb|fragmentation_ratio)=')"
            eval "$(echo "$sqlite_status" | grep -E '^health=')"

            # Database health evaluation
            if [[ "$health" != "healthy" ]]; then
                alerts+=("<tr><td>🚨 SQLite Database Health</td><td style='color:red;'>Health check failed: $health</td></tr>")
                log_error "SQLite database health issue detected: $health"
            fi

            # Use unified threshold evaluation functions
            local size_status wal_status frag_status
            size_status=$(evaluate_sqlite_size_threshold "$file_size_mb")
            wal_status=$(evaluate_sqlite_size_threshold "$wal_size_mb")  # Using same function for WAL
            frag_status=$(evaluate_fragmentation_threshold "$fragmentation_ratio")

            # Generate alerts based on unified evaluation
            case "$size_status" in
                "critical")
                    alerts+=("<tr><td>📊 Critical SQLite Database</td><td style='color:red;'>${file_size_mb}MB (threshold: ${SQLITE_SIZE_CRITICAL_MB}MB)</td></tr>")
                    log_error "Critical SQLite database size: ${file_size_mb}MB"
                    ;;
                "alert")
                    alerts+=("<tr><td>📊 Large SQLite Database</td><td style='color:orange;'>${file_size_mb}MB (threshold: ${SQLITE_SIZE_ALERT_MB}MB)</td></tr>")
                    log_warning "Large SQLite database detected: ${file_size_mb}MB"
                    ;;
            esac

            # WAL file analysis using unified thresholds
            if command -v bc >/dev/null 2>&1 && (( $(echo "$wal_size_mb > $WAL_SIZE_ALERT_MB" | bc -l) )); then
                if (( $(echo "$wal_size_mb > $WAL_SIZE_CRITICAL_MB" | bc -l) )); then
                    alerts+=("<tr><td>📝 Critical WAL File</td><td style='color:red;'>${wal_size_mb}MB (threshold: ${WAL_SIZE_CRITICAL_MB}MB)</td></tr>")
                    log_error "Critical SQLite WAL file size: ${wal_size_mb}MB"
                else
                    alerts+=("<tr><td>📝 Large WAL File</td><td style='color:orange;'>${wal_size_mb}MB (threshold: ${WAL_SIZE_ALERT_MB}MB)</td></tr>")
                    log_warning "Large SQLite WAL file detected: ${wal_size_mb}MB"
                fi
            fi

            # Fragmentation analysis using unified thresholds
            case "$frag_status" in
                "critical")
                    alerts+=("<tr><td>🗂️ Critical Database Fragmentation</td><td style='color:red;'>Ratio: $fragmentation_ratio (threshold: $FRAGMENTATION_CRITICAL_RATIO)</td></tr>")
                    log_error "Critical SQLite fragmentation: $fragmentation_ratio"
                    ;;
                "alert")
                    alerts+=("<tr><td>🗂️ Database Fragmentation</td><td style='color:orange;'>Ratio: $fragmentation_ratio (threshold: $FRAGMENTATION_ALERT_RATIO)</td></tr>")
                    log_warning "SQLite fragmentation detected: $fragmentation_ratio"
                    ;;
            esac

        else
            log_error "SQLite database is not accessible or framework metrics failed"
            alerts+=("<tr><td>🚨 SQLite Database</td><td style='color:red;'>Database not accessible</td></tr>")
        fi

    else
        # Enhanced fallback SQLite monitoring
        log_debug "Using enhanced fallback SQLite monitoring with unified thresholds"
        alerts+=($(check_sqlite_database_fallback))
    fi

    printf '%s\n' "${alerts[@]}"
}

# Enhanced fallback SQLite checks using unified thresholds
check_sqlite_database_fallback() {
    local alerts=()

    # Database accessibility check
    if ! sqlite3 "$SQLITE_DB_PATH" "SELECT 1;" >/dev/null 2>&1; then
        alerts+=("<tr><td>🚨 SQLite Access</td><td style='color:red;'>Database not accessible</td></tr>")
        return
    fi

    # Size check using unified thresholds
    if command -v bc >/dev/null 2>&1; then
        local db_size_mb
        db_size_mb=$(du -m "$SQLITE_DB_PATH" | cut -f1)
        local size_status
        size_status=$(evaluate_sqlite_size_threshold "$db_size_mb")

        case "$size_status" in
            "critical")
                alerts+=("<tr><td>📊 Critical Database Size</td><td style='color:red;'>${db_size_mb}MB (>${SQLITE_SIZE_CRITICAL_MB}MB)</td></tr>")
                ;;
            "alert")
                alerts+=("<tr><td>📊 Large Database</td><td style='color:orange;'>${db_size_mb}MB (>${SQLITE_SIZE_ALERT_MB}MB)</td></tr>")
                ;;
        esac
    fi

    # Integrity check
    local integrity_result
    integrity_result=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA integrity_check;" || echo "failed")
    if [[ "$integrity_result" != "ok" ]]; then
        alerts+=("<tr><td>🚨 SQLite Integrity</td><td style='color:red;'>Check failed</td></tr>")
    fi

    # WAL file check using unified thresholds
    local wal_file="${SQLITE_DB_PATH}-wal"
    if [[ -f "$wal_file" ]] && command -v bc >/dev/null 2>&1; then
        local wal_size_mb
        wal_size_mb=$(du -m "$wal_file" | cut -f1)
        if (( $(echo "$wal_size_mb > $WAL_SIZE_CRITICAL_MB" | bc -l) )); then
            alerts+=("<tr><td>📝 Critical WAL Size</td><td style='color:red;'>${wal_size_mb}MB (>${WAL_SIZE_CRITICAL_MB}MB)</td></tr>")
        elif (( $(echo "$wal_size_mb > $WAL_SIZE_ALERT_MB" | bc -l) )); then
            alerts+=("<tr><td>📝 Large WAL</td><td style='color:orange;'>${wal_size_mb}MB (>${WAL_SIZE_ALERT_MB}MB)</td></tr>")
        fi
    fi

    printf '%s\n' "${alerts[@]}"
}

# ==============================================================================
# UNIFIED CONTAINER MONITORING
# ==============================================================================
get_container_status_unified() {
    local container_report=""
    local alert_triggered=false

    log_debug "Performing container status checks using unified configuration"

    # Container name mapping
    declare -A container_display_names=(
        ["vaultwarden"]="🔐 VaultWarden Core"
        ["bw_caddy"]="🌐 Caddy Proxy" 
        ["bw_fail2ban"]="🛡️ Fail2Ban Security"
        ["bw_backup"]="💾 Backup Service"
        ["bw_watchtower"]="🔄 Watchtower"
        ["bw_ddclient"]="🌐 DD Client"
        ["bw_monitoring"]="📊 Monitoring"
    )

    # Use framework container monitoring if available
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " dashboard-metrics " ]]; then
        local container_metrics
        container_metrics=$(dashboard_get_container_metrics)

        if [[ "$container_metrics" =~ docker_available=true ]]; then
            log_debug "Container metrics collected via framework integration"

            # Parse framework container results
            local containers_running containers_total
            eval "$(echo "$container_metrics" | grep -E '^containers_(running|total)=')"

            log_info "Container status: ${containers_running}/${containers_total} running"

            # Process each expected container
            local expected_containers=("vaultwarden" "bw_caddy" "bw_fail2ban" "bw_backup" "bw_watchtower" "bw_ddclient" "bw_monitoring")

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
                                ;;
                            "starting")
                                color="orange"
                                status_icon="🔄"
                                ;;
                            "unhealthy")
                                color="red"
                                status_icon="❌"
                                needs_alert=true
                                ;;
                        esac
                        ;;
                    "stopped"|"exited")
                        color="red"
                        status_icon="❌"
                        # Only alert for critical services
                        if [[ "$container" =~ ^(vaultwarden|bw_caddy)$ ]]; then
                            needs_alert=true
                        fi
                        ;;
                    "not_found")
                        color="gray"
                        status_icon="➖"
                        ;;
                esac

                # Generate table row
                container_report+="<tr><td>${container_display_names[$container]:-$container}</td><td style='color:$color;'>$status_icon $service_status</td><td style='color:$color;'>$service_health</td></tr>"

                # Track alert status
                if [[ "$needs_alert" == "true" ]]; then
                    alert_triggered=true
                fi
            done

        else
            log_error "Docker system not available via framework"
            container_report="<tr><td>Docker System</td><td style='color:red;'>❌ Not Available</td><td>N/A</td></tr>"
            alert_triggered=true
        fi

    else
        # Enhanced fallback container monitoring
        log_debug "Using enhanced fallback container monitoring"
        container_report=$(get_container_status_fallback)

        # Check for alerts in fallback mode
        if echo "$container_report" | grep -q "❌"; then
            alert_triggered=true
        fi
    fi

    echo "report=$container_report"
    echo "alert_triggered=$alert_triggered"
}

# Fallback container monitoring
get_container_status_fallback() {
    local containers=("vaultwarden" "bw_caddy" "bw_fail2ban" "bw_backup" "bw_watchtower" "bw_ddclient" "bw_monitoring")
    local container_report=""

    declare -A container_display_names=(
        ["vaultwarden"]="🔐 VaultWarden Core"
        ["bw_caddy"]="🌐 Caddy Proxy" 
        ["bw_fail2ban"]="🛡️ Fail2Ban Security"
        ["bw_backup"]="💾 Backup Service"
        ["bw_watchtower"]="🔄 Watchtower"
        ["bw_ddclient"]="🌐 DD Client"
        ["bw_monitoring"]="📊 Monitoring"
    )

    for container in "${containers[@]}"; do
        local color="gray" status_icon="➖" service_status="not_found" service_health="N/A"

        if command -v docker >/dev/null 2>&1; then
            local status_json
            status_json=$(docker inspect "$container" 2>/dev/null || echo "[]")

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
        container_report+="<tr><td>${container_display_names[$container]:-$container}</td><td style='color:$color;'>$status_icon $service_status</td><td style='color:$color;'>$service_health</td></tr>"
    done

    echo "$container_report"
}

# ==============================================================================
# UNIFIED EMAIL GENERATION
# ==============================================================================
generate_status_email_unified() {
    local test_mode="$1"
    local docker_host_ip
    docker_host_ip=$(hostname -I | awk '{print $1}')

    log_step "Generating status email with unified configuration"

    # Collect all status information using unified configuration
    local container_info system_alerts sqlite_alerts
    container_info=$(get_container_status_unified)
    system_alerts=$(check_system_resources_unified)
    sqlite_alerts=$(check_sqlite_database_unified)

    # Parse status information
    local container_report alert_triggered
    eval "$(echo "$container_info" | grep -E '^(report|alert_triggered)=')"

    # Get system information for display
    local system_metrics
    system_metrics=$(get_unified_system_metrics)

    # Parse display metrics
    local load_avg mem_usage disk_usage
    load_avg=$(uptime | awk -F'load average: ' '{print $2}')
    mem_usage=$(free -m | awk 'NR==2{printf "%.2f%% (%d/%d MB)", $3*100/$2, $3, $2}')
    disk_usage=$(df -h . | awk 'NR==2{print $5 " (" $3 "/" $2 ")"}')

    # SQLite information using unified paths
    local sqlite_info="🆕 Not initialized"
    if [[ " ${FRAMEWORK_COMPONENTS[*]} " =~ " dashboard-sqlite " ]]; then
        local sqlite_status sqlite_metrics
        sqlite_status=$(dashboard_sqlite_get_status || echo "status=not_available")
        sqlite_metrics=$(dashboard_sqlite_get_detailed_metrics || echo "available=false")

        if [[ "$sqlite_status" =~ status=accessible ]] && [[ "$sqlite_metrics" =~ available=true ]]; then
            local file_size_mb journal_mode table_count user_count
            eval "$(echo "$sqlite_metrics" | grep -E '^(file_size_mb|journal_mode|table_count|user_count)=')"
            sqlite_info="📊 ${file_size_mb}MB, Mode: $journal_mode, Tables: $table_count, Users: $user_count"
        fi
    elif [[ -f "$SQLITE_DB_PATH" ]]; then
        local db_size journal_mode
        db_size=$(du -h "$SQLITE_DB_PATH" | cut -f1)
        journal_mode=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA journal_mode;" 2>/dev/null || echo "unknown")
        sqlite_info="📊 Size: $db_size, Mode: $journal_mode"
    fi

    # Security information using unified configuration
    local security_status="🔒 Security checks disabled"
    if docker ps --filter "name=bw_fail2ban" --filter "status=running" | grep -q "bw_fail2ban"; then
        local banned_count
        banned_count=$(docker exec bw_fail2ban fail2ban-client status 2>/dev/null | grep "Currently banned" | awk '{print $NF}' || echo "0")

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

    # Generate email subject
    local subject
    if [ "$test_mode" = true ]; then
        subject="📧 VaultWarden Test Report (Unified Config v$MONITORING_CONFIG_VERSION) for $docker_host_ip"
    elif [ "$overall_alert_status" = true ]; then
        subject="🚨 VaultWarden ALERT: Issues Detected on $docker_host_ip"
    else
        subject="✅ VaultWarden Status Report for $docker_host_ip"
    fi

    # Generate HTML email with unified configuration display
    local email_body
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
  .config-badge { background-color: #28a745; color: white; padding: 4px 8px; border-radius: 4px; font-size: 12px; }
  .footer { text-align: center; color: #6c757d; font-size: 12px; margin-top: 30px; }
</style>
</head>
<body>
  <div class="container">
    <h2>🔒 VaultWarden Status Report (Unified Configuration)</h2>
    <p><strong>SQLite Deployment</strong> <span class="config-badge">Config v$MONITORING_CONFIG_VERSION</span> | <em>$(date)</em></p>

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
      <p><strong>Configuration Sources:</strong> $MONITORING_CONFIG_SOURCES<br>
      <strong>Framework Components:</strong> ${FRAMEWORK_COMPONENTS[*]}<br>
      <strong>Unified Thresholds:</strong> CPU ${CPU_ALERT_THRESHOLD}%, Memory ${MEMORY_ALERT_THRESHOLD}%, Load ${LOAD_ALERT_THRESHOLD}, SQLite ${SQLITE_SIZE_ALERT_MB}MB</p>
    </div>
  </div>
</body>
</html>
EOF
    )

    echo "$overall_alert_status"
}

# ==============================================================================
# MAIN EXECUTION WITH UNIFIED CONFIGURATION
# ==============================================================================
main() {
    local test_mode=false
    if [[ "${1:-}" == "--test" ]]; then
        test_mode=true
        log_info "Running alert system in test mode with unified configuration"
    else
        log_info "Starting alert system with unified configuration"
    fi

    # Log configuration status
    log_info "Framework components loaded: ${#FRAMEWORK_COMPONENTS[@]} (${FRAMEWORK_COMPONENTS[*]})"
    log_info "Unified configuration v$MONITORING_CONFIG_VERSION from: $MONITORING_CONFIG_SOURCES"

    # Load settings.env configuration
    if [[ -f "${SCRIPT_DIR}/settings.env" ]]; then
        set -a
        source "${SCRIPT_DIR}/settings.env"
        set +a
        log_debug "Settings loaded from settings.env"
    fi

    # Generate and send email
    local email_content alert_status
    email_content=$(generate_status_email_unified "$test_mode")
    alert_status=$(echo "$email_content" | tail -1)
    email_content=$(echo "$email_content" | head -n -1)

    # Send email
    local send_success=false
    if echo "$email_content" | sendmail -t 2>/dev/null; then
        send_success=true
        log_info "Email sent successfully using unified configuration"
    else
        log_error "Email sending failed"
    fi

    # Result reporting
    if [ "$test_mode" = true ]; then
        if [[ "$send_success" == "true" ]]; then
            log_success "Test report sent successfully to $ALERT_EMAIL (unified configuration verified)"
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
# HELP WITH UNIFIED CONFIGURATION
# ==============================================================================
show_help() {
    cat <<EOF

🔒 VaultWarden-OCI-Slim Alert System (Unified Configuration v$MONITORING_CONFIG_VERSION)
======================================================================================

Usage: $0 [COMMAND]

Commands:
    --help, -h      Shows this help message and exits
    --test          Sends test alert with unified configuration
    (no command)    Runs full health check with unified configuration

🆕 Unified Configuration Benefits:
  ✅ Single source of truth for all thresholds
  ✅ Consistent variable names across all scripts
  ✅ Centralized configuration management
  ✅ External config file support with priority
  ✅ Built-in threshold validation
  ✅ Standardized metric evaluation functions

📋 Configuration Sources (Priority Order):
  1. config/performance-targets.conf (highest priority)
  2. config/alert-thresholds.conf  
  3. config/monitoring-intervals.conf
  4. settings.env / environment variables
  5. Built-in defaults (lowest priority)

⚙️ Unified Threshold Configuration:
  • CPU Usage: Warning ${CPU_WARNING_THRESHOLD}%, Alert ${CPU_ALERT_THRESHOLD}%, Critical ${CPU_CRITICAL_THRESHOLD}%
  • Memory Usage: Warning ${MEMORY_WARNING_THRESHOLD}%, Alert ${MEMORY_ALERT_THRESHOLD}%, Critical ${MEMORY_CRITICAL_THRESHOLD}%
  • Load Average: Warning ${LOAD_WARNING_THRESHOLD}, Alert ${LOAD_ALERT_THRESHOLD}, Critical ${LOAD_CRITICAL_THRESHOLD} (1 OCPU)
  • SQLite Size: Warning ${SQLITE_SIZE_WARNING_MB}MB, Alert ${SQLITE_SIZE_ALERT_MB}MB, Critical ${SQLITE_SIZE_CRITICAL_MB}MB
  • WAL Size: Warning ${WAL_SIZE_WARNING_MB}MB, Alert ${WAL_SIZE_ALERT_MB}MB, Critical ${WAL_SIZE_CRITICAL_MB}MB

🔍 Monitoring Features:
  • Unified system resource monitoring with consistent thresholds
  • SQLite database analysis using centralized configuration
  • Container status monitoring with framework integration
  • Security monitoring with configurable banned IP thresholds
  • Email reports with unified formatting and threshold display

📧 Email Configuration (from settings.env):
  • ALERT_EMAIL: Primary alert destination
  • SMTP_HOST, SMTP_PORT, SMTP_USERNAME, SMTP_PASSWORD: Mail server config
  • WEBHOOK_URL: Alternative webhook notifications

Examples:
    $0                 # Full health check with unified configuration
    $0 --test          # Test unified configuration and email delivery
    $0 --help          # Show unified configuration documentation

Current Configuration Sources: $MONITORING_CONFIG_SOURCES
Framework Components Active: ${FRAMEWORK_COMPONENTS[*]:-"None (using fallback methods)"}

EOF
}

# Script entry point
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --test)
        check_dependencies
        log_info "Running unified configuration test..."
        main "--test"
        ;;
    *)
        check_dependencies
        main
        ;;
esac
