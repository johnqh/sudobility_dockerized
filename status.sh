#!/bin/bash
# status.sh - Show status of all services
# Usage: ./status.sh

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source helper scripts
source "./setup-scripts/common.sh"

# =============================================================================
# Main Status Display
# =============================================================================

print_header "Service Status"

# Check Traefik
echo "Infrastructure:"
echo "─────────────────────────────────────────────────────────────────────────────────────"

if is_traefik_running; then
    TRAEFIK_STATUS="${GREEN}running${NC}"
    TRAEFIK_HEALTH=$(get_container_health "traefik")
    TRAEFIK_UPTIME=$(get_container_uptime "traefik")
else
    TRAEFIK_STATUS="${RED}not running${NC}"
    TRAEFIK_HEALTH="N/A"
    TRAEFIK_UPTIME="N/A"
fi

printf "  Traefik:  Status: %b  Health: %s  Uptime: %s\n" "$TRAEFIK_STATUS" "$TRAEFIK_HEALTH" "$TRAEFIK_UPTIME"
echo ""

# Get list of services (bash 3.x compatible)
read_services_array

if [ ${#SERVICES[@]} -eq 0 ]; then
    print_warning "No services found. Use ./add.sh to add a service."
    exit 0
fi

echo "Services:"
display_services_table "${SERVICES[@]}"

# Quick commands
echo "Quick Commands:"
echo "  ./add.sh      - Add a new service"
echo "  ./upgrade.sh  - Upgrade a service"
echo "  ./remove.sh   - Remove a service"
echo ""
