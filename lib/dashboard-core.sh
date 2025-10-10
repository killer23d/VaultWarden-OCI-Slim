#!/usr/bin/env bash
# dashboard-core.sh -- Core dashboard functionality and interactive modes
# Handles main dashboard display, user interaction, and mode management

# Dashboard state variables
declare -g DASHBOARD_RUNNING=false
declare -g DASHBOARD_LAST_REFRESH=0
declare -g DASHBOARD_CURRENT_VIEW="main"

# Initialize core dashboard
dashboard_core_init() {
    # Initialize all subsystems
    dashboard_config_init
    perf_collector_init || true
    perf_analyzer_init || true
    dashboard_sqlite_init

    # Set up signal handlers
    trap 'dashboard_core_cleanup' EXIT INT TERM
}

# Main dashboard display
dashboard_core_show_main() {
    local refresh_interval="${1:-5}"

    # Show header
    dashboard_show_header "VaultWarden-OCI-Slim Dashboard" "SQLite Optimized • 1 OCPU/6GB • Real-time Monitoring"

    # System Overview Section
    dashboard_show_section "System Overview" "BLUE"
    dashboard_core_show_system_overview

    # Resource Usage Section
    dashboard_show_section "Resource Usage (1 OCPU Context)" "CYAN"
    dashboard_core_show_resource_usage

    # SQLite Database Section
    dashboard_sqlite_show_comprehensive

    # Container Status Section
    dashboard_show_section "Container Status" "GREEN"
    dashboard_core_show_container_status

    # Recent Activity Section
    dashboard_show_section "Recent Activity" "PURPLE"
    dashboard_core_show_recent_activity

    # Show footer
    dashboard_show_footer "$refresh_interval"
}

# Show system overview
dashboard_core_show_system_overview() {
    # Get system info
    local system_info
    system_info=$(dashboard_get_system_info)

    local hostname uptime
    eval "$(echo "$system_info" | grep -E '^(hostname|uptime)=')"

    dashboard_show_keyvalue "Hostname" "$hostname" "info"
    dashboard_show_keyvalue "Uptime" "$uptime" "info"

    # Show current time and timezone
    dashboard_show_keyvalue "Current Time" "$(date '+%Y-%m-%d %H:%M:%S %Z')" "info"

    echo ""
}

# Show resource usage with 1 OCPU context
dashboard_core_show_resource_usage() {
    # Get system metrics
    local system_metrics
    system_metrics=$(dashboard_get_system_metrics)

    # Parse key metrics
    local cpu_usage mem_usage_pct load_1m disk_usage_pct
    eval "$(echo "$system_metrics" | grep -E '^(cpu_usage|mem_usage_pct|load_1m|disk_usage_pct)=')"

    # CPU Usage with 1 OCPU context
    local cpu_threshold_warning cpu_threshold_critical
    cpu_threshold_warning=$(dashboard_get_threshold "CPU_WARNING")
    cpu_threshold_critical=$(dashboard_get_threshold "CPU_CRITICAL")

    dashboard_progress_bar "$cpu_usage" "100" "20" "CPU Usage"

    # Load Average (critical for 1 OCPU)
    local load_status="good"
    if command -v bc >/dev/null 2>&1; then
        if (( $(echo "$load_1m > 1.5" | bc -l || echo 0) )); then
            load_status="critical"
        elif (( $(echo "$load_1m > 1.0" | bc -l || echo 0) )); then
            load_status="warning"
        fi
    fi

    dashboard_show_keyvalue "Load Avg (1min)" "$load_1m" "$load_status"
    if [[ "$load_status" == "critical" ]]; then
        echo "    ⚠️  Single CPU overloaded!"
    fi

    # Memory Usage
    dashboard_progress_bar "$mem_usage_pct" "100" "20" "Memory"

    # Disk Usage
    dashboard_progress_bar "$disk_usage_pct" "100" "20" "Disk Space"

    echo ""
}

# Show container status
dashboard_core_show_container_status() {
    local container_metrics
    container_metrics=$(dashboard_get_container_metrics)

    if [[ ! "$container_metrics" =~ docker_available=true ]]; then
        dashboard_status_indicator "critical" "Docker not available"
        return 1
    fi

    # Parse container metrics
    local containers_running containers_total
    eval "$(echo "$container_metrics" | grep -E '^containers_(running|total)=')"

    dashboard_show_keyvalue "Services" "$containers_running/$containers_total running" "info"

    # Show individual service status
    local services=("vaultwarden" "bw_caddy" "bw_fail2ban" "bw_backup" "bw_watchtower" "bw_ddclient")

    for service in "${services[@]}"; do
        local service_status service_health
        eval "$(echo "$container_metrics" | grep -E "^${service}_(status|health)=")"

        case "$service_status" in
            "running")
                case "$service_health" in
                    "healthy"|"no-health-check")
                        dashboard_status_indicator "good" "$service"
                        ;;
                    "starting")
                        dashboard_status_indicator "warning" "$service (starting)"
                        ;;
                    "unhealthy")
                        dashboard_status_indicator "critical" "$service (unhealthy)"
                        ;;
                    *)
                        dashboard_status_indicator "info" "$service (running)"
                        ;;
                esac
                ;;
            "stopped")
                dashboard_status_indicator "warning" "$service (stopped)"
                ;;
            "not_found")
                dashboard_status_indicator "info" "$service (not configured)"
                ;;
            *)
                dashboard_status_indicator "unknown" "$service"
                ;;
        esac
    done

    echo ""
}

# Show recent activity
dashboard_core_show_recent_activity() {
    # SQLite activity
    local sqlite_activity
    sqlite_activity=$(dashboard_sqlite_monitor_changes)

    if [[ "$sqlite_activity" =~ database=available ]]; then
        local activity
        eval "$(echo "$sqlite_activity" | grep '^activity=')"

        case "$activity" in
            "active")
                echo "🔄 Database: Active writes detected"
                ;;
            "recent") 
                echo "📝 Database: Recent activity (last 15min)"
                ;;
            "idle")
                echo "💤 Database: Idle"
                ;;
        esac
    else
        echo "❓ Database activity: Unknown"
    fi

    # System load trend (simplified)
    local current_time=$(date +%s)
    if [[ $((current_time - DASHBOARD_LAST_REFRESH)) -gt 10 ]]; then
        local load_now
        load_now=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',' || echo "0")

        echo "📊 Current system load: $load_now"
    fi

    echo ""
}

# Interactive mode main loop
dashboard_interactive_mode() {
    local refresh_interval="${1:-5}"

    DASHBOARD_RUNNING=true
    dashboard_core_init

    log_info "Starting interactive dashboard (refresh: ${refresh_interval}s)"

    while [[ "$DASHBOARD_RUNNING" == "true" ]]; do
        dashboard_core_show_main "$refresh_interval"
        DASHBOARD_LAST_REFRESH=$(date +%s)

        # Wait for input with timeout
        if read -t "$refresh_interval" -n 1 -s input; then
            case "$input" in
                q|Q)
                    DASHBOARD_RUNNING=false
                    echo "Exiting dashboard..."
                    ;;
                r|R)
                    # Immediate refresh
                    continue
                    ;;
                s|S)
                    dashboard_core_status_menu
                    ;;
                d|D)
                    dashboard_core_diagnostics_menu
                    ;;
                m|M)
                    dashboard_core_maintenance_menu
                    ;;
                a|A)
                    dashboard_core_alerts_menu
                    ;;
                h|H)
                    dashboard_show_help
                    ;;
                *)
                    # Invalid input, just refresh
                    continue
                    ;;
            esac
        fi
    done
}

# Static mode (single display)
dashboard_static_mode() {
    dashboard_core_init
    dashboard_core_show_main 0
}

# Status menu
dashboard_core_status_menu() {
    dashboard_show_header_simple "System Status Details"

    echo "🔍 Running comprehensive status check..."
    echo ""

    # Detailed system status
    local system_metrics
    system_metrics=$(dashboard_get_system_metrics)

    echo "System Resources:"
    local cpu_usage mem_usage_pct load_1m disk_usage_pct
    eval "$(echo "$system_metrics" | grep -E '^(cpu_usage|mem_usage_pct|load_1m|disk_usage_pct)=')"

    printf "  CPU Usage:    %s%%\n" "$cpu_usage"
    printf "  Memory Usage: %s%%\n" "$mem_usage_pct"  
    printf "  Load Average: %s\n" "$load_1m"
    printf "  Disk Usage:   %s%%\n" "$disk_usage_pct"

    echo ""

    # SQLite detailed status
    dashboard_sqlite_show_status

    dashboard_wait_input
}

# Diagnostics menu
dashboard_core_diagnostics_menu() {
    dashboard_show_header_simple "System Diagnostics"

    echo "🔧 Running system diagnostics..."
    echo ""

    # System requirements check
    if command -v validate_system_requirements >/dev/null 2>&1; then
        echo "System Requirements:"
        if validate_system_requirements >/dev/null 2>&1; then
            echo "  ✅ All system requirements met"
        else
            echo "  ⚠️  Some requirements issues detected"
        fi
    fi

    # Docker status
    if command -v check_docker >/dev/null 2>&1; then
        echo ""
        echo "Docker Status:"
        if check_docker; then
            echo "  ✅ Docker is available and running"
        else
            echo "  ❌ Docker issues detected"
        fi
    fi

    # SQLite diagnostics
    echo ""
    echo "SQLite Database:"
    local sqlite_health
    sqlite_health=$(dashboard_sqlite_quick_check)

    case "$sqlite_health" in
        "healthy")
            echo "  ✅ Database is healthy"
            ;;
        "issues")
            echo "  ⚠️  Database has integrity issues"
            ;;
        "not_found"|"inaccessible")
            echo "  ❌ Database is not accessible"
            ;;
    esac

    # Performance test
    echo ""
    echo "Performance Test:"
    local perf_result
    perf_result=$(dashboard_sqlite_get_performance)

    if [[ "$perf_result" != "failed" && "$perf_result" != "unavailable" ]]; then
        echo "  ✅ Database query test: $perf_result"
    else
        echo "  ❌ Performance test failed"
    fi

    echo ""
    dashboard_wait_input
}

# Maintenance menu integration
dashboard_core_maintenance_menu() {
    if command -v dashboard_maintenance_show_menu >/dev/null 2>&1; then
        dashboard_maintenance_show_menu
    else
        dashboard_show_header_simple "SQLite Maintenance"
        echo "Maintenance menu not available."
        echo ""
        echo "Available maintenance operations:"
        echo "  • Run: ./sqlite-maintenance.sh --analyze"
        echo "  • Run: ./sqlite-maintenance.sh (intelligent auto)"
        echo "  • Run: ./sqlite-maintenance.sh --comprehensive"
        echo ""
        dashboard_wait_input
    fi
}

# Alerts menu
dashboard_core_alerts_menu() {
    dashboard_show_header_simple "System Alerts"

    echo "🚨 Checking for system alerts..."
    echo ""

    local alerts_found=false

    # Resource alerts
    local system_metrics
    system_metrics=$(dashboard_get_system_metrics)

    local cpu_usage load_1m
    eval "$(echo "$system_metrics" | grep -E '^(cpu_usage|load_1m)=')"

    # CPU alerts
    if command -v bc >/dev/null 2>&1 && (( $(echo "$cpu_usage > 90" | bc -l || echo 0) )); then
        echo "🚨 HIGH CPU USAGE: ${cpu_usage}% (critical for 1 OCPU)"
        alerts_found=true
    fi

    # Load alerts  
    if command -v bc >/dev/null 2>&1 && (( $(echo "$load_1m > 1.5" | bc -l || echo 0) )); then
        echo "🚨 HIGH LOAD AVERAGE: $load_1m (critical for 1 OCPU)"
        alerts_found=true
    fi

    # SQLite alerts
    if dashboard_sqlite_check_maintenance_needed; then
        echo "🔧 MAINTENANCE RECOMMENDED: SQLite database needs attention"
        alerts_found=true
    fi

    # Container alerts
    local container_metrics
    container_metrics=$(dashboard_get_container_metrics)

    # Check for stopped critical services
    local services=("vaultwarden" "bw_caddy")
    for service in "${services[@]}"; do
        local service_status
        eval "$(echo "$container_metrics" | grep "^${service}_status=")"

        if [[ "$service_status" != "running" ]]; then
            echo "🚨 CRITICAL SERVICE DOWN: $service is $service_status"
            alerts_found=true
        fi
    done

    if [[ "$alerts_found" == "false" ]]; then
        echo "✅ No active alerts - system is running normally"
    fi

    echo ""
    dashboard_wait_input
}

# Refresh dashboard data
dashboard_core_refresh() {
    # Clear performance cache if available
    if command -v perf_collector_clear_cache >/dev/null 2>&1; then
        perf_collector_clear_cache
    fi

    DASHBOARD_LAST_REFRESH=$(date +%s)
}

# Handle keyboard input in interactive mode
dashboard_core_handle_input() {
    local input="$1"

    case "$input" in
        q|Q)
            DASHBOARD_RUNNING=false
            return 0
            ;;
        r|R)
            dashboard_core_refresh
            return 0
            ;;
        s|S)
            dashboard_core_status_menu
            return 0
            ;;
        d|D)
            dashboard_core_diagnostics_menu
            return 0
            ;;
        m|M)
            dashboard_core_maintenance_menu
            return 0
            ;;
        a|A)
            dashboard_core_alerts_menu
            return 0
            ;;
        h|H)
            dashboard_show_help
            return 0
            ;;
        *)
            return 1  # Unknown input
            ;;
    esac
}

# Check if dashboard should continue running
dashboard_core_should_continue() {
    [[ "$DASHBOARD_RUNNING" == "true" ]]
}

# Get dashboard current state
dashboard_core_get_state() {
    cat <<EOF
running=$DASHBOARD_RUNNING
last_refresh=$DASHBOARD_LAST_REFRESH
current_view=$DASHBOARD_CURRENT_VIEW
uptime=$(($(date +%s) - ${DASHBOARD_START_TIME:-$(date +%s)}))
EOF
}

# Set dashboard view
dashboard_core_set_view() {
    local view="$1"
    DASHBOARD_CURRENT_VIEW="$view"
}

# Quick system health check
dashboard_core_quick_health_check() {
    local health_issues=0

    # Check critical services
    local container_metrics
    container_metrics=$(dashboard_get_container_metrics)

    local critical_services=("vaultwarden" "bw_caddy")
    for service in "${critical_services[@]}"; do
        local service_status
        eval "$(echo "$container_metrics" | grep "^${service}_status=")"

        if [[ "$service_status" != "running" ]]; then
            ((health_issues++))
        fi
    done

    # Check system resources
    local system_metrics
    system_metrics=$(dashboard_get_system_metrics)

    local load_1m
    eval "$(echo "$system_metrics" | grep '^load_1m=')"

    if command -v bc >/dev/null 2>&1 && (( $(echo "$load_1m > 1.5" | bc -l || echo 0) )); then
        ((health_issues++))
    fi

    # Check SQLite
    local sqlite_status
    sqlite_status=$(dashboard_sqlite_quick_check)

    if [[ "$sqlite_status" != "healthy" ]]; then
        ((health_issues++))
    fi

    return $health_issues
}

# Show quick health status
dashboard_core_show_health_indicator() {
    if dashboard_core_quick_health_check; then
        dashboard_status_indicator "good" "System Health: All OK"
    else
        local issue_count=$?
        dashboard_status_indicator "warning" "System Health: $issue_count issues"
    fi
}

# Cleanup function
dashboard_core_cleanup() {
    DASHBOARD_RUNNING=false

    # Clear screen on exit if in interactive mode
    if [[ -t 0 ]]; then
        clear
        echo "Dashboard stopped."
    fi

    # Restore terminal settings
    stty sane || true
}

# Export core dashboard functions
export -f dashboard_core_init
export -f dashboard_core_show_main
export -f dashboard_interactive_mode
export -f dashboard_static_mode
export -f dashboard_core_refresh
export -f dashboard_core_handle_input
export -f dashboard_core_should_continue
export -f dashboard_core_get_state
export -f dashboard_core_set_view
export -f dashboard_core_quick_health_check
export -f dashboard_core_show_health_indicator
export -f dashboard_core_cleanup
