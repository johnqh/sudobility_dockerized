#!/bin/bash
# upgrade.sh - Upgrade script for Sudobility Dockerized
# Usage: ./upgrade.sh

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source helper scripts
source "./setup-scripts/common.sh"
source "./setup-scripts/doppler.sh"
source "./setup-scripts/traefik.sh"

# =============================================================================
# Find Configuration Directory
# =============================================================================

find_config_dir() {
    if [ -d "./config-generated" ] && [ -f "./config-generated/docker-compose.yml" ]; then
        echo "./config-generated"
    else
        echo ""
    fi
}

# =============================================================================
# Main Upgrade Flow
# =============================================================================

print_header "Sudobility Dockerized Upgrade"

# Find existing configuration
CONFIG_DIR=$(find_config_dir)

if [ -z "$CONFIG_DIR" ]; then
    print_error "No existing configuration found."
    print_info "Run ./setup.sh first to create initial configuration."
    exit 1
fi

print_success "Found configuration in: ${CONFIG_DIR}"

# Load deployment config
if load_deployment_config; then
    print_success "Loaded deployment config: API_HOSTNAME=${API_HOSTNAME}"
else
    print_warning "Could not load deployment config, will extract from docker-compose.yml"

    # Try to extract hostname from docker-compose.yml
    API_HOSTNAME=$(grep -oP "Host\(\`\K[^\`]+" "${CONFIG_DIR}/docker-compose.yml" | head -1 || echo "")

    if [ -z "$API_HOSTNAME" ]; then
        print_error "Could not determine API hostname"
        exit 1
    fi
fi

echo ""
echo "This script will:"
echo "  1. Update Doppler secrets"
echo "  2. Update docker-compose.yml"
echo "  3. Rebuild and restart containers"
echo ""

if ! prompt_yes_no "Continue with upgrade?" "y"; then
    print_info "Upgrade cancelled."
    exit 0
fi

# =============================================================================
# Step 1: Update Doppler Secrets
# =============================================================================
print_header "Step 1: Updating Doppler Secrets"

for container_name in $(get_container_names); do
    update_doppler_secrets "$container_name"
done

# =============================================================================
# Step 2: Update Docker Compose
# =============================================================================
print_header "Step 2: Updating Docker Compose"

# Backup current docker-compose.yml
cp "${CONFIG_DIR}/docker-compose.yml" "${CONFIG_DIR}/docker-compose.yml.backup"
print_success "Backed up docker-compose.yml"

# Copy new docker-compose.yml
cp docker-compose.yml "${CONFIG_DIR}/docker-compose.yml"
print_success "Copied new docker-compose.yml template"

# Update hostname placeholders
update_hostname_placeholders "$API_HOSTNAME" "${CONFIG_DIR}/docker-compose.yml"

# Restore Let's Encrypt settings if they were enabled
if grep -q "certificatesresolvers.letsencrypt.acme.email" "${CONFIG_DIR}/docker-compose.yml.backup" 2>/dev/null && \
   ! grep -q "# - \"--certificatesresolvers.letsencrypt.acme.email" "${CONFIG_DIR}/docker-compose.yml.backup" 2>/dev/null; then

    # Extract email from backup
    ACME_EMAIL=$(grep -oP 'acme.email=\K[^"]+' "${CONFIG_DIR}/docker-compose.yml.backup" || echo "")

    if [ -n "$ACME_EMAIL" ]; then
        setup_letsencrypt "$API_HOSTNAME" "$ACME_EMAIL" "${CONFIG_DIR}/docker-compose.yml"
        print_success "Restored Let's Encrypt configuration"
    fi
fi

# Update dynamic config
if [ -d "dynamic_conf" ]; then
    cp -r dynamic_conf/* "${CONFIG_DIR}/dynamic_conf/"
    print_success "Updated Traefik dynamic configuration"
fi

# =============================================================================
# Step 3: Rebuild and Restart Containers
# =============================================================================
print_header "Step 3: Rebuilding and Restarting Containers"

DOCKER_COMPOSE=$(get_docker_compose_cmd)

cd "$CONFIG_DIR"

# Stop containers
print_info "Stopping containers..."
$DOCKER_COMPOSE down

# Pull latest base images
print_info "Pulling latest images..."
$DOCKER_COMPOSE pull traefik || true

# Rebuild application images
print_info "Rebuilding application images..."
$DOCKER_COMPOSE build --no-cache

# Start containers
print_info "Starting containers..."
$DOCKER_COMPOSE up -d

cd "$SCRIPT_DIR"

# Wait for services
print_info "Waiting for services to start..."
sleep 10

# =============================================================================
# Step 4: Verify Upgrade
# =============================================================================
print_header "Step 4: Verifying Upgrade"

cd "$CONFIG_DIR"

echo ""
echo "Container Status:"
$DOCKER_COMPOSE ps

echo ""
echo "Image Versions:"
$DOCKER_COMPOSE images

cd "$SCRIPT_DIR"

# =============================================================================
# Upgrade Complete
# =============================================================================
print_header "Upgrade Complete!"

echo "Your services have been updated."
echo ""
echo "If you encounter issues, you can restore the previous docker-compose.yml:"
echo "  cp ${CONFIG_DIR}/docker-compose.yml.backup ${CONFIG_DIR}/docker-compose.yml"
echo ""

print_success "Upgrade completed successfully!"
