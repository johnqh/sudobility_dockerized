# Sudobility Dockerized

Docker deployment system for Sudobility backend APIs with Traefik reverse proxy and Doppler secrets management.

## Prerequisites

- Docker and Docker Compose v2+
- curl
- jq
- A domain name pointing to your server
- Doppler account with service tokens

## Quick Start

```bash
# Clone and enter directory
cd sudobility_dockerized

# Run setup
./setup.sh
```

The setup script will:
1. Check dependencies
2. Prompt for API hostname
3. Prompt for Doppler service tokens
4. Configure Let's Encrypt SSL
5. Build and start containers

## Doppler Configuration

Each container requires its own Doppler configuration. Create a Doppler project and add configs for each service.

### shapeshyft_api

Create a Doppler config named `shapeshyft_api` with these secrets:

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `ENCRYPTION_KEY` | Yes | 64-char hex string (generate: `openssl rand -hex 32`) |
| `FIREBASE_PROJECT_ID` | Yes | Firebase project ID |
| `FIREBASE_CLIENT_EMAIL` | Yes | Firebase service account email |
| `FIREBASE_PRIVATE_KEY` | Yes | Firebase private key (with newlines) |
| `REVENUECAT_API_KEY` | No | RevenueCat API key for rate limiting |

### Generating a Service Token

1. Go to Doppler Dashboard
2. Select your project
3. Navigate to the config (e.g., `shapeshyft_api`)
4. Go to **Access** → **Service Tokens**
5. Generate a new token
6. Save the token - you'll enter it during setup

## Directory Structure

```
sudobility_dockerized/
├── setup.sh                    # Initial setup
├── upgrade.sh                  # Update containers
├── versions.sh                 # Show version info
├── docker-compose.yml          # Compose template
├── .env.example                # Environment documentation
├── default-config/
│   └── shapeshyft_api/
│       └── .env.defaults       # Non-sensitive defaults
├── setup-scripts/
│   ├── common.sh               # Shared utilities
│   ├── doppler.sh              # Doppler integration
│   └── traefik.sh              # Traefik/SSL setup
├── dynamic_conf/
│   └── dynamic.yml             # Traefik dynamic config
└── config-generated/           # Created by setup.sh
    ├── docker-compose.yml      # Customized compose
    ├── .env.shapeshyft_api     # Container env file
    └── .deployment-config      # Saved settings
```

## Commands

### Initial Setup

```bash
./setup.sh
```

Performs first-time installation. Prompts for:
- API hostname (e.g., `api.example.com`)
- ACME email for Let's Encrypt
- Doppler service tokens for each container

### Upgrade

```bash
./upgrade.sh
```

Updates existing installation:
- Refreshes secrets from Doppler
- Updates docker-compose.yml
- Rebuilds and restarts containers

### Version Info

```bash
./versions.sh
```

Displays:
- Docker/Compose versions
- Container status and health
- Application versions
- Resource usage

### Manual Container Management

```bash
# Enter config directory
cd config-generated

# View logs
docker compose logs -f

# View specific service logs
docker compose logs -f shapeshyft_api

# Restart services
docker compose restart

# Stop services
docker compose down

# Start services
docker compose up -d
```

## API Access

After setup, APIs are accessible via HTTPS:

| Service | URL |
|---------|-----|
| ShapeShyft API | `https://<hostname>/shapeshyft/api/v1/` |

The `/shapeshyft` prefix is stripped before forwarding to the container.

## Adding New Containers

### 1. Create Default Config

```bash
mkdir -p default-config/new_api
```

Create `default-config/new_api/.env.defaults`:

```bash
# Non-sensitive defaults
PORT=3001
NODE_ENV=production

# Secrets come from Doppler
# SECRET_KEY=
```

### 2. Add to Container List

Edit `setup-scripts/common.sh`:

```bash
CONTAINERS=(
    "shapeshyft_api:ShapeShyft API:3000"
    "new_api:New API:3001"  # Add this line
)
```

### 3. Add Docker Compose Service

Edit `docker-compose.yml`:

```yaml
services:
  # ... existing services ...

  new_api:
    build:
      context: ../new_api
    container_name: new_api
    restart: unless-stopped
    env_file:
      - .env.new_api
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.new-api.rule=Host(`API_HOSTNAME`) && PathPrefix(`/newapi`)"
      - "traefik.http.routers.new-api.entrypoints=websecure"
      - "traefik.http.routers.new-api.tls.certresolver=letsencrypt"
      - "traefik.http.middlewares.newapi-strip.stripprefix.prefixes=/newapi"
      - "traefik.http.routers.new-api.middlewares=newapi-strip"
      - "traefik.http.services.new-api.loadbalancer.server.port=3001"
    networks:
      - sudobility_network
```

### 4. Create Doppler Config

1. Add a new config in Doppler named `new_api`
2. Add required secrets
3. Generate a service token

### 5. Run Setup

```bash
./setup.sh
```

The script will prompt for the new container's Doppler token.

## Troubleshooting

### Container won't start

Check logs:
```bash
cd config-generated
docker compose logs shapeshyft_api
```

### SSL certificate issues

Ensure:
- Domain DNS points to your server
- Ports 80 and 443 are open
- No other service is using these ports

Check Traefik logs:
```bash
cd config-generated
docker compose logs traefik
```

### Doppler token invalid

Remove saved token and re-run setup:
```bash
rm .doppler-token-shapeshyft_api
./setup.sh
```

### Missing environment variables

Check the generated env file:
```bash
cat config-generated/.env.shapeshyft_api
```

Verify all required variables are present in Doppler.

### Reset installation

Remove generated config and start fresh:
```bash
rm -rf config-generated
rm .doppler-token-*
./setup.sh
```

## Security Notes

- Doppler tokens are stored in `.doppler-token-*` files with 600 permissions
- Environment files in `config-generated/` contain secrets - never commit
- All sensitive files are in `.gitignore`
- HTTPS is enforced via Traefik with automatic HTTP→HTTPS redirect

## License

Private - Sudobility
