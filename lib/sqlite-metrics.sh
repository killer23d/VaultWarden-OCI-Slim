#!/usr/bin/env bash
# sqlite-metrics.sh -- SQLite database performance metrics collection
# Centralized database metrics gathering for consistent analysis

# Get comprehensive database metrics
sqlite_metrics_get_comprehensive() {
    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        echo "sqlite_available=false"
        return 1
    fi

    local file_size logical_size page_count page_size freelist_count
    local table_count index_count wal_size last_analyze_time

    # Basic file stats
    file_size=$(stat -c%s "$SQLITE_DB_PATH" || echo "0")

    # SQLite internal metrics
    if command -v sqlite3 >/dev/null 2>&1; then
        page_count=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA page_count;" || echo "0")
        page_size=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA page_size;" || echo "0")
        freelist_count=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA freelist_count;" || echo "0")

        # Schema stats
        table_count=$(sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';" || echo "0")
        index_count=$(sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';" || echo "0")
    else
        page_count="0"; page_size="0"; freelist_count="0"
        table_count="0"; index_count="0"
    fi

    # Calculated metrics
    logical_size=$((page_count * page_size))
    local file_size_mb logical_size_mb fragmentation_ratio freelist_pct

    if command -v bc >/dev/null 2>&1; then
        file_size_mb=$(echo "scale=2; $file_size / 1024 / 1024" | bc || echo "0")
        logical_size_mb=$(echo "scale=2; $logical_size / 1024 / 1024" | bc || echo "0")

        if [[ $logical_size -gt 0 ]]; then
            fragmentation_ratio=$(echo "scale=3; $file_size / $logical_size" | bc || echo "1.000")
        else
            fragmentation_ratio="1.000"
        fi

        if [[ $page_count -gt 0 ]]; then
            freelist_pct=$(echo "scale=1; $freelist_count * 100 / $page_count" | bc || echo "0.0")
        else
            freelist_pct="0.0"
        fi
    else
        file_size_mb=$(( file_size / 1024 / 1024 ))
        logical_size_mb=$(( logical_size / 1024 / 1024 ))
        fragmentation_ratio="1.0"
        freelist_pct="0"
    fi

    # WAL file size
    local wal_file="${SQLITE_DB_PATH}-wal"
    local wal_size_bytes wal_size_mb
    if [[ -f "$wal_file" ]]; then
        wal_size_bytes=$(stat -c%s "$wal_file" || echo "0")
        if command -v bc >/dev/null 2>&1; then
            wal_size_mb=$(echo "scale=2; $wal_size_bytes / 1024 / 1024" | bc || echo "0")
        else
            wal_size_mb=$(( wal_size_bytes / 1024 / 1024 ))
        fi
    else
        wal_size_bytes="0"
        wal_size_mb="0"
    fi

    # Statistics freshness analysis
    local stat_freshness="missing"
    if command -v sqlite3 >/dev/null 2>&1; then
        if sqlite3 "$SQLITE_DB_PATH" "SELECT name FROM sqlite_master WHERE name='sqlite_stat1';" | grep -q sqlite_stat1; then
            # Statistics exist, check freshness based on database age
            local db_age_hours
            db_age_hours=$(( ($(date +%s) - $(stat -c %Y "$SQLITE_DB_PATH" || echo 0)) / 3600 ))

            if [[ $db_age_hours -lt 24 ]]; then
                stat_freshness="fresh"
            elif [[ $db_age_hours -lt 168 ]]; then  # 1 week
                stat_freshness="moderate"
            else
                stat_freshness="stale"
            fi
        fi
    fi

    # Journal mode
    local journal_mode
    if command -v sqlite3 >/dev/null 2>&1; then
        journal_mode=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA journal_mode;" || echo "unknown")
    else
        journal_mode="unknown"
    fi

    # Output all metrics
    cat <<EOF
sqlite_available=true
file_size=$file_size
file_size_mb=$file_size_mb
logical_size=$logical_size
logical_size_mb=$logical_size_mb
page_count=$page_count
page_size=$page_size
freelist_count=$freelist_count
freelist_pct=$freelist_pct
fragmentation_ratio=$fragmentation_ratio
table_count=$table_count
index_count=$index_count
wal_size_bytes=$wal_size_bytes
wal_size_mb=$wal_size_mb
stat_freshness=$stat_freshness
journal_mode=$journal_mode
EOF
}

# Get basic database metrics (faster version)
sqlite_metrics_get_basic() {
    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        echo "sqlite_available=false"
        return 1
    fi

    local file_size freelist_count
    file_size=$(stat -c%s "$SQLITE_DB_PATH" || echo "0")

    if command -v sqlite3 >/dev/null 2>&1; then
        freelist_count=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA freelist_count;" || echo "0")
    else
        freelist_count="0"
    fi

    # WAL file size
    local wal_file="${SQLITE_DB_PATH}-wal"
    local wal_size_bytes
    if [[ -f "$wal_file" ]]; then
        wal_size_bytes=$(stat -c%s "$wal_file" || echo "0")
    else
        wal_size_bytes="0"
    fi

    cat <<EOF
sqlite_available=true
file_size=$file_size
freelist_count=$freelist_count
wal_size_bytes=$wal_size_bytes
EOF
}

# Get database performance metrics
sqlite_metrics_get_performance() {
    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        echo "sqlite_available=false"
        return 1
    fi

    local db_modified query_time integrity_ok user_count

    # Database modification time
    db_modified=$(stat -c%Y "$SQLITE_DB_PATH" || echo "0")

    # Simple performance test
    if command -v sqlite3 >/dev/null 2>&1; then
        local query_start query_end
        query_start=$(date +%s%N || date +%s)

        if sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
            query_end=$(date +%s%N || date +%s)

            if command -v bc >/dev/null 2>&1; then
                query_time=$(echo "scale=3; ($query_end - $query_start) / 1000000000" | bc || echo "0")
            else
                query_time="0"
            fi

            # Quick integrity check
            if sqlite3 "$SQLITE_DB_PATH" "PRAGMA quick_check;" | grep -q "ok"; then
                integrity_ok="true"
            else
                integrity_ok="false"
            fi

            # User count (if users table exists)
            if sqlite3 "$SQLITE_DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='users';" | grep -q users; then
                user_count=$(sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM users;" || echo "N/A")
            else
                user_count="N/A"
            fi
        else
            query_time="N/A"
            integrity_ok="false"
            user_count="N/A"
        fi
    else
        query_time="N/A"
        integrity_ok="unknown"
        user_count="N/A"
    fi

    cat <<EOF
sqlite_available=true
db_modified=$db_modified
query_time=$query_time
integrity_ok=$integrity_ok
user_count=$user_count
EOF
}

# Get database health status
sqlite_metrics_get_health() {
    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        echo "sqlite_available=false"
        return 1
    fi

    local health_status="unknown"
    local health_details="Database file exists"

    if command -v sqlite3 >/dev/null 2>&1; then
        # Test basic accessibility
        if sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
            # Run integrity check
            local integrity_result
            integrity_result=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA integrity_check;")

            if [[ "$integrity_result" == "ok" ]]; then
                health_status="healthy"
                health_details="Database is accessible and passes integrity check"
            else
                health_status="corrupted"
                health_details="Database integrity check failed: $integrity_result"
            fi
        else
            health_status="inaccessible"
            health_details="Database file exists but is not accessible"
        fi
    else
        health_status="unknown"
        health_details="sqlite3 command not available for testing"
    fi

    cat <<EOF
sqlite_available=true
health_status=$health_status
health_details=$health_details
EOF
}

# Parse specific metric from output
sqlite_metrics_parse() {
    local metrics="$1"
    local metric_name="$2"

    echo "$metrics" | grep "^${metric_name}=" | cut -d'=' -f2-
}

# Format database size for display
sqlite_metrics_format_size() {
    local size_bytes="$1"

    if [[ $size_bytes -eq 0 ]]; then
        echo "0 B"
        return
    fi

    local units=("B" "KB" "MB" "GB" "TB")
    local unit_index=0
    local size="$size_bytes"

    while [[ $size -gt 1024 && $unit_index -lt $((${#units[@]} - 1)) ]]; do
        if command -v bc >/dev/null 2>&1; then
            size=$(echo "scale=1; $size / 1024" | bc)
        else
            size=$((size / 1024))
        fi
        ((unit_index++))
    done

    echo "${size} ${units[$unit_index]}"
}

# Calculate fragmentation level
sqlite_metrics_fragmentation_level() {
    local fragmentation_ratio="$1"

    if command -v bc >/dev/null 2>&1; then
        if (( $(echo "$fragmentation_ratio > 1.5" | bc -l || echo 0) )); then
            echo "high"
        elif (( $(echo "$fragmentation_ratio > 1.3" | bc -l || echo 0) )); then
            echo "moderate"
        elif (( $(echo "$fragmentation_ratio > 1.1" | bc -l || echo 0) )); then
            echo "low"
        else
            echo "minimal"
        fi
    else
        # Fallback for systems without bc
        local ratio_int
        ratio_int=$(echo "$fragmentation_ratio" | cut -d'.' -f1)
        if [[ $ratio_int -gt 1 ]]; then
            echo "moderate"
        else
            echo "low"
        fi
    fi
}

# Get database age in human readable format
sqlite_metrics_get_age() {
    local timestamp="$1"
    local current_time=$(date +%s)
    local age_seconds=$((current_time - timestamp))

    if [[ $age_seconds -lt 3600 ]]; then
        echo "$((age_seconds / 60)) minutes ago"
    elif [[ $age_seconds -lt 86400 ]]; then
        echo "$((age_seconds / 3600)) hours ago"
    else
        echo "$((age_seconds / 86400)) days ago"
    fi
}

# Export metrics functions
export -f sqlite_metrics_get_comprehensive
export -f sqlite_metrics_get_basic
export -f sqlite_metrics_get_performance
export -f sqlite_metrics_get_health
export -f sqlite_metrics_parse
export -f sqlite_metrics_format_size
export -f sqlite_metrics_fragmentation_level
export -f sqlite_metrics_get_age
