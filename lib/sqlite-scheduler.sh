#!/usr/bin/env bash
# sqlite-scheduler.sh -- Cron scheduling and management for SQLite maintenance
# Handles automatic scheduling of maintenance operations with smart defaults

# Scheduler configuration
declare -A SCHEDULER_CONFIG=(
    ["DEFAULT_SCHEDULE"]="0 3 * * 0"  # Weekly Sunday 3 AM
    ["BACKUP_CRONTAB"]=true
    ["VALIDATE_SCHEDULE"]=true
    ["NOTIFY_ON_INSTALL"]=true
)

# Initialize scheduler
sqlite_scheduler_init() {
    # Load scheduler configuration if available
    local config_file="$SCRIPT_DIR/config/sqlite-scheduler.conf"
    if [[ -f "$config_file" ]]; then
        sqlite_scheduler_load_config "$config_file"
    fi

    # Verify cron is available
    if ! command -v crontab >/dev/null 2>&1; then
        log_error "Crontab command not available - scheduling disabled"
        return 1
    fi
}

# Load scheduler configuration
sqlite_scheduler_load_config() {
    local config_file="$1"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue

        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Update config if valid
        if [[ -n "${SCHEDULER_CONFIG[$key]:-}" ]]; then
            SCHEDULER_CONFIG["$key"]="$value"
        fi
    done < "$config_file"
}

# Install maintenance schedule
sqlite_scheduler_install() {
    local schedule="${1:-${SCHEDULER_CONFIG[DEFAULT_SCHEDULE]}}"
    local script_path
    script_path="$(cd "${SCRIPT_DIR}/.." && pwd)/sqlite-maintenance.sh"

    log_step "📅 Installing SQLite maintenance schedule"

    # Validate schedule format
    if [[ "${SCHEDULER_CONFIG[VALIDATE_SCHEDULE]}" == "true" ]]; then
        if ! sqlite_scheduler_validate_cron_expression "$schedule"; then
            log_error "Invalid cron schedule format: $schedule"
            return 1
        fi
    fi

    # Validate script exists
    if [[ ! -f "$script_path" ]]; then
        log_error "SQLite maintenance script not found: $script_path"
        return 1
    fi

    # Make script executable
    chmod +x "$script_path"

    # Backup existing crontab if requested
    if [[ "${SCHEDULER_CONFIG[BACKUP_CRONTAB]}" == "true" ]]; then
        sqlite_scheduler_backup_crontab
    fi

    # Get current crontab (excluding existing maintenance entries)
    local temp_crontab
    temp_crontab=$(mktemp)

    if crontab -l | grep -v "sqlite-maintenance" > "$temp_crontab"; then
        log_info "Preserved existing crontab entries"
    fi

    # Add new maintenance entry
    echo "$schedule $script_path --cron # VaultWarden SQLite Maintenance" >> "$temp_crontab"

    # Install new crontab
    if crontab "$temp_crontab"; then
        log_success "SQLite maintenance scheduled: $schedule"
        log_info "Command: $script_path --cron"

        # Show next run time
        sqlite_scheduler_show_next_run "$schedule"

        # Send notification if enabled
        if [[ "${SCHEDULER_CONFIG[NOTIFY_ON_INSTALL]}" == "true" ]]; then
            sqlite_scheduler_send_install_notification "$schedule"
        fi
    else
        log_error "Failed to install crontab schedule"
        rm -f "$temp_crontab"
        return 1
    fi

    rm -f "$temp_crontab"
    return 0
}

# Remove maintenance schedule
sqlite_scheduler_remove() {
    log_step "🗑️ Removing SQLite maintenance schedule"

    # Backup existing crontab if requested
    if [[ "${SCHEDULER_CONFIG[BACKUP_CRONTAB]}" == "true" ]]; then
        sqlite_scheduler_backup_crontab
    fi

    # Remove maintenance entries from crontab
    local temp_crontab
    temp_crontab=$(mktemp)

    if crontab -l | grep -v "sqlite-maintenance" > "$temp_crontab"; then
        if crontab "$temp_crontab"; then
            log_success "SQLite maintenance schedule removed"
        else
            log_error "Failed to update crontab"
            rm -f "$temp_crontab"
            return 1
        fi
    else
        # No other entries, clear crontab
        crontab -r || log_info "No existing crontab to remove"
        log_success "SQLite maintenance schedule removed (crontab cleared)"
    fi

    rm -f "$temp_crontab"
    return 0
}

# Show current schedule
sqlite_scheduler_show_current() {
    log_info "📅 Current SQLite maintenance schedule:"

    local maintenance_entries
    maintenance_entries=$(crontab -l | grep "sqlite-maintenance" || echo "")

    if [[ -n "$maintenance_entries" ]]; then
        echo "$maintenance_entries" | while IFS= read -r entry; do
            local schedule_part command_part
            schedule_part=$(echo "$entry" | cut -d' ' -f1-5)
            command_part=$(echo "$entry" | cut -d' ' -f6-)

            echo "  Schedule: $schedule_part"
            echo "  Command:  $command_part"
            echo ""

            # Show next run time
            sqlite_scheduler_show_next_run "$schedule_part"
        done
    else
        log_info "  No maintenance schedule installed"
    fi
}

# Validate cron expression format
sqlite_scheduler_validate_cron_expression() {
    local cron_expr="$1"

    # Basic validation - should have 5 fields (minute hour day month weekday)
    local field_count
    field_count=$(echo "$cron_expr" | wc -w)

    if [[ $field_count -ne 5 ]]; then
        log_error "Cron expression must have exactly 5 fields, got $field_count"
        return 1
    fi

    # Parse fields
    local minute hour day month weekday
    read -r minute hour day month weekday <<< "$cron_expr"

    # Basic range validation
    if ! sqlite_scheduler_validate_cron_field "$minute" "0" "59" "minute"; then
        return 1
    fi

    if ! sqlite_scheduler_validate_cron_field "$hour" "0" "23" "hour"; then
        return 1
    fi

    if ! sqlite_scheduler_validate_cron_field "$day" "1" "31" "day"; then
        return 1
    fi

    if ! sqlite_scheduler_validate_cron_field "$month" "1" "12" "month"; then
        return 1
    fi

    if ! sqlite_scheduler_validate_cron_field "$weekday" "0" "7" "weekday"; then
        return 1
    fi

    return 0
}

# Validate individual cron field
sqlite_scheduler_validate_cron_field() {
    local field="$1"
    local min_val="$2"  
    local max_val="$3"
    local field_name="$4"

    # Allow special characters
    if [[ "$field" == "*" ]] || [[ "$field" == "?" ]]; then
        return 0
    fi

    # Allow ranges (e.g., 1-5)
    if [[ "$field" =~ ^[0-9]+-[0-9]+$ ]]; then
        local start_val end_val
        start_val=$(echo "$field" | cut -d'-' -f1)
        end_val=$(echo "$field" | cut -d'-' -f2)

        if [[ $start_val -ge $min_val && $end_val -le $max_val && $start_val -le $end_val ]]; then
            return 0
        fi
    fi

    # Allow step values (e.g., */5)
    if [[ "$field" =~ ^\*/[0-9]+$ ]]; then
        return 0
    fi

    # Allow lists (e.g., 1,3,5)
    if [[ "$field" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
        local IFS=','
        local values=($field)
        for value in "${values[@]}"; do
            if [[ $value -lt $min_val || $value -gt $max_val ]]; then
                log_error "Invalid $field_name value: $value (range: $min_val-$max_val)"
                return 1
            fi
        done
        return 0
    fi

    # Single numeric value
    if [[ "$field" =~ ^[0-9]+$ ]]; then
        if [[ $field -ge $min_val && $field -le $max_val ]]; then
            return 0
        fi
    fi

    log_error "Invalid $field_name format: $field"
    return 1
}

# Calculate and show next run time
sqlite_scheduler_show_next_run() {
    local schedule="$1"

    # This is a simplified version - for production, you might want to use a more
    # sophisticated cron parser or external tool

    log_info "Next scheduled run:"

    # Parse schedule components
    local minute hour day month weekday
    read -r minute hour day month weekday <<< "$schedule"

    # Simple next run calculation for common patterns
    case "$schedule" in
        "0 3 * * 0")  # Weekly Sunday 3 AM
            echo "  Every Sunday at 3:00 AM"
            ;;
        "0 3 * * *")  # Daily 3 AM
            echo "  Every day at 3:00 AM"
            ;;
        "0 */6 * * *")  # Every 6 hours
            echo "  Every 6 hours"
            ;;
        *)
            echo "  Schedule: $schedule"
            echo "  (Use 'man 5 crontab' for schedule format details)"
            ;;
    esac
}

# Backup current crontab
sqlite_scheduler_backup_crontab() {
    local backup_dir="./data/backup_logs"
    local backup_file="$backup_dir/crontab-backup-$(date +%Y%m%d_%H%M%S).txt"

    mkdir -p "$backup_dir"

    if crontab -l > "$backup_file"; then
        log_info "Crontab backed up to: $backup_file"
    else
        log_debug "No existing crontab to backup"
    fi
}

# Test schedule (dry run)
sqlite_scheduler_test_schedule() {
    local schedule="${1:-${SCHEDULER_CONFIG[DEFAULT_SCHEDULE]}}"

    log_step "🧪 Testing maintenance schedule"

    echo "Schedule: $schedule"
    echo "Command: sqlite-maintenance.sh --cron"
    echo ""

    # Validate schedule
    if sqlite_scheduler_validate_cron_expression "$schedule"; then
        echo "✅ Schedule format is valid"
    else
        echo "❌ Schedule format is invalid"
        return 1
    fi

    # Test command availability
    local script_path
    script_path="$(cd "${SCRIPT_DIR}/.." && pwd)/sqlite-maintenance.sh"

    if [[ -f "$script_path" && -x "$script_path" ]]; then
        echo "✅ Maintenance script is executable"
    else
        echo "❌ Maintenance script not found or not executable: $script_path"
        return 1
    fi

    # Test database accessibility
    if [[ -f "$SQLITE_DB_PATH" ]]; then
        if sqlite3 "$SQLITE_DB_PATH" "SELECT 1;" >/dev/null 2>&1; then
            echo "✅ Database is accessible"
        else
            echo "⚠️  Database is not currently accessible"
        fi
    else
        echo "ℹ️  Database not yet created (will be available after VaultWarden starts)"
    fi

    echo ""
    echo "🎯 Recommended schedule for production:"
    echo "  $schedule (${SCHEDULER_CONFIG[DEFAULT_SCHEDULE]} = Weekly Sunday 3 AM)"
    echo ""

    return 0
}

# List common schedule templates
sqlite_scheduler_list_templates() {
    echo "📅 Common Schedule Templates:"
    echo ""
    echo "Weekly (Recommended):"
    echo "  0 3 * * 0        # Every Sunday at 3:00 AM"
    echo "  0 2 * * 6        # Every Saturday at 2:00 AM"
    echo ""
    echo "Daily:"
    echo "  0 3 * * *        # Every day at 3:00 AM"
    echo "  30 2 * * *       # Every day at 2:30 AM"
    echo ""
    echo "Multiple times per week:"
    echo "  0 3 * * 0,3      # Sunday and Wednesday at 3:00 AM"
    echo "  0 3 * * 1,4      # Monday and Thursday at 3:00 AM"
    echo ""
    echo "Monthly:"
    echo "  0 3 1 * *        # First day of month at 3:00 AM"
    echo "  0 3 15 * *       # 15th of month at 3:00 AM"
    echo ""
    echo "Format: minute hour day month weekday"
    echo "        (0-59) (0-23) (1-31) (1-12) (0-7, 0=Sunday)"
}

# Get schedule status
sqlite_scheduler_get_status() {
    if ! command -v crontab >/dev/null 2>&1; then
        echo "cron_available=false"
        return 1
    fi

    local maintenance_entries entry_count next_run schedule_active
    maintenance_entries=$(crontab -l | grep "sqlite-maintenance" || echo "")
    entry_count=$(echo "$maintenance_entries" | grep -c "sqlite-maintenance" || echo "0")

    if [[ $entry_count -gt 0 ]]; then
        schedule_active="true"

        # Extract schedule from first entry
        local first_schedule
        first_schedule=$(echo "$maintenance_entries" | head -1 | cut -d' ' -f1-5)

        # Simple next run calculation (approximation)
        case "$first_schedule" in
            "0 3 * * 0")
                next_run="Next Sunday 3:00 AM"
                ;;
            "0 3 * * *")
                next_run="Tomorrow 3:00 AM"
                ;;
            *)
                next_run="See crontab for details"
                ;;
        esac
    else
        schedule_active="false"
        next_run="Not scheduled"
    fi

    cat <<EOF
cron_available=true
schedule_active=$schedule_active
entry_count=$entry_count
next_run=$next_run
default_schedule=${SCHEDULER_CONFIG[DEFAULT_SCHEDULE]}
EOF
}

# Show schedule information
sqlite_scheduler_show_info() {
    local status
    status=$(sqlite_scheduler_get_status)

    if [[ ! "$status" =~ cron_available=true ]]; then
        echo "❌ Cron scheduling not available on this system"
        return 1
    fi

    local schedule_active entry_count next_run
    eval "$(echo "$status" | grep -E '^(schedule_active|entry_count|next_run)=')"

    echo "📅 SQLite Maintenance Schedule Status:"

    case "$schedule_active" in
        "true")
            echo "  Status: ✅ Active ($entry_count entries)"
            echo "  Next run: $next_run"
            ;;
        "false")
            echo "  Status: ❌ Not scheduled"
            echo "  Recommendation: Install automatic maintenance"
            ;;
    esac

    echo ""
}

# Install with interactive prompts
sqlite_scheduler_interactive_install() {
    echo "📅 Interactive Schedule Installation"
    echo ""

    sqlite_scheduler_list_templates
    echo ""

    local schedule
    read -p "Enter schedule (or press Enter for weekly default): " schedule

    if [[ -z "$schedule" ]]; then
        schedule="${SCHEDULER_CONFIG[DEFAULT_SCHEDULE]}"
        echo "Using default: $schedule"
    fi

    echo ""
    echo "Schedule: $schedule"
    echo "Command: sqlite-maintenance.sh --cron"
    echo ""

    if dashboard_confirm "Install this maintenance schedule?" "Y"; then
        sqlite_scheduler_install "$schedule"
    else
        echo "Schedule installation cancelled"
    fi
}

# Send installation notification
sqlite_scheduler_send_install_notification() {
    local schedule="$1"

    # This would integrate with notification system
    # For now, just log it
    if command -v logger_info >/dev/null 2>&1; then
        logger_info "scheduler" "SQLite maintenance scheduled: $schedule"
    else
        log_info "SQLite maintenance scheduled: $schedule"
    fi
}

# Backup current crontab with timestamp
sqlite_scheduler_backup_crontab() {
    local backup_dir="./data/backup_logs"
    local backup_file="$backup_dir/crontab-backup-$(date +%Y%m%d_%H%M%S).txt"

    mkdir -p "$backup_dir"

    if crontab -l > "$backup_file"; then
        log_info "Crontab backed up to: $backup_file"
        return 0
    else
        log_debug "No existing crontab to backup"
        return 1
    fi
}

# Show maintenance schedule history
sqlite_scheduler_show_history() {
    echo "📋 Maintenance Schedule History:"
    echo ""

    local backup_dir="./data/backup_logs"

    if [[ -d "$backup_dir" ]]; then
        local crontab_backups
        crontab_backups=$(find "$backup_dir" -name "crontab-backup-*.txt" -mtime -30 | sort -r | head -5)

        if [[ -n "$crontab_backups" ]]; then
            echo "Recent crontab backups:"
            echo "$crontab_backups" | while IFS= read -r backup_file; do
                local backup_date backup_size
                backup_date=$(stat -c %y "$backup_file" | cut -d'.' -f1)
                backup_size=$(du -h "$backup_file" | cut -f1)
                echo "  📄 $(basename "$backup_file") - $backup_date ($backup_size)"
            done
        else
            echo "No recent crontab backups found"
        fi
    fi

    echo ""

    # Show maintenance execution history from logs
    if [[ -d "$backup_dir" ]]; then
        local maintenance_logs
        maintenance_logs=$(find "$backup_dir" -name "sqlite-maintenance-*.log" -mtime -7 | sort -r | head -5)

        if [[ -n "$maintenance_logs" ]]; then
            echo "Recent maintenance executions:"
            echo "$maintenance_logs" | while IFS= read -r log_file; do
                local log_date log_size
                log_date=$(stat -c %y "$log_file" | cut -d'.' -f1)
                log_size=$(du -h "$log_file" | cut -f1)
                echo "  📋 $(basename "$log_file") - $log_date ($log_size)"
            done
        else
            echo "No recent maintenance logs found"
        fi
    fi
}

# Update existing schedule
sqlite_scheduler_update() {
    local new_schedule="$1"

    log_step "🔄 Updating SQLite maintenance schedule"

    # Remove existing schedule
    if sqlite_scheduler_remove; then
        # Install new schedule
        sqlite_scheduler_install "$new_schedule"
    else
        log_error "Failed to remove existing schedule"
        return 1
    fi
}

# Export scheduler functions
export -f sqlite_scheduler_init
export -f sqlite_scheduler_install
export -f sqlite_scheduler_remove
export -f sqlite_scheduler_show_current
export -f sqlite_scheduler_show_info
export -f sqlite_scheduler_interactive_install
export -f sqlite_scheduler_test_schedule
export -f sqlite_scheduler_list_templates
export -f sqlite_scheduler_show_history
export -f sqlite_scheduler_update
export -f sqlite_scheduler_get_status
