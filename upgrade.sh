#!/bin/bash
# upgrade.sh - Upgrade an existing service
# Usage: ./upgrade.sh

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source helper scripts
source "./setup-scripts/common.sh"

# =============================================================================
# Main Upgrade Flow
# =============================================================================

print_header "Upgrade Service"

# Get list of services (bash 3.x compatible)
read_services_array

if [ ${#SERVICES[@]} -eq 0 ]; then
    print_warning "No services found. Use add.sh to add a service first."
    exit 0
fi

echo "Select a service to upgrade:"

if ! select_service "Select service" "${SERVICES[@]}"; then
    print_info "Upgrade cancelled."
    exit 0
fi

SERVICE_NAME="$SELECTED_SERVICE"
SERVICE_DIR="${SERVICES_DIR}/${SERVICE_NAME}"

print_info "Selected: $SERVICE_NAME"

# =============================================================================
# Confirm upgrade
# =============================================================================

echo ""
if ! prompt_yes_no "Upgrade $SERVICE_NAME?" "y"; then
    print_info "Upgrade cancelled."
    exit 0
fi

# =============================================================================
# Step 1: Update environment from Doppler
# =============================================================================
print_header "Step 1: Updating Environment Variables"

DOPPLER_TOKEN=$(get_doppler_token "$SERVICE_NAME")

if [ -n "$DOPPLER_TOKEN" ]; then
    print_info "Fetching latest secrets from Doppler..."

    ENV_FILE="${SERVICE_DIR}/.env"
    ENV_BACKUP="${SERVICE_DIR}/.env.backup"

    # Backup current env
    if [ -f "$ENV_FILE" ]; then
        cp "$ENV_FILE" "$ENV_BACKUP"
    fi

    HTTP_CODE=$(fetch_doppler_secrets "$DOPPLER_TOKEN" "$ENV_FILE")

    if [ "$HTTP_CODE" = "200" ]; then
        secure_file "$ENV_FILE"
        print_success "Environment variables updated"

        # Update PORT in service config if changed
        NEW_PORT=$(grep "^PORT=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")
        OLD_PORT=$(get_service_config "$SERVICE_NAME" "PORT")

        if [ -n "$NEW_PORT" ] && [ "$NEW_PORT" != "$OLD_PORT" ]; then
            print_warning "PORT changed: $OLD_PORT → $NEW_PORT"
            # Update docker-compose.yml with new port
            sed -i.bak "s/server.port=${OLD_PORT}/server.port=${NEW_PORT}/g" "${SERVICE_DIR}/docker-compose.yml"
            sed -i.bak "s/localhost:${OLD_PORT}/localhost:${NEW_PORT}/g" "${SERVICE_DIR}/docker-compose.yml"
            rm -f "${SERVICE_DIR}/docker-compose.yml.bak"

            # Update service config
            sed -i.bak "s/^PORT=.*/PORT=${NEW_PORT}/" "${SERVICE_DIR}/.service.conf"
            rm -f "${SERVICE_DIR}/.service.conf.bak"
        fi
    else
        print_warning "Failed to fetch secrets (HTTP $HTTP_CODE), using existing environment"
        if [ -f "$ENV_BACKUP" ]; then
            mv "$ENV_BACKUP" "$ENV_FILE"
        fi
    fi
else
    print_warning "No Doppler token found, skipping environment update"
fi

# =============================================================================
# Step 2: Pull and restart
# =============================================================================
print_header "Step 2: Pulling Latest Image"

service_pull "$SERVICE_NAME"

print_header "Step 3: Restarting Service"

service_stop "$SERVICE_NAME"
service_start "$SERVICE_NAME"

# =============================================================================
# Verify
# =============================================================================
print_header "Verification"

if service_wait_and_verify "$SERVICE_NAME"; then
    display_service_info "$SERVICE_NAME" name status health version hostname
    print_success "Service '$SERVICE_NAME' upgraded successfully!"
else
    display_service_info "$SERVICE_NAME" name status health version hostname
    print_warning "Service may not have started correctly. Check logs:"
    echo "  cd ${SERVICE_DIR} && docker compose logs"
fi
