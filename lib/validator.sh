#!/usr/bin/env bash
# validator.sh -- Configuration and input validation framework
# Provides comprehensive validation for configuration files, user inputs, and system requirements

# Validation configuration
declare -A VALIDATOR_CONFIG=(
    ["STRICT_MODE"]=false
    ["ENABLE_AUTO_FIX"]=false
    ["LOG_VALIDATION_ERRORS"]=true
    ["VALIDATION_TIMEOUT"]=30
)

# Validation rules storage
declare -A VALIDATION_RULES=()
declare -a VALIDATION_ERRORS=()
declare -a VALIDATION_WARNINGS=()
declare -g VALIDATION_CONTEXT=""

# Initialize validator
validator_init() {
    # Load validation rules if available
    local rules_file="${SCRIPT_DIR:-}/config/validation-rules.conf"
    if [[ -f "$rules_file" ]]; then
        validator_load_rules "$rules_file"
    fi

    # Load validator configuration
    local config_file="${SCRIPT_DIR:-}/config/validator.conf"
    if [[ -f "$config_file" ]]; then
        validator_load_config "$config_file"
    fi
}

# Load validation configuration
validator_load_config() {
    local config_file="$1"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue

        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Update config if valid
        if [[ -n "${VALIDATOR_CONFIG[$key]:-}" ]]; then
            VALIDATOR_CONFIG["$key"]="$value"
        fi
    done < "$config_file"
}

# Load validation rules
validator_load_rules() {
    local rules_file="$1"

    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue

        # Remove leading/trailing whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        VALIDATION_RULES["$key"]="$value"
    done < "$rules_file"
}

# Set validation context
validator_set_context() {
    VALIDATION_CONTEXT="$1"
}

# Add validation error
validator_add_error() {
    local error="$1"
    local context="${VALIDATION_CONTEXT:+[$VALIDATION_CONTEXT] }$error"

    VALIDATION_ERRORS+=("$context")

    if [[ "${VALIDATOR_CONFIG[LOG_VALIDATION_ERRORS]}" == "true" ]]; then
        if command -v logger_error >/dev/null 2>&1; then
            logger_error "validator" "$context"
        else
            echo "VALIDATION ERROR: $context" >&2
        fi
    fi
}

# Add validation warning
validator_add_warning() {
    local warning="$1"
    local context="${VALIDATION_CONTEXT:+[$VALIDATION_CONTEXT] }$warning"

    VALIDATION_WARNINGS+=("$context")

    if [[ "${VALIDATOR_CONFIG[LOG_VALIDATION_ERRORS]}" == "true" ]]; then
        if command -v logger_warn >/dev/null 2>&1; then
            logger_warn "validator" "$context"
        else
            echo "VALIDATION WARNING: $context" >&2
        fi
    fi
}

# Clear validation results
validator_clear_results() {
    VALIDATION_ERRORS=()
    VALIDATION_WARNINGS=()
}

# Basic type validation functions
validator_is_integer() {
    local value="$1"
    [[ "$value" =~ ^-?[0-9]+$ ]]
}

validator_is_positive_integer() {
    local value="$1"
    [[ "$value" =~ ^[1-9][0-9]*$ ]]
}

validator_is_float() {
    local value="$1"
    [[ "$value" =~ ^-?[0-9]+(\.[0-9]+)?$ ]]
}

validator_is_boolean() {
    local value="$1"
    [[ "$value" =~ ^(true|false|yes|no|1|0)$ ]]
}

validator_is_email() {
    local value="$1"
    [[ "$value" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]
}

validator_is_ip_address() {
    local value="$1"
    local IFS='.'
    local parts=($value)

    [[ ${#parts[@]} -eq 4 ]] || return 1

    for part in "${parts[@]}"; do
        [[ "$part" =~ ^[0-9]+$ ]] || return 1
        [[ $part -ge 0 && $part -le 255 ]] || return 1
    done

    return 0
}

validator_is_port() {
    local value="$1"
    validator_is_positive_integer "$value" && [[ $value -ge 1 && $value -le 65535 ]]
}

validator_is_url() {
    local value="$1"
    [[ "$value" =~ ^https?://[a-zA-Z0-9.-]+(/.*)?$ ]]
}

validator_is_domain() {
    local value="$1"
    [[ "$value" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]
}

validator_is_path() {
    local value="$1"
    local type="${2:-any}"  # any, file, directory, executable

    case "$type" in
        "file")
            [[ -f "$value" ]]
            ;;
        "directory")
            [[ -d "$value" ]]
            ;;
        "executable")
            [[ -x "$value" ]]
            ;;
        *)
            [[ -e "$value" ]]
            ;;
    esac
}

# Range validation
validator_in_range() {
    local value="$1"
    local min="$2"
    local max="$3"

    if ! validator_is_float "$value"; then
        return 1
    fi

    if command -v bc >/dev/null 2>&1; then
        (( $(echo "$value >= $min && $value <= $max" | bc -l) ))
    else
        # Fallback for integer comparison
        local value_int min_int max_int
        value_int=${value%.*}
        min_int=${min%.*}
        max_int=${max%.*}
        [[ $value_int -ge $min_int && $value_int -le $max_int ]]
    fi
}

# String length validation
validator_length_check() {
    local value="$1"
    local min_length="${2:-0}"
    local max_length="${3:-999999}"

    local length=${#value}
    [[ $length -ge $min_length && $length -le $max_length ]]
}

# Pattern matching validation
validator_matches_pattern() {
    local value="$1"
    local pattern="$2"

    [[ "$value" =~ $pattern ]]
}

# Custom validation function executor
validator_run_custom() {
    local function_name="$1"
    local value="$2"
    shift 2
    local args=("$@")

    if command -v "$function_name" >/dev/null 2>&1; then
        "$function_name" "$value" "${args[@]}"
    else
        validator_add_error "Custom validation function not found: $function_name"
        return 1
    fi
}

# Validate single value with multiple rules
validator_validate_value() {
    local field_name="$1"
    local value="$2"
    local rules="$3"
    local required="${4:-false}"

    # Check if value is empty and required
    if [[ -z "$value" ]]; then
        if [[ "$required" == "true" ]]; then
            validator_add_error "Field '$field_name' is required but empty"
            return 1
        else
            return 0  # Optional field, empty is OK
        fi
    fi

    # Split rules by comma and validate each
    local IFS=','
    local rule_list=($rules)
    local validation_passed=true

    for rule in "${rule_list[@]}"; do
        rule=$(echo "$rule" | xargs)  # Trim whitespace

        case "$rule" in
            "integer")
                if ! validator_is_integer "$value"; then
                    validator_add_error "Field '$field_name' must be an integer, got: $value"
                    validation_passed=false
                fi
                ;;
            "positive_integer")
                if ! validator_is_positive_integer "$value"; then
                    validator_add_error "Field '$field_name' must be a positive integer, got: $value"
                    validation_passed=false
                fi
                ;;
            "float")
                if ! validator_is_float "$value"; then
                    validator_add_error "Field '$field_name' must be a number, got: $value"
                    validation_passed=false
                fi
                ;;
            "boolean")
                if ! validator_is_boolean "$value"; then
                    validator_add_error "Field '$field_name' must be a boolean (true/false), got: $value"
                    validation_passed=false
                fi
                ;;
            "email")
                if ! validator_is_email "$value"; then
                    validator_add_error "Field '$field_name' must be a valid email address, got: $value"
                    validation_passed=false
                fi
                ;;
            "ip")
                if ! validator_is_ip_address "$value"; then
                    validator_add_error "Field '$field_name' must be a valid IP address, got: $value"
                    validation_passed=false
                fi
                ;;
            "port")
                if ! validator_is_port "$value"; then
                    validator_add_error "Field '$field_name' must be a valid port (1-65535), got: $value"
                    validation_passed=false
                fi
                ;;
            "url")
                if ! validator_is_url "$value"; then
                    validator_add_error "Field '$field_name' must be a valid URL, got: $value"
                    validation_passed=false
                fi
                ;;
            "domain")
                if ! validator_is_domain "$value"; then
                    validator_add_error "Field '$field_name' must be a valid domain name, got: $value"
                    validation_passed=false
                fi
                ;;
            "file")
                if ! validator_is_path "$value" "file"; then
                    validator_add_error "Field '$field_name' must be an existing file, got: $value"
                    validation_passed=false
                fi
                ;;
            "directory")
                if ! validator_is_path "$value" "directory"; then
                    validator_add_error "Field '$field_name' must be an existing directory, got: $value"
                    validation_passed=false
                fi
                ;;
            range:*)
                local range_spec="${rule#range:}"
                local IFS='-'
                local range_parts=($range_spec)
                if [[ ${#range_parts[@]} -eq 2 ]]; then
                    if ! validator_in_range "$value" "${range_parts[0]}" "${range_parts[1]}"; then
                        validator_add_error "Field '$field_name' must be between ${range_parts[0]} and ${range_parts[1]}, got: $value"
                        validation_passed=false
                    fi
                fi
                ;;
            length:*)
                local length_spec="${rule#length:}"
                local IFS='-'
                local length_parts=($length_spec)
                if [[ ${#length_parts[@]} -eq 2 ]]; then
                    if ! validator_length_check "$value" "${length_parts[0]}" "${length_parts[1]}"; then
                        validator_add_error "Field '$field_name' length must be between ${length_parts[0]} and ${length_parts[1]} characters, got: ${#value}"
                        validation_passed=false
                    fi
                fi
                ;;
            pattern:*)
                local pattern="${rule#pattern:}"
                if ! validator_matches_pattern "$value" "$pattern"; then
                    validator_add_error "Field '$field_name' does not match required pattern: $pattern"
                    validation_passed=false
                fi
                ;;
            custom:*)
                local custom_func="${rule#custom:}"
                if ! validator_run_custom "$custom_func" "$value"; then
                    validation_passed=false
                fi
                ;;
            *)
                validator_add_warning "Unknown validation rule: $rule"
                ;;
        esac
    done

    [[ "$validation_passed" == "true" ]]
}

# Validate configuration file
validator_validate_config() {
    local config_file="$1"
    local schema_file="${2:-}"

    validator_set_context "config:$(basename "$config_file")"

    if [[ ! -f "$config_file" ]]; then
        validator_add_error "Configuration file not found: $config_file"
        return 1
    fi

    # If schema file provided, validate against it
    if [[ -n "$schema_file" && -f "$schema_file" ]]; then
        validator_validate_against_schema "$config_file" "$schema_file"
    else
        # Basic configuration file validation
        validator_validate_basic_config "$config_file"
    fi

    validator_set_context ""
}

# Basic configuration validation (syntax check)
validator_validate_basic_config() {
    local config_file="$1"
    local line_number=0

    while IFS= read -r line; do
        ((line_number++))

        # Skip empty lines and comments
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # Check for proper key=value format
        if [[ ! "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*=[[:space:]]*.* ]]; then
            validator_add_error "Invalid configuration syntax at line $line_number: $line"
        fi
    done < "$config_file"
}

# Validate against schema file
validator_validate_against_schema() {
    local config_file="$1"
    local schema_file="$2"

    # Load schema rules
    local -A schema_rules=()
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        schema_rules["$key"]="$value"
    done < "$schema_file"

    # Load and validate configuration values
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] || [[ -z "$key" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        if [[ -n "${schema_rules[$key]:-}" ]]; then
            local rule_spec="${schema_rules[$key]}"
            local IFS=':'
            local rule_parts=($rule_spec)
            local rules="${rule_parts[0]}"
            local required="${rule_parts[1]:-false}"

            validator_validate_value "$key" "$value" "$rules" "$required"
        else
            validator_add_warning "Unknown configuration key: $key"
        fi
    done < "$config_file"

    # Check for missing required fields
    for key in "${!schema_rules[@]}"; do
        local rule_spec="${schema_rules[$key]}"
        local IFS=':'
        local rule_parts=($rule_spec)
        local required="${rule_parts[1]:-false}"

        if [[ "$required" == "true" ]]; then
            if ! grep -q "^[[:space:]]*$key[[:space:]]*=" "$config_file"; then
                validator_add_error "Required configuration key missing: $key"
            fi
        fi
    done
}

# System requirements validation
validator_validate_system_requirements() {
    validator_set_context "system"

    # Check required commands
    local required_commands=("docker" "docker-compose" "sqlite3" "curl" "bc")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            validator_add_error "Required command not found: $cmd"
        fi
    done

    # Check Docker daemon
    if command -v docker >/dev/null 2>&1; then
        if ! docker info >/dev/null 2>&1; then
            validator_add_error "Docker daemon is not running or not accessible"
        fi
    fi

    # Check available disk space (minimum 1GB)
    if command -v df >/dev/null 2>&1; then
        local available_mb
        available_mb=$(df . | awk 'NR==2 {print int($4/1024)}')
        if [[ $available_mb -lt 1024 ]]; then
            validator_add_warning "Low disk space: ${available_mb}MB available (recommended: >1GB)"
        fi
    fi

    # Check available memory (minimum 512MB free)
    if command -v free >/dev/null 2>&1; then
        local available_mb
        available_mb=$(free -m | awk '/^Mem:/ {print $7}')
        if [[ $available_mb -lt 512 ]]; then
            validator_add_warning "Low available memory: ${available_mb}MB (recommended: >512MB)"
        fi
    fi

    validator_set_context ""
}

# Get validation results
validator_has_errors() {
    [[ ${#VALIDATION_ERRORS[@]} -gt 0 ]]
}

validator_has_warnings() {
    [[ ${#VALIDATION_WARNINGS[@]} -gt 0 ]]
}

validator_get_errors() {
    printf '%s
' "${VALIDATION_ERRORS[@]}"
}

validator_get_warnings() {
    printf '%s
' "${VALIDATION_WARNINGS[@]}"
}

validator_get_error_count() {
    echo "${#VALIDATION_ERRORS[@]}"
}

validator_get_warning_count() {
    echo "${#VALIDATION_WARNINGS[@]}"
}

# Validation summary
validator_show_summary() {
    local error_count=${#VALIDATION_ERRORS[@]}
    local warning_count=${#VALIDATION_WARNINGS[@]}

    echo "Validation Summary:"
    echo "  Errors: $error_count"
    echo "  Warnings: $warning_count"

    if [[ $error_count -gt 0 ]]; then
        echo ""
        echo "Errors:"
        printf '  - %s
' "${VALIDATION_ERRORS[@]}"
    fi

    if [[ $warning_count -gt 0 ]]; then
        echo ""
        echo "Warnings:"
        printf '  - %s
' "${VALIDATION_WARNINGS[@]}"
    fi

    if [[ $error_count -eq 0 && $warning_count -eq 0 ]]; then
        echo "  Status: All validations passed"
    fi
}

# Export validator functions
export -f validator_init
export -f validator_set_context
export -f validator_validate_value
export -f validator_validate_config
export -f validator_validate_system_requirements
export -f validator_has_errors
export -f validator_has_warnings
export -f validator_get_errors
export -f validator_get_warnings
export -f validator_show_summary
export -f validator_clear_results
