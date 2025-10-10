#!/usr/bin/env bash
# dashboard-maintenance.sh -- Interactive SQLite maintenance menu system
# Provides user-friendly access to all SQLite maintenance operations

# Initialize maintenance menu
dashboard_maintenance_init() {
    # Ensure SQLite modules are available
    if ! command -v sqlite_analyzer_perform_analysis >/dev/null 2>&1; then
        log_warning "SQLite analyzer not available - limited maintenance functionality"
    fi
}

# Show main maintenance menu
dashboard_maintenance_show_menu() {
    while true; do
        dashboard_show_header_simple "SQLite Maintenance Menu"

        echo "🔧 VaultWarden SQLite Database Maintenance"
        echo ""

        # Show current database status
        dashboard_maintenance_show_current_status

        echo ""
        dashboard_show_menu "Available Operations"             "1) 🧠 Intelligent Analysis (recommended)"             "2) 🤖 Auto Maintenance (analyze + perform needed operations)"             "3) 🔧 Manual Operations Menu"             "4) 📅 Schedule Management"             "5) 📊 Database Statistics"             "6) 📋 Maintenance History"             "7) ⚙️  Advanced Operations"             "8) 🏠 Return to Main Dashboard"

        read -p "Select operation (1-8): " choice

        case "$choice" in
            1) dashboard_maintenance_intelligent_analysis ;;
            2) dashboard_maintenance_auto_maintenance ;;
            3) dashboard_maintenance_manual_operations ;;
            4) dashboard_maintenance_schedule_menu ;;
            5) dashboard_maintenance_database_stats ;;
            6) dashboard_maintenance_history ;;
            7) dashboard_maintenance_advanced_menu ;;
            8) return 0 ;;
            *) 
                echo "Invalid choice. Press Enter to continue..."
                read
                ;;
        esac
    done
}

# Show current database status
dashboard_maintenance_show_current_status() {
    local status_metrics
    status_metrics=$(dashboard_sqlite_get_status)

    if [[ "$status_metrics" =~ status=accessible ]]; then
        local db_size db_health
        eval "$(echo "$status_metrics" | grep -E '^(size|health)=')"

        echo "📊 Current Database Status:"
        printf "  Size: %s\n" "$db_size"
        printf "  Health: %s\n" "$db_health"

        # Show maintenance recommendation
        if dashboard_sqlite_check_maintenance_needed; then
            echo "  Status: 🔧 Maintenance recommended"
        else
            echo "  Status: ✅ Well maintained"
        fi
    else
        echo "❌ Database not accessible"
    fi
}

# Intelligent analysis menu
dashboard_maintenance_intelligent_analysis() {
    dashboard_show_header_simple "Intelligent Database Analysis"

    echo "🧠 Analyzing database and determining optimal maintenance operations..."
    echo ""

    if command -v sqlite_analyzer_perform_analysis >/dev/null 2>&1; then
        if sqlite_analyzer_perform_analysis; then
            echo ""
            echo "📋 Analysis Results:"

            # Show recommendations
            local recommendations
            recommendations=$(sqlite_analyzer_get_recommendations)

            if [[ -n "$recommendations" ]]; then
                echo "$recommendations" | while IFS= read -r operation; do
                    echo "  🔧 $operation recommended"
                done

                echo ""
                echo "💭 Reasoning:"
                local reasons
                reasons=$(sqlite_analyzer_get_reasons)
                echo "$reasons" | while IFS= read -r reason; do
                    echo "  • $reason"
                done

                echo ""
                if dashboard_confirm "Execute recommended operations now?" "N"; then
                    dashboard_maintenance_execute_intelligent
                fi
            else
                echo "  ✅ No maintenance operations needed"
                echo "  Database is already well-optimized"
            fi
        else
            echo "❌ Analysis failed - check database accessibility"
        fi
    else
        echo "❌ SQLite analyzer not available"
    fi

    echo ""
    dashboard_wait_input
}

# Auto maintenance execution
dashboard_maintenance_auto_maintenance() {
    dashboard_show_header_simple "Automatic Maintenance"

    echo "🤖 Running intelligent automatic maintenance..."
    echo ""

    # Warning about VaultWarden downtime
    if is_service_running "vaultwarden"; then
        echo "⚠️  VaultWarden is currently running"
        echo "Some operations (like VACUUM) may cause temporary slowdowns"
        echo ""

        if ! dashboard_confirm "Continue with maintenance?" "Y"; then
            return 0
        fi
    fi

    # Run maintenance script
    if [[ -f "./sqlite-maintenance.sh" ]]; then
        echo "Executing: ./sqlite-maintenance.sh"
        echo ""

        if ./sqlite-maintenance.sh; then
            echo ""
            echo "✅ Automatic maintenance completed successfully"
        else
            echo ""
            echo "⚠️  Maintenance completed with some issues"
        fi
    else
        echo "❌ sqlite-maintenance.sh not found"
    fi

    echo ""
    dashboard_wait_input
}

# Execute intelligent maintenance
dashboard_maintenance_execute_intelligent() {
    echo "🚀 Executing intelligent maintenance operations..."

    if command -v sqlite_operations_run_intelligent >/dev/null 2>&1; then
        if sqlite_operations_run_intelligent false; then
            echo "✅ Maintenance operations completed successfully"
        else
            echo "⚠️  Some maintenance operations failed"
        fi
    else
        echo "❌ SQLite operations module not available"
    fi
}

# Manual operations menu
dashboard_maintenance_manual_operations() {
    while true; do
        dashboard_show_header_simple "Manual SQLite Operations"

        dashboard_show_menu "Individual Operations"             "1) 📊 ANALYZE (update statistics)"             "2) 🗜️ VACUUM (reclaim space)"             "3) 🔄 WAL Checkpoint (merge WAL)"             "4) ⚡ PRAGMA Optimize"             "5) 📈 Table Statistics"             "6) 🔍 Integrity Check"             "7) 📋 Create Backup"             "8) 🔙 Back to Maintenance Menu"

        read -p "Select operation (1-8): " choice

        case "$choice" in
            1) dashboard_maintenance_run_operation "analyze" ;;
            2) dashboard_maintenance_run_operation "vacuum" ;;
            3) dashboard_maintenance_run_operation "checkpoint" ;;
            4) dashboard_maintenance_run_operation "optimize" ;;
            5) dashboard_maintenance_run_operation "statistics" ;;
            6) dashboard_maintenance_integrity_check ;;
            7) dashboard_maintenance_create_backup ;;
            8) return 0 ;;
            *) 
                echo "Invalid choice. Press Enter to continue..."
                read
                ;;
        esac
    done
}

# Run individual maintenance operation
dashboard_maintenance_run_operation() {
    local operation="$1"

    echo "🔧 Running $operation operation..."
    echo ""

    if [[ -f "./sqlite-maintenance.sh" ]]; then
        if ./sqlite-maintenance.sh --operation "$operation"; then
            echo "✅ Operation completed successfully"
        else
            echo "❌ Operation failed"
        fi
    else
        echo "❌ sqlite-maintenance.sh not found"
    fi

    echo ""
    dashboard_wait_input
}

# Integrity check
dashboard_maintenance_integrity_check() {
    dashboard_show_header_simple "Database Integrity Check"

    echo "🔍 Running comprehensive integrity check..."
    echo ""

    if [[ -f "$SQLITE_DB_PATH" ]]; then
        echo "Database: $SQLITE_DB_PATH"

        local integrity_result
        integrity_result=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA integrity_check;" || echo "failed")

        if [[ "$integrity_result" == "ok" ]]; then
            echo "✅ Database integrity: PASSED"
        else
            echo "❌ Database integrity: FAILED"
            echo "Details: $integrity_result"
        fi

        # Additional checks
        echo ""
        echo "Additional Checks:"

        # Check database is not locked
        if sqlite3 "$SQLITE_DB_PATH" "BEGIN IMMEDIATE; ROLLBACK;" >/dev/null 2>&1; then
            echo "  ✅ Database is not locked"
        else
            echo "  ⚠️  Database may be locked"
        fi

        # Check WAL file consistency
        local wal_file="${SQLITE_DB_PATH}-wal"
        if [[ -f "$wal_file" ]]; then
            echo "  ℹ️  WAL file present (database active)"
        else
            echo "  ✅ No WAL file (database clean)"
        fi

    else
        echo "❌ Database file not found: $SQLITE_DB_PATH"
    fi

    echo ""
    dashboard_wait_input
}

# Create maintenance backup
dashboard_maintenance_create_backup() {
    dashboard_show_header_simple "Create Maintenance Backup"

    echo "💾 Creating SQLite database backup..."
    echo ""

    if [[ -f "$SQLITE_DB_PATH" ]]; then
        local backup_dir="./data/backups"
        local backup_name="manual-backup-$(date +%Y%m%d_%H%M%S).sql"
        local backup_file="$backup_dir/$backup_name"

        mkdir -p "$backup_dir"

        echo "Creating backup: $backup_file"

        if sqlite3 "$SQLITE_DB_PATH" ".dump" > "$backup_file"; then
            local backup_size
            backup_size=$(du -h "$backup_file" | cut -f1)
            echo "✅ Backup created successfully ($backup_size)"
            echo "Location: $backup_file"
        else
            echo "❌ Backup creation failed"
        fi
    else
        echo "❌ Database not found: $SQLITE_DB_PATH"
    fi

    echo ""
    dashboard_wait_input
}

# Schedule management menu
dashboard_maintenance_schedule_menu() {
    dashboard_show_header_simple "Maintenance Scheduling"

    # Check current schedule
    local current_schedule
    if command -v crontab >/dev/null 2>&1; then
        current_schedule=$(crontab -l | grep sqlite-maintenance || echo "No schedule found")
    else
        current_schedule="Cron not available"
    fi

    echo "📅 Current Schedule:"
    echo "  $current_schedule"
    echo ""

    dashboard_show_menu "Schedule Options"         "1) Install weekly schedule (recommended)"         "2) Install custom schedule"         "3) Remove current schedule"         "4) View schedule details"         "5) Return to maintenance menu"

    read -p "Select option (1-5): " choice

    case "$choice" in
        1)
            echo "Installing weekly schedule (Sunday 3 AM)..."
            if [[ -f "./sqlite-maintenance.sh" ]]; then
                ./sqlite-maintenance.sh --schedule "0 3 * * 0"
            fi
            ;;
        2)
            echo "Enter cron schedule (e.g., '0 3 * * 0' for weekly):"
            read -p "Schedule: " custom_schedule
            if [[ -n "$custom_schedule" && -f "./sqlite-maintenance.sh" ]]; then
                ./sqlite-maintenance.sh --schedule "$custom_schedule"
            fi
            ;;
        3)
            if dashboard_confirm "Remove current maintenance schedule?" "N"; then
                crontab -l | grep -v sqlite-maintenance | crontab -
                echo "Schedule removed"
            fi
            ;;
        4)
            if command -v crontab >/dev/null 2>&1; then
                echo "Full crontab:"
                crontab -l || echo "No crontab found"
            fi
            ;;
        5)
            return 0
            ;;
    esac

    echo ""
    dashboard_wait_input
}

# Database statistics display
dashboard_maintenance_database_stats() {
    dashboard_show_header_simple "Database Statistics"

    echo "📊 Comprehensive Database Statistics"
    echo ""

    if command -v sqlite_metrics_get_comprehensive >/dev/null 2>&1; then
        local metrics
        metrics=$(sqlite_metrics_get_comprehensive)

        if [[ "$metrics" =~ available=true ]]; then
            # Parse and display metrics
            local file_size_mb page_count table_count user_count fragmentation_ratio
            local freelist_count wal_size_mb journal_mode

            eval "$(echo "$metrics" | grep -E '^(file_size_mb|page_count|table_count|user_count|fragmentation_ratio|freelist_count|wal_size_mb|journal_mode)=')"

            echo "Database File:"
            printf "  Size: %s MB\n" "$file_size_mb"
            printf "  Pages: %s (page size: 4KB)\n" "$page_count"
            printf "  Free pages: %s\n" "$freelist_count"
            printf "  Fragmentation ratio: %s\n" "$fragmentation_ratio"

            echo ""
            echo "Schema:"
            printf "  Tables: %s\n" "$table_count"
            printf "  Users: %s\n" "$user_count"
            printf "  Journal mode: %s\n" "$journal_mode"

            echo ""
            echo "Activity:"
            printf "  WAL file size: %s MB\n" "$wal_size_mb"

            # Maintenance recommendation
            echo ""
            if dashboard_sqlite_check_maintenance_needed; then
                echo "🔧 Maintenance Status: Operations recommended"
            else
                echo "✅ Maintenance Status: Database is well-maintained"
            fi
        else
            echo "❌ Unable to retrieve database statistics"
        fi
    else
        echo "❌ SQLite metrics module not available"
    fi

    echo ""
    dashboard_wait_input
}

# Show maintenance history
dashboard_maintenance_history() {
    dashboard_show_header_simple "Maintenance History"

    echo "📋 Recent Maintenance Operations"
    echo ""

    local log_dir="./data/backup_logs"

    if [[ -d "$log_dir" ]]; then
        echo "Recent maintenance logs:"
        find "$log_dir" -name "sqlite-maintenance-*.log" -mtime -30 |         sort -r | head -10 | while IFS= read -r log_file; do
            if [[ -f "$log_file" ]]; then
                local log_age log_size
                log_age=$(stat -c %y "$log_file" | cut -d'.' -f1)
                log_size=$(du -h "$log_file" | cut -f1)
                echo "  📄 $(basename "$log_file") - $log_age ($log_size)"
            fi
        done

        echo ""
        read -p "View specific log file? (enter filename or press Enter to skip): " log_choice

        if [[ -n "$log_choice" && -f "$log_dir/$log_choice" ]]; then
            echo ""
            echo "📄 Contents of $log_choice:"
            echo "----------------------------------------"
            tail -50 "$log_dir/$log_choice"
            echo "----------------------------------------"
        fi
    else
        echo "No maintenance logs directory found"
    fi

    echo ""
    dashboard_wait_input
}

# Advanced operations menu
dashboard_maintenance_advanced_menu() {
    while true; do
        dashboard_show_header_simple "Advanced Maintenance Operations"

        echo "⚠️  WARNING: Advanced operations should be used with caution"
        echo ""

        dashboard_show_menu "Advanced Operations"             "1) 🔍 Deep Database Analysis"             "2) 📊 Performance Benchmark"             "3) 🧹 Force Complete Maintenance"             "4) 🗂️  Vacuum with Full Backup"             "5) ⚙️  Database Configuration Review"             "6) 📁 Export Database Schema"             "7) 🔙 Back to Maintenance Menu"

        read -p "Select operation (1-7): " choice

        case "$choice" in
            1) dashboard_maintenance_deep_analysis ;;
            2) dashboard_maintenance_performance_benchmark ;;
            3) dashboard_maintenance_force_complete ;;
            4) dashboard_maintenance_vacuum_with_backup ;;
            5) dashboard_maintenance_config_review ;;
            6) dashboard_maintenance_export_schema ;;
            7) return 0 ;;
            *) 
                echo "Invalid choice. Press Enter to continue..."
                read
                ;;
        esac
    done
}

# Deep database analysis
dashboard_maintenance_deep_analysis() {
    dashboard_show_header_simple "Deep Database Analysis"

    echo "🔬 Performing comprehensive database analysis..."
    echo ""

    if [[ -f "$SQLITE_DB_PATH" ]]; then
        # Table-by-table analysis
        echo "📊 Table Analysis:"
        sqlite3 "$SQLITE_DB_PATH" "
            SELECT 
                name,
                (SELECT COUNT(*) FROM " || name || ") as rows
            FROM sqlite_master 
            WHERE type='table' AND name NOT LIKE 'sqlite_%'
            ORDER BY rows DESC;
        " | while IFS='|' read -r table_name row_count; do
            printf "  Table: %-20s Rows: %s\n" "$table_name" "$row_count"
        done

        echo ""
        echo "📈 Index Analysis:"
        local index_count
        index_count=$(sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';" || echo "0")
        echo "  User indexes: $index_count"

        # Storage analysis
        echo ""
        echo "💾 Storage Analysis:"
        if sqlite3 "$SQLITE_DB_PATH" "PRAGMA freelist_count;" >/dev/null 2>&1; then
            local freelist_count page_count page_size
            freelist_count=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA freelist_count;")
            page_count=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA page_count;")
            page_size=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA page_size;")

            local used_space_mb free_space_mb
            if command -v bc >/dev/null 2>&1; then
                used_space_mb=$(echo "scale=2; ($page_count - $freelist_count) * $page_size / 1024 / 1024" | bc)
                free_space_mb=$(echo "scale=2; $freelist_count * $page_size / 1024 / 1024" | bc)
            else
                used_space_mb="N/A"
                free_space_mb="N/A"
            fi

            printf "  Used space: %s MB\n" "$used_space_mb"
            printf "  Free space: %s MB (%s pages)\n" "$free_space_mb" "$freelist_count"
        fi
    else
        echo "❌ Database not accessible for deep analysis"
    fi

    echo ""
    dashboard_wait_input
}

# Force complete maintenance
dashboard_maintenance_force_complete() {
    dashboard_show_header_simple "Force Complete Maintenance"

    echo "🔧 This will run ALL maintenance operations regardless of analysis"
    echo "⚠️  This may take significant time and resources"
    echo ""

    if ! dashboard_confirm "Are you sure you want to force complete maintenance?" "N"; then
        return 0
    fi

    echo "🚀 Running comprehensive maintenance..."

    if [[ -f "./sqlite-maintenance.sh" ]]; then
        ./sqlite-maintenance.sh --comprehensive
    else
        echo "❌ sqlite-maintenance.sh not found"
    fi

    echo ""
    dashboard_wait_input
}

# Performance benchmark
dashboard_maintenance_performance_benchmark() {
    dashboard_show_header_simple "SQLite Performance Benchmark"

    echo "⚡ Running SQLite performance benchmark..."
    echo ""

    if [[ -f "$SQLITE_DB_PATH" ]]; then
        # Simple query benchmark
        echo "Running query performance test..."

        local iterations=10
        local total_time=0

        for ((i=1; i<=iterations; i++)); do
            local start_time end_time
            start_time=$(date +%s%N || date +%s)
            sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1
            end_time=$(date +%s%N || date +%s)

            if command -v bc >/dev/null 2>&1; then
                local duration
                duration=$(echo "($end_time - $start_time) / 1000000" | bc || echo "1000")
                total_time=$(echo "$total_time + $duration" | bc)
            fi
        done

        if command -v bc >/dev/null 2>&1; then
            local avg_time
            avg_time=$(echo "scale=2; $total_time / $iterations" | bc)
            echo "Average query time: ${avg_time}ms ($iterations iterations)"

            if (( $(echo "$avg_time < 10" | bc -l) )); then
                echo "✅ Performance: Excellent"
            elif (( $(echo "$avg_time < 50" | bc -l) )); then
                echo "✅ Performance: Good" 
            else
                echo "⚠️  Performance: May need optimization"
            fi
        else
            echo "Performance test completed (detailed timing unavailable)"
        fi
    else
        echo "❌ Database not found for benchmark"
    fi

    echo ""
    dashboard_wait_input
}

# Configuration review
dashboard_maintenance_config_review() {
    dashboard_show_header_simple "Database Configuration Review"

    echo "⚙️  Current SQLite Configuration:"
    echo ""

    if [[ -f "$SQLITE_DB_PATH" ]]; then
        echo "PRAGMA Settings:"
        local pragmas=("journal_mode" "synchronous" "cache_size" "page_size" "auto_vacuum" "wal_autocheckpoint")

        for pragma in "${pragmas[@]}"; do
            local value
            value=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA $pragma;" || echo "unknown")
            printf "  %-18s: %s\n" "$pragma" "$value"
        done

        echo ""
        echo "Optimization Status:"

        # Check if statistics exist
        if sqlite3 "$SQLITE_DB_PATH" "SELECT name FROM sqlite_master WHERE name='sqlite_stat1';" | grep -q sqlite_stat1; then
            echo "  ✅ Query planner statistics: Present"
        else
            echo "  ⚠️  Query planner statistics: Missing"
        fi

        # Check database size vs page count efficiency
        local file_size page_count page_size
        file_size=$(stat -c%s "$SQLITE_DB_PATH" || echo "0")
        page_count=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA page_count;" || echo "0")
        page_size=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA page_size;" || echo "0")

        if [[ $page_count -gt 0 && $page_size -gt 0 ]]; then
            local expected_size efficiency
            expected_size=$((page_count * page_size))

            if command -v bc >/dev/null 2>&1; then
                efficiency=$(echo "scale=1; $expected_size * 100 / $file_size" | bc)
                echo "  Space efficiency: ${efficiency}%"
            fi
        fi
    else
        echo "❌ Database not accessible for configuration review"
    fi

    echo ""
    dashboard_wait_input
}

# Export schema
dashboard_maintenance_export_schema() {
    dashboard_show_header_simple "Export Database Schema"

    echo "📁 Exporting SQLite database schema..."
    echo ""

    if [[ -f "$SQLITE_DB_PATH" ]]; then
        local schema_dir="./data/exports"
        local schema_file="$schema_dir/schema-$(date +%Y%m%d_%H%M%S).sql"

        mkdir -p "$schema_dir"

        echo "Exporting schema to: $schema_file"

        if sqlite3 "$SQLITE_DB_PATH" ".schema" > "$schema_file"; then
            local schema_size
            schema_size=$(du -h "$schema_file" | cut -f1)
            echo "✅ Schema exported successfully ($schema_size)"
            echo ""
            echo "Schema includes:"
            echo "  • Table definitions"
            echo "  • Index definitions"  
            echo "  • Trigger definitions"
            echo "  • View definitions"
            echo ""
            echo "Location: $schema_file"
        else
            echo "❌ Schema export failed"
        fi
    else
        echo "❌ Database not found for schema export"
    fi

    echo ""
    dashboard_wait_input
}

# Export maintenance menu functions
export -f dashboard_maintenance_init
export -f dashboard_maintenance_show_menu
export -f dashboard_maintenance_show_current_status
export -f dashboard_maintenance_intelligent_analysis
export -f dashboard_maintenance_auto_maintenance
export -f dashboard_maintenance_manual_operations
export -f dashboard_maintenance_run_operation
export -f dashboard_maintenance_integrity_check
export -f dashboard_maintenance_create_backup
export -f dashboard_maintenance_schedule_menu
export -f dashboard_maintenance_database_stats
export -f dashboard_maintenance_history
export -f dashboard_maintenance_advanced_menu
