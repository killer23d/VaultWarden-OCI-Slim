#!/usr/bin/env bash
# perf-analyzer.sh -- Performance analysis and threshold checking framework
# Analyzes collected metrics against configurable thresholds

# Performance thresholds (configurable)
declare -A PERF_THRESHOLDS=(
    # CPU thresholds (1 OCPU optimized)
    ["CPU_WARNING"]=70
    ["CPU_CRITICAL"]=90
    ["LOAD_WARNING"]=1.0
    ["LOAD_CRITICAL"]=1.5

    # Memory thresholds (6GB optimized)
    ["MEMORY_WARNING"]=70
    ["MEMORY_CRITICAL"]=85
    ["SWAP_WARNING"]=10
    ["SWAP_CRITICAL"]=50

    # Disk thresholds
    ["DISK_WARNING"]=80
    ["DISK_CRITICAL"]=95

    # Network thresholds
    ["NETWORK_ERROR_RATE_WARNING"]=0.01
    ["NETWORK_ERROR_RATE_CRITICAL"]=0.05

    # Temperature thresholds
    ["TEMP_WARNING"]=70
    ["TEMP_CRITICAL"]=80
)

# Performance targets for 1 OCPU/6GB deployment
declare -A PERF_TARGETS=(
    ["TARGET_CPU_IDLE"]=50
    ["TARGET_MEMORY_USAGE_MB"]=672
    ["TARGET_MEMORY_USAGE_PCT"]=11
    ["TARGET_LOAD_OPTIMAL"]=0.8
    ["TARGET_RESPONSE_TIME_MS"]=100
)

# Analysis results storage
declare -A PERF_ANALYSIS_RESULTS=()
declare -a PERF_WARNINGS=()
declare -a PERF_CRITICAL_ISSUES=()
declare -a PERF_RECOMMENDATIONS=()

# Initialize performance analyzer
perf_analyzer_init() {
    # Load thresholds from config if available
    local config_file="$SCRIPT_DIR/config/alert-thresholds.conf"
    if [[ -f "$config_file" ]]; then
        perf_analyzer_load_thresholds "$config_file"
    fi

    # Load targets from config if available
    local targets_file="$SCRIPT_DIR/config/performance-targets.conf"
    if [[ -f "$targets_file" ]]; then
        perf_analyzer_load_targets "$targets_file"
    fi
}

# Load thresholds from configuration file
perf_analyzer_load_thresholds() {
    local config_file="$1"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue

        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Update threshold if valid
        if [[ -n "${PERF_THRESHOLDS[$key]:-}" ]]; then
            PERF_THRESHOLDS["$key"]="$value"
        fi
    done < "$config_file"
}

# Load performance targets from configuration file
perf_analyzer_load_targets() {
    local config_file="$1"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue

        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Update target if valid
        if [[ -n "${PERF_TARGETS[$key]:-}" ]]; then
            PERF_TARGETS["$key"]="$value"
        fi
    done < "$config_file"
}

# Compare value against thresholds
perf_analyzer_evaluate_threshold() {
    local metric_name="$1"
    local value="$2"
    local warning_threshold="$3"
    local critical_threshold="$4"
    local comparison="${5:-greater}"  # greater or less

    local status="good"

    if command -v bc >/dev/null 2>&1; then
        case "$comparison" in
            "greater")
                if (( $(echo "$value > $critical_threshold" | bc -l 2>/dev/null || echo 0) )); then
                    status="critical"
                elif (( $(echo "$value > $warning_threshold" | bc -l 2>/dev/null || echo 0) )); then
                    status="warning"
                fi
                ;;
            "less")
                if (( $(echo "$value < $critical_threshold" | bc -l 2>/dev/null || echo 0) )); then
                    status="critical"
                elif (( $(echo "$value < $warning_threshold" | bc -l 2>/dev/null || echo 0) )); then
                    status="warning"
                fi
                ;;
        esac
    else
        # Fallback for systems without bc (integer comparison only)
        local value_int warning_int critical_int
        value_int=$(echo "$value" | cut -d'.' -f1)
        warning_int=$(echo "$warning_threshold" | cut -d'.' -f1)
        critical_int=$(echo "$critical_threshold" | cut -d'.' -f1)

        case "$comparison" in
            "greater")
                if [[ $value_int -gt $critical_int ]]; then
                    status="critical"
                elif [[ $value_int -gt $warning_int ]]; then
                    status="warning"
                fi
                ;;
            "less")
                if [[ $value_int -lt $critical_int ]]; then
                    status="critical"
                elif [[ $value_int -lt $warning_int ]]; then
                    status="warning"
                fi
                ;;
        esac
    fi

    echo "$status"
}

# Analyze CPU performance
perf_analyzer_analyze_cpu() {
    local cpu_metrics="$1"

    # Parse CPU metrics
    local cpu_usage cpu_cores load_1m load_5m cpu_temp
    eval "$(echo "$cpu_metrics" | grep -E '^(cpu_usage|cpu_cores|load_1m|load_5m|cpu_temp)=')"

    # Clear previous results
    unset PERF_ANALYSIS_RESULTS["cpu_status"]
    unset PERF_ANALYSIS_RESULTS["load_status"]

    # Analyze CPU usage
    local cpu_status
    cpu_status=$(perf_analyzer_evaluate_threshold "CPU" "$cpu_usage" "${PERF_THRESHOLDS[CPU_WARNING]}" "${PERF_THRESHOLDS[CPU_CRITICAL]}")
    PERF_ANALYSIS_RESULTS["cpu_status"]="$cpu_status"
    PERF_ANALYSIS_RESULTS["cpu_usage"]="$cpu_usage"

    case "$cpu_status" in
        "critical")
            PERF_CRITICAL_ISSUES+=("CPU usage ${cpu_usage}% is critical (>${PERF_THRESHOLDS[CPU_CRITICAL]}%) for 1 OCPU")
            PERF_RECOMMENDATIONS+=("Check for runaway processes and reduce VaultWarden workers to 1")
            ;;
        "warning")
            PERF_WARNINGS+=("CPU usage ${cpu_usage}% is high (>${PERF_THRESHOLDS[CPU_WARNING]}%) for 1 OCPU")
            PERF_RECOMMENDATIONS+=("Monitor CPU usage and ensure WEBSOCKET_ENABLED=false")
            ;;
    esac

    # Analyze load average (critical for single CPU)
    local load_status
    load_status=$(perf_analyzer_evaluate_threshold "LOAD" "$load_1m" "${PERF_THRESHOLDS[LOAD_WARNING]}" "${PERF_THRESHOLDS[LOAD_CRITICAL]}")
    PERF_ANALYSIS_RESULTS["load_status"]="$load_status"
    PERF_ANALYSIS_RESULTS["load_1m"]="$load_1m"

    case "$load_status" in
        "critical")
            PERF_CRITICAL_ISSUES+=("Load average ${load_1m} is critical (>${PERF_THRESHOLDS[LOAD_CRITICAL]}) for 1 OCPU")
            PERF_RECOMMENDATIONS+=("Single CPU is overloaded - identify high-CPU processes immediately")
            ;;
        "warning")
            PERF_WARNINGS+=("Load average ${load_1m} is elevated (>${PERF_THRESHOLDS[LOAD_WARNING]}) for 1 OCPU")
            PERF_RECOMMENDATIONS+=("Monitor load closely - single CPU utilization is significant")
            ;;
    esac

    # Temperature analysis (if available)
    if [[ "$cpu_temp" != "N/A" ]] && [[ "$cpu_temp" != "0" ]]; then
        local temp_status
        temp_status=$(perf_analyzer_evaluate_threshold "TEMP" "$cpu_temp" "${PERF_THRESHOLDS[TEMP_WARNING]}" "${PERF_THRESHOLDS[TEMP_CRITICAL]}")
        PERF_ANALYSIS_RESULTS["temp_status"]="$temp_status"
        PERF_ANALYSIS_RESULTS["cpu_temp"]="$cpu_temp"

        case "$temp_status" in
            "critical")
                PERF_CRITICAL_ISSUES+=("CPU temperature ${cpu_temp}°C is critical (>${PERF_THRESHOLDS[TEMP_CRITICAL]}°C)")
                PERF_RECOMMENDATIONS+=("Check cooling system and reduce CPU load immediately")
                ;;
            "warning")
                PERF_WARNINGS+=("CPU temperature ${cpu_temp}°C is elevated (>${PERF_THRESHOLDS[TEMP_WARNING]}°C)")
                ;;
        esac
    fi
}

# Analyze memory performance
perf_analyzer_analyze_memory() {
    local memory_metrics="$1"

    # Parse memory metrics
    local mem_total mem_used mem_available swap_total swap_used
    eval "$(echo "$memory_metrics" | grep -E '^(mem_total|mem_used|mem_available|swap_total|swap_used)=')"

    # Calculate percentages
    local mem_usage_pct swap_usage_pct
    if [[ $mem_total -gt 0 ]]; then
        if command -v bc >/dev/null 2>&1; then
            mem_usage_pct=$(echo "scale=1; $mem_used * 100 / $mem_total" | bc)
        else
            mem_usage_pct=$(( (mem_used * 100) / mem_total ))
        fi
    else
        mem_usage_pct="0"
    fi

    if [[ $swap_total -gt 0 ]]; then
        if command -v bc >/dev/null 2>&1; then
            swap_usage_pct=$(echo "scale=1; $swap_used * 100 / $swap_total" | bc)
        else
            swap_usage_pct=$(( (swap_used * 100) / swap_total ))
        fi
    else
        swap_usage_pct="0"
    fi

    # Analyze memory usage
    local mem_status
    mem_status=$(perf_analyzer_evaluate_threshold "MEMORY" "$mem_usage_pct" "${PERF_THRESHOLDS[MEMORY_WARNING]}" "${PERF_THRESHOLDS[MEMORY_CRITICAL]}")
    PERF_ANALYSIS_RESULTS["memory_status"]="$mem_status"
    PERF_ANALYSIS_RESULTS["memory_usage_pct"]="$mem_usage_pct"
    PERF_ANALYSIS_RESULTS["memory_used_mb"]=$(( mem_used / 1024 / 1024 ))

    case "$mem_status" in
        "critical")
            PERF_CRITICAL_ISSUES+=("Memory usage ${mem_usage_pct}% is critical (>${PERF_THRESHOLDS[MEMORY_CRITICAL]}%)")
            PERF_RECOMMENDATIONS+=("Check for memory leaks and reduce container memory limits")
            ;;
        "warning")
            PERF_WARNINGS+=("Memory usage ${mem_usage_pct}% is high (>${PERF_THRESHOLDS[MEMORY_WARNING]}%)")
            PERF_RECOMMENDATIONS+=("Target: ~${PERF_TARGETS[TARGET_MEMORY_USAGE_MB]}MB total for all containers")
            ;;
    esac

    # Analyze swap usage
    if [[ $swap_total -gt 0 ]]; then
        local swap_status
        swap_status=$(perf_analyzer_evaluate_threshold "SWAP" "$swap_usage_pct" "${PERF_THRESHOLDS[SWAP_WARNING]}" "${PERF_THRESHOLDS[SWAP_CRITICAL]}")
        PERF_ANALYSIS_RESULTS["swap_status"]="$swap_status"
        PERF_ANALYSIS_RESULTS["swap_usage_pct"]="$swap_usage_pct"

        case "$swap_status" in
            "critical")
                PERF_CRITICAL_ISSUES+=("Swap usage ${swap_usage_pct}% is critical - system under memory pressure")
                PERF_RECOMMENDATIONS+=("Increase available memory or reduce memory usage immediately")
                ;;
            "warning")
                PERF_WARNINGS+=("Swap usage ${swap_usage_pct}% indicates memory pressure")
                ;;
        esac
    fi
}

# Analyze disk performance
perf_analyzer_analyze_disk() {
    local disk_metrics="$1"

    # Parse disk metrics
    local disk_usage_pct disk_total disk_free
    eval "$(echo "$disk_metrics" | grep -E '^(disk_usage_pct|disk_total|disk_free)=')"

    # Analyze disk usage
    local disk_status
    disk_status=$(perf_analyzer_evaluate_threshold "DISK" "$disk_usage_pct" "${PERF_THRESHOLDS[DISK_WARNING]}" "${PERF_THRESHOLDS[DISK_CRITICAL]}")
    PERF_ANALYSIS_RESULTS["disk_status"]="$disk_status"
    PERF_ANALYSIS_RESULTS["disk_usage_pct"]="$disk_usage_pct"
    PERF_ANALYSIS_RESULTS["disk_free_gb"]=$(( disk_free / 1024 / 1024 / 1024 ))

    case "$disk_status" in
        "critical")
            PERF_CRITICAL_ISSUES+=("Disk usage ${disk_usage_pct}% is critical (>${PERF_THRESHOLDS[DISK_CRITICAL]}%)")
            PERF_RECOMMENDATIONS+=("Clean up old backups, logs, and run SQLite VACUUM operation")
            ;;
        "warning")
            PERF_WARNINGS+=("Disk usage ${disk_usage_pct}% is high (>${PERF_THRESHOLDS[DISK_WARNING]}%)")
            PERF_RECOMMENDATIONS+=("Monitor disk usage and consider cleanup procedures")
            ;;
    esac
}

# Analyze network performance
perf_analyzer_analyze_network() {
    local network_metrics="$1"

    # Parse network metrics
    local net_rx_packets net_tx_packets net_rx_errors net_tx_errors
    eval "$(echo "$network_metrics" | grep -E '^(net_rx_packets|net_tx_packets|net_rx_errors|net_tx_errors)=')"

    # Calculate error rates
    local total_packets error_rate
    total_packets=$((net_rx_packets + net_tx_packets))
    local total_errors=$((net_rx_errors + net_tx_errors))

    if [[ $total_packets -gt 0 ]]; then
        if command -v bc >/dev/null 2>&1; then
            error_rate=$(echo "scale=4; $total_errors / $total_packets" | bc)
        else
            error_rate=$(( total_errors * 10000 / total_packets ))
            error_rate="0.$(printf "%04d" $error_rate)"
        fi
    else
        error_rate="0"
    fi

    # Analyze network error rate
    local network_status
    network_status=$(perf_analyzer_evaluate_threshold "NETWORK" "$error_rate" "${PERF_THRESHOLDS[NETWORK_ERROR_RATE_WARNING]}" "${PERF_THRESHOLDS[NETWORK_ERROR_RATE_CRITICAL]}")
    PERF_ANALYSIS_RESULTS["network_status"]="$network_status"
    PERF_ANALYSIS_RESULTS["network_error_rate"]="$error_rate"
    PERF_ANALYSIS_RESULTS["network_total_errors"]="$total_errors"

    case "$network_status" in
        "critical")
            PERF_CRITICAL_ISSUES+=("Network error rate ${error_rate} is critical (>${PERF_THRESHOLDS[NETWORK_ERROR_RATE_CRITICAL]})")
            PERF_RECOMMENDATIONS+=("Check network connectivity and interface configuration")
            ;;
        "warning")
            PERF_WARNINGS+=("Network error rate ${error_rate} is elevated (>${PERF_THRESHOLDS[NETWORK_ERROR_RATE_WARNING]})")
            ;;
    esac
}

# Perform comprehensive performance analysis
perf_analyzer_analyze_full() {
    local system_metrics="$1"

    # Clear previous analysis results
    PERF_ANALYSIS_RESULTS=()
    PERF_WARNINGS=()
    PERF_CRITICAL_ISSUES=()
    PERF_RECOMMENDATIONS=()

    # Parse and analyze each metric type
    local cpu_metrics memory_metrics disk_metrics network_metrics
    cpu_metrics=$(echo "$system_metrics" | grep -E '^(cpu_|load_)')
    memory_metrics=$(echo "$system_metrics" | grep -E '^(mem_|swap_)')
    disk_metrics=$(echo "$system_metrics" | grep -E '^disk_')
    network_metrics=$(echo "$system_metrics" | grep -E '^net_')

    # Run individual analyses
    [[ -n "$cpu_metrics" ]] && perf_analyzer_analyze_cpu "$cpu_metrics"
    [[ -n "$memory_metrics" ]] && perf_analyzer_analyze_memory "$memory_metrics"
    [[ -n "$disk_metrics" ]] && perf_analyzer_analyze_disk "$disk_metrics"
    [[ -n "$network_metrics" ]] && perf_analyzer_analyze_network "$network_metrics"

    # Calculate overall health score
    local total_issues critical_count warning_count health_score
    critical_count=${#PERF_CRITICAL_ISSUES[@]}
    warning_count=${#PERF_WARNINGS[@]}
    total_issues=$((critical_count + warning_count))

    if [[ $critical_count -gt 0 ]]; then
        health_score="critical"
    elif [[ $warning_count -gt 2 ]]; then
        health_score="poor"
    elif [[ $warning_count -gt 0 ]]; then
        health_score="fair"
    else
        health_score="good"
    fi

    PERF_ANALYSIS_RESULTS["overall_health"]="$health_score"
    PERF_ANALYSIS_RESULTS["critical_issues"]="$critical_count"
    PERF_ANALYSIS_RESULTS["warnings"]="$warning_count"
    PERF_ANALYSIS_RESULTS["analysis_timestamp"]=$(date +%s)

    # Export results for external access
    export PERF_ANALYSIS_RESULTS
    export PERF_WARNINGS
    export PERF_CRITICAL_ISSUES
    export PERF_RECOMMENDATIONS
}

# Get analysis result
perf_analyzer_get_result() {
    local result_key="$1"
    echo "${PERF_ANALYSIS_RESULTS[$result_key]:-unknown}"
}

# Get all warnings
perf_analyzer_get_warnings() {
    printf '%s
' "${PERF_WARNINGS[@]}"
}

# Get all critical issues
perf_analyzer_get_critical_issues() {
    printf '%s
' "${PERF_CRITICAL_ISSUES[@]}"
}

# Get all recommendations
perf_analyzer_get_recommendations() {
    printf '%s
' "${PERF_RECOMMENDATIONS[@]}"
}

# Check if system has critical issues
perf_analyzer_has_critical_issues() {
    [[ ${#PERF_CRITICAL_ISSUES[@]} -gt 0 ]]
}

# Check if system has warnings
perf_analyzer_has_warnings() {
    [[ ${#PERF_WARNINGS[@]} -gt 0 ]]
}

# Get threshold value
perf_analyzer_get_threshold() {
    local threshold_name="$1"
    echo "${PERF_THRESHOLDS[$threshold_name]:-0}"
}

# Get performance target
perf_analyzer_get_target() {
    local target_name="$1"
    echo "${PERF_TARGETS[$target_name]:-0}"
}

# Export analyzer functions
export -f perf_analyzer_init
export -f perf_analyzer_analyze_full
export -f perf_analyzer_get_result
export -f perf_analyzer_get_warnings
export -f perf_analyzer_get_critical_issues
export -f perf_analyzer_get_recommendations
export -f perf_analyzer_has_critical_issues
export -f perf_analyzer_has_warnings
export -f perf_analyzer_get_threshold
export -f perf_analyzer_get_target
