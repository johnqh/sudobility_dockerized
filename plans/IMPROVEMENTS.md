# Improvement Plans for sudobility_dockerized

## Priority 1 - High Impact

### 1. Add Automated Testing for Shell Scripts ✅
- The Bash scripts (`add.sh`, `upgrade.sh`, `remove.sh`, `status.sh`, `setup-scripts/common.sh`) have no automated tests. Adding ShellCheck linting and basic functional tests (e.g., using `bats` testing framework) would catch syntax errors, quoting issues, and logic regressions before deployment.
- The `common.sh` shared library contains critical functions (`get_docker_compose_cmd`, `read_services_array`, Traefik setup, Doppler integration) that should be unit-tested with mocked `docker` and `curl` commands.
- Bash 3.x compatibility (macOS) is explicitly supported but not verified in CI. Adding a test matrix that runs scripts under both Bash 3 and Bash 5 would prevent compatibility regressions.

### 2. Improve Error Recovery and Idempotency ✅
- `add.sh` performs a multi-step process (check Traefik, prompt for config, validate Doppler, fetch secrets, generate compose, start container) but has no rollback mechanism if a later step fails. For example, if the container fails to start, the service directory and config files are left in a partial state.
- Adding a `--dry-run` flag to `add.sh` and `upgrade.sh` that shows what would be done without executing would help operators verify configuration before applying changes.
- The `remove.sh` script has double confirmation (yes/no + type service name) but does not verify the container is actually stopped before removing the directory. Adding a verification step would prevent orphaned Docker resources.

### 3. Document the Traefik Setup and Networking Model ✅
- `setup-scripts/common.sh` creates the `sudobility_network` Docker network and deploys Traefik with Let's Encrypt, but the setup process is only documented in the CLAUDE.md architecture diagram. Adding inline comments to the Traefik `docker-compose.yml` template and a troubleshooting guide for common TLS/routing issues would help operators.
- The relationship between `setup-scripts/traefik.sh`, `setup-scripts/doppler.sh`, `setup-scripts/deps_setup.sh`, and `setup-scripts/common.sh` is not documented. A flowchart or dependency description showing which scripts call which would aid maintenance.

## Priority 2 - Medium Impact

### 4. Add Health Monitoring Integration
- `status.sh` shows current service status but provides no historical data or alerting. Adding an optional integration with a lightweight monitoring solution (e.g., Uptime Kuma, or a simple health-check cron that writes to a log) would improve production reliability.
- Container health checks are defined via Docker Compose labels but the health check URLs are optional during `add.sh`. Making health check endpoints mandatory (or at minimum strongly recommended with a warning) would improve observability.

### 5. Add Service Update Notifications
- `upgrade.sh` pulls the latest Docker image but does not check if the image actually changed before restarting the service. Adding an image digest comparison would avoid unnecessary restarts.
- There is no mechanism to notify operators when a new version of a Docker image is available. Adding an optional `check-updates.sh` script that compares running image digests against the latest tags on Docker Hub would help keep services current.

### 6. Improve Doppler Integration Robustness
- Doppler token files are stored in `config-generated/.doppler-tokens/` with 600 permissions, but the token validation only happens during `add.sh`. If a token expires or is revoked, `upgrade.sh` will fail with an unhelpful error. Adding a token validity check at the start of `upgrade.sh` with a clear error message and re-authentication prompt would improve UX.

## Priority 3 - Nice to Have

### 7. Add Backup and Restore for Service Configurations
- Service configurations in `config-generated/services/` are gitignored and exist only on the deployment server. Adding a `backup-configs.sh` script that archives all service configs (excluding secrets) to a timestamped tarball would provide a recovery path if the server is lost.

### 8. Support Multi-Server Deployments
- The current architecture assumes all services run on a single Docker host behind one Traefik instance. Documenting the limitations and providing guidance for multi-server deployments (e.g., using Docker Swarm or an external Traefik instance) would help as the service count grows.

### 9. Add Service Dependency Management
- Services are currently independent with no dependency ordering. If a future service depends on another (e.g., a web app depending on an API service), there is no mechanism to express or enforce startup order. Adding an optional `depends_on` field to `.service.conf` would support this pattern.
