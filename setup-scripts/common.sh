#!/bin/bash
# common.sh - Shared utility functions for setup scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_info() {
    echo -e "${BLUE}→${NC} $1"
}

print_header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Require a command or exit
require_command() {
    if ! command_exists "$1"; then
        print_error "$1 is required but not installed."
        exit 1
    fi
}

# Check all required dependencies
check_dependencies() {
    print_info "Checking dependencies..."

    local missing=0

    for cmd in docker curl jq; do
        if command_exists "$cmd"; then
            print_success "$cmd is installed"
        else
            print_error "$cmd is not installed"
            missing=1
        fi
    done

    # Check Docker Compose (v2 plugin or standalone)
    if docker compose version >/dev/null 2>&1; then
        print_success "docker compose is available"
    elif command_exists docker-compose; then
        print_success "docker-compose is available"
    else
        print_error "docker compose is not available"
        missing=1
    fi

    if [ $missing -eq 1 ]; then
        print_error "Please install missing dependencies and try again."
        exit 1
    fi

    echo ""
}

# Get the docker compose command (v2 or v1)
get_docker_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

# List of containers to manage (add new containers here)
# Format: container_name:display_name:port
CONTAINERS=(
    "shapeshyft_api:ShapeShyft API:3000"
)

# Get container names only
get_container_names() {
    for container in "${CONTAINERS[@]}"; do
        echo "${container%%:*}"
    done
}

# Get container display name
get_container_display_name() {
    local name="$1"
    for container in "${CONTAINERS[@]}"; do
        if [[ "${container%%:*}" == "$name" ]]; then
            local rest="${container#*:}"
            echo "${rest%%:*}"
            return
        fi
    done
    echo "$name"
}

# Get container port
get_container_port() {
    local name="$1"
    for container in "${CONTAINERS[@]}"; do
        if [[ "${container%%:*}" == "$name" ]]; then
            echo "${container##*:}"
            return
        fi
    done
    echo "3000"
}

# Secure file permissions
secure_file() {
    local file="$1"
    if [ -f "$file" ]; then
        chmod 600 "$file"
    fi
}

# Prompt for yes/no with default
prompt_yes_no() {
    local prompt="$1"
    local default="${2:-y}"

    if [ "$default" = "y" ]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -p "$prompt" response
    response="${response:-$default}"

    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Configuration directory
CONFIG_DIR="config-generated"

# Ensure config directory exists
ensure_config_dir() {
    mkdir -p "$CONFIG_DIR"
}
