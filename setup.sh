#!/bin/bash
# setup.sh - Main installation script for Sudobility Dockerized
# Usage: ./setup.sh

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source helper scripts
source "./setup-scripts/common.sh"
source "./setup-scripts/doppler.sh"
source "./setup-scripts/traefik.sh"

# =============================================================================
# Step 0: Install Dependencies
# =============================================================================
print_header "Step 0: Installing Dependencies"
source "./setup-scripts/deps_setup.sh"

# =============================================================================
# Main Setup Flow
# =============================================================================

print_header "Sudobility Dockerized Setup"

echo "This script will set up Docker containers for your backend APIs."
echo "It will:"
echo "  1. Check dependencies"
echo "  2. Configure API hostname"
echo "  3. Set up Doppler secrets for each container"
echo "  4. Configure Traefik with Let's Encrypt SSL"
echo "  5. Start all services"
echo ""

# Check if config already exists
if [ -d "$CONFIG_DIR" ] && [ -f "${CONFIG_DIR}/docker-compose.yml" ]; then
    print_warning "Existing configuration found in ${CONFIG_DIR}/"

    if ! prompt_yes_no "Do you want to remove it and start fresh?" "n"; then
        print_info "Setup cancelled. Use upgrade.sh to update existing installation."
        exit 0
    fi

    print_info "Removing existing configuration..."
    rm -rf "$CONFIG_DIR"
fi

# =============================================================================
# Step 1: Check Dependencies
# =============================================================================
print_header "Step 1: Checking Dependencies"
check_dependencies

# =============================================================================
# Step 2: Configure Hostname
# =============================================================================
print_header "Step 2: Configure API Hostname"

API_HOSTNAME=$(prompt_hostname)
ACME_EMAIL=$(prompt_acme_email "$API_HOSTNAME")

print_success "API Hostname: ${API_HOSTNAME}"
print_success "ACME Email: ${ACME_EMAIL}"

# =============================================================================
# Step 3: Set up Doppler for each container
# =============================================================================
print_header "Step 3: Configure Doppler Secrets"

# Ensure config directory exists
ensure_config_dir

# Process each container
for container_name in $(get_container_names); do
    if ! setup_doppler_for_container "$container_name"; then
        print_error "Failed to configure Doppler for ${container_name}"
        exit 1
    fi
done

# =============================================================================
# Step 4: Validate Required Environment Variables
# =============================================================================
print_header "Step 4: Validating Configuration"

# Validate each container's required environment variables
validation_failed=false

for container_name in $(get_container_names); do
    display_name=$(get_container_display_name "$container_name")

    if ! validate_container_env "$container_name"; then
        if [ ${#MISSING_VARS[@]} -gt 0 ]; then
            print_error "Missing required environment variables for ${display_name}:"
            for var in "${MISSING_VARS[@]}"; do
                echo "  - ${var}"
            done
            validation_failed=true
        fi
    else
        print_success "${display_name}: All required environment variables present"
    fi
done

if [ "$validation_failed" = true ]; then
    print_info "Please add missing variables to your Doppler configuration and run setup again."
    exit 1
fi

# =============================================================================
# Step 5: Configure Docker Compose
# =============================================================================
print_header "Step 5: Setting up Docker Compose"

# Copy docker-compose.yml to config directory
cp docker-compose.yml "${CONFIG_DIR}/docker-compose.yml"
print_success "Docker Compose template copied"

# Create .env file for docker-compose variable substitution
# Extract PORT from each container's env file
print_info "Creating docker-compose environment file..."
echo "# Docker Compose environment variables (auto-generated)" > "${CONFIG_DIR}/.env"
for container_name in $(get_container_names); do
    env_file="${CONFIG_DIR}/.env.${container_name}"
    if [ -f "$env_file" ]; then
        port=$(grep "^PORT=" "$env_file" | cut -d'=' -f2 | tr -d '"')
        if [ -n "$port" ]; then
            # Convert container name to uppercase for env var (e.g., shapeshyft_api -> SHAPESHYFT_PORT)
            var_name=$(echo "${container_name}" | tr '[:lower:]' '[:upper:]' | sed 's/_API$//')_PORT
            echo "${var_name}=${port}" >> "${CONFIG_DIR}/.env"
            print_success "Set ${var_name}=${port}"
        fi
    fi
done

# Copy dynamic_conf
mkdir -p "${CONFIG_DIR}/dynamic_conf"
cp -r dynamic_conf/* "${CONFIG_DIR}/dynamic_conf/"
print_success "Traefik dynamic configuration copied"

# Update hostname placeholders
update_hostname_placeholders "$API_HOSTNAME" "${CONFIG_DIR}/docker-compose.yml"

# Configure Let's Encrypt
setup_letsencrypt "$API_HOSTNAME" "$ACME_EMAIL" "${CONFIG_DIR}/docker-compose.yml"

# Save deployment configuration
save_deployment_config "$API_HOSTNAME" "$ACME_EMAIL"

# =============================================================================
# Step 6: Start Services
# =============================================================================
print_header "Step 6: Starting Services"

DOCKER_COMPOSE=$(get_docker_compose_cmd)

print_info "Building and starting containers..."
cd "$CONFIG_DIR"

# Build images
$DOCKER_COMPOSE build

# Start services
$DOCKER_COMPOSE up -d

cd "$SCRIPT_DIR"

# Wait for services to start
print_info "Waiting for services to start..."
sleep 10

# =============================================================================
# Step 7: Verify Installation
# =============================================================================
print_header "Step 7: Verifying Installation"

cd "$CONFIG_DIR"

# Show container status
echo ""
echo "Container Status:"
$DOCKER_COMPOSE ps

cd "$SCRIPT_DIR"

# =============================================================================
# Setup Complete
# =============================================================================
print_header "Setup Complete!"

echo "Your services are now running."
echo ""
echo "Access Points:"
echo "  - ShapeShyft API: https://${API_HOSTNAME}/shapeshyft/api/v1/"
echo ""
echo "Useful Commands:"
echo "  - View logs:      cd ${CONFIG_DIR} && docker compose logs -f"
echo "  - Stop services:  cd ${CONFIG_DIR} && docker compose down"
echo "  - Restart:        cd ${CONFIG_DIR} && docker compose restart"
echo "  - Update:         ./upgrade.sh"
echo "  - Show versions:  ./versions.sh"
echo ""
echo "Configuration files are in: ${CONFIG_DIR}/"
echo ""

print_success "Setup completed successfully!"
