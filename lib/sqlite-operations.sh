#!/usr/bin/env bash
# sqlite-operations.sh -- Individual SQLite maintenance operations
# Modular implementation of database maintenance tasks

# Global variables for operation tracking
declare -a SQLITE_EXECUTED_OPERATIONS=()
declare -a SQLITE_FAILED_OPERATIONS=()
declare -g SQLITE_MAINTENANCE_SUMMARY=""

# Initialize operations module
sqlite_operations_init() {
    # Load operation configuration if available
    local config_file="$SCRIPT_DIR/config/sqlite-operations.conf"
    if [[ -f "$config_file" ]]; then
        source "$config_file" || log_warning "Failed to load operations config"
    fi
}

# Check if database exists and is accessible
sqlite_operations_check_database() {
    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        log_error "SQLite database not found: $SQLITE_DB_PATH"
        return 1
    fi

    if ! sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
        log_error "SQLite database is not accessible: $SQLITE_DB_PATH"
        return 1
    fi

    return 0
}

# Run integrity check
sqlite_operations_integrity_check() {
    log_step "🔍 Running database integrity check..."

    local integrity_result
    integrity_result=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA integrity_check;")

    if [[ "$integrity_result" == "ok" ]]; then
        log_success "Database integrity check: PASSED"
        return 0
    else
        log_error "Database integrity check: FAILED - $integrity_result"
        return 1
    fi
}

# ANALYZE operation - Update query planner statistics
sqlite_operations_analyze() {
    log_step "📊 ANALYZE - Updating query planner statistics..."
    local start_time=$(date +%s)

    if sqlite3 "$SQLITE_DB_PATH" "ANALYZE;"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "ANALYZE completed in ${duration}s - Query planner statistics updated"
        SQLITE_EXECUTED_OPERATIONS+=("ANALYZE")
        SQLITE_MAINTENANCE_SUMMARY+="✓ ANALYZE: COMPLETED\n"
        return 0
    else
        log_error "ANALYZE operation failed"
        SQLITE_FAILED_OPERATIONS+=("ANALYZE")
        SQLITE_MAINTENANCE_SUMMARY+="✗ ANALYZE: FAILED\n"
        return 1
    fi
}

# WAL CHECKPOINT operation
sqlite_operations_wal_checkpoint() {
    log_step "🔄 WAL Checkpoint - Merging WAL changes to main database..."
    local start_time=$(date +%s)

    # Check if WAL mode is enabled
    local journal_mode
    journal_mode=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA journal_mode;")

    if [[ "$journal_mode" != "wal" ]]; then
        log_info "Database not in WAL mode ($journal_mode), skipping checkpoint"
        return 0
    fi

    # Get WAL file size before checkpoint
    local wal_file="${SQLITE_DB_PATH}-wal"
    local wal_size_before=0
    if [[ -f "$wal_file" ]]; then
        wal_size_before=$(stat -c%s "$wal_file" || echo "0")
    fi

    if [[ $wal_size_before -eq 0 ]]; then
        log_info "No WAL file present, checkpoint not needed"
        return 0
    fi

    local wal_size_mb_before
    wal_size_mb_before=$(echo "scale=1; $wal_size_before / 1024 / 1024" | bc)
    log_info "WAL file size before checkpoint: ${wal_size_mb_before} MB"

    # Perform TRUNCATE checkpoint
    if sqlite3 "$SQLITE_DB_PATH" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1; then
        local wal_size_after=0
        if [[ -f "$wal_file" ]]; then
            wal_size_after=$(stat -c%s "$wal_file" || echo "0")
        fi

        local wal_size_mb_after space_freed_mb
        wal_size_mb_after=$(echo "scale=1; $wal_size_after / 1024 / 1024" | bc)
        space_freed_mb=$(echo "scale=1; ($wal_size_before - $wal_size_after) / 1024 / 1024" | bc)

        local end_time=$(date +%s)
        local duration=$((end_time - start_time))

        log_success "WAL checkpoint completed in ${duration}s"
        log_info "Space freed from WAL: ${space_freed_mb} MB"
        SQLITE_EXECUTED_OPERATIONS+=("WAL_CHECKPOINT")
        SQLITE_MAINTENANCE_SUMMARY+="✓ WAL Checkpoint: COMPLETED\n"
        return 0
    else
        log_error "WAL checkpoint failed"
        SQLITE_FAILED_OPERATIONS+=("WAL_CHECKPOINT")
        SQLITE_MAINTENANCE_SUMMARY+="✗ WAL Checkpoint: FAILED\n"
        return 1
    fi
}

# VACUUM operation
sqlite_operations_vacuum() {
    local create_backup="${1:-true}"

    log_step "🗜️ VACUUM - Reclaiming space and defragmenting database..."

    # Get pre-VACUUM metrics
    local pre_metrics pre_size_mb
    pre_metrics=$(sqlite_metrics_get_basic)
    local pre_file_size pre_freelist_count
    eval "$(echo "$pre_metrics" | grep -E '^(file_size|freelist_count)=')"
    pre_size_mb=$(echo "scale=1; $pre_file_size / 1024 / 1024" | bc)

    log_info "Pre-VACUUM: Size=${pre_size_mb}MB, Freelist=${pre_freelist_count} pages"

    # Create backup if requested
    if [[ "$create_backup" == "true" ]]; then
        if ! sqlite_operations_create_backup >/dev/null; then
            log_error "Backup creation failed, aborting VACUUM"
            SQLITE_FAILED_OPERATIONS+=("VACUUM")
            SQLITE_MAINTENANCE_SUMMARY+="✗ VACUUM: FAILED (backup)\n"
            return 1
        fi
    fi

    # Vacuum with timing
    local vacuum_start_time vacuum_end_time vacuum_duration
    vacuum_start_time=$(date +%s)

    if sqlite3 "$SQLITE_DB_PATH" "VACUUM;"; then
        vacuum_end_time=$(date +%s)
        vacuum_duration=$((vacuum_end_time - vacuum_start_time))

        # Get post-VACUUM metrics
        local post_metrics post_size_mb space_saved
        post_metrics=$(sqlite_metrics_get_basic)
        local post_file_size post_freelist_count
        eval "$(echo "$post_metrics" | grep -E '^(file_size|freelist_count)=')"
        post_size_mb=$(echo "scale=1; $post_file_size / 1024 / 1024" | bc)
        space_saved=$(echo "scale=1; ($pre_file_size - $post_file_size) / 1024 / 1024" | bc)

        log_success "VACUUM completed in ${vacuum_duration}s"
        log_info "Post-VACUUM: Size=${post_size_mb}MB, Freelist=${post_freelist_count} pages"
        log_info "Space reclaimed: ${space_saved} MB"

        SQLITE_EXECUTED_OPERATIONS+=("VACUUM")
        SQLITE_MAINTENANCE_SUMMARY+="✓ VACUUM: COMPLETED\n"
        return 0
    else
        log_error "VACUUM operation failed"
        SQLITE_FAILED_OPERATIONS+=("VACUUM")
        SQLITE_MAINTENANCE_SUMMARY+="✗ VACUUM: FAILED\n"
        return 1
    fi
}

# PRAGMA OPTIMIZE operation
sqlite_operations_pragma_optimize() {
    log_step "⚡ PRAGMA Optimize - Running automatic optimization..."
    local start_time=$(date +%s)

    if sqlite3 "$SQLITE_DB_PATH" "PRAGMA optimize;"; then
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        log_success "PRAGMA optimize completed in ${duration}s"
        SQLITE_EXECUTED_OPERATIONS+=("PRAGMA_OPTIMIZE")
        SQLITE_MAINTENANCE_SUMMARY+="✓ PRAGMA Optimize: COMPLETED\n"
        return 0
    else
        log_error "PRAGMA optimize failed"
        SQLITE_FAILED_OPERATIONS+=("PRAGMA_OPTIMIZE")
        SQLITE_MAINTENANCE_SUMMARY+="✗ PRAGMA Optimize: FAILED\n"
        return 1
    fi
}

# Table statistics operation
sqlite_operations_table_statistics() {
    log_step "📈 Recomputing detailed table statistics..."
    local start_time=$(date +%s)

    # Get list of tables
    local tables
    tables=$(sqlite3 "$SQLITE_DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")

    if [[ -z "$tables" ]]; then
        log_warning "No user tables found for statistics computation"
        return 0
    fi

    local table_count=0
    local failed_count=0

    while IFS= read -r table; do
        if [[ -n "$table" ]]; then
            if sqlite3 "$SQLITE_DB_PATH" "ANALYZE \"$table\";"; then
                ((table_count++))
                log_info "  ✓ Statistics updated for table: $table"
            else
                ((failed_count++))
                log_warning "  ✗ Failed to update statistics for table: $table"
            fi
        fi
    done <<< "$tables"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ $failed_count -eq 0 ]]; then
        log_success "Table statistics recomputed for $table_count tables in ${duration}s"
        SQLITE_EXECUTED_OPERATIONS+=("TABLE_STATISTICS")
        SQLITE_MAINTENANCE_SUMMARY+="✓ Table Statistics: COMPLETED\n"
        return 0
    else
        log_warning "Table statistics completed with $failed_count failures"
        SQLITE_FAILED_OPERATIONS+=("TABLE_STATISTICS")
        SQLITE_MAINTENANCE_SUMMARY+="✗ Table Statistics: PARTIAL\n"
        return 1
    fi
}

# Create maintenance backup
sqlite_operations_create_backup() {
    log_info "Creating maintenance backup..."

    local backup_dir="${ROOT_DIR}/data/backups"
    local backup_name="maintenance-backup-$(date +%Y%m%d_%H%M%S).sql"
    local backup_file="$backup_dir/$backup_name"

    mkdir -p "$backup_dir"

    if sqlite3 "$SQLITE_DB_PATH" ".dump" > "$backup_file"; then
        log_success "Maintenance backup created: $backup_file"
        echo "$backup_file"
        return 0
    else
        log_error "Failed to create maintenance backup"
        return 1
    fi
}

# Run single operation
sqlite_operations_run_single() {
    local operation="$1"

    case "$operation" in
        "analyze") sqlite_operations_analyze; exit $? ;;
        "vacuum") sqlite_operations_vacuum; exit $? ;;
        "checkpoint") sqlite_operations_wal_checkpoint; exit $? ;;
        "optimize") sqlite_operations_pragma_optimize; exit $? ;;
        "statistics") sqlite_operations_table_statistics; exit $? ;;
        *) log_error "Unknown operation: $operation"; exit 1 ;;
    esac
}

# Run comprehensive maintenance (all operations)
sqlite_operations_run_comprehensive() {
    local is_cron_mode="${1:-false}"

    # Clear tracking arrays
    SQLITE_EXECUTED_OPERATIONS=()
    SQLITE_FAILED_OPERATIONS=()
    SQLITE_MAINTENANCE_SUMMARY=""

    # Always check integrity first
    if ! sqlite_operations_integrity_check; then
        log_error "Integrity check failed - aborting maintenance"
        return 1
    fi

    # Set all operations as needed for comprehensive mode
    ANALYZER_RECOMMENDED_OPERATIONS=("WAL_CHECKPOINT" "ANALYZE" "TABLE_STATISTICS" "VACUUM" "PRAGMA_OPTIMIZE")

    # Execute in optimal order
    sqlite_operations_execute_sequence "$is_cron_mode"
}

# Run intelligent maintenance
sqlite_operations_run_intelligent() {
    local is_cron_mode="${1:-false}"

    # Clear tracking arrays
    SQLITE_EXECUTED_OPERATIONS=()
    SQLITE_FAILED_OPERATIONS=()
    SQLITE_MAINTENANCE_SUMMARY=""

    # Always check integrity first
    if ! sqlite_operations_integrity_check; then
        log_error "Integrity check failed - aborting maintenance"
        return 1
    fi

    # Perform intelligent analysis
    local operations_needed=false
    if sqlite_analyzer_perform_analysis; then
        operations_needed=true
    fi

    if [[ "$operations_needed" == "false" ]]; then
        log_success "🎉 Database is well-maintained - no operations needed"
        return 0
    fi

    # Execute recommended operations
    sqlite_operations_execute_sequence "$is_cron_mode"
}

# Execute operation sequence in optimal order
sqlite_operations_execute_sequence() {
    local is_cron_mode="${1:-false}"

    # Process operations in optimal order
    local operation_order=("WAL_CHECKPOINT" "ANALYZE" "TABLE_STATISTICS" "VACUUM" "PRAGMA_OPTIMIZE")

    for operation in "${operation_order[@]}"; do
        # Check if this operation is recommended
        if sqlite_analyzer_is_recommended "$operation"; then
            case "$operation" in
                "WAL_CHECKPOINT")
                    sqlite_operations_wal_checkpoint
                    ;;
                "ANALYZE")
                    sqlite_operations_analyze
                    ;;
                "TABLE_STATISTICS")
                    sqlite_operations_table_statistics
                    ;;
                "VACUUM")
                    # Check if VaultWarden is running for VACUUM warning
                    if docker ps --filter "name=vaultwarden" --filter "status=running" | grep -q vaultwarden; then
                        if [[ "$is_cron_mode" == "true" ]]; then
                            log_warning "Skipping VACUUM in cron mode - VaultWarden is running"
                            SQLITE_MAINTENANCE_SUMMARY+="⏭ VACUUM: SKIPPED (VaultWarden running)\n"
                            continue
                        else
                            log_warning "VaultWarden is running - VACUUM may cause temporary slowdowns"
                        fi
                    fi
                    sqlite_operations_vacuum
                    ;;
                "PRAGMA_OPTIMIZE")
                    sqlite_operations_pragma_optimize
                    ;;
            esac
        fi
    done

    # Final integrity check
    if sqlite_operations_integrity_check; then
        SQLITE_MAINTENANCE_SUMMARY+="✓ Final Integrity Check: PASSED\n"
    else
        SQLITE_FAILED_OPERATIONS+=("FINAL_INTEGRITY_CHECK")
        SQLITE_MAINTENANCE_SUMMARY+="✗ Final Integrity Check: FAILED\n"
    fi

    # Export results
    export SQLITE_EXECUTED_OPERATIONS
    export SQLITE_FAILED_OPERATIONS
    export SQLITE_MAINTENANCE_SUMMARY

    # Return success if no failures
    [[ ${#SQLITE_FAILED_OPERATIONS[@]} -eq 0 ]]
}

# Export operations functions
export -f sqlite_operations_init
export -f sqlite_operations_check_database
export -f sqlite_operations_integrity_check
export -f sqlite_operations_run_single
export -f sqlite_operations_run_comprehensive
export -f sqlite_operations_run_intelligent
export -f sqlite_operations_create_backup
