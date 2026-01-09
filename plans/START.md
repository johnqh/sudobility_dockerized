# Sudobility Dockerized - Installation Scripts Plan

## Overview

Create a modular Docker installation system for backend APIs, using `wildduck-dockerized` as reference. The system will support multiple containers with separate Doppler configurations for each.

## Project Structure

```
sudobility_dockerized/
├── setup.sh                    # Main setup script
├── upgrade.sh                  # Upgrade script
├── versions.sh                 # Version reporting
├── docker-compose.yml          # Main compose file (template)
├── .env.example                # Environment template
├── default-config/
│   └── shapeshyft_api/
│       └── .env.defaults       # Non-sensitive defaults
├── setup-scripts/
│   ├── common.sh               # Shared utilities
│   ├── doppler.sh              # Doppler integration functions
│   └── traefik.sh              # Traefik/SSL setup
├── dynamic_conf/
│   └── dynamic.yml             # Traefik TLS configuration
├── config-generated/           # Created at runtime
│   ├── docker-compose.yml      # Customized compose
│   ├── .env.shapeshyft_api     # Per-container env files
│   └── .deployment-config      # Saved hostnames
└── plans/
    └── START.md                # This file
```

## Key Design Decisions

### 1. Modular Container Support
- Each container has its own:
  - Default config in `default-config/<container_name>/`
  - Doppler token file: `.doppler-token-<container_name>`
  - Environment file: `config-generated/.env.<container_name>`
- Adding new containers requires:
  1. Add default config directory
  2. Add service to `docker-compose.yml`
  3. Add to container list in scripts

### 2. Doppler Integration (Per-Container)
- Separate Doppler service tokens for each container
- Token files: `.doppler-token-shapeshyft_api`, `.doppler-token-<future_container>`
- Merge strategy: Doppler values override defaults

### 3. Environment Variables

**shapeshyft_api - Required (from Doppler):**
- `DATABASE_URL` - PostgreSQL connection string
- `ENCRYPTION_KEY` - 64-char hex (AES-256 key)
- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`

**shapeshyft_api - Optional (from Doppler):**
- `REVENUECAT_API_KEY` - Rate limiting (graceful degradation if missing)

**shapeshyft_api - Defaults (non-sensitive):**
- `PORT=3000`
- `NODE_ENV=production`

### 4. Traefik Routing
- Let's Encrypt for SSL certificates
- Path-based routing for multiple APIs on same domain
- Example routes:
  - `https://API_HOSTNAME/shapeshyft/*` → shapeshyft_api:3000
  - Future: `https://API_HOSTNAME/other/*` → other_api:port

### 5. No Local Database
- DATABASE_URL must point to external PostgreSQL
- No PostgreSQL container in docker-compose

---

## Implementation Steps

### Step 1: Create Directory Structure
Create folders:
- `default-config/shapeshyft_api/`
- `setup-scripts/`
- `dynamic_conf/`
- `plans/`

### Step 2: Create Helper Scripts

#### `setup-scripts/common.sh`
- Color output functions (print_success, print_error, print_warning)
- Utility functions (command_exists, require_command)
- Container list management

#### `setup-scripts/doppler.sh`
Functions:
- `fetch_doppler_secrets(container_name)` - Download secrets for a container
- `validate_doppler_token(token)` - Validate token with API
- `merge_env_files(defaults_file, doppler_file, output_file)` - Merge with Doppler precedence
- `prompt_doppler_token(container_name)` - Interactive token prompt

#### `setup-scripts/traefik.sh`
Functions:
- `setup_letsencrypt(hostname, email)` - Configure Let's Encrypt
- `update_traefik_config(hostname)` - Update dynamic.yml

### Step 3: Create Default Configurations

#### `default-config/shapeshyft_api/.env.defaults`
```bash
# Non-sensitive defaults for shapeshyft_api
PORT=3000
NODE_ENV=production

# Sensitive values - MUST be set via Doppler
# DATABASE_URL=
# ENCRYPTION_KEY=
# FIREBASE_PROJECT_ID=
# FIREBASE_CLIENT_EMAIL=
# FIREBASE_PRIVATE_KEY=
# REVENUECAT_API_KEY=
```

### Step 4: Create docker-compose.yml Template

```yaml
services:
  traefik:
    image: traefik:v3.0
    command:
      - "--api.dashboard=false"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      # Uncommented during setup:
      # - "--certificatesresolvers.letsencrypt.acme.email=ACME_EMAIL"
      # - "--certificatesresolvers.letsencrypt.acme.storage=/data/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_data:/data
      - ./dynamic_conf:/etc/traefik/dynamic_conf:ro
    networks:
      - sudobility_network

  shapeshyft_api:
    build:
      context: ../shapeshyft_api
    env_file:
      - .env.shapeshyft_api
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.shapeshyft-api.rule=Host(`API_HOSTNAME`) && PathPrefix(`/shapeshyft`)"
      - "traefik.http.routers.shapeshyft-api.entrypoints=websecure"
      - "traefik.http.routers.shapeshyft-api.tls.certresolver=letsencrypt"
      - "traefik.http.middlewares.shapeshyft-strip.stripprefix.prefixes=/shapeshyft"
      - "traefik.http.routers.shapeshyft-api.middlewares=shapeshyft-strip"
      - "traefik.http.services.shapeshyft-api.loadbalancer.server.port=3000"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/"]
      interval: 30s
      timeout: 15s
      retries: 3
      start_period: 30s
    networks:
      - sudobility_network
    restart: unless-stopped

volumes:
  traefik_data:

networks:
  sudobility_network:
    driver: bridge
```

### Step 5: Create setup.sh

Main flow:
1. Source helper scripts
2. Check prerequisites (docker, curl, jq)
3. Prompt for API_HOSTNAME
4. Prompt for ACME email (for Let's Encrypt)
5. **For each container** (modular loop):
   - Check for saved Doppler token
   - Prompt for Doppler token if not found
   - Fetch secrets from Doppler
   - Merge with defaults
   - Validate required variables
6. Copy docker-compose.yml to config-generated/
7. Replace hostname placeholders
8. Enable Let's Encrypt configuration
9. Start services with `docker compose up -d`
10. Save deployment config

Key code patterns (from wildduck-dockerized):
```bash
# Modular container handling
CONTAINERS=("shapeshyft_api")  # Add more containers here

for container in "${CONTAINERS[@]}"; do
    fetch_doppler_secrets "$container"
done
```

### Step 6: Create upgrade.sh

Main flow:
1. Detect config directory
2. Load saved deployment config
3. **For each container**:
   - Update Doppler secrets (if token exists)
   - Merge with existing env
4. Backup and update docker-compose.yml
5. Apply hostname replacements
6. Pull latest images
7. Recreate containers

### Step 7: Create versions.sh

Display:
- Docker and Docker Compose versions
- For each container:
  - Image version
  - Container status
  - App version (via container exec if possible)

---

## Files to Create

| File | Purpose |
|------|---------|
| `setup.sh` | Main installation script |
| `upgrade.sh` | Upgrade/update script |
| `versions.sh` | Version information display |
| `docker-compose.yml` | Docker Compose template |
| `.env.example` | Environment variable template |
| `setup-scripts/common.sh` | Shared utility functions |
| `setup-scripts/doppler.sh` | Doppler integration |
| `setup-scripts/traefik.sh` | Traefik/SSL setup |
| `default-config/shapeshyft_api/.env.defaults` | Default env values |
| `dynamic_conf/dynamic.yml` | Traefik TLS config |
| `.gitignore` | Ignore sensitive files |

---

## Adding Future Containers

To add a new container (e.g., `another_api`):

1. Create `default-config/another_api/.env.defaults`
2. Add service to `docker-compose.yml` with Traefik labels
3. Add to CONTAINERS array in scripts:
   ```bash
   CONTAINERS=("shapeshyft_api" "another_api")
   ```
4. Create Doppler project/config for the new container
5. Run `setup.sh` (will prompt for new container's Doppler token)

---

## Security Considerations

- `.doppler-token-*` files: chmod 600 (owner read/write only)
- `.env.*` files in config-generated: chmod 600
- Never commit tokens or secrets to git

---

## .gitignore Entries

```
config-generated/
.doppler-token-*
.env
.env.*
!.env.example
acme.json
*.log
```
