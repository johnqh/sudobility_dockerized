#!/bin/bash
# doppler.sh - Doppler secrets management functions

# Doppler API endpoint
DOPPLER_API_URL="https://api.doppler.com/v3/configs/config/secrets/download"

# Get the token file path for a container
get_doppler_token_file() {
    local container_name="$1"
    echo ".doppler-token-${container_name}"
}

# Get the env file path for a container
get_container_env_file() {
    local container_name="$1"
    echo "${CONFIG_DIR}/.env.${container_name}"
}

# Validate a Doppler token
validate_doppler_token() {
    local token="$1"

    if [ -z "$token" ]; then
        return 1
    fi

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -u "${token}:" \
        "${DOPPLER_API_URL}?format=env")

    [ "$http_code" -eq 200 ]
}

# Prompt for Doppler token for a container
prompt_doppler_token() {
    local container_name="$1"
    local display_name
    display_name=$(get_container_display_name "$container_name")

    echo ""
    print_info "Doppler configuration for ${display_name}"
    echo "   Create a service token in Doppler for the ${container_name} config"
    echo "   Doppler Dashboard → Project → ${container_name} → Access → Service Tokens"
    echo ""

    local token=""
    local valid=false

    while [ "$valid" = false ]; do
        read -p "Enter Doppler service token for ${container_name}: " token

        if [ -z "$token" ]; then
            print_error "Token cannot be empty"
            continue
        fi

        print_info "Validating token..."

        if validate_doppler_token "$token"; then
            print_success "Token validated successfully"
            valid=true
        else
            print_error "Invalid token. Please check and try again."
        fi
    done

    echo "$token"
}

# Load or prompt for Doppler token
get_doppler_token() {
    local container_name="$1"
    local token_file
    token_file=$(get_doppler_token_file "$container_name")

    local token=""

    # Check for saved token
    if [ -f "$token_file" ]; then
        token=$(cat "$token_file")
        print_info "Found saved Doppler token for ${container_name}, validating..."

        if validate_doppler_token "$token"; then
            print_success "Saved token is valid"
            echo "$token"
            return 0
        else
            print_warning "Saved token is invalid or expired"
            rm -f "$token_file"
        fi
    fi

    # Prompt for new token
    token=$(prompt_doppler_token "$container_name")

    # Save the token
    echo "$token" > "$token_file"
    secure_file "$token_file"
    print_success "Token saved to ${token_file}"

    echo "$token"
}

# Fetch secrets from Doppler for a container
fetch_doppler_secrets() {
    local container_name="$1"
    local token="$2"
    local output_file="$3"

    print_info "Fetching secrets from Doppler for ${container_name}..."

    local http_code
    http_code=$(curl -s -w "%{http_code}" \
        -u "${token}:" \
        -o "$output_file" \
        "${DOPPLER_API_URL}?format=env")

    if [ "$http_code" -eq 200 ]; then
        print_success "Secrets downloaded successfully"
        return 0
    else
        print_error "Failed to fetch secrets (HTTP ${http_code})"
        return 1
    fi
}

# Merge default env with Doppler secrets (Doppler takes precedence)
merge_env_files() {
    local defaults_file="$1"
    local doppler_file="$2"
    local output_file="$3"

    # Create temp file
    local temp_file="${output_file}.tmp"

    # Start with Doppler values (highest priority)
    if [ -f "$doppler_file" ]; then
        cat "$doppler_file" > "$temp_file"
    else
        touch "$temp_file"
    fi

    # Add defaults that aren't in Doppler
    if [ -f "$defaults_file" ]; then
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip comments and empty lines
            if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
                continue
            fi

            # Extract key
            local key="${line%%=*}"

            # Only add if not already present
            if ! grep -q "^${key}=" "$temp_file" 2>/dev/null; then
                echo "$line" >> "$temp_file"
            fi
        done < "$defaults_file"
    fi

    # Move to final location
    mv "$temp_file" "$output_file"
    secure_file "$output_file"

    print_success "Environment file created: ${output_file}"
}

# Setup Doppler for a container (main function)
setup_doppler_for_container() {
    local container_name="$1"
    local display_name
    display_name=$(get_container_display_name "$container_name")

    print_header "Configuring Doppler for ${display_name}"

    # Get or prompt for token
    local token
    token=$(get_doppler_token "$container_name")

    # Fetch secrets
    local doppler_env_file=".env.doppler.${container_name}"
    if ! fetch_doppler_secrets "$container_name" "$token" "$doppler_env_file"; then
        print_error "Failed to fetch Doppler secrets for ${container_name}"
        return 1
    fi

    # Get defaults file
    local defaults_file="default-config/${container_name}/.env.defaults"

    # Merge files
    local output_file
    output_file=$(get_container_env_file "$container_name")
    merge_env_files "$defaults_file" "$doppler_env_file" "$output_file"

    # Clean up temp doppler file
    rm -f "$doppler_env_file"

    return 0
}

# Update Doppler secrets for a container (for upgrade.sh)
update_doppler_secrets() {
    local container_name="$1"
    local token_file
    token_file=$(get_doppler_token_file "$container_name")

    # Check for saved token
    if [ ! -f "$token_file" ]; then
        print_warning "No saved Doppler token for ${container_name}, skipping update"
        return 0
    fi

    local token
    token=$(cat "$token_file")

    if ! validate_doppler_token "$token"; then
        print_warning "Saved token for ${container_name} is invalid, skipping update"
        return 0
    fi

    print_info "Updating secrets from Doppler for ${container_name}..."

    # Fetch new secrets
    local doppler_env_file=".env.doppler.${container_name}"
    if ! fetch_doppler_secrets "$container_name" "$token" "$doppler_env_file"; then
        print_warning "Failed to update Doppler secrets for ${container_name}"
        return 1
    fi

    # Get current env file
    local current_env_file
    current_env_file=$(get_container_env_file "$container_name")

    # Backup current
    if [ -f "$current_env_file" ]; then
        cp "$current_env_file" "${current_env_file}.backup"
    fi

    # Get defaults file
    local defaults_file="default-config/${container_name}/.env.defaults"

    # Merge (Doppler overrides existing)
    merge_env_files "$defaults_file" "$doppler_env_file" "$current_env_file"

    # Clean up
    rm -f "$doppler_env_file"

    print_success "Secrets updated for ${container_name}"
    return 0
}
