#!/usr/bin/env bash
# test-utils.sh -- Testing utilities and mock functions for VaultWarden components
# Provides comprehensive testing framework for bash modules

# Test configuration
declare -A TEST_CONFIG=(
    ["VERBOSE"]=false
    ["SHOW_STACK_TRACE"]=true
    ["STOP_ON_FIRST_FAILURE"]=false
    ["ENABLE_MOCKS"]=true
    ["TEST_TIMEOUT"]=30
    ["TEMP_DIR"]="/tmp/vaultwarden_tests"
)

# Test state
declare -g TEST_SUITE_NAME=""
declare -g TEST_CASE_NAME=""
declare -g TEST_TOTAL=0
declare -g TEST_PASSED=0
declare -g TEST_FAILED=0
declare -g TEST_SKIPPED=0
declare -a TEST_FAILURES=()

# Mock state
declare -A MOCK_FUNCTIONS=()
declare -A MOCK_COMMANDS=()
declare -A MOCK_FILES=()

# Colors for output
if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
    readonly TEST_RED='[0;31m'
    readonly TEST_GREEN='[0;32m'
    readonly TEST_YELLOW='[1;33m'
    readonly TEST_BLUE='[0;34m'
    readonly TEST_BOLD='[1m'
    readonly TEST_NC='[0m'
else
    readonly TEST_RED=''
    readonly TEST_GREEN=''
    readonly TEST_YELLOW=''
    readonly TEST_BLUE=''
    readonly TEST_BOLD=''
    readonly TEST_NC=''
fi

# Initialize test framework
test_init() {
    # Create temporary directory for tests
    mkdir -p "${TEST_CONFIG[TEMP_DIR]}"

    # Set up cleanup trap
    trap 'test_cleanup' EXIT INT TERM

    # Load test configuration if available
    local config_file="${SCRIPT_DIR:-}/config/test.conf"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    fi
}

# Start test suite
test_suite() {
    TEST_SUITE_NAME="$1"
    TEST_TOTAL=0
    TEST_PASSED=0
    TEST_FAILED=0
    TEST_SKIPPED=0
    TEST_FAILURES=()

    echo -e "${TEST_BOLD}${TEST_BLUE}=== Test Suite: $TEST_SUITE_NAME ===${TEST_NC}"
}

# Start individual test case
test_case() {
    TEST_CASE_NAME="$1"
    ((TEST_TOTAL++))

    if [[ "${TEST_CONFIG[VERBOSE]}" == "true" ]]; then
        echo -e "${TEST_BLUE}Running: $TEST_CASE_NAME${TEST_NC}"
    fi
}

# Test assertions
assert_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should be equal}"

    if [[ "$expected" == "$actual" ]]; then
        test_pass "$message"
    else
        test_fail "$message: expected '$expected', got '$actual'"
    fi
}

assert_not_equals() {
    local expected="$1"
    local actual="$2"
    local message="${3:-Values should not be equal}"

    if [[ "$expected" != "$actual" ]]; then
        test_pass "$message"
    else
        test_fail "$message: both values are '$expected'"
    fi
}

assert_true() {
    local condition="$1"
    local message="${2:-Condition should be true}"

    if [[ "$condition" == "true" ]] || [[ "$condition" == "0" ]]; then
        test_pass "$message"
    else
        test_fail "$message: condition evaluated to '$condition'"
    fi
}

assert_false() {
    local condition="$1"
    local message="${2:-Condition should be false}"

    if [[ "$condition" == "false" ]] || [[ "$condition" != "0" && "$condition" != "true" ]]; then
        test_pass "$message"
    else
        test_fail "$message: condition evaluated to '$condition'"
    fi
}

assert_empty() {
    local value="$1"
    local message="${2:-Value should be empty}"

    if [[ -z "$value" ]]; then
        test_pass "$message"
    else
        test_fail "$message: got '$value'"
    fi
}

assert_not_empty() {
    local value="$1"
    local message="${2:-Value should not be empty}"

    if [[ -n "$value" ]]; then
        test_pass "$message"
    else
        test_fail "$message: value is empty"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local message="${3:-String should contain substring}"

    if [[ "$haystack" == *"$needle"* ]]; then
        test_pass "$message"
    else
        test_fail "$message: '$haystack' does not contain '$needle'"
    fi
}

assert_matches() {
    local string="$1"
    local pattern="$2"
    local message="${3:-String should match pattern}"

    if [[ "$string" =~ $pattern ]]; then
        test_pass "$message"
    else
        test_fail "$message: '$string' does not match pattern '$pattern'"
    fi
}

assert_file_exists() {
    local file="$1"
    local message="${2:-File should exist}"

    if [[ -f "$file" ]]; then
        test_pass "$message"
    else
        test_fail "$message: file '$file' does not exist"
    fi
}

assert_directory_exists() {
    local dir="$1"
    local message="${2:-Directory should exist}"

    if [[ -d "$dir" ]]; then
        test_pass "$message"
    else
        test_fail "$message: directory '$dir' does not exist"
    fi
}

assert_command_succeeds() {
    local command=("$@")
    local message="Command should succeed: ${command[*]}"

    if "${command[@]}" >/dev/null 2>&1; then
        test_pass "$message"
    else
        test_fail "$message (exit code: $?)"
    fi
}

assert_command_fails() {
    local command=("$@")
    local message="Command should fail: ${command[*]}"

    if ! "${command[@]}" >/dev/null 2>&1; then
        test_pass "$message"
    else
        test_fail "$message (command unexpectedly succeeded)"
    fi
}

assert_function_exists() {
    local function_name="$1"
    local message="${2:-Function should exist}"

    if command -v "$function_name" >/dev/null 2>&1; then
        test_pass "$message"
    else
        test_fail "$message: function '$function_name' not found"
    fi
}

# Test result handlers
test_pass() {
    local message="$1"
    ((TEST_PASSED++))

    if [[ "${TEST_CONFIG[VERBOSE]}" == "true" ]]; then
        echo -e "  ${TEST_GREEN}✓${TEST_NC} $message"
    fi
}

test_fail() {
    local message="$1"
    ((TEST_FAILED++))
    TEST_FAILURES+=("[$TEST_CASE_NAME] $message")

    echo -e "  ${TEST_RED}✗${TEST_NC} $message"

    if [[ "${TEST_CONFIG[SHOW_STACK_TRACE]}" == "true" ]]; then
        test_show_stack_trace
    fi

    if [[ "${TEST_CONFIG[STOP_ON_FIRST_FAILURE]}" == "true" ]]; then
        test_show_summary
        exit 1
    fi
}

test_skip() {
    local message="$1"
    ((TEST_SKIPPED++))

    echo -e "  ${TEST_YELLOW}⊘${TEST_NC} Skipped: $message"
}

test_show_stack_trace() {
    echo -e "${TEST_YELLOW}Stack trace:${TEST_NC}"
    local i=2  # Skip test_fail and test_show_stack_trace frames
    while [[ $i -lt ${#BASH_SOURCE[@]} ]]; do
        local source_file="${BASH_SOURCE[$i]}"
        local line_num="${BASH_LINENO[$((i-1))]}"
        local function_name="${FUNCNAME[$i]}"

        [[ "$source_file" != "${BASH_SOURCE[0]}" ]] && 
        echo -e "  ${TEST_YELLOW}$i: $function_name() at $(basename "$source_file"):$line_num${TEST_NC}"
        ((i++))
    done
}

# Mock system
mock_function() {
    local function_name="$1"
    local mock_behavior="$2"

    if [[ "${TEST_CONFIG[ENABLE_MOCKS]}" != "true" ]]; then
        return 0
    fi

    # Store original function if it exists
    if command -v "$function_name" >/dev/null 2>&1; then
        eval "original_$function_name() { $(declare -f "$function_name" | sed '1d'); }"
    fi

    # Create mock function
    eval "$function_name() { $mock_behavior; }"

    MOCK_FUNCTIONS["$function_name"]="$mock_behavior"
}

mock_command() {
    local command_name="$1"
    local mock_script="$2"

    if [[ "${TEST_CONFIG[ENABLE_MOCKS]}" != "true" ]]; then
        return 0
    fi

    local mock_file="${TEST_CONFIG[TEMP_DIR]}/mock_$command_name"

    cat > "$mock_file" <<EOF
#!/bin/bash
$mock_script
EOF

    chmod +x "$mock_file"
    export PATH="${TEST_CONFIG[TEMP_DIR]}:$PATH"

    MOCK_COMMANDS["$command_name"]="$mock_file"
}

mock_file() {
    local file_path="$1"
    local content="$2"

    if [[ "${TEST_CONFIG[ENABLE_MOCKS]}" != "true" ]]; then
        return 0
    fi

    local mock_dir
    mock_dir=$(dirname "$file_path")
    mkdir -p "$mock_dir"

    echo "$content" > "$file_path"
    MOCK_FILES["$file_path"]="$content"
}

# Restore original functions and commands
restore_mocks() {
    if [[ "${TEST_CONFIG[ENABLE_MOCKS]}" != "true" ]]; then
        return 0
    fi

    # Restore functions
    for function_name in "${!MOCK_FUNCTIONS[@]}"; do
        if command -v "original_$function_name" >/dev/null 2>&1; then
            eval "$function_name() { original_$function_name "\$@"; }"
        else
            unset -f "$function_name"
        fi
    done

    # Clean up mock commands
    for command_name in "${!MOCK_COMMANDS[@]}"; do
        rm -f "${MOCK_COMMANDS[$command_name]}"
    done

    # Clean up mock files
    for file_path in "${!MOCK_FILES[@]}"; do
        rm -f "$file_path"
    done

    MOCK_FUNCTIONS=()
    MOCK_COMMANDS=()
    MOCK_FILES=()
}

# Test utilities
test_create_temp_file() {
    local content="$1"
    local temp_file
    temp_file=$(mktemp "${TEST_CONFIG[TEMP_DIR]}/test_file.XXXXXX")

    if [[ -n "$content" ]]; then
        echo "$content" > "$temp_file"
    fi

    echo "$temp_file"
}

test_create_temp_dir() {
    mktemp -d "${TEST_CONFIG[TEMP_DIR]}/test_dir.XXXXXX"
}

test_run_with_timeout() {
    local timeout="${1:-${TEST_CONFIG[TEST_TIMEOUT]}}"
    shift
    local command=("$@")

    timeout "$timeout" "${command[@]}"
}

test_capture_output() {
    local command=("$@")
    local temp_file
    temp_file=$(test_create_temp_file)

    "${command[@]}" > "$temp_file" 2>&1
    local exit_code=$?

    cat "$temp_file"
    rm -f "$temp_file"

    return $exit_code
}

# Test suite summary and cleanup
test_show_summary() {
    echo ""
    echo -e "${TEST_BOLD}${TEST_BLUE}=== Test Results for $TEST_SUITE_NAME ===${TEST_NC}"
    echo -e "Total: $TEST_TOTAL"
    echo -e "${TEST_GREEN}Passed: $TEST_PASSED${TEST_NC}"

    if [[ $TEST_FAILED -gt 0 ]]; then
        echo -e "${TEST_RED}Failed: $TEST_FAILED${TEST_NC}"
        echo ""
        echo -e "${TEST_RED}Failures:${TEST_NC}"
        for failure in "${TEST_FAILURES[@]}"; do
            echo -e "  ${TEST_RED}✗${TEST_NC} $failure"
        done
    fi

    if [[ $TEST_SKIPPED -gt 0 ]]; then
        echo -e "${TEST_YELLOW}Skipped: $TEST_SKIPPED${TEST_NC}"
    fi

    echo ""

    local success_rate
    if [[ $TEST_TOTAL -gt 0 ]]; then
        success_rate=$(( (TEST_PASSED * 100) / TEST_TOTAL ))
        echo -e "Success Rate: ${success_rate}%"
    fi

    if [[ $TEST_FAILED -eq 0 ]]; then
        echo -e "${TEST_GREEN}${TEST_BOLD}All tests passed!${TEST_NC}"
        return 0
    else
        echo -e "${TEST_RED}${TEST_BOLD}Some tests failed.${TEST_NC}"
        return 1
    fi
}

test_cleanup() {
    # Restore any mocks
    restore_mocks

    # Clean up temporary directory
    if [[ -d "${TEST_CONFIG[TEMP_DIR]}" ]]; then
        rm -rf "${TEST_CONFIG[TEMP_DIR]}"
    fi

    # Reset traps
    trap - EXIT INT TERM
}

# Integration with existing logging system
test_log() {
    local level="$1"
    local message="$2"

    if command -v logger_"$level" >/dev/null 2>&1; then
        logger_"$level" "test" "$message"
    else
        echo "[$level] $message"
    fi
}

# Performance testing utilities
test_benchmark() {
    local name="$1"
    local iterations="${2:-1}"
    shift 2
    local command=("$@")

    echo "Benchmarking: $name ($iterations iterations)"

    local total_time=0
    local start_time end_time duration

    for ((i=1; i<=iterations; i++)); do
        start_time=$(date +%s%N)
        "${command[@]}" >/dev/null 2>&1
        end_time=$(date +%s%N)
        duration=$((end_time - start_time))
        total_time=$((total_time + duration))
    done

    local avg_time_ms
    if command -v bc >/dev/null 2>&1; then
        avg_time_ms=$(echo "scale=3; ($total_time / $iterations) / 1000000" | bc)
    else
        avg_time_ms=$(( (total_time / iterations) / 1000000 ))
    fi

    echo "Average execution time: ${avg_time_ms}ms"
}

# Export test utilities
export -f test_init
export -f test_suite
export -f test_case
export -f assert_equals
export -f assert_not_equals
export -f assert_true
export -f assert_false
export -f assert_empty
export -f assert_not_empty
export -f assert_contains
export -f assert_matches
export -f assert_file_exists
export -f assert_directory_exists
export -f assert_command_succeeds
export -f assert_command_fails
export -f assert_function_exists
export -f test_skip
export -f mock_function
export -f mock_command
export -f mock_file
export -f restore_mocks
export -f test_create_temp_file
export -f test_create_temp_dir
export -f test_run_with_timeout
export -f test_capture_output
export -f test_show_summary
export -f test_benchmark
