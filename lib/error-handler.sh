#!/usr/bin/env bash
# error-handler.sh -- Standardized error handling and recovery framework
# Provides consistent error handling, logging, and recovery strategies

# Error handling configuration
declare -A ERROR_CONFIG=(
    ["ENABLE_STACK_TRACE"]=true
    ["ENABLE_AUTO_RECOVERY"]=true
    ["MAX_RETRY_ATTEMPTS"]=3
    ["RETRY_DELAY_SECONDS"]=2
    ["EXIT_ON_CRITICAL"]=true
    ["LOG_ERRORS"]=true
)

# Error categories and their default behaviors
declare -A ERROR_CATEGORIES=(
    ["VALIDATION"]="retry"
    ["NETWORK"]="retry"
    ["FILESYSTEM"]="retry"
    ["DATABASE"]="escalate"
    ["CONFIGURATION"]="abort"
    ["PERMISSION"]="escalate"
    ["SYSTEM"]="escalate"
    ["UNKNOWN"]="abort"
)

# Recovery strategies
declare -A RECOVERY_STRATEGIES=(
    ["retry"]="error_handler_retry_operation"
    ["escalate"]="error_handler_escalate_error"
    ["abort"]="error_handler_abort_with_cleanup"
    ["ignore"]="error_handler_log_and_continue"
    ["fallback"]="error_handler_use_fallback"
)

# Global error state
declare -g ERROR_HANDLER_LAST_ERROR=""
declare -g ERROR_HANDLER_ERROR_COUNT=0
declare -g ERROR_HANDLER_RECOVERY_ATTEMPTS=0

# Initialize error handler
error_handler_init() {
    # Load configuration if available
    local config_file="${SCRIPT_DIR:-}/config/error-recovery.conf"
    if [[ -f "$config_file" ]]; then
        error_handler_load_config "$config_file"
    fi

    # Set up trap for unhandled errors
    if [[ "${ERROR_CONFIG[ENABLE_STACK_TRACE]}" == "true" ]]; then
        set -E  # Enable ERR trap inheritance
        trap 'error_handler_unhandled_error $? $LINENO $BASH_LINENO "$BASH_COMMAND" "$FUNCNAME"' ERR
    fi

    # Set up cleanup trap
    trap 'error_handler_cleanup' EXIT INT TERM
}

# Load error handling configuration
error_handler_load_config() {
    local config_file="$1"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue

        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Update config if valid
        if [[ -n "${ERROR_CONFIG[$key]:-}" ]]; then
            ERROR_CONFIG["$key"]="$value"
        elif [[ -n "${ERROR_CATEGORIES[$key]:-}" ]]; then
            ERROR_CATEGORIES["$key"]="$value"
        fi
    done < "$config_file"
}

# Handle unhandled errors (trap function)
error_handler_unhandled_error() {
    local exit_code=$1
    local line_number=$2
    local bash_lineno=$3
    local command="$4"
    local function_stack="$5"

    ERROR_HANDLER_LAST_ERROR="Unhandled error in ${BASH_SOURCE[1]}:$line_number"
    ((ERROR_HANDLER_ERROR_COUNT++))

    if [[ "${ERROR_CONFIG[LOG_ERRORS]}" == "true" ]]; then
        error_handler_log_error "UNHANDLED" "$exit_code" "$ERROR_HANDLER_LAST_ERROR" "$command" "$function_stack"
    fi

    if [[ "${ERROR_CONFIG[ENABLE_STACK_TRACE]}" == "true" ]]; then
        error_handler_print_stack_trace "$bash_lineno" "$function_stack"
    fi

    # Don't exit immediately for trapped errors - let the calling code handle it
    return $exit_code
}

# Main error handling function
error_handler_handle() {
    local error_category="$1"
    local error_message="$2"
    local error_code="${3:-1}"
    local context="${4:-}"
    local operation="${5:-}"

    ERROR_HANDLER_LAST_ERROR="$error_message"
    ((ERROR_HANDLER_ERROR_COUNT++))

    # Log the error
    if [[ "${ERROR_CONFIG[LOG_ERRORS]}" == "true" ]]; then
        error_handler_log_error "$error_category" "$error_code" "$error_message" "$context" "$operation"
    fi

    # Get recovery strategy for this error category
    local strategy="${ERROR_CATEGORIES[$error_category]:-abort}"
    local recovery_function="${RECOVERY_STRATEGIES[$strategy]:-error_handler_abort_with_cleanup}"

    # Execute recovery strategy
    $recovery_function "$error_category" "$error_message" "$error_code" "$context" "$operation"
}

# Log error with structured format
error_handler_log_error() {
    local category="$1"
    local code="$2" 
    local message="$3"
    local context="$4"
    local operation="$5"

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_entry="[$timestamp] ERROR [$category:$code] $message"

    [[ -n "$context" ]] && log_entry+=" | Context: $context"
    [[ -n "$operation" ]] && log_entry+=" | Operation: $operation"

    # Use logger if available, otherwise use existing log functions
    if command -v logger_error >/dev/null 2>&1; then
        logger_error "$log_entry"
    elif command -v log_error >/dev/null 2>&1; then
        log_error "$log_entry"
    else
        echo "$log_entry" >&2
    fi
}

# Print stack trace
error_handler_print_stack_trace() {
    local bash_lineno="$1"
    local function_stack="$2"

    echo "Stack trace:" >&2

    local i=1
    while [[ $i -lt ${#BASH_SOURCE[@]} ]]; do
        local source_file="${BASH_SOURCE[$i]}"
        local line_num="${bash_lineno:-${BASH_LINENO[$((i-1))]}}"
        local function_name="${FUNCNAME[$i]:-main}"

        [[ "$source_file" != "$0" ]] && echo "  $i: $function_name() at $source_file:$line_num" >&2
        ((i++))
    done
}

# Recovery strategy: Retry operation
error_handler_retry_operation() {
    local category="$1"
    local message="$2"
    local code="$3"
    local context="$4"
    local operation="$5"

    ((ERROR_HANDLER_RECOVERY_ATTEMPTS++))

    if [[ $ERROR_HANDLER_RECOVERY_ATTEMPTS -le ${ERROR_CONFIG[MAX_RETRY_ATTEMPTS]} ]]; then
        echo "Retrying operation (attempt $ERROR_HANDLER_RECOVERY_ATTEMPTS/${ERROR_CONFIG[MAX_RETRY_ATTEMPTS]}): $operation" >&2
        sleep "${ERROR_CONFIG[RETRY_DELAY_SECONDS]}"
        return 0  # Allow retry
    else
        error_handler_escalate_error "$category" "$message" "$code" "$context" "$operation"
    fi
}

# Recovery strategy: Escalate error
error_handler_escalate_error() {
    local category="$1"
    local message="$2"
    local code="$3"
    local context="$4"
    local operation="$5"

    echo "ESCALATED ERROR [$category]: $message" >&2
    [[ -n "$context" ]] && echo "Context: $context" >&2

    # Try to send notification if available
    if command -v error_handler_send_notification >/dev/null 2>&1; then
        error_handler_send_notification "$category" "$message" "$context"
    fi

    if [[ "${ERROR_CONFIG[EXIT_ON_CRITICAL]}" == "true" ]]; then
        error_handler_abort_with_cleanup "$category" "$message" "$code" "$context" "$operation"
    fi

    return $code
}

# Recovery strategy: Abort with cleanup
error_handler_abort_with_cleanup() {
    local category="$1"
    local message="$2"
    local code="$3"
    local context="$4"
    local operation="$5"

    echo "FATAL ERROR [$category]: $message" >&2
    echo "Performing cleanup and exiting..." >&2

    # Perform cleanup
    error_handler_cleanup

    exit "${code:-1}"
}

# Recovery strategy: Log and continue
error_handler_log_and_continue() {
    local category="$1"
    local message="$2"
    local code="$3"
    local context="$4"
    local operation="$5"

    echo "WARNING [$category]: $message (continuing)" >&2
    return 0
}

# Recovery strategy: Use fallback
error_handler_use_fallback() {
    local category="$1"
    local message="$2"
    local code="$3"
    local context="$4"
    local operation="$5"

    echo "Using fallback for [$category]: $message" >&2

    # Look for fallback function
    local fallback_function="fallback_${operation}"
    if command -v "$fallback_function" >/dev/null 2>&1; then
        $fallback_function "$context"
    else
        echo "No fallback available for operation: $operation" >&2
        return $code
    fi
}

# Cleanup function
error_handler_cleanup() {
    # Reset error traps
    trap - ERR EXIT INT TERM

    # Call custom cleanup if available
    if command -v cleanup >/dev/null 2>&1; then
        cleanup
    fi

    # Clean up temporary files with error handler prefix
    if [[ -n "${TMPDIR:-}" ]]; then
        rm -f "${TMPDIR}/error_handler_"* 2>/dev/null || true
    fi
}

# Wrapper for safe command execution
error_handler_safe_execute() {
    local category="$1"
    local operation="$2"
    shift 2
    local command=("$@")

    local temp_file
    temp_file=$(mktemp "${TMPDIR:-/tmp}/error_handler_output.XXXXXX")

    # Reset recovery attempts for new operation
    ERROR_HANDLER_RECOVERY_ATTEMPTS=0

    while [[ $ERROR_HANDLER_RECOVERY_ATTEMPTS -le ${ERROR_CONFIG[MAX_RETRY_ATTEMPTS]} ]]; do
        if "${command[@]}" 2>"$temp_file"; then
            # Success
            rm -f "$temp_file"
            return 0
        else
            local exit_code=$?
            local error_output
            error_output=$(cat "$temp_file" 2>/dev/null || echo "No error output available")

            # Handle the error
            error_handler_handle "$category" "Command failed: ${command[*]}" "$exit_code" "$error_output" "$operation"

            # Check if we should retry (recovery function sets this)
            if [[ $? -eq 0 ]]; then
                continue  # Retry
            else
                rm -f "$temp_file"
                return $exit_code
            fi
        fi
    done

    rm -f "$temp_file"
    return 1
}

# Validate error category
error_handler_validate_category() {
    local category="$1"
    [[ -n "${ERROR_CATEGORIES[$category]:-}" ]]
}

# Get error statistics
error_handler_get_stats() {
    cat <<EOF
error_count=$ERROR_HANDLER_ERROR_COUNT
last_error=$ERROR_HANDLER_LAST_ERROR
recovery_attempts=$ERROR_HANDLER_RECOVERY_ATTEMPTS
timestamp=$(date +%s)
EOF
}

# Reset error statistics
error_handler_reset_stats() {
    ERROR_HANDLER_ERROR_COUNT=0
    ERROR_HANDLER_LAST_ERROR=""
    ERROR_HANDLER_RECOVERY_ATTEMPTS=0
}

# Send error notification (placeholder - implement as needed)
error_handler_send_notification() {
    local category="$1"
    local message="$2"
    local context="$3"

    # This would integrate with your notification system
    # For now, just log it
    echo "NOTIFICATION: [$category] $message" >&2
}

# Convenience functions for common error types
error_validation() { error_handler_handle "VALIDATION" "$1" "${2:-1}" "$3" "$4"; }
error_network() { error_handler_handle "NETWORK" "$1" "${2:-1}" "$3" "$4"; }
error_filesystem() { error_handler_handle "FILESYSTEM" "$1" "${2:-1}" "$3" "$4"; }
error_database() { error_handler_handle "DATABASE" "$1" "${2:-1}" "$3" "$4"; }
error_configuration() { error_handler_handle "CONFIGURATION" "$1" "${2:-1}" "$3" "$4"; }
error_permission() { error_handler_handle "PERMISSION" "$1" "${2:-1}" "$3" "$4"; }
error_system() { error_handler_handle "SYSTEM" "$1" "${2:-1}" "$3" "$4"; }

# Export error handler functions
export -f error_handler_init
export -f error_handler_handle
export -f error_handler_safe_execute
export -f error_handler_validate_category
export -f error_handler_get_stats
export -f error_handler_reset_stats
export -f error_validation
export -f error_network
export -f error_filesystem
export -f error_database
export -f error_configuration
export -f error_permission
export -f error_system
