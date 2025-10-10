#!/usr/bin/env bash
# dashboard-metrics.sh -- System and resource metrics collection
# Centralized metrics gathering for consistent data across dashboard

# System performance metrics collection
dashboard_get_system_metrics() {
    local timestamp
    timestamp=$(date -Iseconds)

    # CPU usage
    local cpu_usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "0")

    # Memory usage
    local mem_total mem_used mem_free mem_usage_pct
    if command -v free >/dev/null 2>&1; then
        read -r mem_total mem_used mem_free < <(free -m | awk '/^Mem:/{print $2, $3, $4}')
        if command -v bc >/dev/null 2>&1; then
            mem_usage_pct=$(echo "scale=1; $mem_used * 100 / $mem_total" | bc || echo "0")
        else
            mem_usage_pct=$(( (mem_used * 100) / mem_total ))
        fi
    else
        mem_total="0"; mem_used="0"; mem_free="0"; mem_usage_pct="0"
    fi

    # Load average
    local load_1m load_5m load_15m
    if command -v uptime >/dev/null 2>&1; then
        read -r load_1m load_5m load_15m < <(uptime | awk -F'load average:' '{print $2}' | awk '{gsub(/,/, ""); print $1, $2, $3}' || echo "0 0 0")
    else
        load_1m="0"; load_5m="0"; load_15m="0"
    fi

    # Disk usage
    local disk_total disk_used disk_free disk_usage_pct
    if command -v df >/dev/null 2>&1; then
        read -r disk_total disk_used disk_free disk_usage_pct < <(df . | awk 'NR==2 {print $2, $3, $4, $5}' | sed 's/%//' || echo "0 0 0 0")
    else
        disk_total="0"; disk_used="0"; disk_free="0"; disk_usage_pct="0"
    fi

    # Output metrics as key=value pairs
    cat <<EOF
timestamp=$timestamp
cpu_usage=$cpu_usage
mem_total=$mem_total
mem_used=$mem_used
mem_free=$mem_free
mem_usage_pct=$mem_usage_pct
load_1m=$load_1m
load_5m=$load_5m
load_15m=$load_15m
disk_total=$disk_total
disk_used=$disk_used
disk_free=$disk_free
disk_usage_pct=$disk_usage_pct
EOF
}

# Container metrics collection
dashboard_get_container_metrics() {
    # Check Docker availability
    if ! command -v docker >/dev/null 2>&1; then
        echo "docker_available=false"
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        echo "docker_available=false"
        return 1
    fi

    echo "docker_available=true"

    # Expected services for SQLite deployment
    local services=("vaultwarden" "bw_caddy" "bw_fail2ban" "bw_backup" "bw_watchtower" "bw_ddclient")
    local running_count=0
    local total_count=${#services[@]}

    for service in "${services[@]}"; do
        local status="stopped"
        local uptime="N/A"
        local health="N/A"

        if docker ps --filter "name=$service" --filter "status=running" | grep -q "$service"; then
            status="running"
            uptime=$(docker ps --filter "name=$service" --format "{{.RunningFor}}" || echo "unknown")
            health=$(docker inspect "$service" --format='{{.State.Health.Status}}' || echo "no-health-check")
            ((running_count++))
        elif docker ps -a --filter "name=$service" | grep -q "$service"; then
            local exit_code
            exit_code=$(docker inspect "$service" --format='{{.State.ExitCode}}' || echo "unknown")
            status="stopped"
            uptime="exit: $exit_code"
        else
            status="not_found"
        fi

        echo "${service}_status=$status"
        echo "${service}_uptime=$uptime"
        echo "${service}_health=$health"
    done

    echo "containers_running=$running_count"
    echo "containers_total=$total_count"
}

# Network connectivity metrics
dashboard_get_network_metrics() {
    local local_access="false"
    local external_access="false"
    local internet_access="false"
    local ssl_status="unknown"
    local ssl_days_left="0"

    # Local access test
    if curl -sf http://localhost:80/alive >/dev/null 2>&1; then
        local_access="true"
    fi

    # External domain access (if configured)
    if [[ -n "${APP_DOMAIN:-}" ]]; then
        if curl -sf "${DOMAIN:-https://${APP_DOMAIN}}/alive" >/dev/null 2>&1; then
            external_access="true"
        fi

        # SSL certificate check
        if command -v openssl >/dev/null 2>&1; then
            local cert_expiry
            cert_expiry=$(echo | timeout 5 openssl s_client -servername "${APP_DOMAIN}" -connect "${APP_DOMAIN}:443" | openssl x509 -noout -dates | grep notAfter | cut -d= -f2)

            if [[ -n "$cert_expiry" ]]; then
                local cert_exp_epoch
                cert_exp_epoch=$(date -d "$cert_expiry" +%s || echo "0")
                ssl_days_left=$(( (cert_exp_epoch - $(date +%s)) / 86400 ))

                if [[ $ssl_days_left -gt 30 ]]; then
                    ssl_status="valid"
                elif [[ $ssl_days_left -gt 0 ]]; then
                    ssl_status="expiring"
                else
                    ssl_status="expired"
                fi
            fi
        fi
    fi

    # Internet connectivity test
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        internet_access="true"
    fi

    cat <<EOF
local_access=$local_access
external_access=$external_access
internet_access=$internet_access
ssl_status=$ssl_status
ssl_days_left=$ssl_days_left
app_domain=${APP_DOMAIN:-}
EOF
}

# Parse metrics from key=value format
dashboard_parse_metrics() {
    local metrics="$1"
    local key="$2"

    echo "$metrics" | grep "^${key}=" | cut -d'=' -f2-
}

# Evaluate metric against thresholds
dashboard_evaluate_metric() {
    local metric_name="$1"
    local value="$2"
    local warning_threshold="$3"
    local critical_threshold="$4"

    if command -v bc >/dev/null 2>&1; then
        if (( $(echo "$value > $critical_threshold" | bc -l || echo 0) )); then
            echo "critical"
        elif (( $(echo "$value > $warning_threshold" | bc -l || echo 0) )); then
            echo "warning"
        else
            echo "good"
        fi
    else
        # Fallback for systems without bc
        local value_int critical_int warning_int
        value_int=$(echo "$value" | cut -d'.' -f1)
        critical_int=$(echo "$critical_threshold" | cut -d'.' -f1)
        warning_int=$(echo "$warning_threshold" | cut -d'.' -f1)

        if [[ $value_int -gt $critical_int ]]; then
            echo "critical"
        elif [[ $value_int -gt $warning_int ]]; then
            echo "warning"
        else
            echo "good"
        fi
    fi
}

# Get system hostname and uptime
dashboard_get_system_info() {
    local hostname uptime
    hostname=$(hostname || echo "unknown")
    uptime=$(uptime -p || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}' || echo "unknown")

    echo "hostname=$hostname"
    echo "uptime=$uptime"
}

# Format bytes to human readable
dashboard_format_bytes() {
    local bytes="$1"
    local units=("B" "KB" "MB" "GB" "TB")
    local unit_index=0
    local size="$bytes"

    while [[ $size -gt 1024 && $unit_index -lt $((${#units[@]} - 1)) ]]; do
        size=$((size / 1024))
        ((unit_index++))
    done

    echo "${size}${units[$unit_index]}"
}

# Calculate percentage
dashboard_calculate_percentage() {
    local part="$1"
    local total="$2"

    if [[ $total -eq 0 ]]; then
        echo "0"
        return
    fi

    if command -v bc >/dev/null 2>&1; then
        echo "scale=1; $part * 100 / $total" | bc || echo "0"
    else
        echo $(( (part * 100) / total ))
    fi
}

# Export metrics functions
export -f dashboard_get_system_metrics
export -f dashboard_get_container_metrics
export -f dashboard_get_network_metrics
export -f dashboard_parse_metrics
export -f dashboard_evaluate_metric
export -f dashboard_get_system_info
export -f dashboard_format_bytes
export -f dashboard_calculate_percentage
