#!/usr/bin/env bash
# monitor.sh -- VaultWarden-OCI Real-time Monitoring Dashboard
# UNIFIED VERSION: Uses centralized monitoring configuration

set -euo pipefail
IFS=$'\n\t'

# Source common library and CENTRALIZED monitoring configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/lib/common.sh" || {
    echo "ERROR: lib/common.sh required" >&2
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

# ALL THRESHOLD VARIABLES NOW COME FROM monitoring-config.sh
# No more duplicate definitions!

# The rest of the script uses the centralized thresholds:
# - $CPU_ALERT_THRESHOLD
# - $MEMORY_ALERT_THRESHOLD  
# - $LOAD_ALERT_THRESHOLD
# - $SQLITE_SIZE_ALERT_MB
# etc.

# Check thresholds using unified evaluation functions
check_thresholds_and_alert() {
    local metrics="$1"
    local alerts=()
    
    eval "$metrics"  # Load metrics
    
    # Use unified threshold evaluation functions
    local cpu_status mem_status load_status
    cpu_status=$(evaluate_cpu_threshold "${metrics[cpu_usage]}")
    mem_status=$(evaluate_memory_threshold "${metrics[memory_usage]}")
    load_status=$(evaluate_load_threshold "${metrics[load_1min]}")
    
    # Generate alerts based on unified evaluation
    case "$cpu_status" in
        "critical"|"alert")
            alerts+=("CPU usage ${metrics[cpu_usage]}% is $cpu_status (threshold: $CPU_ALERT_THRESHOLD%)")
            ;;
    esac
    
    case "$mem_status" in
        "critical"|"alert")
            alerts+=("Memory usage ${metrics[memory_usage]}% is $mem_status (threshold: $MEMORY_ALERT_THRESHOLD%)")
            ;;
    esac
    
    case "$load_status" in
        "critical"|"alert")
            alerts+=("Load average ${metrics[load_1min]} is $load_status (threshold: $LOAD_ALERT_THRESHOLD)")
            ;;
    esac
    
    # Send alerts if any exist
    if [[ ${#alerts[@]} -gt 0 ]]; then
        send_unified_alert "${alerts[@]}"
    fi
}

# Use unified alert system
send_unified_alert() {
    local alert_message="VaultWarden-OCI Alert: $*"
    
    # Use unified paths and configuration
    echo "$(date): $alert_message" >> "$METRICS_LOG"
    
    # Send email using unified SMTP configuration
    if [[ -n "$ALERT_EMAIL" && -n "$SMTP_HOST" ]]; then
        if command -v mail >/dev/null 2>&1; then
            echo "$alert_message" | mail -s "VaultWarden Alert" "$ALERT_EMAIL" || true
        fi
    fi
    
    # Send webhook using unified configuration
    if [[ -n "$WEBHOOK_URL" ]]; then
        if command -v curl >/dev/null 2>&1; then
            curl -X POST -H "Content-Type: application/json" \
                -d "{\"text\":\"$alert_message\"}" \
                "$WEBHOOK_URL" >/dev/null 2>&1 || true
        fi
    fi
}
