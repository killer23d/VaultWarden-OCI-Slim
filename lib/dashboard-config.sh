#!/usr/bin/env bash
# dashboard-config.sh -- Configuration management for VaultWarden Dashboard
# Handles settings, thresholds, and environment setup

# Default configuration values
declare -g DASHBOARD_REFRESH_INTERVAL=5
declare -g SETTINGS_FILE="${SETTINGS_FILE:-./settings.env}"
declare -g SQLITE_DB_PATH="${SQLITE_DB_PATH:-./data/bw/data/bwdata/db.sqlite3}"

# Performance thresholds (will be overridden by config file)
declare -A DASHBOARD_THRESHOLDS=(
    ["CPU_WARNING"]=70
    ["CPU_CRITICAL"]=90
    ["MEMORY_WARNING"]=70
    ["MEMORY_CRITICAL"]=85
    ["LOAD_WARNING"]=1.0
    ["LOAD_CRITICAL"]=1.5
    ["FRAGMENTATION_WARNING"]=1.3
    ["FRAGMENTATION_CRITICAL"]=1.5
)

# UI Layout settings
declare -A DASHBOARD_LAYOUT=(
    ["HEADER_WIDTH"]=78
    ["LOG_LINES_DEFAULT"]=10
    ["REFRESH_DISPLAY"]=true
    ["COLOR_OUTPUT"]=true
)

# Initialize dashboard configuration
dashboard_config_init() {
    # Load main settings file if available
    if [[ -f "$SETTINGS_FILE" ]]; then
        set -a
        source "$SETTINGS_FILE" || log_warning "Failed to load $SETTINGS_FILE"
        set +a
    fi

    # Load dashboard-specific configuration files
    local config_dir="$SCRIPT_DIR/config"

    # Load thresholds configuration
    if [[ -f "$config_dir/dashboard-thresholds.conf" ]]; then
        dashboard_load_thresholds "$config_dir/dashboard-thresholds.conf"
    fi

    # Load layout configuration
    if [[ -f "$config_dir/dashboard-layout.conf" ]]; then
        dashboard_load_layout "$config_dir/dashboard-layout.conf"
    fi

    # Validate critical paths
    dashboard_validate_config
}

# Load threshold configuration
dashboard_load_thresholds() {
    local config_file="$1"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue

        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Update threshold if valid
        if [[ -n "${DASHBOARD_THRESHOLDS[$key]:-}" ]]; then
            DASHBOARD_THRESHOLDS["$key"]="$value"
        fi
    done < "$config_file"
}

# Load layout configuration
dashboard_load_layout() {
    local config_file="$1"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue

        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Update layout setting if valid
        if [[ -n "${DASHBOARD_LAYOUT[$key]:-}" ]]; then
            DASHBOARD_LAYOUT["$key"]="$value"
        fi
    done < "$config_file"
}

# Validate configuration
dashboard_validate_config() {
    local validation_errors=()

    # Check refresh interval
    if ! [[ "$DASHBOARD_REFRESH_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$DASHBOARD_REFRESH_INTERVAL" -lt 1 ]]; then
        validation_errors+=("Invalid refresh interval: $DASHBOARD_REFRESH_INTERVAL")
        DASHBOARD_REFRESH_INTERVAL=5
    fi

    # Check critical thresholds
    local critical_thresholds=("CPU_CRITICAL" "MEMORY_CRITICAL" "LOAD_CRITICAL")
    for threshold in "${critical_thresholds[@]}"; do
        local value="${DASHBOARD_THRESHOLDS[$threshold]}"
        if ! [[ "$value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            validation_errors+=("Invalid $threshold value: $value")
        fi
    done

    # Report validation errors
    if [[ ${#validation_errors[@]} -gt 0 ]]; then
        log_warning "Configuration validation issues:"
        for error in "${validation_errors[@]}"; do
            log_warning "  • $error"
        done
    fi
}

# Get threshold value
dashboard_get_threshold() {
    local threshold_name="$1"
    echo "${DASHBOARD_THRESHOLDS[$threshold_name]:-0}"
}

# Get layout setting
dashboard_get_layout() {
    local setting_name="$1"
    echo "${DASHBOARD_LAYOUT[$setting_name]:-}"
}

# Check if color output is enabled
dashboard_color_enabled() {
    [[ "${DASHBOARD_LAYOUT[COLOR_OUTPUT]}" == "true" ]]
}

# Get header width
dashboard_get_header_width() {
    echo "${DASHBOARD_LAYOUT[HEADER_WIDTH]}"
}

# Export configuration functions for use by other modules
export -f dashboard_config_init
export -f dashboard_get_threshold
export -f dashboard_get_layout
export -f dashboard_color_enabled
export -f dashboard_get_header_width
