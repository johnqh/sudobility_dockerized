#!/bin/bash
# remove.sh - Remove a service from the server
# Usage: ./remove.sh

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source helper scripts
source "./setup-scripts/common.sh"

# =============================================================================
# Main Remove Flow
# =============================================================================

print_header "Remove Service"

# Get list of services (bash 3.x compatible)
read_services_array

if [ ${#SERVICES[@]} -eq 0 ]; then
    print_warning "No services found."
    exit 0
fi

echo "Select a service to remove:"

if ! select_service "Select service" "${SERVICES[@]}"; then
    print_info "Removal cancelled."
    exit 0
fi

SERVICE_NAME="$SELECTED_SERVICE"
SERVICE_DIR="${SERVICES_DIR}/${SERVICE_NAME}"
HOSTNAME=$(get_service_config "$SERVICE_NAME" "HOSTNAME")

print_info "Selected: $SERVICE_NAME"

# =============================================================================
# Confirm removal
# =============================================================================

echo ""
print_warning "This will permanently remove the service and all its configuration."
display_service_info "$SERVICE_NAME" name hostname version status

if ! prompt_yes_no "Are you sure you want to remove '$SERVICE_NAME'?" "n"; then
    print_info "Removal cancelled."
    exit 0
fi

# Double confirmation for safety
echo ""
read -p "Type the service name to confirm removal: " CONFIRM_NAME

if [ "$CONFIRM_NAME" != "$SERVICE_NAME" ]; then
    print_error "Service name does not match. Removal cancelled."
    exit 1
fi

# =============================================================================
# Step 1: Stop and remove container
# =============================================================================
print_header "Step 1: Stopping Service"

service_remove "$SERVICE_NAME"
print_success "Container stopped and removed"

# =============================================================================
# Step 2: Remove configuration
# =============================================================================
print_header "Step 2: Removing Configuration"

service_cleanup_config "$SERVICE_NAME"

# =============================================================================
# Done
# =============================================================================
print_header "Removal Complete"

echo "Service '$SERVICE_NAME' has been removed."
echo ""
echo "Note: The SSL certificate may still be cached in Traefik."
echo "It will be cleaned up automatically when it expires."
echo ""

print_success "Service removed successfully!"
