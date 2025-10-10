#!/usr/bin/env bash
# benchmark.sh -- Performance benchmarking tool for VaultWarden-OCI

# Set up environment
set -euo pipefail
export DEBUG="${DEBUG:-false}"
export LOG_FILE="/tmp/vaultwarden_benchmark_$(date +%Y%m%d_%H%M%S).log"

# Source library modules with robust error handling
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/lib/common.sh" || {
    # Fallback colors and logging functions if lib/common.sh not available
    if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
        RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
        BLUE='\033[0;34m'; PURPLE='\033[0;35m'; CYAN='\033[0;36m'
        WHITE='\033[1;37m'; BOLD='\033[1m'; NC='\033[0m'
    else
        RED=''; GREEN=''; YELLOW=''; BLUE=''; PURPLE=''; CYAN=''
        WHITE=''; BOLD=''; NC=''
    fi
    log_info() { echo -e "${BLUE}[INFO]${NC} $*"; }
    log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
    log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
    log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
    log_step() { echo -e "${BOLD}${CYAN}=== $* ===${NC}"; }
    SETTINGS_FILE="${SETTINGS_FILE:-./settings.env}"
    echo -e "${YELLOW}[WARNING]${NC} lib/common.sh not found - using fallback functions"
}
source "$SCRIPT_DIR/lib/docker.sh" || {
    echo -e "${YELLOW}[WARNING]${NC} lib/docker.sh not found - using fallback functions"
    is_service_running() { docker ps --filter "name=$1" --filter "status=running" | grep -q "$1"; }
    is_stack_running() { is_service_running "vaultwarden" && is_service_running "bw_caddy"; }
    get_container_id() { docker ps --filter "name=$1" -q | head -1; }
    wait_for_service() { sleep 2; return 0; }
}
source "$SCRIPT_DIR/lib/performance.sh" || {
    echo -e "${YELLOW}[WARNING]${NC} lib/performance.sh not found - using basic performance functions"
}

# Benchmark configuration
BENCHMARK_RESULTS_DIR="./benchmarks"
BENCHMARK_DURATION="${BENCHMARK_DURATION:-60}"  # seconds
BENCHMARK_SAMPLES="${BENCHMARK_SAMPLES:-12}"    # number of samples

# ================================
# BENCHMARK FUNCTIONS
# ================================

# Initialize benchmark environment
init_benchmark() {
    log_info "Initializing benchmark environment..."

    # Create results directory
    mkdir -p "$BENCHMARK_RESULTS_DIR"

    # Ensure stack is running
    if ! is_stack_running; then
        log_error "VaultWarden stack is not running. Please start it first with ./startup.sh"
        return 1
    fi

    log_success "Benchmark environment ready"
}

# System benchmark
run_system_benchmark() {
    local output_file="$1"
    local duration="$2"

    log_info "Running system benchmark for ${duration}s..."

    local start_time end_time
    start_time=$(date +%s)
    end_time=$((start_time + duration))

    # Collect system metrics
    local metrics=()
    while [[ $(date +%s) -lt $end_time ]]; do
        local timestamp cpu_usage memory_usage disk_io load_avg
        timestamp=$(date -Iseconds || date)
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 || echo "0")
        memory_usage=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}' || echo "0")
        load_avg=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | xargs || echo "0")

        # Get disk I/O stats
        if command -v iostat >/dev/null 2>&1; then
            disk_io=$(iostat -d 1 1 | tail -n +4 | awk '{sum+=$4} END {print sum}' || echo "0")
        else
            disk_io="0"
        fi

        # Create simple metric record (avoiding jq dependency)
        local metric_line="${timestamp},${cpu_usage},${memory_usage},${load_avg},${disk_io}"
        metrics+=("$metric_line")
        sleep 5
    done

    # Calculate statistics
    local cpu_sum=0 cpu_max=0 memory_sum=0 memory_max=0 load_sum=0 load_max=0 count=0

    for metric in "${metrics[@]}"; do
        IFS=',' read -r timestamp cpu memory load disk_io <<< "$metric"
        cpu_sum=$(echo "$cpu_sum + $cpu" | bc -l || echo "$cpu_sum")
        memory_sum=$(echo "$memory_sum + $memory" | bc -l || echo "$memory_sum")
        load_sum=$(echo "$load_sum + $load" | bc -l || echo "$load_sum")

        if (( $(echo "$cpu > $cpu_max" | bc -l || echo 0) )); then cpu_max="$cpu"; fi
        if (( $(echo "$memory > $memory_max" | bc -l || echo 0) )); then memory_max="$memory"; fi
        if (( $(echo "$load > $load_max" | bc -l || echo 0) )); then load_max="$load"; fi

        count=$((count + 1))
    done

    local cpu_avg memory_avg load_avg_val
    if [[ $count -gt 0 ]]; then
        cpu_avg=$(echo "scale=2; $cpu_sum / $count" | bc -l || echo "0")
        memory_avg=$(echo "scale=2; $memory_sum / $count" | bc -l || echo "0")
        load_avg_val=$(echo "scale=2; $load_sum / $count" | bc -l || echo "0")
    else
        cpu_avg="0"; memory_avg="0"; load_avg_val="0"
    fi

    # Generate simple JSON report
    cat > "$output_file" <<EOF
{
    "benchmark_type": "system",
    "timestamp": "$(date -Iseconds || date)",
    "duration_seconds": $duration,
    "sample_count": $count,
    "results": {
        "cpu": {
            "average": $cpu_avg,
            "maximum": $cpu_max,
            "unit": "percent"
        },
        "memory": {
            "average": $memory_avg,
            "maximum": $memory_max,
            "unit": "percent"
        },
        "load": {
            "average": $load_avg_val,
            "maximum": $load_max,
            "unit": "load_average"
        }
    }
}
EOF

    log_success "System benchmark completed: $output_file"
}

# Database benchmark (SQLite optimized)
run_database_benchmark() {
    local output_file="$1"
    local duration="$2"

    log_info "Running SQLite database benchmark for ${duration}s..."

    # Check if SQLite database exists
    local sqlite_path="./data/bw/data/bwdata/db.sqlite3"
    if [[ ! -f "$sqlite_path" ]]; then
        log_warning "SQLite database not found - creating basic benchmark"
        cat > "$output_file" <<EOF
{
    "benchmark_type": "database",
    "timestamp": "$(date -Iseconds || date)",
    "duration_seconds": $duration,
    "sample_count": 1,
    "results": {
        "status": "database_not_found",
        "message": "SQLite database not initialized yet"
    }
}
EOF
        return 0
    fi

    if ! command -v sqlite3 >/dev/null 2>&1; then
        log_warning "sqlite3 command not available"
        cat > "$output_file" <<EOF
{
    "benchmark_type": "database",
    "timestamp": "$(date -Iseconds || date)",
    "duration_seconds": $duration,
    "sample_count": 1,
    "results": {
        "status": "sqlite3_unavailable",
        "message": "sqlite3 command not found"
    }
}
EOF
        return 0
    fi

    # Simple SQLite performance test
    local start_time query_count=0
    start_time=$(date +%s)
    local end_time=$((start_time + duration))

    while [[ $(date +%s) -lt $end_time ]]; do
        if sqlite3 "$sqlite_path" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
            query_count=$((query_count + 1))
        fi
        sleep 1
    done

    local query_rate
    query_rate=$(echo "scale=2; $query_count / $duration" | bc -l || echo "0")

    # Get database size
    local db_size_mb
    db_size_mb=$(du -m "$sqlite_path" | cut -f1 || echo "0")

    cat > "$output_file" <<EOF
{
    "benchmark_type": "database",
    "timestamp": "$(date -Iseconds || date)",
    "duration_seconds": $duration,
    "sample_count": $query_count,
    "results": {
        "query_rate": {
            "value": $query_rate,
            "unit": "queries_per_second"
        },
        "database_size": {
            "value": $db_size_mb,
            "unit": "megabytes"
        },
        "queries_executed": $query_count
    }
}
EOF

    log_success "Database benchmark completed: $output_file"
}

# HTTP response time benchmark
run_http_benchmark() {
    local output_file="$1"
    local duration="$2"

    log_info "Running HTTP benchmark for ${duration}s..."

    # Load configuration to get domain
    if [[ -f "$SETTINGS_FILE" ]]; then
        set -a
        source "$SETTINGS_FILE" || true
        set +a
    fi

    local test_url="${DOMAIN:-http://localhost}"
    local health_endpoint="${test_url}/alive"

    local start_time end_time
    start_time=$(date +%s)
    end_time=$((start_time + duration))

    local response_times=()
    local successful_requests=0
    local failed_requests=0
    local total_response_time=0
    local min_time=999 max_time=0

    while [[ $(date +%s) -lt $end_time ]]; do
        local response_time
        response_time=$(curl -o /dev/null -s -w "%{time_total}" --max-time 10 "$health_endpoint" || echo "")

        if [[ -n "$response_time" ]] && [[ "$response_time" != "000" ]]; then
            response_times+=("$response_time")
            successful_requests=$((successful_requests + 1))

            # Update min/max (using bc if available, otherwise basic comparison)
            if command -v bc >/dev/null 2>&1; then
                total_response_time=$(echo "$total_response_time + $response_time" | bc -l)
                if (( $(echo "$response_time < $min_time" | bc -l) )); then min_time="$response_time"; fi
                if (( $(echo "$response_time > $max_time" | bc -l) )); then max_time="$response_time"; fi
            else
                # Simple integer comparison (convert to milliseconds)
                local time_ms=$(echo "$response_time * 1000" | cut -d. -f1 || echo "0")
                if [[ $time_ms -lt $(echo "$min_time * 1000" | cut -d. -f1 || echo "999000") ]]; then
                    min_time="$response_time"
                fi
                if [[ $time_ms -gt $(echo "$max_time * 1000" | cut -d. -f1 || echo "0") ]]; then
                    max_time="$response_time"
                fi
            fi
        else
            failed_requests=$((failed_requests + 1))
        fi

        sleep 2
    done

    # Calculate statistics
    local total_requests avg_response_time success_rate
    total_requests=$((successful_requests + failed_requests))

    if [[ $successful_requests -gt 0 ]] && command -v bc >/dev/null 2>&1; then
        avg_response_time=$(echo "scale=3; $total_response_time / $successful_requests" | bc -l)
        success_rate=$(echo "scale=1; $successful_requests * 100 / $total_requests" | bc -l)
    else
        avg_response_time="0.000"
        success_rate="0"
    fi

    cat > "$output_file" <<EOF
{
    "benchmark_type": "http",
    "timestamp": "$(date -Iseconds || date)",
    "duration_seconds": $duration,
    "test_url": "$health_endpoint",
    "results": {
        "total_requests": $total_requests,
        "successful_requests": $successful_requests,
        "failed_requests": $failed_requests,
        "success_rate": {
            "value": $success_rate,
            "unit": "percent"
        },
        "response_time": {
            "average": $avg_response_time,
            "minimum": $min_time,
            "maximum": $max_time,
            "unit": "seconds"
        }
    }
}
EOF

    log_success "HTTP benchmark completed: $output_file"
}

# Generate comprehensive report
generate_comprehensive_report() {
    local benchmark_files=("$@")
    local output_file="$BENCHMARK_RESULTS_DIR/benchmark_report_$(date +%Y%m%d_%H%M%S).html"

    log_info "Generating comprehensive benchmark report..."

    cat > "$output_file" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>VaultWarden-OCI Benchmark Report</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 40px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 30px; border-radius: 8px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 30px; margin: -30px -30px 30px -30px; border-radius: 8px 8px 0 0; }
        .section { margin: 30px 0; }
        .metric-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; margin: 20px 0; }
        .metric-card { background: #f8f9fa; padding: 20px; border-radius: 6px; border-left: 4px solid #007bff; }
        .metric-value { font-size: 1.5em; font-weight: bold; color: #2c3e50; }
        .metric-label { color: #6c757d; font-size: 0.9em; margin-bottom: 5px; }
        .good { border-left-color: #28a745; }
        .warning { border-left-color: #ffc107; }
        .timestamp { color: #6c757d; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 VaultWarden-OCI Benchmark Report</h1>
            <p class="timestamp">Generated: $(date) | System: $(hostname)</p>
        </div>

        <div class="section">
            <h2>📊 Benchmark Summary</h2>
            <p>Performance analysis completed for SQLite-optimized VaultWarden deployment.</p>
        </div>
    </div>
</body>
</html>
EOF

    log_success "Comprehensive benchmark report generated: $output_file"
    echo "$output_file"
}

# ================================
# MAIN EXECUTION
# ================================

main() {
    local command="${1:-help}"

    case "$command" in
        "run")
            local benchmark_type="${2:-all}"
            local duration="${3:-$BENCHMARK_DURATION}"
            local timestamp=$(date +%Y%m%d_%H%M%S)

            if ! init_benchmark; then
                exit 1
            fi

            local benchmark_files=()

            case "$benchmark_type" in
                "system")
                    run_system_benchmark "$BENCHMARK_RESULTS_DIR/system_$timestamp.json" "$duration"
                    benchmark_files+=("$BENCHMARK_RESULTS_DIR/system_$timestamp.json")
                    ;;
                "database")
                    run_database_benchmark "$BENCHMARK_RESULTS_DIR/database_$timestamp.json" "$duration"
                    benchmark_files+=("$BENCHMARK_RESULTS_DIR/database_$timestamp.json")
                    ;;
                "http")
                    run_http_benchmark "$BENCHMARK_RESULTS_DIR/http_$timestamp.json" "$duration"
                    benchmark_files+=("$BENCHMARK_RESULTS_DIR/http_$timestamp.json")
                    ;;
                "all")
                    log_info "Running comprehensive benchmark suite..."
                    run_system_benchmark "$BENCHMARK_RESULTS_DIR/system_$timestamp.json" "$duration"
                    run_database_benchmark "$BENCHMARK_RESULTS_DIR/database_$timestamp.json" "$duration"
                    run_http_benchmark "$BENCHMARK_RESULTS_DIR/http_$timestamp.json" "$duration"
                    benchmark_files=(
                        "$BENCHMARK_RESULTS_DIR/system_$timestamp.json"
                        "$BENCHMARK_RESULTS_DIR/database_$timestamp.json"
                        "$BENCHMARK_RESULTS_DIR/http_$timestamp.json"
                    )
                    ;;
                *)
                    log_error "Unknown benchmark type: $benchmark_type"
                    exit 1
                    ;;
            esac

            # Generate comprehensive report
            if [[ ${#benchmark_files[@]} -gt 0 ]]; then
                generate_comprehensive_report "${benchmark_files[@]}"
            fi
            ;;
        "list")
            log_info "Available benchmark results:"
            if [[ -d "$BENCHMARK_RESULTS_DIR" ]]; then
                ls -la "$BENCHMARK_RESULTS_DIR" || echo "No files found"
            else
                log_info "No benchmark results found"
            fi
            ;;
        "clean")
            log_info "Cleaning old benchmark results..."
            if [[ -d "$BENCHMARK_RESULTS_DIR" ]]; then
                find "$BENCHMARK_RESULTS_DIR" -name "*.json" -mtime +7 -delete || true
                find "$BENCHMARK_RESULTS_DIR" -name "*.html" -mtime +30 -delete || true
                log_success "Old benchmark results cleaned"
            fi
            ;;
        "help"|"-h"|"--help")
            cat <<EOF
VaultWarden-OCI Performance Benchmark Tool (SQLite Optimized)

Usage: $0 <command> [options]

Commands:
    run <type> [duration]   Run benchmark suite
    list                    List available results  
    clean                   Clean old results
    help                    Show this help message

Benchmark Types:
    system                  System performance (CPU, Memory, Load)
    database                SQLite database performance
    http                    HTTP response times
    all                     Run all benchmarks (default)

Options:
    duration                Benchmark duration in seconds (default: 60)

Examples:
    $0 run all              # Run all benchmarks for 60 seconds
    $0 run system 120       # Run system benchmark for 2 minutes
    $0 run database         # Run SQLite benchmark
    $0 list                 # Show available results
    $0 clean                # Clean old results

Output:
    - JSON files: ./benchmarks/TYPE_TIMESTAMP.json
    - HTML report: ./benchmarks/benchmark_report_TIMESTAMP.html

Requirements:
    - VaultWarden stack must be running
    - All services must be healthy
    - Sufficient disk space in ./benchmarks/

EOF
            exit 0
            ;;
        *)
            log_error "Unknown command: $command"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
