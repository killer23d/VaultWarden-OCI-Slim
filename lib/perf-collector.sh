#!/usr/bin/env bash
# perf-collector.sh -- Generic performance data collection framework
# Centralized, reusable performance metrics collection for all VaultWarden scripts

# Global configuration
declare -A PERF_COLLECTOR_CONFIG=(
    ["COLLECTION_TIMEOUT"]=30
    ["CACHE_DURATION"]=5
    ["ENABLE_CACHING"]=true
    ["DEBUG_MODE"]=false
)

# Cache variables
declare -A PERF_CACHE_DATA=()
declare -A PERF_CACHE_TIMESTAMPS=()

# Initialize performance collector
perf_collector_init() {
    # Load configuration from file if available
    local config_file="$SCRIPT_DIR/config/monitoring-intervals.conf"
    if [[ -f "$config_file" ]]; then
        perf_collector_load_config "$config_file"
    fi

    # Set debug mode from environment
    [[ "${DEBUG:-false}" == "true" ]] && PERF_COLLECTOR_CONFIG["DEBUG_MODE"]=true
}

# Load configuration from file
perf_collector_load_config() {
    local config_file="$1"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue

        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Update config if valid
        if [[ -n "${PERF_COLLECTOR_CONFIG[$key]:-}" ]]; then
            PERF_COLLECTOR_CONFIG["$key"]="$value"
        fi
    done < "$config_file"
}

# Debug logging
perf_collector_debug() {
    [[ "${PERF_COLLECTOR_CONFIG[DEBUG_MODE]}" == "true" ]] && echo "[PERF-DEBUG] $*" >&2
}

# Check if cached data is valid
perf_collector_cache_valid() {
    local cache_key="$1"
    local current_time=$(date +%s)
    local cache_timestamp="${PERF_CACHE_TIMESTAMPS[$cache_key]:-0}"
    local cache_duration="${PERF_COLLECTOR_CONFIG[CACHE_DURATION]}"

    [[ "${PERF_COLLECTOR_CONFIG[ENABLE_CACHING]}" == "true" ]] && 
    [[ $((current_time - cache_timestamp)) -lt $cache_duration ]]
}

# Store data in cache
perf_collector_cache_store() {
    local cache_key="$1"
    local data="$2"

    if [[ "${PERF_COLLECTOR_CONFIG[ENABLE_CACHING]}" == "true" ]]; then
        PERF_CACHE_DATA["$cache_key"]="$data"
        PERF_CACHE_TIMESTAMPS["$cache_key"]=$(date +%s)
        perf_collector_debug "Cached data for key: $cache_key"
    fi
}

# Retrieve data from cache
perf_collector_cache_get() {
    local cache_key="$1"
    echo "${PERF_CACHE_DATA[$cache_key]:-}"
}

# Collect system CPU metrics
perf_collector_cpu() {
    local cache_key="cpu_metrics"

    # Check cache first
    if perf_collector_cache_valid "$cache_key"; then
        perf_collector_cache_get "$cache_key"
        return 0
    fi

    perf_collector_debug "Collecting CPU metrics"

    local cpu_usage cpu_cores load_1m load_5m load_15m cpu_temp

    # CPU usage percentage
    if command -v top >/dev/null 2>&1; then
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "0")
    else
        cpu_usage="0"
    fi

    # CPU cores count
    cpu_cores=$(nproc || grep -c ^processor /proc/cpuinfo || echo "1")

    # Load averages
    if command -v uptime >/dev/null 2>&1; then
        read -r load_1m load_5m load_15m < <(uptime | awk -F'load average:' '{print $2}' | awk '{gsub(/,/, ""); print $1, $2, $3}' || echo "0 0 0")
    else
        load_1m="0"; load_5m="0"; load_15m="0"
    fi

    # CPU temperature (if available)
    if [[ -f "/sys/class/thermal/thermal_zone0/temp" ]]; then
        local temp_millicelsius
        temp_millicelsius=$(cat /sys/class/thermal/thermal_zone0/temp || echo "0")
        cpu_temp=$((temp_millicelsius / 1000))
    else
        cpu_temp="N/A"
    fi

    local result
    result=$(cat <<EOF
cpu_usage=$cpu_usage
cpu_cores=$cpu_cores
load_1m=$load_1m
load_5m=$load_5m
load_15m=$load_15m
cpu_temp=$cpu_temp
timestamp=$(date +%s)
EOF
)

    perf_collector_cache_store "$cache_key" "$result"
    echo "$result"
}

# Collect system memory metrics
perf_collector_memory() {
    local cache_key="memory_metrics"

    # Check cache first
    if perf_collector_cache_valid "$cache_key"; then
        perf_collector_cache_get "$cache_key"
        return 0
    fi

    perf_collector_debug "Collecting memory metrics"

    local mem_total mem_used mem_free mem_available mem_cached mem_buffers swap_total swap_used

    if command -v free >/dev/null 2>&1; then
        # Parse free output
        read -r mem_total mem_used mem_free < <(free -b | awk '/^Mem:/{print $2, $3, $4}')
        mem_available=$(free -b | awk '/^Mem:/{print $7}' || echo "$mem_free")
        mem_cached=$(free -b | awk '/^Mem:/{print $6}' || echo "0")
        mem_buffers=$(free -b | awk '/^Mem:/{print $5}' || echo "0")

        # Swap information
        read -r swap_total swap_used < <(free -b | awk '/^Swap:/{print $2, $3}' || echo "0 0")
    elif [[ -f "/proc/meminfo" ]]; then
        # Fallback to /proc/meminfo
        mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2 * 1024}' || echo "0")
        mem_free=$(grep MemFree /proc/meminfo | awk '{print $2 * 1024}' || echo "0")
        mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2 * 1024}' || echo "$mem_free")
        mem_cached=$(grep '^Cached:' /proc/meminfo | awk '{print $2 * 1024}' || echo "0")
        mem_buffers=$(grep Buffers /proc/meminfo | awk '{print $2 * 1024}' || echo "0")
        mem_used=$((mem_total - mem_available))
        swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2 * 1024}' || echo "0")
        swap_used=$(grep SwapFree /proc/meminfo | awk '{print $2 * 1024}' || echo "0")
        swap_used=$((swap_total - swap_used))
    else
        mem_total="0"; mem_used="0"; mem_free="0"; mem_available="0"
        mem_cached="0"; mem_buffers="0"; swap_total="0"; swap_used="0"
    fi

    local result
    result=$(cat <<EOF
mem_total=$mem_total
mem_used=$mem_used
mem_free=$mem_free
mem_available=$mem_available
mem_cached=$mem_cached
mem_buffers=$mem_buffers
swap_total=$swap_total
swap_used=$swap_used
timestamp=$(date +%s)
EOF
)

    perf_collector_cache_store "$cache_key" "$result"
    echo "$result"
}

# Collect disk I/O metrics
perf_collector_disk() {
    local cache_key="disk_metrics"
    local disk_path="${1:-.}"

    # Check cache first  
    if perf_collector_cache_valid "$cache_key"; then
        perf_collector_cache_get "$cache_key"
        return 0
    fi

    perf_collector_debug "Collecting disk metrics for: $disk_path"

    local disk_total disk_used disk_free disk_usage_pct
    local disk_read_ops disk_write_ops disk_read_bytes disk_write_bytes

    # Disk space usage
    if command -v df >/dev/null 2>&1; then
        read -r disk_total disk_used disk_free disk_usage_pct < <(df "$disk_path" | awk 'NR==2 {print $2*1024, $3*1024, $4*1024, $5}' | sed 's/%//' || echo "0 0 0 0")
    else
        disk_total="0"; disk_used="0"; disk_free="0"; disk_usage_pct="0"
    fi

    # Disk I/O statistics (if available)
    if command -v iostat >/dev/null 2>&1; then
        # Get device name for the path
        local device
        device=$(df "$disk_path" | awk 'NR==2 {print $1}' | sed 's|.*/||' | sed 's/[0-9]*$//')

        if [[ -n "$device" ]]; then
            read -r disk_read_ops disk_write_ops disk_read_bytes disk_write_bytes < <(
                iostat -d "$device" 1 1 | awk -v dev="$device" '
                    $1 == dev && NF >= 6 {
                        print $4, $5, $6*512, $7*512
                        exit
                    }
                ' || echo "0 0 0 0"
            )
        else
            disk_read_ops="0"; disk_write_ops="0"; disk_read_bytes="0"; disk_write_bytes="0"
        fi
    else
        disk_read_ops="0"; disk_write_ops="0"; disk_read_bytes="0"; disk_write_bytes="0"
    fi

    local result
    result=$(cat <<EOF
disk_total=$disk_total
disk_used=$disk_used
disk_free=$disk_free
disk_usage_pct=$disk_usage_pct
disk_read_ops=$disk_read_ops
disk_write_ops=$disk_write_ops
disk_read_bytes=$disk_read_bytes
disk_write_bytes=$disk_write_bytes
disk_path=$disk_path
timestamp=$(date +%s)
EOF
)

    perf_collector_cache_store "$cache_key" "$result"
    echo "$result"
}

# Collect network metrics
perf_collector_network() {
    local cache_key="network_metrics"
    local interface="${1:-}"

    # Check cache first
    if perf_collector_cache_valid "$cache_key"; then
        perf_collector_cache_get "$cache_key"
        return 0
    fi

    perf_collector_debug "Collecting network metrics for interface: ${interface:-all}"

    local net_rx_bytes net_tx_bytes net_rx_packets net_tx_packets
    local net_rx_errors net_tx_errors net_interfaces_count

    if [[ -d "/sys/class/net" ]]; then
        net_rx_bytes=0; net_tx_bytes=0; net_rx_packets=0; net_tx_packets=0
        net_rx_errors=0; net_tx_errors=0; net_interfaces_count=0

        # Sum statistics for all interfaces or specific interface
        for iface in /sys/class/net/*/; do
            local iface_name
            iface_name=$(basename "$iface")

            # Skip loopback and specific interface filter
            [[ "$iface_name" == "lo" ]] && continue
            [[ -n "$interface" && "$iface_name" != "$interface" ]] && continue

            if [[ -f "${iface}statistics/rx_bytes" ]]; then
                net_rx_bytes=$((net_rx_bytes + $(cat "${iface}statistics/rx_bytes" || echo 0)))
                net_tx_bytes=$((net_tx_bytes + $(cat "${iface}statistics/tx_bytes" || echo 0)))
                net_rx_packets=$((net_rx_packets + $(cat "${iface}statistics/rx_packets" || echo 0)))
                net_tx_packets=$((net_tx_packets + $(cat "${iface}statistics/tx_packets" || echo 0)))
                net_rx_errors=$((net_rx_errors + $(cat "${iface}statistics/rx_errors" || echo 0)))
                net_tx_errors=$((net_tx_errors + $(cat "${iface}statistics/tx_errors" || echo 0)))
                ((net_interfaces_count++))
            fi
        done
    else
        net_rx_bytes="0"; net_tx_bytes="0"; net_rx_packets="0"; net_tx_packets="0"
        net_rx_errors="0"; net_tx_errors="0"; net_interfaces_count="0"
    fi

    local result
    result=$(cat <<EOF
net_rx_bytes=$net_rx_bytes
net_tx_bytes=$net_tx_bytes
net_rx_packets=$net_rx_packets
net_tx_packets=$net_tx_packets
net_rx_errors=$net_rx_errors
net_tx_errors=$net_tx_errors
net_interfaces_count=$net_interfaces_count
net_interface=${interface:-all}
timestamp=$(date +%s)
EOF
)

    perf_collector_cache_store "$cache_key" "$result"
    echo "$result"
}

# Collect all system metrics
perf_collector_system_full() {
    local disk_path="${1:-.}"
    local network_interface="${2:-}"

    perf_collector_debug "Collecting full system metrics"

    cat <<EOF
# System Performance Metrics - $(date -Iseconds)
$(perf_collector_cpu)
$(perf_collector_memory)
$(perf_collector_disk "$disk_path")
$(perf_collector_network "$network_interface")
EOF
}

# Get system uptime and hostname
perf_collector_system_info() {
    local cache_key="system_info"

    # Check cache first (longer cache for relatively static data)
    if [[ "${PERF_CACHE_TIMESTAMPS[$cache_key]:-0}" -gt $(($(date +%s) - 60)) ]]; then
        perf_collector_cache_get "$cache_key"
        return 0
    fi

    perf_collector_debug "Collecting system info"

    local hostname uptime_seconds uptime_formatted boot_time

    hostname=$(hostname || echo "unknown")

    if [[ -f "/proc/uptime" ]]; then
        uptime_seconds=$(cut -d'.' -f1 /proc/uptime || echo "0")
        boot_time=$(($(date +%s) - uptime_seconds))
    else
        uptime_seconds="0"
        boot_time="0"
    fi

    # Format uptime in human readable form
    if command -v uptime >/dev/null 2>&1; then
        uptime_formatted=$(uptime -p || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}' || echo "unknown")
    else
        local days hours minutes
        days=$((uptime_seconds / 86400))
        hours=$(((uptime_seconds % 86400) / 3600))
        minutes=$(((uptime_seconds % 3600) / 60))
        uptime_formatted="${days}d ${hours}h ${minutes}m"
    fi

    local result
    result=$(cat <<EOF
hostname=$hostname
uptime_seconds=$uptime_seconds
uptime_formatted=$uptime_formatted
boot_time=$boot_time
timestamp=$(date +%s)
EOF
)

    perf_collector_cache_store "$cache_key" "$result"
    echo "$result"
}

# Clear performance cache
perf_collector_clear_cache() {
    perf_collector_debug "Clearing performance cache"
    PERF_CACHE_DATA=()
    PERF_CACHE_TIMESTAMPS=()
}

# Get cache statistics
perf_collector_cache_stats() {
    local cached_items=${#PERF_CACHE_DATA[@]}
    local oldest_timestamp=999999999999
    local newest_timestamp=0

    for timestamp in "${PERF_CACHE_TIMESTAMPS[@]}"; do
        [[ $timestamp -lt $oldest_timestamp ]] && oldest_timestamp=$timestamp
        [[ $timestamp -gt $newest_timestamp ]] && newest_timestamp=$timestamp
    done

    [[ $oldest_timestamp -eq 999999999999 ]] && oldest_timestamp=0

    cat <<EOF
cache_enabled=${PERF_COLLECTOR_CONFIG[ENABLE_CACHING]}
cache_duration=${PERF_COLLECTOR_CONFIG[CACHE_DURATION]}
cached_items=$cached_items
oldest_cache=$oldest_timestamp
newest_cache=$newest_timestamp
EOF
}

# Export collector functions
export -f perf_collector_init
export -f perf_collector_cpu
export -f perf_collector_memory
export -f perf_collector_disk
export -f perf_collector_network
export -f perf_collector_system_full
export -f perf_collector_system_info
export -f perf_collector_clear_cache
export -f perf_collector_cache_stats
