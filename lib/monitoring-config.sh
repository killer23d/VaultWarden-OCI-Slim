#!/usr/bin/env bash
# lib/monitoring-config.sh - Centralized Monitoring Configuration
# Single source of truth for all monitoring thresholds and configuration

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This file should be sourced, not executed directly"
    exit 1
fi

# ================================
# MONITORING FRAMEWORK INTEGRATION
# ================================

# Load core common functions if available
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/common.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# Framework initialization flag
export MONITORING_CONFIG_LOADED=true
export MONITORING_CONFIG_VERSION="3.0"

# ================================
# CENTRALIZED THRESHOLD CONFIGURATION
# ================================

# Load configuration from external files (priority order)
load_monitoring_configuration() {
    local config_sources=()
    
    # 1. External configuration files (highest priority)
    local config_files=(
        "$(dirname "${BASH_SOURCE[0]}")/../config/performance-targets.conf"
        "$(dirname "${BASH_SOURCE[0]}")/../config/alert-thresholds.conf" 
        "$(dirname "${BASH_SOURCE[0]}")/../config/monitoring-intervals.conf"
    )
    
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            source "$config_file"
            config_sources+=("$(basename "$config_file")")
        fi
    done
    
    # 2. Environment variables from settings.env/Docker Compose (medium priority)
    if [[ -f "$(dirname "${BASH_SOURCE[0]}")/../settings.env" ]]; then
        set -a
        source "$(dirname "${BASH_SOURCE[0]}")/../settings.env"
        set +a
        config_sources+=("settings.env")
    fi
    
    # 3. Fallback defaults (lowest priority)
    config_sources+=("built-in defaults")
    
    export MONITORING_CONFIG_SOURCES="${config_sources[*]}"
}

# Initialize configuration loading
load_monitoring_configuration

# ================================
# UNIFIED SYSTEM THRESHOLDS
# ================================

# CPU Thresholds (aligned across all scripts)
export CPU_WARNING_THRESHOLD="${CPU_WARNING_THRESHOLD:-70}"
export CPU_ALERT_THRESHOLD="${CPU_ALERT_THRESHOLD:-80}"
export CPU_CRITICAL_THRESHOLD="${CPU_CRITICAL_THRESHOLD:-90}"

# Memory Thresholds (aligned across all scripts)
export MEMORY_WARNING_THRESHOLD="${MEMORY_WARNING_THRESHOLD:-75}"
export MEMORY_ALERT_THRESHOLD="${MEMORY_ALERT_THRESHOLD:-85}"
export MEMORY_CRITICAL_THRESHOLD="${MEMORY_CRITICAL_THRESHOLD:-85}"

# Load Average Thresholds (critical for 1 OCPU)
export LOAD_WARNING_THRESHOLD="${LOAD_WARNING_THRESHOLD:-1.0}"
export LOAD_ALERT_THRESHOLD="${LOAD_ALERT_THRESHOLD:-1.5}"
export LOAD_CRITICAL_THRESHOLD="${LOAD_CRITICAL_THRESHOLD:-2.0}"

# Disk Usage Thresholds
export DISK_WARNING_THRESHOLD="${DISK_WARNING_THRESHOLD:-75}"
export DISK_ALERT_THRESHOLD="${DISK_ALERT_THRESHOLD:-85}"
export DISK_CRITICAL_THRESHOLD="${DISK_CRITICAL_THRESHOLD:-85}"

# ================================
# UNIFIED SQLITE THRESHOLDS
# ================================

# SQLite Database Size Thresholds
export SQLITE_SIZE_WARNING_MB="${SQLITE_SIZE_WARNING_MB:-75}"
export SQLITE_SIZE_ALERT_MB="${SQLITE_SIZE_ALERT_MB:-100}"
export SQLITE_SIZE_CRITICAL_MB="${SQLITE_SIZE_CRITICAL_MB:-500}"

# SQLite WAL File Thresholds
export WAL_SIZE_WARNING_MB="${WAL_SIZE_WARNING_MB:-5}"
export WAL_SIZE_ALERT_MB="${WAL_SIZE_ALERT_MB:-10}"
export WAL_SIZE_CRITICAL_MB="${WAL_SIZE_CRITICAL_MB:-50}"

# SQLite Fragmentation Thresholds
export FRAGMENTATION_WARNING_RATIO="${FRAGMENTATION_WARNING_RATIO:-1.2}"
export FRAGMENTATION_ALERT_RATIO="${FRAGMENTATION_ALERT_RATIO:-1.5}"
export FRAGMENTATION_CRITICAL_RATIO="${FRAGMENTATION_CRITICAL_RATIO:-1.5}"

# SQLite Performance Thresholds
export SQLITE_QUERY_WARNING_MS="${SQLITE_QUERY_WARNING_MS:-100}"
export SQLITE_QUERY_CRITICAL_MS="${SQLITE_QUERY_CRITICAL_MS:-1000}"

# ================================
# UNIFIED MONITORING INTERVALS
# ================================

# Monitoring Refresh Intervals
export MONITOR_REFRESH_INTERVAL="${MONITOR_REFRESH_INTERVAL:-5}"
export PERF_MONITOR_INTERVAL="${PERF_MONITOR_INTERVAL:-5}"
export DASHBOARD_REFRESH_INTERVAL="${DASHBOARD_REFRESH_INTERVAL:-5}"

# Alert Intervals
export ALERT_MIN_INTERVAL_S="${ALERT_MIN_INTERVAL_S:-1800}"  # 30 minutes
export ALERT_COOLDOWN_S="${ALERT_COOLDOWN_S:-3600}"         # 1 hour

# Log Retention
export LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
export MAX_LOG_ENTRIES="${MAX_LOG_ENTRIES:-50}"

# ================================
# UNIFIED SECURITY THRESHOLDS
# ================================

# Security Monitoring Thresholds
export FAIL2BAN_BANNED_WARNING="${FAIL2BAN_BANNED_WARNING:-10}"
export FAIL2BAN_BANNED_CRITICAL="${FAIL2BAN_BANNED_CRITICAL:-25}"

# Container Health Thresholds
export CONTAINER_START_TIMEOUT_S="${CONTAINER_START_TIMEOUT_S:-120}"
export CONTAINER_HEALTH_TIMEOUT_S="${CONTAINER_HEALTH_TIMEOUT_S:-30}"

# ================================
# UNIFIED PATH CONFIGURATION
# ================================

# Standardized paths across all scripts
export SQLITE_DB_PATH="${SQLITE_DB_PATH:-./data/bwdata/db.sqlite3}"
export SQLITE_DB_CONTAINER_PATH="${SQLITE_DB_CONTAINER_PATH:-/data/bwdata/db.sqlite3}"
export VAULTWARDEN_DATA_DIR="${VAULTWARDEN_DATA_DIR:-./data/bwdata}"
export VAULTWARDEN_DATA_CONTAINER_DIR="${VAULTWARDEN_DATA_CONTAINER_DIR:-/data/bwdata}"

# Log directories
export LOG_DIR="${LOG_DIR:-./logs}"
export PERF_LOG_DIR="${PERF_LOG_DIR:-./data/performance_logs}"
export METRICS_LOG="${METRICS_LOG:-$LOG_DIR/metrics.log}"

# ================================
# UNIFIED ALERT CONFIGURATION
# ================================

# Alert destinations (from settings.env)
export ALERT_EMAIL="${ALERT_EMAIL:-}"
export WEBHOOK_URL="${WEBHOOK_URL:-}"

# SMTP Configuration (from settings.env)
export SMTP_HOST="${SMTP_HOST:-}"
export SMTP_PORT="${SMTP_PORT:-587}"
export SMTP_USERNAME="${SMTP_USERNAME:-}"
export SMTP_PASSWORD="${SMTP_PASSWORD:-}"
export SMTP_FROM="${SMTP_FROM:-}"

# ================================
# THRESHOLD VALIDATION FUNCTIONS
# ================================

# Validate threshold configuration consistency
validate_monitoring_thresholds() {
    local errors=()
    
    # Check threshold ordering (warning < alert < critical)
    if [[ $CPU_WARNING_THRESHOLD -ge $CPU_ALERT_THRESHOLD ]]; then
        errors+=("CPU_WARNING_THRESHOLD ($CPU_WARNING_THRESHOLD) should be less than CPU_ALERT_THRESHOLD ($CPU_ALERT_THRESHOLD)")
    fi
    
    if [[ $CPU_ALERT_THRESHOLD -ge $CPU_CRITICAL_THRESHOLD ]]; then
        errors+=("CPU_ALERT_THRESHOLD ($CPU_ALERT_THRESHOLD) should be less than CPU_CRITICAL_THRESHOLD ($CPU_CRITICAL_THRESHOLD)")
    fi
    
    # Validate SQLite thresholds
    if [[ $SQLITE_SIZE_WARNING_MB -ge $SQLITE_SIZE_ALERT_MB ]]; then
        errors+=("SQLITE_SIZE_WARNING_MB should be less than SQLITE_SIZE_ALERT_MB")
    fi
    
    # Check 1 OCPU load thresholds
    if (( $(echo "$LOAD_CRITICAL_THRESHOLD > 3.0" | bc -l 2>/dev/null || echo "0") )); then
        errors+=("LOAD_CRITICAL_THRESHOLD ($LOAD_CRITICAL_THRESHOLD) is too high for 1 OCPU (recommend <2.0)")
    fi
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        if command -v log_error >/dev/null 2>&1; then
            log_error "Monitoring threshold validation failed:"
            printf '%s\n' "${errors[@]}" | while read -r error; do
                log_error "  - $error"
            done
        else
            echo "ERROR: Monitoring threshold validation failed:" >&2
            printf '%s\n' "${errors[@]}" | while read -r error; do
                echo "  - $error" >&2
            done
        fi
        return 1
    fi
    
    return 0
}

# ================================
# UNIFIED METRIC EVALUATION FUNCTIONS
# ================================

# Evaluate CPU usage against unified thresholds
evaluate_cpu_threshold() {
    local cpu_usage="$1"
    
    if ! command -v bc >/dev/null 2>&1; then
        echo "warning:bc_unavailable"
        return 1
    fi
    
    if (( $(echo "$cpu_usage > $CPU_CRITICAL_THRESHOLD" | bc -l) )); then
        echo "critical"
    elif (( $(echo "$cpu_usage > $CPU_ALERT_THRESHOLD" | bc -l) )); then
        echo "alert"
    elif (( $(echo "$cpu_usage > $CPU_WARNING_THRESHOLD" | bc -l) )); then
        echo "warning"
    else
        echo "normal"
    fi
}

# Evaluate memory usage against unified thresholds
evaluate_memory_threshold() {
    local mem_usage="$1"
    
    if ! command -v bc >/dev/null 2>&1; then
        echo "warning:bc_unavailable"
        return 1
    fi
    
    if (( $(echo "$mem_usage > $MEMORY_CRITICAL_THRESHOLD" | bc -l) )); then
        echo "critical"
    elif (( $(echo "$mem_usage > $MEMORY_ALERT_THRESHOLD" | bc -l) )); then
        echo "alert"
    elif (( $(echo "$mem_usage > $MEMORY_WARNING_THRESHOLD" | bc -l) )); then
        echo "warning"
    else
        echo "normal"
    fi
}

# Evaluate load average against unified thresholds (1 OCPU context)
evaluate_load_threshold() {
    local load_avg="$1"
    
    if ! command -v bc >/dev/null 2>&1; then
        echo "warning:bc_unavailable"
        return 1
    fi
    
    if (( $(echo "$load_avg > $LOAD_CRITICAL_THRESHOLD" | bc -l) )); then
        echo "critical"
    elif (( $(echo "$load_avg > $LOAD_ALERT_THRESHOLD" | bc -l) )); then
        echo "alert"
    elif (( $(echo "$load_avg > $LOAD_WARNING_THRESHOLD" | bc -l) )); then
        echo "warning"
    else
        echo "normal"
    fi
}

# Evaluate SQLite database size against unified thresholds
evaluate_sqlite_size_threshold() {
    local db_size_mb="$1"
    
    if ! command -v bc >/dev/null 2>&1; then
        echo "warning:bc_unavailable"
        return 1
    fi
    
    if (( $(echo "$db_size_mb > $SQLITE_SIZE_CRITICAL_MB" | bc -l) )); then
        echo "critical"
    elif (( $(echo "$db_size_mb > $SQLITE_SIZE_ALERT_MB" | bc -l) )); then
        echo "alert"
    elif (( $(echo "$db_size_mb > $SQLITE_SIZE_WARNING_MB" | bc -l) )); then
        echo "warning"
    else
        echo "normal"
    fi
}

# Evaluate SQLite fragmentation against unified thresholds
evaluate_fragmentation_threshold() {
    local fragmentation_ratio="$1"
    
    if ! command -v bc >/dev/null 2>&1; then
        echo "warning:bc_unavailable"
        return 1
    fi
    
    if (( $(echo "$fragmentation_ratio > $FRAGMENTATION_CRITICAL_RATIO" | bc -l) )); then
        echo "critical"
    elif (( $(echo "$fragmentation_ratio > $FRAGMENTATION_ALERT_RATIO" | bc -l) )); then
        echo "alert"
    elif (( $(echo "$fragmentation_ratio > $FRAGMENTATION_WARNING_RATIO" | bc -l) )); then
        echo "warning"
    else
        echo "normal"
    fi
}

# ================================
# UNIFIED METRICS COLLECTION
# ================================

# Standardized system metrics collection
get_unified_system_metrics() {
    local timestamp cpu_usage mem_usage_pct load_1m disk_usage_pct
    
    timestamp=$(date -Iseconds)
    
    # CPU usage (standardized method)
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "0")
    
    # Memory usage (standardized method)
    if command -v free >/dev/null 2>&1; then
        mem_usage_pct=$(free | awk '/^Mem:/{printf "%.1f", $3*100/$2}' || echo "0")
    else
        mem_usage_pct="0"
    fi
    
    # Load average (standardized method)
    load_1m=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',' || echo "0")
    
    # Disk usage (standardized method)
    disk_usage_pct=$(df . | awk 'NR==2 {print $5}' | sed 's/%//' || echo "0")
    
    # Output in consistent format
    cat <<EOF
timestamp=$timestamp
cpu_usage=$cpu_usage
cpu_threshold=$(evaluate_cpu_threshold "$cpu_usage")
mem_usage_pct=$mem_usage_pct
mem_threshold=$(evaluate_memory_threshold "$mem_usage_pct")
load_1m=$load_1m
load_threshold=$(evaluate_load_threshold "$load_1m")
disk_usage_pct=$disk_usage_pct
disk_threshold=$(evaluate_disk_threshold "$disk_usage_pct")
EOF
}

# Evaluate disk usage threshold
evaluate_disk_threshold() {
    local disk_usage="$1"
    
    if [[ ${disk_usage:-0} -gt ${DISK_CRITICAL_THRESHOLD} ]]; then
        echo "critical"
    elif [[ ${disk_usage:-0} -gt ${DISK_ALERT_THRESHOLD} ]]; then
        echo "alert"
    elif [[ ${disk_usage:-0} -gt ${DISK_WARNING_THRESHOLD} ]]; then
        echo "warning"
    else
        echo "normal"
    fi
}

# ================================
# CONFIGURATION REPORTING
# ================================

# Display current monitoring configuration
show_monitoring_configuration() {
    cat <<EOF
Monitoring Configuration (v$MONITORING_CONFIG_VERSION)
============================

Configuration Sources: $MONITORING_CONFIG_SOURCES

System Thresholds:
├─ CPU Usage:      Warning: ${CPU_WARNING_THRESHOLD}%, Alert: ${CPU_ALERT_THRESHOLD}%, Critical: ${CPU_CRITICAL_THRESHOLD}%
├─ Memory Usage:   Warning: ${MEMORY_WARNING_THRESHOLD}%, Alert: ${MEMORY_ALERT_THRESHOLD}%, Critical: ${MEMORY_CRITICAL_THRESHOLD}%
├─ Load Average:   Warning: ${LOAD_WARNING_THRESHOLD}, Alert: ${LOAD_ALERT_THRESHOLD}, Critical: ${LOAD_CRITICAL_THRESHOLD} (1 OCPU)
└─ Disk Usage:     Warning: ${DISK_WARNING_THRESHOLD}%, Alert: ${DISK_ALERT_THRESHOLD}%, Critical: ${DISK_CRITICAL_THRESHOLD}%

SQLite Thresholds:
├─ Database Size:  Warning: ${SQLITE_SIZE_WARNING_MB}MB, Alert: ${SQLITE_SIZE_ALERT_MB}MB, Critical: ${SQLITE_SIZE_CRITICAL_MB}MB
├─ WAL File Size:  Warning: ${WAL_SIZE_WARNING_MB}MB, Alert: ${WAL_SIZE_ALERT_MB}MB, Critical: ${WAL_SIZE_CRITICAL_MB}MB
└─ Fragmentation:  Warning: ${FRAGMENTATION_WARNING_RATIO}, Alert: ${FRAGMENTATION_ALERT_RATIO}, Critical: ${FRAGMENTATION_CRITICAL_RATIO}

Monitoring Intervals:
├─ Refresh Rate:   ${MONITOR_REFRESH_INTERVAL}s
├─ Alert Cooldown: ${ALERT_COOLDOWN_S}s
└─ Log Retention:  ${LOG_RETENTION_DAYS} days

Alert Configuration:
├─ Email:          ${ALERT_EMAIL:-"Not configured"}
├─ Webhook:        ${WEBHOOK_URL:-"Not configured"}
└─ SMTP Host:      ${SMTP_HOST:-"Not configured"}

Standardized Paths:
├─ SQLite DB:      $SQLITE_DB_PATH
├─ Data Directory: $VAULTWARDEN_DATA_DIR
└─ Log Directory:  $LOG_DIR
EOF
}

# ================================
# INITIALIZATION AND VALIDATION
# ================================

# Initialize monitoring configuration system
init_monitoring_config() {
    # Validate threshold configuration
    if ! validate_monitoring_thresholds; then
        if command -v log_error >/dev/null 2>&1; then
            log_error "Monitoring configuration validation failed"
        else
            echo "ERROR: Monitoring configuration validation failed" >&2
        fi
        return 1
    fi
    
    # Create necessary directories
    local dirs=("$LOG_DIR" "$PERF_LOG_DIR")
    for dir in "${dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" || {
                if command -v log_warning >/dev/null 2>&1; then
                    log_warning "Could not create directory: $dir"
                else
                    echo "WARNING: Could not create directory: $dir" >&2
                fi
            }
        fi
    done
    
    if command -v log_debug >/dev/null 2>&1; then
        log_debug "Monitoring configuration initialized (v$MONITORING_CONFIG_VERSION)"
        log_debug "Configuration sources: $MONITORING_CONFIG_SOURCES"
    fi
    
    return 0
}

# Auto-initialize when sourced
init_monitoring_config

# Export configuration status
export MONITORING_CONFIG_INITIALIZED=true
