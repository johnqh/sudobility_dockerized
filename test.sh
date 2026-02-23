#!/bin/bash
# test.sh - Automated tests for shell scripts
# Usage: ./test.sh
#
# Tests:
#   1. Syntax check (bash -n) on all .sh files
#   2. Source common.sh and verify key functions exist
#   3. Verify get_docker_compose_cmd output format
#   4. Structure verification (no actual Docker commands)

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output (standalone - don't source common.sh at top level)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
TEST_COUNT=0

test_pass() {
    echo -e "${GREEN}  PASS${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
    TEST_COUNT=$((TEST_COUNT + 1))
}

test_fail() {
    echo -e "${RED}  FAIL${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    TEST_COUNT=$((TEST_COUNT + 1))
}

test_skip() {
    echo -e "${YELLOW}  SKIP${NC} $1"
    TEST_COUNT=$((TEST_COUNT + 1))
}

echo ""
echo -e "${BLUE}===========================================================${NC}"
echo -e "${BLUE}  Shell Script Tests${NC}"
echo -e "${BLUE}===========================================================${NC}"
echo ""

# =============================================================================
# Test Suite 1: Syntax checks (bash -n)
# =============================================================================
echo -e "${BLUE}--- Syntax Checks (bash -n) ---${NC}"

SCRIPTS="add.sh upgrade.sh remove.sh status.sh versions.sh lint.sh test.sh"
SCRIPTS="${SCRIPTS} setup-scripts/common.sh setup-scripts/traefik.sh"
SCRIPTS="${SCRIPTS} setup-scripts/doppler.sh setup-scripts/deps_setup.sh"

for script in $SCRIPTS; do
    if [ ! -f "$script" ]; then
        test_skip "$script (file not found)"
        continue
    fi

    if bash -n "$script" 2>/dev/null; then
        test_pass "$script syntax OK"
    else
        test_fail "$script has syntax errors"
    fi
done

echo ""

# =============================================================================
# Test Suite 2: common.sh function existence
# =============================================================================
echo -e "${BLUE}--- common.sh Function Verification ---${NC}"

# Source common.sh in a subshell to verify it loads without error
# We override docker commands so nothing actually runs
if (
    # Stub out docker so sourcing doesn't trigger anything
    docker() { return 0; }
    export -f docker
    source "./setup-scripts/common.sh" 2>/dev/null
); then
    test_pass "common.sh sources without error"
else
    test_fail "common.sh failed to source"
fi

# Check that expected functions are defined after sourcing common.sh
EXPECTED_FUNCTIONS="print_success print_error print_warning print_info"
EXPECTED_FUNCTIONS="${EXPECTED_FUNCTIONS} print_header command_exists get_docker_compose_cmd"
EXPECTED_FUNCTIONS="${EXPECTED_FUNCTIONS} ensure_dirs secure_file ensure_network"
EXPECTED_FUNCTIONS="${EXPECTED_FUNCTIONS} is_traefik_running install_traefik"
EXPECTED_FUNCTIONS="${EXPECTED_FUNCTIONS} get_managed_services read_services_array"
EXPECTED_FUNCTIONS="${EXPECTED_FUNCTIONS} service_exists get_service_config"
EXPECTED_FUNCTIONS="${EXPECTED_FUNCTIONS} validate_doppler_token fetch_doppler_secrets"

for func in $EXPECTED_FUNCTIONS; do
    if (
        docker() { return 0; }
        export -f docker
        source "./setup-scripts/common.sh" 2>/dev/null
        type "$func" >/dev/null 2>&1
    ); then
        test_pass "function $func exists"
    else
        test_fail "function $func not found"
    fi
done

echo ""

# =============================================================================
# Test Suite 3: get_docker_compose_cmd output format
# =============================================================================
echo -e "${BLUE}--- get_docker_compose_cmd Output Format ---${NC}"

COMPOSE_CMD=$(
    # Provide a docker stub that simulates "docker compose version" succeeding
    docker() {
        if [ "$1" = "compose" ] && [ "$2" = "version" ]; then
            echo "Docker Compose version v2.20.0"
            return 0
        fi
        return 1
    }
    export -f docker
    source "./setup-scripts/common.sh" 2>/dev/null
    get_docker_compose_cmd
)

if [ "$COMPOSE_CMD" = "docker compose" ]; then
    test_pass "get_docker_compose_cmd returns 'docker compose' when v2 available"
else
    test_fail "get_docker_compose_cmd returned '${COMPOSE_CMD}', expected 'docker compose'"
fi

COMPOSE_CMD_V1=$(
    # Provide a docker stub that simulates "docker compose version" failing
    docker() {
        if [ "$1" = "compose" ] && [ "$2" = "version" ]; then
            return 1
        fi
        return 1
    }
    export -f docker
    source "./setup-scripts/common.sh" 2>/dev/null
    get_docker_compose_cmd
)

if [ "$COMPOSE_CMD_V1" = "docker-compose" ]; then
    test_pass "get_docker_compose_cmd returns 'docker-compose' when v2 unavailable"
else
    test_fail "get_docker_compose_cmd returned '${COMPOSE_CMD_V1}', expected 'docker-compose'"
fi

echo ""

# =============================================================================
# Test Suite 4: Variable and constant verification
# =============================================================================
echo -e "${BLUE}--- Constants and Variables ---${NC}"

# Verify key constants are set after sourcing
CONFIG_DIR_VALUE=$(
    docker() { return 0; }
    export -f docker
    source "./setup-scripts/common.sh" 2>/dev/null
    echo "$CONFIG_DIR"
)

if [ "$CONFIG_DIR_VALUE" = "config-generated" ]; then
    test_pass "CONFIG_DIR is 'config-generated'"
else
    test_fail "CONFIG_DIR is '${CONFIG_DIR_VALUE}', expected 'config-generated'"
fi

SERVICES_DIR_VALUE=$(
    docker() { return 0; }
    export -f docker
    source "./setup-scripts/common.sh" 2>/dev/null
    echo "$SERVICES_DIR"
)

if [ "$SERVICES_DIR_VALUE" = "config-generated/services" ]; then
    test_pass "SERVICES_DIR is 'config-generated/services'"
else
    test_fail "SERVICES_DIR is '${SERVICES_DIR_VALUE}', expected 'config-generated/services'"
fi

DOPPLER_URL_VALUE=$(
    docker() { return 0; }
    export -f docker
    source "./setup-scripts/common.sh" 2>/dev/null
    echo "$DOPPLER_API_URL"
)

if [ "$DOPPLER_URL_VALUE" = "https://api.doppler.com/v3/configs/config/secrets/download" ]; then
    test_pass "DOPPLER_API_URL is correct"
else
    test_fail "DOPPLER_API_URL is '${DOPPLER_URL_VALUE}'"
fi

echo ""

# =============================================================================
# Test Suite 5: Script structure verification
# =============================================================================
echo -e "${BLUE}--- Script Structure ---${NC}"

# Verify main scripts source common.sh
for script in add.sh upgrade.sh remove.sh status.sh; do
    if grep -q 'source.*common\.sh' "$script" 2>/dev/null; then
        test_pass "$script sources common.sh"
    else
        test_fail "$script does not source common.sh"
    fi
done

# Verify main scripts (except status.sh) use set -e
for script in add.sh upgrade.sh remove.sh; do
    if grep -q '^set -e' "$script" 2>/dev/null; then
        test_pass "$script uses set -e"
    else
        test_fail "$script does not use set -e"
    fi
done

echo ""

# =============================================================================
# Summary
# =============================================================================
echo "==========================================================="
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed out of ${TEST_COUNT} tests"
echo "==========================================================="

if [ "$FAIL_COUNT" -gt 0 ]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
fi
