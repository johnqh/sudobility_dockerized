#!/bin/bash
# versions.sh - Display version information for all services
# Usage: ./versions.sh

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source helper scripts
source "./setup-scripts/common.sh"

# =============================================================================
# Check Configuration Exists
# =============================================================================

check_config_exists() {
    [ -d "$CONFIG_DIR" ] && [ -f "${CONFIG_DIR}/docker-compose.yml" ]
}

# =============================================================================
# Version Detection Functions
# =============================================================================

get_container_status() {
    local container_name="$1"
    local status

    status=$(docker inspect --format='{{.State.Status}}' "$container_name" 2>/dev/null || echo "not found")
    echo "$status"
}

get_container_health() {
    local container_name="$1"
    local health

    health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}N/A{{end}}' "$container_name" 2>/dev/null || echo "N/A")
    echo "$health"
}

get_image_version() {
    local container_name="$1"
    local image

    image=$(docker inspect --format='{{.Config.Image}}' "$container_name" 2>/dev/null || echo "N/A")
    echo "$image"
}

get_app_version() {
    local container_name="$1"
    local service="$2"
    local version="N/A"

    case "$service" in
        "shapeshyft_api")
            # Try to get version from package.json
            version=$(docker exec "$container_name" cat /app/package.json 2>/dev/null | jq -r '.version' 2>/dev/null || echo "N/A")
            ;;
        "traefik")
            version=$(docker exec "$container_name" traefik version 2>/dev/null | head -1 | awk '{print $2}' || echo "N/A")
            ;;
        *)
            version="N/A"
            ;;
    esac

    echo "$version"
}

# =============================================================================
# Main Display
# =============================================================================

print_header "Sudobility Dockerized - Version Information"

# System information
echo "System:"
echo "  Docker:         $(docker --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
echo "  Docker Compose: $(docker compose version 2>/dev/null | awk '{print $4}' || docker-compose --version 2>/dev/null | awk '{print $3}' | tr -d ',')"
echo ""

# Check for configuration (CONFIG_DIR is defined in common.sh)
if ! check_config_exists; then
    print_warning "No configuration found in ${CONFIG_DIR}/. Run ./setup.sh first."
    exit 0
fi

# Load deployment config if available
if [ -f "${CONFIG_DIR}/.deployment-config" ]; then
    source "${CONFIG_DIR}/.deployment-config"
    echo "Deployment:"
    echo "  API Hostname:   ${API_HOSTNAME:-N/A}"
    echo "  ACME Email:     ${ACME_EMAIL:-N/A}"
    echo "  Setup Date:     ${SETUP_DATE:-N/A}"
    echo ""
fi

# Container information
echo "Containers:"
echo "─────────────────────────────────────────────────────────────────────"
printf "%-20s %-12s %-10s %-15s %s\n" "SERVICE" "STATUS" "HEALTH" "APP VERSION" "IMAGE"
echo "─────────────────────────────────────────────────────────────────────"

# Traefik
container_name="traefik"
status=$(get_container_status "$container_name")
health=$(get_container_health "$container_name")
app_version=$(get_app_version "$container_name" "traefik")
image=$(get_image_version "$container_name")
printf "%-20s %-12s %-10s %-15s %s\n" "Traefik" "$status" "$health" "$app_version" "$image"

# Application containers
for container_info in "${CONTAINERS[@]}"; do
    container_name="${container_info%%:*}"
    display_name=$(get_container_display_name "$container_name")

    status=$(get_container_status "$container_name")
    health=$(get_container_health "$container_name")
    app_version=$(get_app_version "$container_name" "$container_name")
    image=$(get_image_version "$container_name")

    printf "%-20s %-12s %-10s %-15s %s\n" "$display_name" "$status" "$health" "$app_version" "$image"
done

echo "─────────────────────────────────────────────────────────────────────"
echo ""

# Resource usage
echo "Resource Usage:"
echo "─────────────────────────────────────────────────────────────────────"

cd "$CONFIG_DIR"

DOCKER_COMPOSE=$(get_docker_compose_cmd)

# Get stats for running containers
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" 2>/dev/null | head -10 || echo "Could not retrieve stats"

cd "$SCRIPT_DIR"

echo ""
