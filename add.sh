#!/bin/bash
# add.sh - Add a new service to the server
# Usage: ./add.sh

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source helper scripts
source "./setup-scripts/common.sh"

# =============================================================================
# Main Add Flow
# =============================================================================

print_header "Add New Service"

echo "This script will add a new Docker service with:"
echo "  - Automatic SSL certificate via Let's Encrypt"
echo "  - Environment variables from Doppler"
echo "  - Traefik routing by hostname"
echo ""

# =============================================================================
# Step 1: Ensure Traefik is running
# =============================================================================
print_header "Step 1: Checking Traefik"

if ! install_traefik; then
    print_error "Failed to set up Traefik. Cannot continue."
    exit 1
fi

# =============================================================================
# Step 2: Get service details
# =============================================================================
print_header "Step 2: Service Configuration"

# Service name
echo "Enter a name for this service (used for container name, e.g., 'shapeshyft_api'):"
read -p "Service name: " SERVICE_NAME

if [ -z "$SERVICE_NAME" ]; then
    print_error "Service name cannot be empty"
    exit 1
fi

# Validate service name (alphanumeric and underscores only)
if [[ ! "$SERVICE_NAME" =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then
    print_error "Service name must start with a letter and contain only letters, numbers, and underscores"
    exit 1
fi

# Check if service already exists
if service_exists "$SERVICE_NAME"; then
    print_error "Service '$SERVICE_NAME' already exists. Use upgrade.sh to update it."
    exit 1
fi

# Hostname
echo ""
echo "Enter the public hostname for this service (e.g., 'api.example.com'):"
read -p "Hostname: " HOSTNAME

if [ -z "$HOSTNAME" ]; then
    print_error "Hostname cannot be empty"
    exit 1
fi

# Docker image
echo ""
echo "Enter the Docker image (e.g., 'docker.io/username/image:latest'):"
read -p "Docker image: " DOCKER_IMAGE

if [ -z "$DOCKER_IMAGE" ]; then
    print_error "Docker image cannot be empty"
    exit 1
fi

# Health endpoint (optional)
echo ""
echo "Health check configuration:"
echo "  1) Use /health endpoint"
echo "  2) Skip health check"
read -p "Select [1-2]: " HEALTH_CHOICE

case "$HEALTH_CHOICE" in
    1) HEALTH_ENDPOINT="/health" ;;
    *) HEALTH_ENDPOINT="" ;;
esac

# =============================================================================
# Step 3: Configure Doppler
# =============================================================================
print_header "Step 3: Doppler Configuration"

echo "Enter the Doppler service token for this service."
echo "Create one at: Doppler Dashboard → Project → Config → Access → Service Tokens"
echo ""

DOPPLER_TOKEN=""
while true; do
    read -sp "Doppler service token: " DOPPLER_TOKEN
    echo ""

    if [ -z "$DOPPLER_TOKEN" ]; then
        print_error "Token cannot be empty"
        continue
    fi

    print_info "Validating token..."
    if validate_doppler_token "$DOPPLER_TOKEN"; then
        print_success "Token validated successfully"
        break
    else
        print_error "Invalid token. Please check and try again."
    fi
done

# =============================================================================
# Step 4: Fetch and validate environment
# =============================================================================
print_header "Step 4: Fetching Environment Variables"

ensure_dirs

SERVICE_DIR="${SERVICES_DIR}/${SERVICE_NAME}"
mkdir -p "$SERVICE_DIR"

ENV_FILE="${SERVICE_DIR}/.env"
print_info "Fetching secrets from Doppler..."

HTTP_CODE=$(fetch_doppler_secrets "$DOPPLER_TOKEN" "$ENV_FILE")

if [ "$HTTP_CODE" != "200" ]; then
    print_error "Failed to fetch secrets from Doppler (HTTP $HTTP_CODE)"
    rm -rf "$SERVICE_DIR"
    exit 1
fi

secure_file "$ENV_FILE"
print_success "Environment variables saved"

# Check for PORT variable
PORT=$(grep "^PORT=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'")

if [ -z "$PORT" ]; then
    print_error "PORT environment variable not found in Doppler secrets"
    print_info "Please add a PORT variable to your Doppler configuration"
    rm -rf "$SERVICE_DIR"
    exit 1
fi

print_success "Found PORT=$PORT"

# =============================================================================
# Step 5: Create service configuration
# =============================================================================
print_header "Step 5: Creating Service"

# Save service config
cat > "${SERVICE_DIR}/.service.conf" << EOF
# Service configuration - created by add.sh
SERVICE_NAME=${SERVICE_NAME}
HOSTNAME=${HOSTNAME}
DOCKER_IMAGE=${DOCKER_IMAGE}
PORT=${PORT}
HEALTH_ENDPOINT=${HEALTH_ENDPOINT}
CREATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

secure_file "${SERVICE_DIR}/.service.conf"

# Save Doppler token
save_doppler_token "$SERVICE_NAME" "$DOPPLER_TOKEN"

# Create docker-compose.yml for the service
# Build healthcheck section conditionally
HEALTHCHECK_SECTION=""
if [ -n "$HEALTH_ENDPOINT" ]; then
    HEALTHCHECK_SECTION="    healthcheck:
      test: [\"CMD\", \"curl\", \"-f\", \"http://localhost:${PORT}${HEALTH_ENDPOINT}\"]
      interval: 30s
      timeout: 15s
      retries: 3
      start_period: 30s"
fi

cat > "${SERVICE_DIR}/docker-compose.yml" << EOF
# ${SERVICE_NAME} - Generated by add.sh
services:
  ${SERVICE_NAME}:
    image: ${DOCKER_IMAGE}
    container_name: ${SERVICE_NAME}
    restart: unless-stopped
    env_file:
      - .env
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${SERVICE_NAME}.rule=Host(\`${HOSTNAME}\`)"
      - "traefik.http.routers.${SERVICE_NAME}.entrypoints=websecure"
      - "traefik.http.routers.${SERVICE_NAME}.tls.certresolver=letsencrypt"
      - "traefik.http.services.${SERVICE_NAME}.loadbalancer.server.port=${PORT}"
${HEALTHCHECK_SECTION}
    networks:
      - sudobility_network
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

networks:
  sudobility_network:
    external: true
EOF

print_success "Service configuration created"

# =============================================================================
# Step 6: Start the service
# =============================================================================
print_header "Step 6: Starting Service"

service_pull "$SERVICE_NAME"
service_start "$SERVICE_NAME"

# =============================================================================
# Step 7: Verify
# =============================================================================
print_header "Step 7: Verification"

service_wait_and_verify "$SERVICE_NAME"
display_service_info "$SERVICE_NAME" name hostname image version port

echo "Access your service at:"
echo "  https://${HOSTNAME}/"
echo ""
echo "Note: SSL certificate may take a minute to be issued."
echo ""
echo "Useful commands:"
echo "  View logs:    cd ${SERVICE_DIR} && docker compose logs -f"
echo "  Restart:      cd ${SERVICE_DIR} && docker compose restart"
echo "  Stop:         cd ${SERVICE_DIR} && docker compose down"
echo ""

print_success "Service '$SERVICE_NAME' added successfully!"
