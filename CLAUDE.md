# CLAUDE.md - AI Development Context

## Project Overview

**Sudobility Dockerized** is a flexible Docker deployment system for managing multiple backend services. It provides automated add, upgrade, and remove scripts with Traefik reverse proxy, automatic SSL via Let's Encrypt, and Doppler secrets management.

## Architecture

```
                           Internet
                              │
        ┌─────────────────────┼─────────────────────┐
        │ api.shapeshyft.ai   │   api.other.com    │
        ▼                     ▼                     ▼
┌─────────────────────────────────────────────────────────────┐
│                    Traefik (Reverse Proxy)                   │
│  - SSL termination (Let's Encrypt ACME)                     │
│  - Host-based routing (no path prefix)                      │
│  - HTTP → HTTPS redirect                                     │
│  - Docker label-based discovery                              │
└─────────────────────────────────────────────────────────────┘
                              │
        ┌─────────────────────┴─────────────────────┐
        │ Host: api.shapeshyft.ai                   │ Host: api.other.com
        ▼                                           ▼
┌───────────────────┐                       ┌───────────────────┐
│  shapeshyft_api   │                       │    other_api      │
│  (Port 3000)      │                       │    (Port 8080)    │
└───────────────────┘                       └───────────────────┘
```

## Key Files

| File | Purpose |
|------|---------|
| `add.sh` | Add a new service interactively |
| `upgrade.sh` | Upgrade an existing service |
| `remove.sh` | Remove a service with confirmation |
| `status.sh` | Display status of all services |
| `setup-scripts/common.sh` | Shared utilities, Traefik, Doppler, service management |

## Directory Structure

```
sudobility_dockerized/
├── add.sh
├── upgrade.sh
├── remove.sh
├── status.sh
├── setup-scripts/
│   └── common.sh
└── config-generated/           # Auto-generated, gitignored
    ├── traefik/
    │   └── docker-compose.yml
    ├── services/
    │   └── <service_name>/
    │       ├── docker-compose.yml
    │       ├── .env
    │       └── .service.conf
    └── .doppler-tokens/
        └── <service_name>
```

## Service Management Flow

### Adding a Service

```bash
./add.sh
```

1. Ensures Traefik is running (installs if needed)
2. Prompts for: service name, hostname, Docker image, health endpoint (optional)
3. Prompts for Doppler service token, validates it
4. Fetches secrets from Doppler, requires `PORT` env var
5. Creates service directory with docker-compose.yml and .env
6. Starts the service container

### Upgrading a Service

```bash
./upgrade.sh
```

1. Lists all services with status
2. User selects a service
3. Fetches latest secrets from Doppler
4. Updates PORT in config if changed
5. Pulls latest Docker image
6. Restarts the service

### Removing a Service

```bash
./remove.sh
```

1. Lists all services with status
2. User selects a service
3. Confirms removal (yes/no + type service name)
4. Stops and removes container
5. Removes Doppler token and service directory

## Traefik Routing

Each service gets these Docker labels (auto-generated):

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.<name>.rule=Host(`<hostname>`)"
  - "traefik.http.routers.<name>.entrypoints=websecure"
  - "traefik.http.routers.<name>.tls.certresolver=letsencrypt"
  - "traefik.http.services.<name>.loadbalancer.server.port=<port>"
```

**Key points:**
- Host-based routing (no PathPrefix) - services accessible at hostname root
- Each service has unique router name preventing conflicts
- SSL certificates automatically provisioned per hostname
- All services share `sudobility_network` Docker network

## Doppler Integration

```
1. User provides Doppler service token for each service
2. Token validated via Doppler API
3. Secrets fetched as .env format
4. PORT variable required (determines Traefik port routing)
5. Token saved securely for upgrade operations
```

Key API endpoint:
```
https://api.doppler.com/v3/configs/config/secrets/download?format=env
```

## Common Tasks

### Add a new service

```bash
./add.sh
# Follow prompts for:
#   - Service name (e.g., my_api)
#   - Hostname (e.g., api.example.com)
#   - Docker image (e.g., docker.io/user/image:latest)
#   - Health endpoint (e.g., /health) - optional
#   - Doppler service token
```

### Check status

```bash
./status.sh
```

### View logs

```bash
cd config-generated/services/<name>
docker compose logs -f
```

### Manually restart a service

```bash
cd config-generated/services/<name>
docker compose restart
```

## Environment Variables

Each service must have these in Doppler:

| Variable | Required | Description |
|----------|----------|-------------|
| `PORT` | Yes | Port the service listens on |
| Others | Varies | Service-specific secrets |

## Code Conventions

- **Bash scripts**: Use `set -e` for fail-fast, source common.sh at top
- **Output**: Use `print_success`, `print_error`, `print_warning`, `print_info`
- **Docker Compose**: Use `$(get_docker_compose_cmd)` for v1/v2 compatibility
- **Arrays**: Use `read_services_array` for bash 3.x (macOS) compatibility

## File Permissions

- `.doppler-tokens/*`: 700 directory, 600 files
- `.env`: 600
- `.service.conf`: 600
- Scripts: 755

## Dependencies

- **Docker**: Container runtime
- **Docker Compose v2**: Orchestration (falls back to v1)
- **curl**: Doppler API calls
- **bash**: Script execution (3.x compatible)

## Gotchas

1. **Network order**: Traefik creates `sudobility_network`; services use it as external
2. **Let's Encrypt**: HTTP challenge requires port 80 accessible from internet
3. **Hostname DNS**: Must point to server IP before SSL works
4. **Service names**: Must be unique across all services (used as container name)
5. **macOS**: Scripts use bash 3.x compatible patterns (no mapfile)

## Testing

```bash
# Check syntax
bash -n add.sh

# View all services
./status.sh

# Check Traefik logs
cd config-generated/traefik && docker compose logs -f
```
