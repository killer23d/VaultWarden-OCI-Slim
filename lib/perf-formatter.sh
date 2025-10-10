#!/usr/bin/env bash
# perf-formatter.sh -- Standardized performance output formatting
# Provides consistent formatting for performance data across all monitoring scripts

# Formatting configuration
declare -A PERF_FORMAT_CONFIG=(
    ["ENABLE_COLORS"]=true
    ["PROGRESS_BAR_WIDTH"]=20
    ["DECIMAL_PLACES"]=1
    ["TABLE_WIDTH"]=78
    ["COMPACT_MODE"]=false
)

# Initialize formatter
perf_formatter_init() {
    # Disable colors if not in terminal or explicitly disabled
    if [[ ! -t 1 ]] || [[ "${TERM:-}" == "dumb" ]] || [[ "${NO_COLOR:-}" == "1" ]]; then
        PERF_FORMAT_CONFIG["ENABLE_COLORS"]=false
    fi

    # Load formatting config if available
    local config_file="$SCRIPT_DIR/config/monitoring-intervals.conf"
    if [[ -f "$config_file" ]]; then
        while IFS='=' read -r key value; do
            [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            [[ -n "${PERF_FORMAT_CONFIG[$key]:-}" ]] && PERF_FORMAT_CONFIG["$key"]="$value"
        done < "$config_file"
    fi
}

# Format bytes to human readable units
perf_formatter_bytes() {
    local bytes="$1"
    local precision="${2:-1}"

    [[ "$bytes" =~ ^[0-9]+$ ]] || { echo "0 B"; return; }

    local units=("B" "KB" "MB" "GB" "TB" "PB")
    local unit_index=0
    local size="$bytes"

    while [[ $size -gt 1024 && $unit_index -lt $((${#units[@]} - 1)) ]]; do
        if command -v bc >/dev/null 2>&1; then
            size=$(echo "scale=$precision; $size / 1024" | bc)
        else
            size=$((size / 1024))
        fi
        ((unit_index++))
    done

    # Format with appropriate precision
    if [[ $unit_index -eq 0 ]]; then
        echo "${size} ${units[$unit_index]}"
    else
        if command -v bc >/dev/null 2>&1; then
            printf "%.${precision}f %s" "$size" "${units[$unit_index]}"
        else
            echo "${size} ${units[$unit_index]}"
        fi
    fi
}

# Format percentage with color coding
perf_formatter_percentage() {
    local value="$1"
    local warning_threshold="${2:-70}"
    local critical_threshold="${3:-90}"
    local precision="${4:-1}"

    local color=""
    local reset=""

    if [[ "${PERF_FORMAT_CONFIG[ENABLE_COLORS]}" == "true" ]]; then
        if (( $(echo "$value > $critical_threshold" | bc -l || echo 0) )); then
            color="\033[0;31m"  # Red
        elif (( $(echo "$value > $warning_threshold" | bc -l || echo 0) )); then
            color="\033[1;33m"  # Yellow
        else
            color="\033[0;32m"  # Green
        fi
        reset="\033[0m"
    fi

    if command -v bc >/dev/null 2>&1; then
        printf "${color}%.${precision}f%%${reset}" "$value"
    else
        printf "${color}%d%%${reset}" "${value%.*}"
    fi
}

# Create progress bar
perf_formatter_progress_bar() {
    local value="$1"
    local max_value="${2:-100}"
    local width="${3:-${PERF_FORMAT_CONFIG[PROGRESS_BAR_WIDTH]}}"
    local show_text="${4:-true}"

    local percentage
    if command -v bc >/dev/null 2>&1 && [[ $max_value -ne 0 ]]; then
        percentage=$(echo "scale=1; $value * 100 / $max_value" | bc)
    else
        [[ $max_value -eq 0 ]] && max_value=1
        percentage=$(( (value * 100) / max_value ))
    fi

    local filled_width
    if command -v bc >/dev/null 2>&1; then
        filled_width=$(echo "$value * $width / $max_value" | bc)
    else
        filled_width=$(( (value * width) / max_value ))
    fi

    [[ $filled_width -gt $width ]] && filled_width=$width
    [[ $filled_width -lt 0 ]] && filled_width=0

    local empty_width=$((width - filled_width))

    # Color coding
    local bar_color=""
    local reset=""

    if [[ "${PERF_FORMAT_CONFIG[ENABLE_COLORS]}" == "true" ]]; then
        if (( $(echo "$percentage > 90" | bc -l || echo 0) )); then
            bar_color="\033[0;31m"  # Red
        elif (( $(echo "$percentage > 70" | bc -l || echo 0) )); then
            bar_color="\033[1;33m"  # Yellow
        else
            bar_color="\033[0;32m"  # Green
        fi
        reset="\033[0m"
    fi

    # Build progress bar
    local bar
    bar="${bar_color}$(printf '%.0s█' $(seq 1 $filled_width))${reset}"
    bar="${bar}$(printf '%.0s░' $(seq 1 $empty_width))"

    if [[ "$show_text" == "true" ]]; then
        printf "[%s] %s" "$bar" "$(perf_formatter_percentage "$percentage" 70 90)"
    else
        printf "[%s]" "$bar"
    fi
}

# Format status indicator with color
perf_formatter_status() {
    local status="$1"
    local text="${2:-$status}"

    if [[ "${PERF_FORMAT_CONFIG[ENABLE_COLORS]}" == "true" ]]; then
        case "$status" in
            "good"|"ok"|"healthy"|"running"|"online")
                printf "\033[0;32m●\033[0m %s" "$text"
                ;;
            "warning"|"moderate"|"elevated"|"degraded")
                printf "\033[1;33m●\033[0m %s" "$text"
                ;;
            "critical"|"error"|"failed"|"offline"|"down")
                printf "\033[0;31m●\033[0m %s" "$text"
                ;;
            "info"|"unknown"|"pending")
                printf "\033[0;34m●\033[0m %s" "$text"
                ;;
            *)
                printf "\033[1;37m○\033[0m %s" "$text"
                ;;
        esac
    else
        case "$status" in
            "good"|"ok"|"healthy"|"running"|"online")
                printf "✓ %s" "$text"
                ;;
            "warning"|"moderate"|"elevated"|"degraded")
                printf "⚠ %s" "$text"
                ;;
            "critical"|"error"|"failed"|"offline"|"down")
                printf "✗ %s" "$text"
                ;;
            *)
                printf "• %s" "$text"
                ;;
        esac
    fi
}

# Format table header
perf_formatter_table_header() {
    local title="$1"
    shift
    local columns=("$@")

    local width="${PERF_FORMAT_CONFIG[TABLE_WIDTH]}"

    if [[ "${PERF_FORMAT_CONFIG[ENABLE_COLORS]}" == "true" ]]; then
        printf "\033[1;36m%s\033[0m\n" "$title"
        printf "\033[1;34m$(printf '%.0s─' $(seq 1 $width))\033[0m\n"
    else
        echo "$title"
        printf '%.0s-' $(seq 1 $width)
        echo
    fi

    if [[ ${#columns[@]} -gt 0 ]]; then
        local col_width=$((width / ${#columns[@]}))
        for column in "${columns[@]}"; do
            printf "%-${col_width}s" "$column"
        done
        echo
        if [[ "${PERF_FORMAT_CONFIG[ENABLE_COLORS]}" == "true" ]]; then
            printf "\033[0;37m$(printf '%.0s─' $(seq 1 $width))\033[0m\n"
        else
            printf '%.0s-' $(seq 1 $width)
            echo
        fi
    fi
}

# Format table row
perf_formatter_table_row() {
    local columns=("$@")
    local width="${PERF_FORMAT_CONFIG[TABLE_WIDTH]}"

    if [[ ${#columns[@]} -gt 0 ]]; then
        local col_width=$((width / ${#columns[@]}))
        for column in "${columns[@]}"; do
            # Strip color codes for width calculation
            local clean_column
            clean_column=$(echo "$column" | sed 's/\033\[[0-9;]*m//g')
            local padding=$((col_width - ${#clean_column}))
            [[ $padding -lt 0 ]] && padding=0

            printf "%s%*s" "$column" $padding ""
        done
        echo
    fi
}

# Format key-value pair
perf_formatter_keyvalue() {
    local key="$1"
    local value="$2"
    local status="${3:-info}"
    local key_width="${4:-20}"

    local value_color=""
    local reset=""

    if [[ "${PERF_FORMAT_CONFIG[ENABLE_COLORS]}" == "true" ]]; then
        case "$status" in
            "good"|"ok") value_color="\033[0;32m" ;;
            "warning") value_color="\033[1;33m" ;;
            "critical"|"error") value_color="\033[0;31m" ;;
            "info") value_color="\033[0;36m" ;;
            *) value_color="\033[1;37m" ;;
        esac
        reset="\033[0m"
    fi

    printf "\033[1;37m%-${key_width}s:\033[0m %s%s%s\n" "$key" "$value_color" "$value" "$reset"
}

# Format section header
perf_formatter_section() {
    local title="$1"
    local style="${2:-normal}"  # normal, compact, minimal

    case "$style" in
        "compact")
            if [[ "${PERF_FORMAT_CONFIG[ENABLE_COLORS]}" == "true" ]]; then
                printf "\n\033[1;35m▶ %s\033[0m\n" "$title"
            else
                printf "\n> %s\n" "$title"
            fi
            ;;
        "minimal")
            if [[ "${PERF_FORMAT_CONFIG[ENABLE_COLORS]}" == "true" ]]; then
                printf "\033[1;34m%s:\033[0m " "$title"
            else
                printf "%s: " "$title"
            fi
            ;;
        *)
            if [[ "${PERF_FORMAT_CONFIG[ENABLE_COLORS]}" == "true" ]]; then
                printf "\n\033[1;36m━━━ %s ━━━\033[0m\n" "$title"
            else
                printf "\n=== %s ===\n" "$title"
            fi
            ;;
    esac
}

# Format duration
perf_formatter_duration() {
    local seconds="$1"
    local format="${2:-auto}"  # auto, short, long

    [[ "$seconds" =~ ^[0-9]+$ ]] || { echo "0s"; return; }

    case "$format" in
        "short")
            if [[ $seconds -lt 60 ]]; then
                echo "${seconds}s"
            elif [[ $seconds -lt 3600 ]]; then
                echo "$((seconds / 60))m"
            elif [[ $seconds -lt 86400 ]]; then
                echo "$((seconds / 3600))h"
            else
                echo "$((seconds / 86400))d"
            fi
            ;;
        "long")
            local days hours minutes secs
            days=$((seconds / 86400))
            hours=$(((seconds % 86400) / 3600))
            minutes=$(((seconds % 3600) / 60))
            secs=$((seconds % 60))

            local parts=()
            [[ $days -gt 0 ]] && parts+=("${days}d")
            [[ $hours -gt 0 ]] && parts+=("${hours}h")
            [[ $minutes -gt 0 ]] && parts+=("${minutes}m")
            [[ $secs -gt 0 ]] || [[ ${#parts[@]} -eq 0 ]] && parts+=("${secs}s")

            printf '%s' "$(IFS=' '; echo "${parts[*]}")"
            ;;
        *)
            # Auto format
            if [[ $seconds -lt 60 ]]; then
                echo "${seconds}s"
            elif [[ $seconds -lt 3600 ]]; then
                printf "%dm %ds" $((seconds / 60)) $((seconds % 60))
            elif [[ $seconds -lt 86400 ]]; then
                printf "%dh %dm" $((seconds / 3600)) $(((seconds % 3600) / 60))
            else
                printf "%dd %dh" $((seconds / 86400)) $(((seconds % 86400) / 3600))
            fi
            ;;
    esac
}

# Format timestamp
perf_formatter_timestamp() {
    local timestamp="$1"
    local format="${2:-relative}"  # relative, absolute, both

    case "$format" in
        "absolute")
            date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" || echo "Invalid timestamp"
            ;;
        "both")
            local abs_time rel_time
            abs_time=$(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S" || echo "Invalid")
            rel_time=$(perf_formatter_duration $(($(date +%s) - timestamp)))
            echo "$abs_time ($rel_time ago)"
            ;;
        *)
            # Relative (default)
            perf_formatter_duration $(($(date +%s) - timestamp))
            echo " ago"
            ;;
    esac
}

# Format system load for 1 OCPU
perf_formatter_load_1cpu() {
    local load_1m="$1"
    local load_5m="$2"
    local load_15m="$3"

    printf "Load: "

    # 1-minute load (most critical)
    if (( $(echo "$load_1m > 1.5" | bc -l || echo 0) )); then
        perf_formatter_status "critical" "$load_1m"
    elif (( $(echo "$load_1m > 1.0" | bc -l || echo 0) )); then
        perf_formatter_status "warning" "$load_1m"
    else
        perf_formatter_status "good" "$load_1m"
    fi

    printf " / %s / %s (1/5/15 min)\n" "$load_5m" "$load_15m"

    # Add context for 1 OCPU
    if (( $(echo "$load_1m > 1.5" | bc -l || echo 0) )); then
        if [[ "${PERF_FORMAT_CONFIG[ENABLE_COLORS]}" == "true" ]]; then
            printf "  \033[0;31m⚠ Single CPU overloaded - system may be unresponsive\033[0m\n"
        else
            echo "  ⚠ Single CPU overloaded - system may be unresponsive"
        fi
    fi
}

# Format container resource summary
perf_formatter_container_resources() {
    local container_name="$1"
    local cpu_percent="$2"
    local memory_usage="$3"
    local memory_limit="$4"
    local status="$5"

    # Extract numeric values
    cpu_percent=${cpu_percent%\%}
    memory_usage=${memory_usage%MiB*}
    memory_limit=${memory_limit%MiB*}

    printf "%-15s " "$container_name"

    # CPU percentage
    perf_formatter_percentage "$cpu_percent" 50 80 1
    printf "  "

    # Memory usage
    if [[ "$memory_limit" != "N/A" ]] && [[ $memory_limit -gt 0 ]]; then
        local mem_percent
        mem_percent=$(echo "scale=1; $memory_usage * 100 / $memory_limit" | bc || echo "0")
        perf_formatter_progress_bar "$memory_usage" "$memory_limit" 10 false
        printf " %s/%s" "$(perf_formatter_bytes $((memory_usage * 1024 * 1024)))" "$(perf_formatter_bytes $((memory_limit * 1024 * 1024)))"
    else
        printf "%s" "$(perf_formatter_bytes $((memory_usage * 1024 * 1024)))"
    fi

    printf "  "
    perf_formatter_status "$status"
    echo
}

# Export formatter functions
export -f perf_formatter_init
export -f perf_formatter_bytes
export -f perf_formatter_percentage
export -f perf_formatter_progress_bar
export -f perf_formatter_status
export -f perf_formatter_table_header
export -f perf_formatter_table_row
export -f perf_formatter_keyvalue
export -f perf_formatter_section
export -f perf_formatter_duration
export -f perf_formatter_timestamp
export -f perf_formatter_load_1cpu
export -f perf_formatter_container_resources
