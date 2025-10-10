#!/usr/bin/env bash
# logger.sh -- Enhanced logging system with levels, rotation, and structured output
# Provides centralized logging for all VaultWarden-OCI-Slim components

# Logging configuration
declare -A LOGGER_CONFIG=(
    ["LOG_LEVEL"]="INFO"
    ["LOG_DIR"]="./logs"
    ["LOG_FILE"]="vaultwarden.log"
    ["MAX_LOG_SIZE_MB"]=10
    ["MAX_LOG_FILES"]=5
    ["ENABLE_ROTATION"]=true
    ["ENABLE_CONSOLE"]=true
    ["ENABLE_SYSLOG"]=false
    ["LOG_FORMAT"]="standard"
    ["TIMESTAMP_FORMAT"]="%Y-%m-%d %H:%M:%S"
    ["ENABLE_COLORS"]=true
)

# Log levels (numeric values for comparison)
declare -A LOG_LEVELS=(
    ["TRACE"]=0
    ["DEBUG"]=1
    ["INFO"]=2
    ["WARN"]=3
    ["ERROR"]=4
    ["FATAL"]=5
)

# Log level colors
declare -A LOG_COLORS=(
    ["TRACE"]="[0;37m"    # White
    ["DEBUG"]="[0;36m"    # Cyan
    ["INFO"]="[0;32m"     # Green
    ["WARN"]="[1;33m"     # Yellow
    ["ERROR"]="[0;31m"    # Red
    ["FATAL"]="[1;31m"    # Bold Red
    ["RESET"]="[0m"       # Reset
)

# Initialize logger
logger_init() {
    # Load configuration if available
    local config_file="${SCRIPT_DIR:-}/config/logging.conf"
    if [[ -f "$config_file" ]]; then
        logger_load_config "$config_file"
    fi

    # Create log directory
    mkdir -p "${LOGGER_CONFIG[LOG_DIR]}"

    # Validate log level
    if [[ -z "${LOG_LEVELS[${LOGGER_CONFIG[LOG_LEVEL]}]:-}" ]]; then
        LOGGER_CONFIG["LOG_LEVEL"]="INFO"
    fi

    # Disable colors if not in terminal
    if [[ ! -t 1 ]] || [[ "${TERM:-}" == "dumb" ]] || [[ "${NO_COLOR:-}" == "1" ]]; then
        LOGGER_CONFIG["ENABLE_COLORS"]=false
    fi

    # Set up log rotation if enabled
    if [[ "${LOGGER_CONFIG[ENABLE_ROTATION]}" == "true" ]]; then
        logger_setup_rotation
    fi
}

# Load logging configuration
logger_load_config() {
    local config_file="$1"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue

        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Update config if valid
        if [[ -n "${LOGGER_CONFIG[$key]:-}" ]]; then
            LOGGER_CONFIG["$key"]="$value"
        fi
    done < "$config_file"
}

# Set up log rotation
logger_setup_rotation() {
    local log_file="${LOGGER_CONFIG[LOG_DIR]}/${LOGGER_CONFIG[LOG_FILE]}"

    # Check if log file needs rotation
    if [[ -f "$log_file" ]]; then
        local file_size_mb
        file_size_mb=$(du -m "$log_file" | cut -f1)

        if [[ $file_size_mb -ge ${LOGGER_CONFIG[MAX_LOG_SIZE_MB]} ]]; then
            logger_rotate_logs
        fi
    fi
}

# Rotate log files
logger_rotate_logs() {
    local log_file="${LOGGER_CONFIG[LOG_DIR]}/${LOGGER_CONFIG[LOG_FILE]}"
    local max_files=${LOGGER_CONFIG[MAX_LOG_FILES]}

    # Remove oldest log file if it exists
    [[ -f "${log_file}.$max_files" ]] && rm -f "${log_file}.$max_files"

    # Rotate existing log files
    for ((i=max_files-1; i>=1; i--)); do
        [[ -f "${log_file}.$i" ]] && mv "${log_file}.$i" "${log_file}.$((i+1))"
    done

    # Move current log file
    [[ -f "$log_file" ]] && mv "$log_file" "${log_file}.1"

    # Compress old log files (keep most recent uncompressed)
    for ((i=2; i<=max_files; i++)); do
        if [[ -f "${log_file}.$i" ]] && [[ ! -f "${log_file}.$i.gz" ]]; then
            gzip "${log_file}.$i" || true
        fi
    done
}

# Check if log level should be processed
logger_should_log() {
    local level="$1"
    local current_level_num=${LOG_LEVELS[${LOGGER_CONFIG[LOG_LEVEL]}]}
    local message_level_num=${LOG_LEVELS[$level]}

    [[ $message_level_num -ge $current_level_num ]]
}

# Format log message
logger_format_message() {
    local level="$1"
    local component="$2"
    local message="$3"
    local format="${LOGGER_CONFIG[LOG_FORMAT]}"

    local timestamp
    timestamp=$(date +"${LOGGER_CONFIG[TIMESTAMP_FORMAT]}")

    case "$format" in
        "json")
            printf '{"timestamp":"%s","level":"%s","component":"%s","message":"%s","pid":%d}
'                 "$timestamp" "$level" "$component" "$message" "$$"
            ;;
        "structured")
            printf "[%s] [%s] [%s] [PID:%d] %s
"                 "$timestamp" "$level" "$component" "$$" "$message"
            ;;
        *)
            # Standard format
            printf "[%s] %-5s [%s] %s
" "$timestamp" "$level" "$component" "$message"
            ;;
    esac
}

# Core logging function
logger_log() {
    local level="$1"
    local component="$2"
    local message="$3"

    # Check if we should log this level
    if ! logger_should_log "$level"; then
        return 0
    fi

    # Check for log rotation
    if [[ "${LOGGER_CONFIG[ENABLE_ROTATION]}" == "true" ]]; then
        logger_setup_rotation
    fi

    # Format the message
    local formatted_message
    formatted_message=$(logger_format_message "$level" "$component" "$message")

    # Log to file
    local log_file="${LOGGER_CONFIG[LOG_DIR]}/${LOGGER_CONFIG[LOG_FILE]}"
    echo "$formatted_message" >> "$log_file"

    # Log to console if enabled
    if [[ "${LOGGER_CONFIG[ENABLE_CONSOLE]}" == "true" ]]; then
        if [[ "${LOGGER_CONFIG[ENABLE_COLORS]}" == "true" ]]; then
            local color="${LOG_COLORS[$level]:-}"
            local reset="${LOG_COLORS[RESET]}"
            echo -e "${color}${formatted_message}${reset}"
        else
            echo "$formatted_message"
        fi
    fi

    # Log to syslog if enabled
    if [[ "${LOGGER_CONFIG[ENABLE_SYSLOG]}" == "true" ]] && command -v logger >/dev/null 2>&1; then
        local syslog_priority
        case "$level" in
            "FATAL"|"ERROR") syslog_priority="err" ;;
            "WARN") syslog_priority="warning" ;;
            "INFO") syslog_priority="info" ;;
            "DEBUG"|"TRACE") syslog_priority="debug" ;;
            *) syslog_priority="info" ;;
        esac

        logger -p "local0.$syslog_priority" -t "vaultwarden[$component]" "$message"
    fi
}

# Convenience logging functions
logger_trace() {
    local component="${1:-main}"
    local message="$2"
    logger_log "TRACE" "$component" "$message"
}

logger_debug() {
    local component="${1:-main}"
    local message="$2"
    logger_log "DEBUG" "$component" "$message"
}

logger_info() {
    local component="${1:-main}"
    local message="$2"
    logger_log "INFO" "$component" "$message"
}

logger_warn() {
    local component="${1:-main}"
    local message="$2"
    logger_log "WARN" "$component" "$message"
}

logger_error() {
    local component="${1:-main}"
    local message="$2"
    logger_log "ERROR" "$component" "$message"
}

logger_fatal() {
    local component="${1:-main}"
    local message="$2"
    logger_log "FATAL" "$component" "$message"
}

# Log with context (key-value pairs)
logger_log_with_context() {
    local level="$1"
    local component="$2"
    local message="$3"
    shift 3
    local context=("$@")

    local context_str=""
    if [[ ${#context[@]} -gt 0 ]]; then
        local pairs=()
        for ((i=0; i<${#context[@]}; i+=2)); do
            if [[ $((i+1)) -lt ${#context[@]} ]]; then
                pairs+=("${context[$i]}=${context[$((i+1))]}")
            fi
        done
        context_str=" | $(IFS=', '; echo "${pairs[*]}")"
    fi

    logger_log "$level" "$component" "$message$context_str"
}

# Performance logging (with timing)
logger_perf() {
    local component="$1"
    local operation="$2"
    local start_time="$3"
    local end_time="${4:-$(date +%s%N)}"

    local duration_ms
    if command -v bc >/dev/null 2>&1; then
        duration_ms=$(echo "scale=3; ($end_time - $start_time) / 1000000" | bc)
    else
        duration_ms=$(( (end_time - start_time) / 1000000 ))
    fi

    logger_log_with_context "INFO" "$component" "Performance: $operation" "duration_ms" "$duration_ms"
}

# Security logging
logger_security() {
    local component="$1"
    local event="$2"
    local user="${3:-unknown}"
    local ip="${4:-unknown}"
    local details="$5"

    logger_log_with_context "WARN" "$component" "Security: $event"         "user" "$user" "ip" "$ip" "details" "$details"
}

# Audit logging
logger_audit() {
    local component="$1"
    local action="$2"
    local resource="$3"
    local user="${4:-system}"
    local result="${5:-success}"

    logger_log_with_context "INFO" "$component" "Audit: $action on $resource"         "user" "$user" "result" "$result"
}

# Get log statistics
logger_get_stats() {
    local log_file="${LOGGER_CONFIG[LOG_DIR]}/${LOGGER_CONFIG[LOG_FILE]}"

    if [[ ! -f "$log_file" ]]; then
        echo "log_exists=false"
        return 1
    fi

    local file_size_bytes file_size_mb line_count
    file_size_bytes=$(stat -c%s "$log_file" || echo "0")
    file_size_mb=$(( file_size_bytes / 1024 / 1024 ))
    line_count=$(wc -l < "$log_file" || echo "0")

    cat <<EOF
log_exists=true
log_file=$log_file
file_size_bytes=$file_size_bytes
file_size_mb=$file_size_mb
line_count=$line_count
current_level=${LOGGER_CONFIG[LOG_LEVEL]}
rotation_enabled=${LOGGER_CONFIG[ENABLE_ROTATION]}
max_size_mb=${LOGGER_CONFIG[MAX_LOG_SIZE_MB]}
EOF
}

# Set log level dynamically
logger_set_level() {
    local new_level="$1"

    if [[ -n "${LOG_LEVELS[$new_level]:-}" ]]; then
        LOGGER_CONFIG["LOG_LEVEL"]="$new_level"
        logger_info "logger" "Log level changed to $new_level"
        return 0
    else
        logger_error "logger" "Invalid log level: $new_level"
        return 1
    fi
}

# Tail log file
logger_tail() {
    local lines="${1:-50}"
    local log_file="${LOGGER_CONFIG[LOG_DIR]}/${LOGGER_CONFIG[LOG_FILE]}"

    if [[ -f "$log_file" ]]; then
        tail -n "$lines" "$log_file"
    else
        echo "Log file not found: $log_file" >&2
        return 1
    fi
}

# Search log file
logger_search() {
    local pattern="$1"
    local context_lines="${2:-0}"
    local log_file="${LOGGER_CONFIG[LOG_DIR]}/${LOGGER_CONFIG[LOG_FILE]}"

    if [[ -f "$log_file" ]]; then
        if [[ $context_lines -gt 0 ]]; then
            grep -C "$context_lines" "$pattern" "$log_file"
        else
            grep "$pattern" "$log_file"
        fi
    else
        echo "Log file not found: $log_file" >&2
        return 1
    fi
}

# Clear log file
logger_clear() {
    local log_file="${LOGGER_CONFIG[LOG_DIR]}/${LOGGER_CONFIG[LOG_FILE]}"

    if [[ -f "$log_file" ]]; then
        > "$log_file"
        logger_info "logger" "Log file cleared"
    fi
}

# Archive current log
logger_archive() {
    local archive_name="${1:-archive-$(date +%Y%m%d_%H%M%S)}"
    local log_file="${LOGGER_CONFIG[LOG_DIR]}/${LOGGER_CONFIG[LOG_FILE]}"
    local archive_file="${LOGGER_CONFIG[LOG_DIR]}/${archive_name}.log.gz"

    if [[ -f "$log_file" ]]; then
        gzip -c "$log_file" > "$archive_file"
        > "$log_file"  # Clear current log
        logger_info "logger" "Log archived to $archive_file"
        echo "$archive_file"
    else
        echo "No log file to archive" >&2
        return 1
    fi
}

# Export logger functions
export -f logger_init
export -f logger_trace
export -f logger_debug
export -f logger_info
export -f logger_warn
export -f logger_error
export -f logger_fatal
export -f logger_log_with_context
export -f logger_perf
export -f logger_security
export -f logger_audit
export -f logger_set_level
export -f logger_tail
export -f logger_search
export -f logger_clear
export -f logger_archive
export -f logger_get_stats
