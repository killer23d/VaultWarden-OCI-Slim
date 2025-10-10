#!/usr/bin/env bash
# lib/common.sh -- Common functions for VaultWarden-OCI-Slim SQLite deployment
# Optimized for 1 OCPU/6GB OCI A1 Flex

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This file should be sourced, not executed directly"
    exit 1
fi

# Environment variables
export DEBUG="${DEBUG:-false}"
export SCRIPT_NAME="${SCRIPT_NAME:-$(basename "${BASH_SOURCE[1]}")}"

# --- Smart Color Setup ---
if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
    readonly RED='\033[0;31m'; readonly GREEN='\033[0;32m'; readonly YELLOW='\033[1;33m';
    readonly BLUE='\033[0;34m'; readonly PURPLE='\033[0;35m'; readonly CYAN='\033[0;36m';
    readonly WHITE='\033[1;37m'; readonly BOLD='\033[1m'; readonly NC='\033[0m';
else
    readonly RED=''; readonly GREEN=''; readonly YELLOW=''; readonly BLUE='';
    readonly PURPLE=''; readonly CYAN=''; readonly WHITE=''; readonly BOLD=''; readonly NC='';
fi

# Configuration files
SETTINGS_FILE="${SETTINGS_FILE:-./settings.env}"
SETTINGS_EXAMPLE="${SETTINGS_EXAMPLE:-./settings.env.example}"
COMPOSE_FILE="${COMPOSE_FILE:-./docker-compose.yml}"

# SQLite database paths
SQLITE_DB_PATH="./data/bwdata/db.sqlite3"
VAULTWARDEN_DATA_DIR="${VAULTWARDEN_DATA_DIR:-./data/bwdata}"

# Required directories for SQLite deployment
REQUIRED_DIRS=(
    "./data"
    "./data/bwdata"
    "./data/caddy_data"
    "./data/caddy_config"
    "./data/caddy_logs"
    "./data/backups"
    "./data/backup_logs"
    "./data/fail2ban"
    "./backup/config"
)

# SQLite-specific service list (no MariaDB/Redis)
SQLITE_SERVICES=(
    "vaultwarden"
    "bw_caddy"
    "bw_fail2ban"
    "bw_backup"
    "bw_watchtower"
    "bw_ddclient"
)

# Critical services that must be running
CRITICAL_SERVICES=(
    "vaultwarden"
    "bw_caddy"
)

# Optional services (profile-dependent)
OPTIONAL_SERVICES=(
    "bw_fail2ban"
    "bw_backup"
    "bw_watchtower"
    "bw_ddclient"
)

# ================================
# LOGGING FUNCTIONS
# ================================

log_debug() {
    if [[ "$DEBUG" == "true" ]]; then
        echo -e "${PURPLE}[DEBUG]${NC} $*" >&2
    fi
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_fatal() {
    echo -e "${RED}[FATAL]${NC} $*" >&2
    exit 1
}

log_step() {
    echo -e "${BOLD}${CYAN}=== $* ===${NC}"
}

# ================================
# VALIDATION FUNCTIONS
# ================================

# Validate system requirements for 1 OCPU/6GB
validate_system_requirements() {
    local errors=0

    # Check CPU cores
    local cpu_cores
    cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 1 ]]; then
        log_error "Insufficient CPU cores: $cpu_cores (minimum: 1)"
        ((errors++))
    else
        log_debug "CPU cores: $cpu_cores"
    fi

    # Check available memory
    local mem_gb
    mem_gb=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $mem_gb -lt 4 ]]; then
        log_warning "Low memory: ${mem_gb}GB (recommended: 6GB for optimal performance)"
    else
        log_debug "Memory: ${mem_gb}GB"
    fi

    # Check disk space
    local disk_free_gb
    disk_free_gb=$(df -BG . | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $disk_free_gb -lt 10 ]]; then
        log_error "Insufficient disk space: ${disk_free_gb}GB (minimum: 10GB)"
        ((errors++))
    else
        log_debug "Disk space: ${disk_free_gb}GB available"
    fi

    return $errors
}

# Validate project structure
validate_project_structure() {
    local errors=0

    # Check required files
    local required_files=("$SETTINGS_EXAMPLE" "$COMPOSE_FILE")
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            log_error "Required file missing: $file"
            ((errors++))
        else
            log_debug "Required file found: $file"
        fi
    done

    # Check if required directories can be created
    for dir in "${REQUIRED_DIRS[@]}"; do
        if ! mkdir -p "$dir"; then
            log_error "Cannot create required directory: $dir"
            ((errors++))
        else
            log_debug "Directory available: $dir"
        fi
    done

    return $errors
}

# ================================
# SQLITE DATABASE FUNCTIONS
# ================================

# Check if SQLite database exists and is accessible
check_sqlite_database() {
    if [[ ! -f "$SQLITE_DB_PATH" ]]; then
        log_debug "SQLite database not found: $SQLITE_DB_PATH"
        return 1
    fi

    if ! sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master;" >/dev/null 2>&1; then
        log_error "SQLite database is not accessible or corrupted: $SQLITE_DB_PATH"
        return 1
    fi

    log_debug "SQLite database is accessible: $SQLITE_DB_PATH"
    return 0
}

# Get SQLite database statistics
get_sqlite_stats() {
    if ! check_sqlite_database; then
        return 1
    fi

    local db_size table_count user_count

    # Database file size
    db_size=$(du -h "$SQLITE_DB_PATH" | cut -f1)

    # Table count
    table_count=$(sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM sqlite_master WHERE type='table';" || echo "0")

    # User count (if users table exists)
    if sqlite3 "$SQLITE_DB_PATH" "SELECT name FROM sqlite_master WHERE type='table' AND name='users';" | grep -q users; then
        user_count=$(sqlite3 "$SQLITE_DB_PATH" "SELECT COUNT(*) FROM users;" || echo "0")
    else
        user_count="N/A"
    fi

    echo "size=$db_size;tables=$table_count;users=$user_count"
}

# Check SQLite database health
check_sqlite_health() {
    if ! check_sqlite_database; then
        return 1
    fi

    # Run integrity check
    local integrity_result
    integrity_result=$(sqlite3 "$SQLITE_DB_PATH" "PRAGMA integrity_check;")

    if [[ "$integrity_result" == "ok" ]]; then
        log_debug "SQLite integrity check: OK"
        return 0
    else
        log_error "SQLite integrity check failed: $integrity_result"
        return 1
    fi
}

# Get SQLite journal mode
get_sqlite_journal_mode() {
    if ! check_sqlite_database; then
        echo "unknown"
        return 1
    fi

    sqlite3 "$SQLITE_DB_PATH" "PRAGMA journal_mode;" || echo "unknown"
}

# ================================
# DOCKER FUNCTIONS
# ================================

# Check if Docker is available and running
check_docker() {
    if ! command -v docker >/dev/null 2>&1; then
        log_error "Docker is not installed"
        return 1
    fi

    if ! docker info >/dev/null 2>&1; then
        log_error "Docker daemon is not running or accessible"
        return 1
    fi

    log_debug "Docker is available"
    return 0
}

# Check if Docker Compose is available
check_docker_compose() {
    if ! docker compose version >/dev/null 2>&1; then
        log_error "Docker Compose is not available"
        return 1
    fi

    log_debug "Docker Compose is available"
    return 0
}

# Check if a specific service is running
is_service_running() {
    local service_name="$1"

    if ! check_docker; then
        return 1
    fi

    docker ps --filter "name=$service_name" --filter "status=running" | grep -q "$service_name"
}

# Check if the SQLite stack is running
is_stack_running() {
    local running_count=0

    for service in "${CRITICAL_SERVICES[@]}"; do
        if is_service_running "$service"; then
            ((running_count++))
        fi
    done

    # Stack is considered running if all critical services are running
    [[ $running_count -eq ${#CRITICAL_SERVICES[@]} ]]
}

# Get service status
get_service_status() {
    local service_name="$1"

    if ! check_docker; then
        echo "docker_unavailable"
        return 1
    fi

    if docker ps --filter "name=$service_name" --filter "status=running" | grep -q "$service_name"; then
        echo "running"
    elif docker ps -a --filter "name=$service_name" | grep -q "$service_name"; then
        echo "stopped"
    else
        echo "not_found"
    fi
}

# Get container health status
get_container_health() {
    local service_name="$1"

    if ! is_service_running "$service_name"; then
        echo "not_running"
        return 1
    fi

    local health_status
    health_status=$(docker inspect "$service_name" --format='{{.State.Health.Status}}')

    case "$health_status" in
        "healthy") echo "healthy" ;;
        "unhealthy") echo "unhealthy" ;;
        "starting") echo "starting" ;;
        "") echo "no_healthcheck" ;;
        *) echo "unknown" ;;
    esac
}

# ================================
# CONFIGURATION FUNCTIONS
# ================================

# Load configuration from settings file
load_config() {
    if [[ -f "$SETTINGS_FILE" ]]; then
        set -a
        source "$SETTINGS_FILE"
        set +a
        log_debug "Configuration loaded from: $SETTINGS_FILE"
        return 0
    else
        log_warning "Configuration file not found: $SETTINGS_FILE"
        return 1
    fi
}

# Validate SQLite-specific configuration
validate_sqlite_config() {
    if ! load_config; then
        return 1
    fi

    local errors=0

    # Check DATABASE_URL is SQLite
    if [[ "${DATABASE_URL:-}" != *"sqlite"* ]]; then
        log_warning "DATABASE_URL is not SQLite: ${DATABASE_URL:-'not set'}"
        ((errors++))
    fi

    # Check worker configuration for 1 OCPU - Fixed to check ROCKET_WORKERS
    if [[ "${ROCKET_WORKERS:-1}" != "1" ]]; then
        log_warning "ROCKET_WORKERS=${ROCKET_WORKERS:-1} (recommended: 1 for 1 OCPU)"
    fi

    # Check WebSocket configuration
    if [[ "${WEBSOCKET_ENABLED:-true}" != "false" ]]; then
        log_warning "WEBSOCKET_ENABLED=${WEBSOCKET_ENABLED:-true} (recommended: false for efficiency)"
    fi

    return $errors
}

# ================================
# NETWORK FUNCTIONS
# ================================

# Test internal connectivity
test_internal_connectivity() {
    local errors=0

    # Test VaultWarden health endpoint
    if curl -sf http://localhost:80/alive >/dev/null 2>&1; then
        log_debug "VaultWarden local connectivity: OK"
    else
        log_error "VaultWarden not responding on localhost:80"
        ((errors++))
    fi

    return $errors
}

# Test external connectivity (if domain configured)
test_external_connectivity() {
    local errors=0

    if [[ -n "${APP_DOMAIN:-}" ]]; then
        local domain_url="${DOMAIN:-https://${APP_DOMAIN}}"

        if curl -sf "${domain_url}/alive" >/dev/null 2>&1; then
            log_debug "External connectivity: OK ($domain_url)"
        else
            log_warning "External connectivity failed: $domain_url"
            ((errors++))
        fi
    else
        log_debug "No domain configured for external connectivity test"
    fi

    return $errors
}

# ================================
# PERFORMANCE MONITORING
# ================================

# Get system resource usage optimized for 1 OCPU
get_system_resources() {
    local cpu_usage mem_usage_pct load_avg disk_usage_pct

    # CPU usage
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)

    # Memory usage percentage
    mem_usage_pct=$(free | awk '/^Mem:/{printf "%.1f", $3*100/$2}')

    # Load average (critical for 1 OCPU)
    load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')

    # Disk usage percentage
    disk_usage_pct=$(df . | awk 'NR==2 {print $5}' | sed 's/%//')

    echo "cpu=$cpu_usage;memory=$mem_usage_pct;load=$load_avg;disk=$disk_usage_pct"
}

# Check if system resources are within healthy limits for 1 OCPU
check_resource_health() {
    local resources
    resources=$(get_system_resources)

    local cpu_usage mem_usage load_avg disk_usage
    eval "$(echo "$resources" | tr ';' '\n' | sed 's/^/local /')"

    local issues=0

    # CPU check (90% threshold for 1 OCPU)
    if (( $(echo "$cpu_usage > 90" | bc -l || echo 0) )); then
        log_warning "High CPU usage: ${cpu_usage}% (threshold: 90%)"
        ((issues++))
    fi

    # Memory check (85% threshold)
    if (( $(echo "$mem_usage > 85" | bc -l || echo 0) )); then
        log_warning "High memory usage: ${mem_usage}% (threshold: 85%)"
        ((issues++))
    fi

    # Load average check (critical for single CPU)
    if (( $(echo "$load_avg > 1.5" | bc -l || echo 0) )); then
        log_warning "High load average: $load_avg (threshold: 1.5 for 1 OCPU)"
        ((issues++))
    fi

    # Disk usage check
    if [[ $disk_usage -gt 85 ]]; then
        log_warning "High disk usage: ${disk_usage}% (threshold: 85%)"
        ((issues++))
    fi

    return $issues
}

# ================================
# UTILITY FUNCTIONS
# ================================

# Wait for a service to be ready
wait_for_service() {
    local service_name="$1"
    local max_attempts="${2:-30}"
    local sleep_interval="${3:-2}"

    log_info "Waiting for $service_name to be ready..."

    local attempt=0
    while [[ $attempt -lt $max_attempts ]]; do
        if is_service_running "$service_name"; then
            local health
            health=$(get_container_health "$service_name")

            case "$health" in
                "healthy"|"no_healthcheck")
                    log_success "$service_name is ready"
                    return 0
                    ;;
                "starting")
                    log_debug "$service_name is starting... (attempt $((attempt + 1))/$max_attempts)"
                    ;;
                "unhealthy")
                    log_warning "$service_name is unhealthy (attempt $((attempt + 1))/$max_attempts)"
                    ;;
            esac
        else
            log_debug "$service_name is not running (attempt $((attempt + 1))/$max_attempts)"
        fi

        sleep "$sleep_interval"
        ((attempt++))
    done

    log_error "$service_name did not become ready within $((max_attempts * sleep_interval)) seconds"
    return 1
}

# Generate secure random string
generate_random_string() {
    local length="${1:-32}"
    openssl rand -hex "$length" || {
        # Fallback method
        LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length" || echo "fallback$(date +%s)"
    }
}

# Check if Cloudflare IPs need updating
need_cloudflare_ip_update() {
    local cloudflare_ips_file="./caddy/cloudflare_ips.txt"
    local cloudflare_caddy_file="./caddy/cloudflare_ips.caddy"

    # Check if files exist and are recent (less than 30 days old)
    if [[ -f "$cloudflare_ips_file" && -f "$cloudflare_caddy_file" ]]; then
        local file_age
        file_age=$(( ($(date +%s) - $(stat -c %Y "$cloudflare_ips_file")) / 86400 ))

        if [[ $file_age -lt 30 ]]; then
            return 1  # Files are recent, no update needed
        fi
    fi

    return 0  # Files need updating
}

# Collect diagnostic information
collect_diagnostics() {
    local output_dir="diagnostics_$(date +%Y%m%d_%H%M%S)"

    mkdir -p "$output_dir"

    # System information
    {
        echo "=== SYSTEM INFORMATION ==="
        uname -a
        echo ""
        free -h
        echo ""
        df -h
        echo ""
        uptime
        echo ""
    } > "$output_dir/system_info.txt"

    # Docker information
    {
        echo "=== DOCKER INFORMATION ==="
        docker --version
        docker compose version
        echo ""
        docker info
        echo ""
        docker ps -a
        echo ""
    } > "$output_dir/docker_info.txt" 2>&1

    # SQLite information
    if [[ -f "$SQLITE_DB_PATH" ]]; then
        {
            echo "=== SQLITE DATABASE INFORMATION ==="
            echo "Database path: $SQLITE_DB_PATH"
            echo "Database size: $(du -h "$SQLITE_DB_PATH" | cut -f1)"
            echo "Last modified: $(stat -c %y "$SQLITE_DB_PATH")"
            echo ""

            if check_sqlite_database; then
                echo "Database statistics:"
                get_sqlite_stats
                echo ""

                echo "Journal mode: $(get_sqlite_journal_mode)"
                echo ""

                echo "Integrity check:"
                sqlite3 "$SQLITE_DB_PATH" "PRAGMA integrity_check;" || echo "Failed"
                echo ""
            else
                echo "Database not accessible"
            fi
        } > "$output_dir/sqlite_info.txt" 2>&1
    fi

    # Configuration
    if [[ -f "$SETTINGS_FILE" ]]; then
        # Sanitize sensitive information
        {
            echo "=== CONFIGURATION (SANITIZED) ==="
            sed -E 's/(PASSWORD|TOKEN|SECRET|KEY)=.*/\1=***REDACTED***/g' "$SETTINGS_FILE"
        } > "$output_dir/config_sanitized.txt"
    fi

    # Docker Compose configuration
    if [[ -f "$COMPOSE_FILE" ]]; then
        {
            echo "=== DOCKER COMPOSE CONFIGURATION ==="
            docker compose config
        } > "$output_dir/compose_config.txt" 2>&1
    fi

    # Container logs (last 100 lines each)
    for service in "${SQLITE_SERVICES[@]}"; do
        if is_service_running "$service"; then
            docker logs --tail 100 "$service" > "$output_dir/${service}_logs.txt" 2>&1
        fi
    done

    # Resource usage
    {
        echo "=== RESOURCE USAGE ==="
        get_system_resources
        echo ""

        if check_docker; then
            echo "Container resource usage:"
            docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
        fi
    } > "$output_dir/resource_usage.txt"

    log_success "Diagnostic information collected in: $output_dir"
    echo "$output_dir"
}

# ================================
# INITIALIZATION
# ================================

# Initialize common environment
init_common() {
    # Set up error handling
    set -euo pipefail

    # Load configuration if available
    load_config || true

    log_debug "Common library initialized for SQLite deployment"
}

# Auto-initialize when sourced
init_common
