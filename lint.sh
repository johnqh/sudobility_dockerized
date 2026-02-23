#!/bin/bash
# lint.sh - Run ShellCheck on all shell scripts
# Usage: ./lint.sh

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source helper scripts
source "./setup-scripts/common.sh"

print_header "Shell Script Linting"

# Check if shellcheck is available
if ! command_exists shellcheck; then
    print_error "ShellCheck is not installed."
    echo ""
    echo "Install ShellCheck:"
    echo "  macOS:   brew install shellcheck"
    echo "  Ubuntu:  sudo apt-get install shellcheck"
    echo "  Fedora:  sudo dnf install ShellCheck"
    echo "  Other:   https://github.com/koalaman/shellcheck#installing"
    exit 1
fi

print_success "ShellCheck found: $(shellcheck --version | head -2 | tail -1)"
echo ""

# Collect all .sh files
SCRIPTS=""
SCRIPTS="${SCRIPTS} add.sh"
SCRIPTS="${SCRIPTS} upgrade.sh"
SCRIPTS="${SCRIPTS} remove.sh"
SCRIPTS="${SCRIPTS} status.sh"
SCRIPTS="${SCRIPTS} versions.sh"
SCRIPTS="${SCRIPTS} setup-scripts/common.sh"
SCRIPTS="${SCRIPTS} setup-scripts/traefik.sh"
SCRIPTS="${SCRIPTS} setup-scripts/doppler.sh"
SCRIPTS="${SCRIPTS} setup-scripts/deps_setup.sh"

# Also include lint.sh and test.sh themselves if they exist
if [ -f "lint.sh" ]; then
    SCRIPTS="${SCRIPTS} lint.sh"
fi
if [ -f "test.sh" ]; then
    SCRIPTS="${SCRIPTS} test.sh"
fi

PASS_COUNT=0
FAIL_COUNT=0

for script in $SCRIPTS; do
    if [ ! -f "$script" ]; then
        print_warning "File not found: $script (skipping)"
        continue
    fi

    if shellcheck -x -S warning "$script" 2>&1; then
        print_success "$script"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        print_error "$script"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    echo ""
done

# Summary
echo ""
echo "─────────────────────────────────────────"
echo "Results: ${PASS_COUNT} passed, ${FAIL_COUNT} failed"
echo "─────────────────────────────────────────"

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_error "Linting failed. Fix the issues above."
    exit 1
else
    print_success "All scripts passed linting!"
fi
