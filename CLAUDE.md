# CLAUDE.md - AI Development Context

## Project Overview

**Sudobility Dockerized** is a Docker deployment system for Sudobility backend APIs. It provides automated setup, upgrade, and management scripts with Traefik reverse proxy and Doppler secrets management.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└─────────────────────────┬───────────────────────────────────┘
                          │ HTTPS (443)
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    Traefik (Reverse Proxy)                   │
│  - SSL termination (Let's Encrypt)                          │
│  - Path-based routing                                        │
│  - HTTP → HTTPS redirect                                     │
└─────────────────────────┬───────────────────────────────────┘
                          │
        ┌─────────────────┴─────────────────┐
        │ /shapeshyft/*                     │ /future/*
        ▼                                   ▼
┌───────────────────┐               ┌───────────────────┐
│  shapeshyft_api   │               │   future_api      │
│  (Port 3000)      │               │   (Port 300X)     │
└───────────────────┘               └───────────────────┘
```

## Key Files

| File | Purpose |
|------|---------|
| `setup.sh` | Main installation script - runs once for initial setup |
| `upgrade.sh` | Updates existing installation with new code/secrets |
| `versions.sh` | Displays version and status information |
| `docker-compose.yml` | Template with placeholder `API_HOSTNAME` |
| `setup-scripts/common.sh` | Shared utilities, colors, container registry |
| `setup-scripts/doppler.sh` | Doppler API integration for secrets |
| `setup-scripts/traefik.sh` | Traefik and Let's Encrypt configuration |
| `default-config/<container>/.env.defaults` | Non-sensitive default values |

## Container Registry

New containers are registered in `setup-scripts/common.sh`:

```bash
CONTAINERS=(
    "container_name:Display Name:port"
)
```

This array drives all script behavior - setup, upgrade, and versions.

## Doppler Integration Pattern

```
1. Check for saved token: .doppler-token-<container>
2. If not found, prompt user
3. Validate token via Doppler API
4. Download secrets as .env format
5. Merge with defaults (Doppler takes precedence)
6. Output to config-generated/.env.<container>
```

Key functions in `setup-scripts/doppler.sh`:
- `get_doppler_token()` - Load or prompt for token
- `fetch_doppler_secrets()` - Download from Doppler API
- `merge_env_files()` - Combine defaults + secrets
- `setup_doppler_for_container()` - Full setup flow

## Traefik Routing Pattern

Each container needs these labels in `docker-compose.yml`:

```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.<name>.rule=Host(`API_HOSTNAME`) && PathPrefix(`/<path>`)"
  - "traefik.http.routers.<name>.entrypoints=websecure"
  - "traefik.http.routers.<name>.tls.certresolver=letsencrypt"
  - "traefik.http.middlewares.<name>-strip.stripprefix.prefixes=/<path>"
  - "traefik.http.routers.<name>.middlewares=<name>-strip"
  - "traefik.http.services.<name>.loadbalancer.server.port=<port>"
```

`API_HOSTNAME` is replaced during setup.

## Common Tasks

### Add a new container

1. Create `default-config/<name>/.env.defaults`
2. Add to `CONTAINERS` array in `setup-scripts/common.sh`
3. Add service block in `docker-compose.yml`
4. Create Doppler config with secrets
5. Run `./setup.sh`

### Modify Doppler integration

Edit `setup-scripts/doppler.sh`. Key API endpoint:
```
https://api.doppler.com/v3/configs/config/secrets/download?format=env
```
Auth: Basic auth with token as username, empty password.

### Change routing paths

Edit Traefik labels in `docker-compose.yml`. The `PathPrefix` rule determines the URL path, and `stripprefix` middleware removes it before forwarding.

### Add environment variables

1. Non-sensitive: Add to `default-config/<container>/.env.defaults`
2. Sensitive: Add to Doppler, will be fetched automatically

## Code Conventions

- **Bash scripts**: Use `set -e` for fail-fast, source helpers at top
- **Functions**: Defined in setup-scripts/, prefixed by domain (e.g., `setup_doppler_*`)
- **Output**: Use `print_success`, `print_error`, `print_warning`, `print_info` from common.sh
- **Config paths**: Use `$CONFIG_DIR` variable (default: `config-generated`)
- **Docker Compose**: Use `$(get_docker_compose_cmd)` for v1/v2 compatibility

## File Permissions

- `.doppler-token-*`: 600 (owner read/write only)
- `.env.*` in config-generated: 600
- Scripts: 755 (executable)

## Dependencies

- **Docker**: Container runtime
- **Docker Compose v2**: Orchestration (falls back to v1)
- **curl**: Doppler API calls
- **jq**: JSON parsing (versions.sh)
- **sed**: Text replacement in configs

## Testing Changes

```bash
# Dry run - check syntax
bash -n setup.sh

# Test with fresh config
rm -rf config-generated
./setup.sh

# Check container status
./versions.sh

# View logs
cd config-generated && docker compose logs -f
```

## Related Projects

- `../shapeshyft_api` - ShapeShyft API source code (Bun/Hono)
- Reference: `~/0xmail/wildduck-dockerized` - Original pattern source

## Environment Variables Reference

### shapeshyft_api

| Variable | Type | Required | Source |
|----------|------|----------|--------|
| `PORT` | int | No | defaults (3000) |
| `NODE_ENV` | string | No | defaults (production) |
| `DATABASE_URL` | string | Yes | Doppler |
| `ENCRYPTION_KEY` | string | Yes | Doppler (64 hex chars) |
| `FIREBASE_PROJECT_ID` | string | Yes | Doppler |
| `FIREBASE_CLIENT_EMAIL` | string | Yes | Doppler |
| `FIREBASE_PRIVATE_KEY` | string | Yes | Doppler |
| `REVENUECAT_API_KEY` | string | No | Doppler |

## Gotchas

1. **Hostname placeholder**: `API_HOSTNAME` in docker-compose.yml is literal text, replaced by sed during setup
2. **Let's Encrypt**: Commented lines in Traefik command are uncommented during setup
3. **Path stripping**: `/shapeshyft/api/v1/users` becomes `/api/v1/users` at the container
4. **Doppler merge**: Doppler values always override defaults, never vice versa
5. **macOS sed**: Scripts use `sed -i.bak` pattern for macOS compatibility, then clean up .bak files
