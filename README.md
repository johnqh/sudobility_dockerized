# Sudobility Dockerized

A flexible Docker deployment system for managing multiple backend services with Traefik reverse proxy, automatic SSL via Let's Encrypt, and Doppler secrets management.

## Features

- **Per-service management**: Add, upgrade, and remove services independently
- **Host-based routing**: Each service gets its own hostname (e.g., `api.example.com`)
- **Automatic SSL**: Let's Encrypt certificates via ACME HTTP challenge
- **Secrets management**: Environment variables from Doppler
- **Health checks**: Optional health endpoint monitoring
- **Cloudflare compatible**: Works with Cloudflare proxy enabled

## Prerequisites

- Docker and Docker Compose v2+
- curl
- bash 3.2+ (macOS) or 4+ (Linux)
- A domain name with DNS pointing to your server
- Doppler account with service tokens

## Architecture

```
                           Internet
                              |
        +---------------------+---------------------+
        | api.shapeshyft.ai   |   api.other.com    |
        v                     v                     v
+-------------------------------------------------------------+
|                    Traefik (Reverse Proxy)                   |
|  - SSL termination (Let's Encrypt ACME)                     |
|  - Host-based routing (no path prefix)                      |
|  - HTTP -> HTTPS redirect                                    |
|  - Docker label-based service discovery                      |
+-------------------------------------------------------------+
                              |
        +---------------------+---------------------+
        | Host: api.shapeshyft.ai                   | Host: api.other.com
        v                                           v
+-------------------+                       +-------------------+
|  shapeshyft_api   |                       |    other_api      |
|  (Port 8020)      |                       |    (Port 3000)    |
+-------------------+                       +-------------------+
```

## Quick Start

### Adding Your First Service

```bash
./add.sh
```

You'll be prompted for:
1. **Service name**: Container name (e.g., `shapeshyft_api`)
2. **Hostname**: Public URL (e.g., `api.shapeshyft.ai`)
3. **Docker image**: Image to pull (e.g., `docker.io/username/image:latest`)
4. **Health check**: Use `/health` endpoint or skip
5. **Doppler token**: Service token for secrets

The script will:
- Install Traefik if not running
- Fetch environment variables from Doppler
- Create service configuration
- Pull the Docker image
- Start the container with SSL enabled

### Example: Deploy ShapeShyft API

```bash
./add.sh

# Enter when prompted:
# Service name: shapeshyft_api
# Hostname: api.shapeshyft.ai
# Docker image: docker.io/johnqh/shapeshyft_api:latest
# Health check: 1 (Use /health endpoint)
# Doppler token: dp.st.xxx...
```

## Commands

### Add a Service

```bash
./add.sh
```

Interactively add a new service with:
- Automatic Traefik installation
- Doppler token validation
- SSL certificate provisioning
- Health check configuration

### Check Status

```bash
./status.sh
```

Displays all services with:
- Container status (running/stopped)
- Health check status
- Version (Docker image tag)
- Uptime
- Hostname

Example output:
```
Infrastructure:
─────────────────────────────────────────────────────────────────────────────────────
  Traefik:  Status: running  Health: no healthcheck  Uptime: 11h 41m

Services:

#    SERVICE              STATUS       HEALTH       VERSION    UPTIME       HOSTNAME
───────────────────────────────────────────────────────────────────────────────────────────────
1    shapeshyft_api       running      healthy      latest     6s           api.shapeshyft.ai
```

### Upgrade a Service

```bash
./upgrade.sh
```

Select a service to:
- Refresh secrets from Doppler
- Pull the latest Docker image
- Restart the container

### Remove a Service

```bash
./remove.sh
```

Select a service to remove with:
- Double confirmation (yes/no + type service name)
- Container and volume removal
- Configuration cleanup

## Directory Structure

```
sudobility_dockerized/
├── add.sh                      # Add new service
├── upgrade.sh                  # Upgrade existing service
├── remove.sh                   # Remove service
├── status.sh                   # Show all services status
├── setup-scripts/
│   └── common.sh               # Shared utilities
└── config-generated/           # Auto-generated (gitignored)
    ├── traefik/
    │   └── docker-compose.yml  # Traefik configuration
    ├── services/
    │   └── <service_name>/
    │       ├── docker-compose.yml
    │       ├── .env
    │       └── .service.conf
    └── .doppler-tokens/
        └── <service_name>
```

## Doppler Configuration

### Required Environment Variables

Each service must have `PORT` defined in Doppler. All other variables are service-specific.

| Variable | Required | Description |
|----------|----------|-------------|
| `PORT` | Yes | Port the service listens on |
| Others | Varies | Service-specific secrets |

### Generating a Service Token

1. Go to [Doppler Dashboard](https://dashboard.doppler.com)
2. Select your project
3. Navigate to your config (e.g., `prd`)
4. Go to **Access** → **Service Tokens**
5. Generate a new token
6. Save the token for use with `add.sh`

### ShapeShyft API Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `PORT` | Yes | Default: 8020 |
| `DATABASE_URL` | Yes | PostgreSQL connection string |
| `ENCRYPTION_KEY` | Yes | 64-char hex (`openssl rand -hex 32`) |
| `FIREBASE_PROJECT_ID` | Yes | Firebase project ID |
| `FIREBASE_CLIENT_EMAIL` | Yes | Firebase service account email |
| `FIREBASE_PRIVATE_KEY` | Yes | Firebase private key |
| `REVENUECAT_API_KEY` | No | RevenueCat API key |

## Cloudflare Integration

This system works with Cloudflare proxy enabled:

### Setup with Cloudflare

1. **Add DNS record** in Cloudflare:
   - Type: `A`
   - Name: `api` (or your subdomain)
   - Content: Your server IP
   - Proxy: Can be OFF initially

2. **Run `add.sh`** to deploy your service

3. **Turn on Cloudflare proxy** (orange cloud)

4. **Set SSL mode** to **Full (Strict)**:
   - Cloudflare Dashboard → SSL/TLS → Overview → Full (Strict)

### Why Full (Strict)?

- **Flexible**: Cloudflare connects to origin via HTTP (breaks - Traefik redirects to HTTPS)
- **Full**: Cloudflare connects via HTTPS (works)
- **Full (Strict)**: Same as Full + validates certificate (recommended)

### Certificate Renewal

Let's Encrypt certificates auto-renew. The ACME HTTP challenge works through Cloudflare proxy since Cloudflare forwards HTTP traffic to your origin.

## Manual Operations

### View Service Logs

```bash
cd config-generated/services/<service_name>
docker compose logs -f
```

### Restart a Service

```bash
cd config-generated/services/<service_name>
docker compose restart
```

### View Traefik Logs

```bash
cd config-generated/traefik
docker compose logs -f
```

### Check SSL Certificate

```bash
curl -vI https://api.shapeshyft.ai 2>&1 | grep -A5 "Server certificate"
```

## Troubleshooting

### Service won't start

Check logs:
```bash
cd config-generated/services/<service_name>
docker compose logs
```

Common issues:
- Missing `PORT` in Doppler
- Invalid Doppler token
- Docker image not found

### SSL certificate errors

1. Ensure DNS points to your server IP
2. If using Cloudflare, temporarily turn proxy OFF
3. Check Traefik logs for ACME errors:
   ```bash
   cd config-generated/traefik
   docker compose logs | grep -i acme
   ```

### 502 Bad Gateway

- Service container might not be running
- Check service health: `./status.sh`
- Verify PORT matches what the app listens on

### Connection refused

- Ensure ports 80 and 443 are open on your firewall
- Check if another service is using these ports

### Doppler token invalid

Remove and re-add the service:
```bash
./remove.sh  # Select the service
./add.sh     # Re-add with new token
```

### Reset everything

```bash
# Stop all services
cd config-generated/services
for dir in */; do (cd "$dir" && docker compose down); done

# Stop Traefik
cd ../traefik && docker compose down

# Remove all config
cd ../..
rm -rf config-generated

# Start fresh
./add.sh
```

## Security Notes

- Doppler tokens stored in `config-generated/.doppler-tokens/` with 600 permissions
- Service `.env` files contain secrets - never commit
- All sensitive files are in `.gitignore`
- HTTPS enforced via Traefik (HTTP redirects to HTTPS)
- Traefik dashboard is disabled by default

## Adding Custom Services

Any Docker image can be deployed. Requirements:

1. **PORT environment variable**: Define in Doppler
2. **Health endpoint** (optional): Implement `GET /health` returning 200
3. **HTTP server**: Must listen on the PORT

Example for a Node.js app:
```javascript
const port = process.env.PORT || 3000;
app.get('/health', (req, res) => res.status(200).json({ status: 'healthy' }));
app.listen(port);
```

## License

Private - Sudobility
