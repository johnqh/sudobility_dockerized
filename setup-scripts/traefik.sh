#!/bin/bash
# traefik.sh - Traefik and SSL configuration functions

# Setup Let's Encrypt configuration in docker-compose
setup_letsencrypt() {
    local hostname="$1"
    local email="$2"
    local compose_file="$3"

    print_info "Configuring Let's Encrypt for ${hostname}..."

    # Uncomment and set ACME email
    sed -i.bak "s|# - \"--certificatesresolvers.letsencrypt.acme.email=ACME_EMAIL\"|- \"--certificatesresolvers.letsencrypt.acme.email=${email}\"|g" "$compose_file"

    # Uncomment ACME storage
    sed -i.bak "s|# - \"--certificatesresolvers.letsencrypt.acme.storage=/data/acme.json\"|- \"--certificatesresolvers.letsencrypt.acme.storage=/data/acme.json\"|g" "$compose_file"

    # Clean up backup files
    rm -f "${compose_file}.bak"

    print_success "Let's Encrypt configured with email: ${email}"
}

# Replace hostname placeholders in docker-compose
update_hostname_placeholders() {
    local hostname="$1"
    local compose_file="$2"

    print_info "Updating hostname to ${hostname}..."

    # Replace API_HOSTNAME placeholder
    sed -i.bak "s|API_HOSTNAME|${hostname}|g" "$compose_file"

    # Clean up backup files
    rm -f "${compose_file}.bak"

    print_success "Hostname updated in docker-compose.yml"
}

# Save deployment configuration
save_deployment_config() {
    local hostname="$1"
    local email="$2"
    local config_file="${CONFIG_DIR}/.deployment-config"

    cat > "$config_file" << EOF
# Deployment configuration - saved by setup.sh
API_HOSTNAME=${hostname}
ACME_EMAIL=${email}
SETUP_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
EOF

    print_success "Deployment config saved to ${config_file}"
}

# Load deployment configuration
load_deployment_config() {
    local config_file="${CONFIG_DIR}/.deployment-config"

    if [ -f "$config_file" ]; then
        source "$config_file"
        return 0
    fi

    return 1
}

# Update Traefik dynamic configuration
update_traefik_dynamic_config() {
    local hostname="$1"
    local dynamic_file="dynamic_conf/dynamic.yml"
    local target_file="${CONFIG_DIR}/dynamic_conf/dynamic.yml"

    # Ensure directory exists
    mkdir -p "${CONFIG_DIR}/dynamic_conf"

    # Copy and update
    if [ -f "$dynamic_file" ]; then
        cp "$dynamic_file" "$target_file"
        # Update hostname if needed
        sed -i.bak "s|example.com|${hostname}|g" "$target_file"
        rm -f "${target_file}.bak"
    fi
}

# Setup HTTP to HTTPS redirect
setup_https_redirect() {
    local compose_file="$1"

    print_info "HTTP to HTTPS redirect is configured via Traefik entrypoint"
    # The redirect is already configured in the docker-compose.yml template
}

# Prompt for hostname configuration
# Note: All informational output goes to stderr so only the value goes to stdout
prompt_hostname() {
    echo "" >&2
    print_info "API Hostname Configuration" >&2
    echo "   Enter the hostname where the APIs will be accessible" >&2
    echo "   Example: api.example.com" >&2
    echo "" >&2

    local hostname=""
    while [ -z "$hostname" ]; do
        read -p "Enter API hostname: " hostname </dev/tty

        if [ -z "$hostname" ]; then
            print_error "Hostname cannot be empty" >&2
        fi
    done

    echo "$hostname"
}

# Prompt for ACME email
# Note: All informational output goes to stderr so only the value goes to stdout
prompt_acme_email() {
    local hostname="$1"
    local default_email="admin@${hostname#*.}"  # Extract domain from hostname

    echo "" >&2
    print_info "Let's Encrypt Email Configuration" >&2
    echo "   This email will receive certificate expiry notifications" >&2
    echo "" >&2

    read -p "Enter email for Let's Encrypt [${default_email}]: " email </dev/tty
    email="${email:-$default_email}"

    echo "$email"
}
