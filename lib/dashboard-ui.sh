#!/usr/bin/env bash
# dashboard-ui.sh -- UI components and formatting utilities
# Provides consistent UI elements and formatting across dashboard

# Header display functions
dashboard_show_header() {
    local title="${1:-VaultWarden-OCI-Slim Dashboard}"
    local subtitle="${2:-SQLite Optimized for 1 OCPU/6GB + Maintenance}"
    local width
    width=$(dashboard_get_header_width)

    if dashboard_color_enabled; then
        clear
        echo -e "${BOLD}${BLUE}╔$(printf '%.0s═' $(seq 1 $((width-2))))╗${NC}"
        echo -e "${BOLD}${BLUE}║$(printf "%*s" $(((width-${#title})/2)) "")${title}$(printf "%*s" $(((width-${#title})/2)) "")║${NC}"
        echo -e "${BOLD}${BLUE}║$(printf "%*s" $(((width-${#subtitle})/2)) "")${subtitle}$(printf "%*s" $(((width-${#subtitle})/2)) "")║${NC}"
        echo -e "${BOLD}${BLUE}╚$(printf '%.0s═' $(seq 1 $((width-2))))╝${NC}"
        echo -e "${WHITE}Last Updated: $(date)                           Press 'q' to quit${NC}"
    else
        clear
        echo "$(printf '%.0s=' $(seq 1 $width))"
        echo "$title"
        echo "$subtitle" 
        echo "$(printf '%.0s=' $(seq 1 $width))"
        echo "Last Updated: $(date)"
    fi
    echo ""
}

# Simple header for submenus
dashboard_show_header_simple() {
    local title="$1"
    local width
    width=$(dashboard_get_header_width)

    if dashboard_color_enabled; then
        clear
        echo -e "${BOLD}${BLUE}╔$(printf '%.0s═' $(seq 1 $((width-2))))╗${NC}"
        echo -e "${BOLD}${BLUE}║$(printf "%*s" $(((width-${#title})/2)) "")${title}$(printf "%*s" $(((width-${#title})/2)) "")║${NC}"
        echo -e "${BOLD}${BLUE}╚$(printf '%.0s═' $(seq 1 $((width-2))))╝${NC}"
    else
        clear
        echo "$(printf '%.0s=' $(seq 1 $width))"
        echo "$title"
        echo "$(printf '%.0s=' $(seq 1 $width))"
    fi
    echo ""
}

# Section headers
dashboard_show_section() {
    local title="$1"
    local color="${2:-CYAN}"

    if dashboard_color_enabled; then
        echo -e "${BOLD}${!color}━━━ $title ━━━${NC}"
    else
        echo "=== $title ==="
    fi
}

# Footer with controls
dashboard_show_footer() {
    local refresh_interval="${1:-5}"

    if dashboard_color_enabled; then
        echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${WHITE}Controls:${NC} ${GREEN}[r]${NC}efresh ${GREEN}[q]${NC}uit ${GREEN}[s]${NC}tatus ${GREEN}[d]${NC}iagnose ${GREEN}[m]${NC}aintenance ${GREEN}[a]${NC}lerts ${GREEN}[h]${NC}elp"
        echo -e "${WHITE}Auto-refresh:${NC} ${CYAN}${refresh_interval}s${NC}   ${WHITE}SQLite optimization:${NC} ${GREEN}Active${NC}   ${WHITE}Maintenance:${NC} ${CYAN}Press 'm'${NC}"
    else
        echo "$(printf '%.0s-' $(seq 1 78))"
        echo "Controls: [r]efresh [q]uit [s]tatus [d]iagnose [m]aintenance [a]lerts [h]elp"
        echo "Auto-refresh: ${refresh_interval}s   SQLite optimization: Active   Maintenance: Press 'm'"
    fi
    echo ""
}

# Status indicators with color coding
dashboard_status_indicator() {
    local status="$1"
    local text="$2"

    if dashboard_color_enabled; then
        case "$status" in
            "good"|"ok"|"running"|"healthy")
                echo -e "${GREEN}●${NC} $text"
                ;;
            "warning"|"moderate"|"elevated")
                echo -e "${YELLOW}●${NC} $text"
                ;;
            "critical"|"error"|"failed"|"stopped")
                echo -e "${RED}●${NC} $text"
                ;;
            "info"|"unknown")
                echo -e "${BLUE}●${NC} $text"
                ;;
            *)
                echo -e "${WHITE}○${NC} $text"
                ;;
        esac
    else
        case "$status" in
            "good"|"ok"|"running"|"healthy")
                echo "✓ $text"
                ;;
            "warning"|"moderate"|"elevated")
                echo "⚠ $text"
                ;;
            "critical"|"error"|"failed"|"stopped")
                echo "✗ $text"
                ;;
            *)
                echo "• $text"
                ;;
        esac
    fi
}

# Progress bars for resource usage
dashboard_progress_bar() {
    local value="$1"
    local max_value="${2:-100}"
    local width="${3:-10}"
    local label="$4"

    local percentage
    if command -v bc >/dev/null 2>&1; then
        percentage=$(echo "scale=1; $value * 100 / $max_value" | bc 2>/dev/null || echo "0")
    else
        percentage=$(( (value * 100) / max_value ))
    fi

    local filled_width
    filled_width=$(( (value * width) / max_value ))
    [[ $filled_width -gt $width ]] && filled_width=$width
    [[ $filled_width -lt 0 ]] && filled_width=0

    local empty_width=$((width - filled_width))

    if dashboard_color_enabled; then
        local color
        if (( $(echo "$percentage > 85" | bc -l 2>/dev/null || echo 0) )); then
            color="$RED"
        elif (( $(echo "$percentage > 70" | bc -l 2>/dev/null || echo 0) )); then
            color="$YELLOW"
        else
            color="$GREEN"
        fi

        echo -e "${WHITE}$label:${NC} ${color}${percentage}%${NC} ${color}$(printf '%.0s█' $(seq 1 $filled_width))${NC}$(printf '%.0s░' $(seq 1 $empty_width))"
    else
        echo "$label: ${percentage}% [$(printf '%.0s#' $(seq 1 $filled_width))$(printf '%.0s-' $(seq 1 $empty_width))]"
    fi
}

# Formatted key-value display
dashboard_show_keyvalue() {
    local key="$1"
    local value="$2"
    local status="${3:-info}"

    if dashboard_color_enabled; then
        local value_color
        case "$status" in
            "good"|"ok") value_color="$GREEN" ;;
            "warning") value_color="$YELLOW" ;;
            "critical"|"error") value_color="$RED" ;;
            *) value_color="$NC" ;;
        esac
        echo -e "${WHITE}$key:${NC} ${value_color}$value${NC}"
    else
        echo "$key: $value"
    fi
}

# Menu display helper
dashboard_show_menu() {
    local title="$1"
    shift
    local options=("$@")

    echo -e "${BOLD}${BLUE}$title:${NC}"
    for option in "${options[@]}"; do
        echo "  $option"
    done
    echo ""
}

# Confirmation prompt
dashboard_confirm() {
    local message="$1"
    local default="${2:-N}"

    if [[ "$default" == "Y" ]]; then
        read -p "$message (Y/n): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Nn]$ ]] && return 1 || return 0
    else
        read -p "$message (y/N): " -n 1 -r
        echo
        [[ $REPLY =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

# Wait for user input
dashboard_wait_input() {
    local message="${1:-Press Enter to continue...}"
    read -p "$message"
}

# Show help information
dashboard_show_help() {
    dashboard_show_header_simple "VaultWarden-OCI-Slim Dashboard Help"

    cat <<EOF
${WHITE}Interactive Controls:${NC}
  ${GREEN}r${NC} - Refresh dashboard immediately
  ${GREEN}q${NC} - Quit dashboard
  ${GREEN}s${NC} - Run status check
  ${GREEN}d${NC} - Run diagnostics
  ${GREEN}m${NC} - SQLite Maintenance Menu
  ${GREEN}a${NC} - Check alerts
  ${GREEN}h${NC} - Show this help

${WHITE}Dashboard Sections:${NC}
  • System Overview - Host information and load
  • Resource Usage - CPU, memory, disk with 1 OCPU context
  • SQLite Database - Database file status, fragmentation, and maintenance
  • Container Status - All services in SQLite stack
  • Backup Status - SQLite backup information
  • Network Status - Connectivity and SSL certificates

${WHITE}SQLite Maintenance Features:${NC}
  • 🧠 Intelligent analysis - detects what operations are needed
  • 🤖 Auto maintenance - performs only required operations
  • ⚡ Individual operations - ANALYZE, VACUUM, WAL checkpoint, etc.
  • 📅 Schedule management - setup/modify cron schedules
  • 📊 Database statistics - detailed fragmentation and health metrics
  • 📋 Log viewing - maintenance history with syntax highlighting

${WHITE}Auto-refresh:${NC} Dashboard updates every ${DASHBOARD_REFRESH_INTERVAL} seconds
${WHITE}Optimization:${NC} Designed for 1 OCPU/6GB OCI A1 Flex instances

${YELLOW}Press any key to return to dashboard...${NC}
EOF
    read -n 1 -s
}

# Export UI functions
export -f dashboard_show_header
export -f dashboard_show_header_simple
export -f dashboard_show_section
export -f dashboard_show_footer
export -f dashboard_status_indicator
export -f dashboard_progress_bar
export -f dashboard_show_keyvalue
export -f dashboard_show_menu
export -f dashboard_confirm
export -f dashboard_wait_input
export -f dashboard_show_help
