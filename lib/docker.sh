#!/usr/bin/env bash
# lib/docker.sh -- Docker-specific functions for VaultWarden-OCI-Slim SQLite deployment
# Optimized for 1 OCPU/6GB OCI A1 Flex

# Prevent direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This file should be sourced, not executed directly"
    exit 1
fi

# Source common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
source "$SCRIPT_DIR/common.sh"

# ================================
# DOCKER COMPOSE FUNCTIONS
# ================================

# Get running Docker Compose services
get_running_services() {
    if ! check_docker_compose; then
        return 1
    fi

    docker compose ps --services --filter "status=running" || true
}

# Get all Docker Compose services (running and stopped)
get_all_services() {
    if ! check_docker_compose; then
        return 1
    fi

    docker compose ps --services || true
}

# Start Docker Compose stack with profile support
start_stack() {
    local profiles=()
    local services=()
    local detached=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --profile)
                profiles+=("--profile" "$2")
                shift 2
                ;;
            --service)
                services+=("$2")
                shift 2
                ;;
            --foreground)
                detached=false
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                return 1
                ;;
        esac
    done

    if ! check_docker_compose; then
        return 1
    fi

    log_info "Starting SQLite stack..."

    local compose_cmd="docker compose"

    # Add profiles
    for profile in "${profiles[@]}"; do
        compose_cmd+=" $profile"
    done

    # Add up command
    if [[ "$detached" == "true" ]]; then
        compose_cmd+=" up -d"
    else
        compose_cmd+=" up"
    fi

    # Add specific services if provided
    for service in "${services[@]}"; do
        compose_cmd+=" $service"
    done

    log_debug "Executing: $compose_cmd"
    eval "$compose_cmd"
}

# Stop Docker Compose stack
stop_stack() {
    local remove_containers=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --remove)
                remove_containers=true
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                return 1
                ;;
        esac
    done

    if ! check_docker_compose; then
        return 1
    fi

    log_info "Stopping SQLite stack..."

    if [[ "$remove_containers" == "true" ]]; then
        docker compose down
    else
        docker compose stop
    fi
}

# Restart specific service or entire stack
restart_stack() {
    local services=()

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --service)
                services+=("$2")
                shift 2
                ;;
            *)
                services+=("$1")
                shift
                ;;
        esac
    done

    if ! check_docker_compose; then
        return 1
    fi

    if [[ ${#services[@]} -gt 0 ]]; then
        log_info "Restarting services: ${services[*]}"
        docker compose restart "${services[@]}"
    else
        log_info "Restarting entire SQLite stack..."
        docker compose restart
    fi
}

# ================================
# HEALTH CHECK FUNCTIONS
# ================================

# Perform comprehensive health check for SQLite stack
perform_health_check() {
    log_step "Performing SQLite stack health check..."

    local healthy_services=()
    local unhealthy_services=()
    local missing_services=()

    for service in "${SQLITE_SERVICES[@]}"; do
        local status health_status
        status=$(get_service_status "$service")

        case "$status" in
            "running")
                health_status=$(get_container_health "$service")
                case "$health_status" in
                    "healthy"|"no_healthcheck")
                        healthy_services+=("$service")
                        log_success "✓ $service is healthy"
                        ;;
                    "unhealthy")
                        unhealthy_services+=("$service")
                        log_error "✗ $service is unhealthy"
                        ;;
                    "starting")
                        log_warning "⟳ $service is starting"
                        ;;
                    *)
                        log_warning "? $service health status unknown: $health_status"
                        ;;
                esac
                ;;
            "stopped")
                # Check if service is optional
                if [[ " ${OPTIONAL_SERVICES[*]} " =~ " $service " ]]; then
                    log_info "○ $service is stopped (optional)"
                else
                    unhealthy_services+=("$service")
                    log_error "✗ $service is stopped (should be running)"
                fi
                ;;
            "not_found")
                missing_services+=("$service")
                log_warning "? $service not found"
                ;;
            *)
                log_warning "? $service status unknown: $status"
                ;;
        esac
    done

    # Summary
    echo ""
    log_info "Health check summary:"
    log_info "  Healthy services: ${#healthy_services[@]}"
    log_info "  Unhealthy services: ${#unhealthy_services[@]}"
    log_info "  Missing services: ${#missing_services[@]}"

    # Return success only if critical services are healthy
    local critical_healthy=0
    for service in "${CRITICAL_SERVICES[@]}"; do
        if [[ " ${healthy_services[*]} " =~ " $service " ]]; then
            ((critical_healthy++))
        fi
    done

    if [[ $critical_healthy -eq ${#CRITICAL_SERVICES[@]} ]]; then
        log_success "Critical services are healthy"
        return 0
    else
        log_error "Critical services are not all healthy"
        return 1
    fi
}

# Test specific service health
test_service_health() {
    local service_name="$1"
    local timeout="${2:-30}"

    log_info "Testing $service_name health..."

    # Service-specific health tests
    case "$service_name" in
        "vaultwarden")
            if curl -sf http://localhost:80/alive >/dev/null 2>&1; then
                log_success "VaultWarden health endpoint responding"
                return 0
            else
                log_error "VaultWarden health endpoint not responding"
                return 1
            fi
            ;;
        "bw_caddy")
            if docker exec bw_caddy caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                log_success "Caddy configuration is valid"
                return 0
            else
                log_error "Caddy configuration validation failed"
                return 1
            fi
            ;;
        "bw_fail2ban")
            if docker exec bw_fail2ban fail2ban-client ping >/dev/null 2>&1; then
                log_success "Fail2ban is responding"
                return 0
            else
                log_error "Fail2ban is not responding"
                return 1
            fi
            ;;
        "bw_backup")
            if docker exec bw_backup test -w /backups >/dev/null 2>&1; then
                log_success "Backup service has write access"
                return 0
            else
                log_error "Backup service write test failed"
                return 1
            fi
            ;;
        *)
            # Generic health check using container health status
            local health_status
            health_status=$(get_container_health "$service_name")

            case "$health_status" in
                "healthy")
                    log_success "$service_name is healthy"
                    return 0
                    ;;
                "no_healthcheck")
                    log_success "$service_name is running (no health check configured)"
                    return 0
                    ;;
                *)
                    log_error "$service_name health check failed: $health_status"
                    return 1
                    ;;
            esac
            ;;
    esac
}

# ================================
# CONTAINER MANAGEMENT FUNCTIONS
# ================================

# Get container resource usage
get_container_resources() {
    if ! check_docker; then
        return 1
    fi

    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" | head -20
}

# Get container logs with filtering
get_container_logs() {
    local service_name="$1"
    local lines="${2:-50}"
    local since="${3:-}"

    if ! is_service_running "$service_name"; then
        log_error "$service_name is not running"
        return 1
    fi

    local docker_cmd="docker logs --tail $lines"

    if [[ -n "$since" ]]; then
        docker_cmd+=" --since $since"
    fi

    docker_cmd+=" $service_name"

    eval "$docker_cmd"
}

# Execute command in container
exec_in_container() {
    local service_name="$1"
    shift
    local command=("$@")

    if ! is_service_running "$service_name"; then
        log_error "$service_name is not running"
        return 1
    fi

    docker exec -it "$service_name" "${command[@]}"
}

# ================================
# BACKUP FUNCTIONS (SQLite-specific)
# ================================

# Create immediate SQLite backup
create_immediate_backup() {
    log_info "Creating immediate SQLite backup..."

    if is_service_running "bw_backup"; then
        if docker exec bw_backup /usr/local/bin/db-backup.sh --force; then
            log_success "Immediate backup completed"
            return 0
        else
            log_error "Immediate backup failed"
            return 1
        fi
    else
        log_error "Backup service is not running"
        return 1
    fi
}

# Verify latest backup
verify_latest_backup() {
    log_info "Verifying latest SQLite backup..."

    if is_service_running "bw_backup"; then
        if docker exec bw_backup /usr/local/bin/verify-backup.sh --latest; then
            log_success "Backup verification completed"
            return 0
        else
            log_error "Backup verification failed"
            return 1
        fi
    else
        log_error "Backup service is not running"
        return 1
    fi
}

# ================================
# PROFILE MANAGEMENT FUNCTIONS
# ================================

# Get active profiles from configuration
get_active_profiles() {
    local active_profiles=()

    if ! load_config; then
        return 1
    fi

    # Check which profiles are enabled
    if [[ "${ENABLE_BACKUP:-false}" == "true" ]]; then
        active_profiles+=("backup")
    fi

    if [[ "${ENABLE_SECURITY:-false}" == "true" ]]; then
        active_profiles+=("security")
    fi

    if [[ "${ENABLE_DNS:-false}" == "true" ]]; then
        active_profiles+=("dns")
    fi

    if [[ "${ENABLE_MAINTENANCE:-false}" == "true" ]]; then
        active_profiles+=("maintenance")
    fi

    printf "%s\n" "${active_profiles[@]}"
}

# Start stack with appropriate profiles
start_with_profiles() {
    local force_profiles=()
    local auto_detect=true

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --profile)
                force_profiles+=("$2")
                auto_detect=false
                shift 2
                ;;
            --auto)
                auto_detect=true
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                return 1
                ;;
        esac
    done

    local profiles_to_use=()

    if [[ "$auto_detect" == "true" ]]; then
        # Auto-detect profiles from configuration
        readarray -t profiles_to_use < <(get_active_profiles)
        log_info "Auto-detected profiles: ${profiles_to_use[*]:-none}"
    else
        # Use forced profiles
        profiles_to_use=("${force_profiles[@]}")
        log_info "Using specified profiles: ${profiles_to_use[*]:-none}"
    fi

    # Build profile arguments
    local profile_args=()
    for profile in "${profiles_to_use[@]}"; do
        profile_args+=("--profile" "$profile")
    done

    # Start stack with profiles
    start_stack "${profile_args[@]}"
}

# ================================
# TROUBLESHOOTING FUNCTIONS
# ================================

# Diagnose common Docker issues
diagnose_docker_issues() {
    log_step "Diagnosing Docker issues..."

    local issues_found=0

    # Check Docker daemon
    if ! check_docker; then
        log_error "Docker daemon issue detected"
        ((issues_found++))
    fi

    # Check disk space
    local docker_root
    docker_root=$(docker info --format '{{.DockerRootDir}}' || echo "/var/lib/docker")
    local disk_usage
    disk_usage=$(df "$docker_root" | awk 'NR==2 {print $5}' | sed 's/%//')

    if [[ $disk_usage -gt 85 ]]; then
        log_error "Docker storage disk usage is high: ${disk_usage}%"
        ((issues_found++))
    fi

    # Check for failed containers
    local failed_containers
    failed_containers=$(docker ps -a --filter "status=exited" --filter "status=dead" --format "{{.Names}}" | head -5)

    if [[ -n "$failed_containers" ]]; then
        log_warning "Failed containers detected:"
        echo "$failed_containers" | while read -r container; do
            log_warning "  $container"
        done
        ((issues_found++))
    fi

    # Check container resource constraints (1 OCPU specific)
    if docker stats --no-stream >/dev/null 2>&1; then
        local high_cpu_containers
        high_cpu_containers=$(docker stats --no-stream --format "table {{.Name}}	{{.CPUPerc}}" | awk 'NR>1 {gsub(/%/, "", $2); if ($2 > 50) print $1 " (" $2 "%)"}')

        if [[ -n "$high_cpu_containers" ]]; then
            log_warning "Containers with high CPU usage (>50% on 1 OCPU):"
            echo "$high_cpu_containers" | while read -r line; do
                log_warning "  $line"
            done
        fi
    fi

    if [[ $issues_found -eq 0 ]]; then
        log_success "No Docker issues detected"
    else
        log_warning "$issues_found Docker issues found"
    fi

    return $issues_found
}

# Clean up Docker resources
cleanup_docker_resources() {
    local remove_volumes=false
    local remove_images=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --volumes)
                remove_volumes=true
                shift
                ;;
            --images)
                remove_images=true
                shift
                ;;
            --all)
                remove_volumes=true
                remove_images=true
                shift
                ;;
            *)
                log_error "Unknown argument: $1"
                return 1
                ;;
        esac
    done

    if ! check_docker; then
        return 1
    fi

    log_info "Cleaning up Docker resources..."

    # Remove stopped containers
    local stopped_containers
    stopped_containers=$(docker ps -aq --filter "status=exited" --filter "status=dead")
    if [[ -n "$stopped_containers" ]]; then
        log_info "Removing stopped containers..."
        docker rm $stopped_containers
    fi

    # Remove dangling images
    local dangling_images
    dangling_images=$(docker images -q --filter "dangling=true")
    if [[ -n "$dangling_images" ]]; then
        log_info "Removing dangling images..."
        docker rmi $dangling_images
    fi

    # Remove unused volumes (if requested)
    if [[ "$remove_volumes" == "true" ]]; then
        log_warning "Removing unused volumes..."
        docker volume prune -f
    fi

    # Remove unused images (if requested)
    if [[ "$remove_images" == "true" ]]; then
        log_warning "Removing unused images..."
        docker image prune -a -f
    fi

    # Clean up build cache
    docker builder prune -f >/dev/null 2>&1 || true

    log_success "Docker cleanup completed"
}

# ================================
# INITIALIZATION
# ================================

# Initialize Docker library
init_docker() {
    log_debug "Docker library initialized for SQLite deployment"

    # Validate Docker availability
    if ! check_docker || ! check_docker_compose; then
        log_fatal "Docker environment not available"
    fi
}

# Auto-initialize when sourced
init_docker
