#!/usr/bin/env bash
# dashboard-sqlite.sh -- SQLite monitoring functions for VaultWarden Dashboard
# Comprehensive SQLite database monitoring, health checks, and status display

# Initialize SQLite monitoring
dashboard_sqlite_init() {
    # Ensure SQLite database path is set
    SQLITE_DB_PATH="${SQLITE_DB_PATH:-./data/bw/data/bwdata/db.sqlite3}"

    # Load SQLite-specific thresholds
    local config_file="$SCRIPT_DIR/config/sqlite-thresholds.conf"
    if [[ -f "$config_file" ]]; then
        dashboard_sqlite_load_config "$config_file"
    fi
}

# Load SQLite configuration
dashboard_sqlite_load_config() {
    local config_file="$1"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue

        # Remove leading/trailing whitespace and export
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Set as environment variable for use by other functions
        export "$key"="$value"
    done < "$config_file" || true
}

# Get SQLite database status
dashboard_sqlite_get_status() {
    local db_status="unknown"
    local db_size="0"
    local db_health="unknown"
    local last_access="never"

    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        db_status="not_found"
    else
        # Basic accessibility test
        if sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
            db_status="accessible"
            db_size=$(du -h "$SQLITE_DB_PATH" | cut -f1 || echo "0")
            last_access=$(stat -c %y "$SQLITE_DB_PATH" | cut -d'.' -f1 || echo "unknown")

            # Health check
            local integrity_check
            integrity_check=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA integrity_check;" || echo "failed")

            if [[ "$integrity_check" == "ok" ]]; then
                db_health="healthy"
            else
                db_health="corrupted"
            fi
        else
            db_status="inaccessible"
            db_health="error"
        fi
    fi

    cat <<EOF
status=$db_status
size=$db_size
health=$db_health
last_access=$last_access
path=$SQLITE_DB_PATH
EOF
}

# Get detailed SQLite metrics for dashboard display
dashboard_sqlite_get_detailed_metrics() {
    if [[ ! -f "$SQLITE_DB_PATH" ]] || ! sqlite3 "$SQLITE_DB_PATH" "SELECT 1;" >/dev/null 2>&1; then
        echo "available=false"
        return 1
    fi

    local page_count page_size freelist_count table_count user_count
    local wal_size journal_mode fragmentation_ratio

    # Core database metrics
    page_count=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA page_count;" || echo "0")
    page_size=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA page_size;" || echo "0")
    freelist_count=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA freelist_count;" || echo "0")
    table_count=$(sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';" || echo "0")
    journal_mode=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA journal_mode;" || echo "unknown")

    # User count (VaultWarden specific)
    if sqlite3 "$SQLITE_DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='users';" | grep -q users; then
        user_count=$(sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM users;" || echo "0")
    else
        user_count="N/A"
    fi

    # WAL file size
    local wal_file="${SQLITE_DB_PATH}-wal"
    if [[ -f "$wal_file" ]]; then
        wal_size=$(du -h "$wal_file" | cut -f1 || echo "0")
    else
        wal_size="None"
    fi

    # Calculate fragmentation
    local file_size logical_size
    file_size=$(stat -c%s "$SQLITE_DB_PATH" || echo "0")
    logical_size=$((page_count * page_size))

    if [[ $logical_size -gt 0 ]] && command -v bc >/dev/null 2>&1; then
        fragmentation_ratio=$(echo "scale=3; $file_size / $logical_size" | bc || echo "1.000")
    else
        fragmentation_ratio="1.0"
    fi

    # Database activity metrics
    local connection_count=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA database_list;" | wc -l || echo "0")

    cat <<EOF
available=true
page_count=$page_count
page_size=$page_size
freelist_count=$freelist_count
table_count=$table_count
user_count=$user_count
wal_size=$wal_size
journal_mode=$journal_mode
fragmentation_ratio=$fragmentation_ratio
connection_count=$connection_count
EOF
}

# Display SQLite status section for dashboard
dashboard_sqlite_show_status() {
    dashboard_show_section "SQLite Database Status" "CYAN"

    local status_metrics detailed_metrics
    status_metrics=$(dashboard_sqlite_get_status)
    detailed_metrics=$(dashboard_sqlite_get_detailed_metrics)

    # Parse status metrics
    local db_status db_size db_health
    eval "$(echo "$status_metrics" | grep -E '^(status|size|health)=')"

    # Display basic status
    case "$db_status" in
        "accessible")
            dashboard_status_indicator "good" "Database: Accessible ($db_size)"
            ;;
        "not_found")
            dashboard_status_indicator "critical" "Database: Not Found"
            return 1
            ;;
        "inaccessible")
            dashboard_status_indicator "critical" "Database: Inaccessible"
            return 1
            ;;
        *)
            dashboard_status_indicator "warning" "Database: Unknown Status"
            ;;
    esac

    # Show health status
    case "$db_health" in
        "healthy")
            dashboard_status_indicator "good" "Integrity: Healthy"
            ;;
        "corrupted")
            dashboard_status_indicator "critical" "Integrity: Corrupted"
            ;;
        *)
            dashboard_status_indicator "warning" "Integrity: Unknown"
            ;;
    esac

    # Show detailed metrics if available
    if [[ "$detailed_metrics" =~ available=true ]]; then
        local table_count user_count journal_mode fragmentation_ratio wal_size
        eval "$(echo "$detailed_metrics" | grep -E '^(table_count|user_count|journal_mode|fragmentation_ratio|wal_size)=')"

        echo ""
        dashboard_show_keyvalue "Tables" "$table_count" "info"
        dashboard_show_keyvalue "Users" "$user_count" "info"
        dashboard_show_keyvalue "Journal Mode" "$journal_mode" "info"

        # Fragmentation analysis
        local frag_status="good"
        if command -v bc >/dev/null 2>&1; then
            if (( $(echo "$fragmentation_ratio > 1.5" | bc -l || echo 0) )); then
                frag_status="critical"
            elif (( $(echo "$fragmentation_ratio > 1.3" | bc -l || echo 0) )); then
                frag_status="warning"
            fi
        fi
        dashboard_show_keyvalue "Fragmentation" "$fragmentation_ratio" "$frag_status"

        # WAL file status
        local wal_status="good"
        if [[ "$wal_size" != "None" ]]; then
            dashboard_show_keyvalue "WAL File" "$wal_size" "info"
        else
            dashboard_show_keyvalue "WAL File" "None (idle)" "good"
        fi
    fi

    echo ""
    return 0
}

# Show SQLite maintenance recommendations
dashboard_sqlite_show_recommendations() {
    if ! command -v sqlite_analyzer_perform_analysis >/dev/null 2>&1; then
        echo "SQLite analyzer not available"
        return 1
    fi

    dashboard_show_section "SQLite Maintenance Recommendations" "YELLOW"

    # Temporarily capture analysis without logging
    local temp_log_level="${LOG_LEVEL:-}"
    export LOG_LEVEL="ERROR"  # Suppress info logging for clean display

    if sqlite_analyzer_perform_analysis >/dev/null 2>&1; then
        # Show recommendations
        local recommendations
        recommendations=$(sqlite_analyzer_get_recommendations)

        if [[ -n "$recommendations" ]]; then
            echo "Recommended maintenance operations:"
            echo "$recommendations" | while IFS= read -r operation; do
                dashboard_status_indicator "warning" "$operation recommended"
            done

            echo ""
            echo "💡 Run maintenance: ./sqlite-maintenance.sh"
        else
            dashboard_status_indicator "good" "No maintenance needed"
        fi
    else
        dashboard_status_indicator "good" "Database is well-maintained"
    fi

    # Restore log level
    export LOG_LEVEL="$temp_log_level"
    echo ""
}

# Quick SQLite health check for dashboard
dashboard_sqlite_quick_check() {
    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        echo "not_found"
        return 1
    fi

    # Test basic query
    if sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
        # Quick integrity check
        local integrity
        integrity=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA quick_check;")

        if [[ "$integrity" == "ok" ]]; then
            echo "healthy"
        else
            echo "issues"
        fi
    else
        echo "inaccessible"
        return 1
    fi
}

# Get SQLite performance metrics for dashboard
dashboard_sqlite_get_performance() {
    if ! dashboard_sqlite_quick_check >/dev/null; then
        echo "unavailable"
        return 1
    fi

    # Simple performance test
    local query_start query_end query_duration
    query_start=$(date +%s%N || date +%s)

    if sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master; SELECT COUNT(*) FROM sqlite_master; SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
        query_end=$(date +%s%N || date +%s)

        if command -v bc >/dev/null 2>&1; then
            query_duration=$(echo "scale=3; ($query_end - $query_start) / 1000000000" | bc || echo "0")
        else
            query_duration="<1"
        fi

        echo "duration=${query_duration}s"
    else
        echo "failed"
        return 1
    fi
}

# Show SQLite backup status
dashboard_sqlite_show_backup_status() {
    dashboard_show_section "SQLite Backup Status" "GREEN"

    local backup_dir="./data/backups"

    if [[ ! -d "$backup_dir" ]]; then
        dashboard_status_indicator "warning" "Backup directory not found"
        return 1
    fi

    # Count SQLite backups
    local sqlite_backup_count
    sqlite_backup_count=$(find "$backup_dir" -name "*sqlite*backup*.sql*" | wc -l)

    if [[ $sqlite_backup_count -eq 0 ]]; then
        dashboard_status_indicator "warning" "No SQLite backups found"
    else
        dashboard_status_indicator "good" "SQLite backups: $sqlite_backup_count"

        # Show most recent backup
        local recent_backup
        recent_backup=$(find "$backup_dir" -name "*sqlite*backup*.sql*" -printf "%T@ %p\n" | sort -nr | head -1 | cut -d' ' -f2-)

        if [[ -n "$recent_backup" ]]; then
            local backup_age backup_size
            backup_age=$(stat -c %Y "$recent_backup" || echo "0")
            backup_age=$(( ($(date +%s) - backup_age) / 3600 ))
            backup_size=$(du -h "$recent_backup" | cut -f1 || echo "unknown")

            echo "  Latest: $(basename "$recent_backup") (${backup_size}, ${backup_age}h ago)"
        fi
    fi

    echo ""
}

# Monitor SQLite file changes
dashboard_sqlite_monitor_changes() {
    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        echo "database=not_found"
        return 1
    fi

    local db_mtime wal_mtime shm_mtime
    db_mtime=$(stat -c %Y "$SQLITE_DB_PATH" || echo "0")

    # Check for WAL and SHM files (indicates active database)
    local wal_file="${SQLITE_DB_PATH}-wal"
    local shm_file="${SQLITE_DB_PATH}-shm"

    if [[ -f "$wal_file" ]]; then
        wal_mtime=$(stat -c %Y "$wal_file" || echo "0")
    else
        wal_mtime="0"
    fi

    if [[ -f "$shm_file" ]]; then
        shm_mtime=$(stat -c %Y "$shm_file" || echo "0")
    else
        shm_mtime="0"
    fi

    # Determine activity level
    local current_time=$(date +%s)
    local activity="idle"

    # If WAL or SHM files exist and are recent (within 5 minutes)
    if [[ $wal_mtime -gt 0 ]] && [[ $((current_time - wal_mtime)) -lt 300 ]]; then
        activity="active"
    elif [[ $shm_mtime -gt 0 ]] && [[ $((current_time - shm_mtime)) -lt 300 ]]; then
        activity="active"
    elif [[ $((current_time - db_mtime)) -lt 900 ]]; then  # 15 minutes
        activity="recent"
    fi

    cat <<EOF
database=available
activity=$activity
db_mtime=$db_mtime
wal_mtime=$wal_mtime
shm_mtime=$shm_mtime
EOF
}

# Display SQLite activity status
dashboard_sqlite_show_activity() {
    local activity_info
    activity_info=$(dashboard_sqlite_monitor_changes)

    if [[ "$activity_info" =~ database=not_found ]]; then
        dashboard_status_indicator "critical" "Database not found"
        return 1
    fi

    local activity
    eval "$(echo "$activity_info" | grep '^activity=')"

    case "$activity" in
        "active")
            dashboard_status_indicator "good" "Database: Active (recent writes)"
            ;;
        "recent")
            dashboard_status_indicator "info" "Database: Recently active"
            ;;
        "idle")
            dashboard_status_indicator "info" "Database: Idle"
            ;;
        *)
            dashboard_status_indicator "warning" "Database: Unknown activity"
            ;;
    esac
}

# Check for SQLite maintenance needs
dashboard_sqlite_check_maintenance_needed() {
    if ! command -v sqlite_metrics_get_comprehensive >/dev/null 2>&1; then
        return 1
    fi

    local metrics
    metrics=$(sqlite_metrics_get_comprehensive)

    if [[ ! "$metrics" =~ available=true ]]; then
        return 1
    fi

    # Parse key metrics
    local fragmentation_ratio freelist_pct wal_size_mb
    eval "$(echo "$metrics" | grep -E '^(fragmentation_ratio|freelist_pct|wal_size_mb)=')"

    # Check if maintenance is recommended
    local maintenance_needed=false

    # High fragmentation
    if command -v bc >/dev/null 2>&1; then
        if (( $(echo "$fragmentation_ratio > 1.3" | bc -l || echo 0) )); then
            maintenance_needed=true
        elif (( $(echo "$freelist_pct > 10" | bc -l || echo 0) )); then
            maintenance_needed=true
        elif (( $(echo "$wal_size_mb > 10" | bc -l || echo 0) )); then
            maintenance_needed=true
        fi
    fi

    [[ "$maintenance_needed" == "true" ]]
}

# Show maintenance urgency indicator
dashboard_sqlite_show_maintenance_urgency() {
    if dashboard_sqlite_check_maintenance_needed; then
        dashboard_status_indicator "warning" "Maintenance recommended"
        echo "  Run: ./sqlite-maintenance.sh --analyze"
    else
        dashboard_status_indicator "good" "Maintenance up to date"
    fi
}

# Get SQLite version and capabilities
dashboard_sqlite_get_version_info() {
    if ! command -v sqlite3 >/dev/null 2>&1; then
        echo "sqlite_available=false"
        return 1
    fi

    local sqlite_version compile_options
    sqlite_version=$(sqlite3 --version | cut -d' ' -f1 || echo "unknown")

    # Key compile options that affect performance
    local has_fts has_rtree has_json
    has_fts="false"
    has_rtree="false" 
    has_json="false"

    if sqlite3 ":memory:" "PRAGMA compile_options;" | grep -qi "fts"; then
        has_fts="true"
    fi

    if sqlite3 ":memory:" "PRAGMA compile_options;" | grep -qi "rtree"; then
        has_rtree="true"
    fi

    if sqlite3 ":memory:" "PRAGMA compile_options;" | grep -qi "json"; then
        has_json="true"
    fi

    cat <<EOF
sqlite_available=true
version=$sqlite_version
has_fts=$has_fts
has_rtree=$has_rtree
has_json=$has_json
EOF
}

# Show comprehensive SQLite dashboard section
dashboard_sqlite_show_comprehensive() {
    dashboard_sqlite_show_status
    dashboard_sqlite_show_activity
    dashboard_sqlite_show_maintenance_urgency
    echo ""
}

# Export SQLite dashboard functions
export -f dashboard_sqlite_init
export -f dashboard_sqlite_get_status
export -f dashboard_sqlite_get_detailed_metrics
export -f dashboard_sqlite_show_status
export -f dashboard_sqlite_show_activity
export -f dashboard_sqlite_check_maintenance_needed
export -f dashboard_sqlite_show_maintenance_urgency
export -f dashboard_sqlite_show_backup_status
export -f dashboard_sqlite_get_version_info
export -f dashboard_sqlite_show_comprehensive
