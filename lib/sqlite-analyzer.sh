#!/usr/bin/env bash
# sqlite-analyzer.sh -- Intelligent database analysis and decision engine
# Determines optimal maintenance operations based on database metrics

# Global variables for analysis results
declare -a ANALYZER_RECOMMENDED_OPERATIONS=()
declare -a ANALYZER_OPERATION_REASONS=()
declare -g ANALYZER_VACUUM_PRIORITY="normal"

# Configuration thresholds (loaded from config)
declare -A ANALYZER_THRESHOLDS=(
    ["FRAGMENTATION_WARNING"]=1.3
    ["FRAGMENTATION_CRITICAL"]=1.5
    ["FREELIST_WARNING"]=10.0
    ["FREELIST_CRITICAL"]=15.0
    ["WAL_SIZE_WARNING_MB"]=1.0
    ["WAL_SIZE_CRITICAL_MB"]=10.0
    ["DB_SIZE_LARGE_MB"]=50.0
    ["DB_SIZE_HUGE_MB"]=100.0
    ["STAT_FRESHNESS_DAYS"]=7
)

# Initialize analyzer
sqlite_analyzer_init() {
    # Load thresholds from config if available
    local config_file="$SCRIPT_DIR/config/sqlite-thresholds.conf"
    if [[ -f "$config_file" ]]; then
        sqlite_analyzer_load_thresholds "$config_file"
    fi
}

# Load thresholds from configuration file
sqlite_analyzer_load_thresholds() {
    local config_file="$1"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue

        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Update threshold if valid
        if [[ -n "${ANALYZER_THRESHOLDS[$key]:-}" ]]; then
            ANALYZER_THRESHOLDS["$key"]="$value"
        fi
    done < "$config_file"
}

# Perform comprehensive database analysis
sqlite_analyzer_perform_analysis() {
    log_step "🧠 Performing intelligent database analysis..."

    if ! sqlite_operations_check_database; then
        return 1
    fi

    # Get comprehensive database metrics
    local metrics
    metrics=$(sqlite_metrics_get_comprehensive)

    # Parse metrics
    local file_size_mb logical_size_mb fragmentation_ratio
    local freelist_count freelist_pct wal_size_mb stat_freshness
    local table_count page_count

    eval "$(echo "$metrics" | grep -E '^(file_size_mb|logical_size_mb|fragmentation_ratio|freelist_count|freelist_pct|wal_size_mb|stat_freshness|table_count|page_count)=')"

    log_info "📊 Database Analysis Results:"
    log_info "  📁 Database size: ${file_size_mb} MB"
    log_info "  📄 Total pages: $page_count"
    log_info "  🗂️  Free pages: $freelist_count (${freelist_pct}%)"
    log_info "  📊 Fragmentation ratio: $fragmentation_ratio"
    log_info "  🔄 WAL file size: ${wal_size_mb} MB"
    log_info "  📈 Tables: $table_count"
    log_info "  📋 Statistics: $stat_freshness"

    # Reset analysis results
    ANALYZER_RECOMMENDED_OPERATIONS=()
    ANALYZER_OPERATION_REASONS=()
    ANALYZER_VACUUM_PRIORITY="normal"

    # Decision matrix for operations
    sqlite_analyzer_analyze_statistics "$stat_freshness" "$file_size_mb" "$table_count"
    sqlite_analyzer_analyze_wal "$wal_size_mb" "$file_size_mb"
    sqlite_analyzer_analyze_fragmentation "$fragmentation_ratio" "$freelist_pct" "$file_size_mb"
    sqlite_analyzer_analyze_optimization "$stat_freshness" "$file_size_mb"

    # Export results
    export ANALYZER_RECOMMENDED_OPERATIONS
    export ANALYZER_OPERATION_REASONS
    export ANALYZER_VACUUM_PRIORITY

    # Summary
    if [[ ${#ANALYZER_RECOMMENDED_OPERATIONS[@]} -gt 0 ]]; then
        log_decision "Recommended operations: ${ANALYZER_RECOMMENDED_OPERATIONS[*]}"
        for reason in "${ANALYZER_OPERATION_REASONS[@]}"; do
            log_decision "  • $reason"
        done
        return 0  # Operations needed
    else
        log_decision "No maintenance operations needed - database is well-optimized"
        return 1  # No operations needed
    fi
}

# Analyze statistics freshness
sqlite_analyzer_analyze_statistics() {
    local stat_freshness="$1"
    local file_size_mb="$2"
    local table_count="$3"

    case "$stat_freshness" in
        "missing")
            ANALYZER_RECOMMENDED_OPERATIONS+=("ANALYZE")
            ANALYZER_OPERATION_REASONS+=("ANALYZE: Statistics missing, query planner needs data")
            ;;
        "stale")
            ANALYZER_RECOMMENDED_OPERATIONS+=("ANALYZE")
            ANALYZER_OPERATION_REASONS+=("ANALYZE: Statistics are stale (>${ANALYZER_THRESHOLDS[STAT_FRESHNESS_DAYS]} days old)")
            ;;
        "moderate")
            if (( $(echo "$file_size_mb > 10" | bc -l || echo 0) )); then
                ANALYZER_RECOMMENDED_OPERATIONS+=("ANALYZE")
                ANALYZER_OPERATION_REASONS+=("ANALYZE: Moderate age statistics on sizeable database")
            fi
            ;;
    esac

    # Table statistics for complex databases
    if [[ $table_count -gt 3 ]] && [[ "$stat_freshness" == "stale" || "$stat_freshness" == "missing" ]]; then
        ANALYZER_RECOMMENDED_OPERATIONS+=("TABLE_STATISTICS")
        ANALYZER_OPERATION_REASONS+=("TABLE_STATISTICS: Multiple tables with outdated statistics")
    fi
}

# Analyze WAL file requirements
sqlite_analyzer_analyze_wal() {
    local wal_size_mb="$1"
    local file_size_mb="$2"

    if (( $(echo "$wal_size_mb > ${ANALYZER_THRESHOLDS[WAL_SIZE_CRITICAL_MB]}" | bc -l || echo 0) )); then
        ANALYZER_RECOMMENDED_OPERATIONS+=("WAL_CHECKPOINT")
        ANALYZER_OPERATION_REASONS+=("WAL_CHECKPOINT: Large WAL file (${wal_size_mb} MB) needs merging")
    elif (( $(echo "$wal_size_mb > ${ANALYZER_THRESHOLDS[WAL_SIZE_WARNING_MB]}" | bc -l || echo 0) )) && (( $(echo "$file_size_mb < ${ANALYZER_THRESHOLDS[DB_SIZE_LARGE_MB]}" | bc -l || echo 0) )); then
        ANALYZER_RECOMMENDED_OPERATIONS+=("WAL_CHECKPOINT")
        ANALYZER_OPERATION_REASONS+=("WAL_CHECKPOINT: WAL size significant relative to database size")
    fi
}

# Analyze fragmentation and VACUUM requirements
sqlite_analyzer_analyze_fragmentation() {
    local fragmentation_ratio="$1"
    local freelist_pct="$2"
    local file_size_mb="$3"

    local vacuum_needed=false

    # High fragmentation threshold
    if (( $(echo "$fragmentation_ratio > ${ANALYZER_THRESHOLDS[FRAGMENTATION_CRITICAL]}" | bc -l || echo 0) )); then
        vacuum_needed=true
        ANALYZER_VACUUM_PRIORITY="high"
        ANALYZER_OPERATION_REASONS+=("VACUUM (HIGH): Severe fragmentation ratio ($fragmentation_ratio)")
    # Moderate fragmentation with significant free space
    elif (( $(echo "$fragmentation_ratio > ${ANALYZER_THRESHOLDS[FRAGMENTATION_WARNING]}" | bc -l || echo 0) )) && (( $(echo "$freelist_pct > ${ANALYZER_THRESHOLDS[FREELIST_WARNING]}" | bc -l || echo 0) )); then
        vacuum_needed=true
        ANALYZER_VACUUM_PRIORITY="normal"
        ANALYZER_OPERATION_REASONS+=("VACUUM (NORMAL): Moderate fragmentation ($fragmentation_ratio) with ${freelist_pct}% free pages")
    # Large databases with modest fragmentation
    elif (( $(echo "$file_size_mb > ${ANALYZER_THRESHOLDS[DB_SIZE_HUGE_MB]}" | bc -l || echo 0) )) && (( $(echo "$fragmentation_ratio > 1.2" | bc -l || echo 0) )); then
        vacuum_needed=true
        ANALYZER_VACUUM_PRIORITY="normal"
        ANALYZER_OPERATION_REASONS+=("VACUUM (NORMAL): Large database with modest fragmentation")
    # Significant free space percentage
    elif (( $(echo "$freelist_pct > ${ANALYZER_THRESHOLDS[FREELIST_CRITICAL]}" | bc -l || echo 0) )); then
        vacuum_needed=true
        ANALYZER_VACUUM_PRIORITY="normal"
        ANALYZER_OPERATION_REASONS+=("VACUUM (NORMAL): High percentage of free pages (${freelist_pct}%)")
    fi

    if [[ "$vacuum_needed" == "true" ]]; then
        ANALYZER_RECOMMENDED_OPERATIONS+=("VACUUM")
    fi
}

# Analyze optimization requirements
sqlite_analyzer_analyze_optimization() {
    local stat_freshness="$1"
    local file_size_mb="$2"

    # PRAGMA OPTIMIZE - Always beneficial for active databases with statistics
    if [[ "$stat_freshness" != "missing" ]] && (( $(echo "$file_size_mb > 1" | bc -l || echo 0) )); then
        ANALYZER_RECOMMENDED_OPERATIONS+=("PRAGMA_OPTIMIZE")
        ANALYZER_OPERATION_REASONS+=("PRAGMA_OPTIMIZE: Active database benefits from automatic optimization")
    fi
}

# Check if analysis has recommendations
sqlite_analyzer_has_recommendations() {
    [[ ${#ANALYZER_RECOMMENDED_OPERATIONS[@]} -gt 0 ]]
}

# Check if operations were executed
sqlite_analyzer_has_executed_operations() {
    [[ -n "${SQLITE_EXECUTED_OPERATIONS:-}" ]] && [[ ${#SQLITE_EXECUTED_OPERATIONS[@]} -gt 0 ]]
}

# Get recommended operations
sqlite_analyzer_get_recommendations() {
    printf '%s
' "${ANALYZER_RECOMMENDED_OPERATIONS[@]}"
}

# Get operation reasons
sqlite_analyzer_get_reasons() {
    printf '%s
' "${ANALYZER_OPERATION_REASONS[@]}"
}

# Get vacuum priority
sqlite_analyzer_get_vacuum_priority() {
    echo "$ANALYZER_VACUUM_PRIORITY"
}

# Check if specific operation is recommended
sqlite_analyzer_is_recommended() {
    local operation="$1"
    local op
    for op in "${ANALYZER_RECOMMENDED_OPERATIONS[@]}"; do
        [[ "$op" == "$operation" ]] && return 0
    done
    return 1
}

# Get threshold value
sqlite_analyzer_get_threshold() {
    local threshold_name="$1"
    echo "${ANALYZER_THRESHOLDS[$threshold_name]:-0}"
}

# Export analyzer functions
export -f sqlite_analyzer_init
export -f sqlite_analyzer_perform_analysis
export -f sqlite_analyzer_has_recommendations
export -f sqlite_analyzer_has_executed_operations
export -f sqlite_analyzer_get_recommendations
export -f sqlite_analyzer_get_reasons
export -f sqlite_analyzer_get_vacuum_priority
export -f sqlite_analyzer_is_recommended
export -f sqlite_analyzer_get_threshold
