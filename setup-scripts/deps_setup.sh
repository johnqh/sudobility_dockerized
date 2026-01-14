#!/bin/bash
# deps_setup.sh - Install system dependencies for Sudobility Dockerized
# This script handles the installation of all system dependencies.
# It should be sourced from the main setup.sh script.

# --- Script Configuration & Setup ---

# Get the original user who invoked the script (or the current user if not sudo)
ORIGINAL_USER=$(whoami)
echo "Running dependency setup as user: $ORIGINAL_USER"

# --- Variables ---
DOCKER_GROUP_ADDED="false" # Flag to track if the user was added to the docker group

# --- Helper Functions for OS Detection ---
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_ubuntu_debian() {
    command_exists apt-get
}

is_centos_rhel() {
    command_exists yum && ! command_exists dnf
}

is_fedora() {
    command_exists dnf
}

is_macos() {
    [[ "$(uname)" == "Darwin" ]]
}

# --- Installation Functions ---

install_curl() {
    echo "--- Installing curl ---"
    if command_exists curl; then
        echo "curl is already installed."
        return 0
    fi

    if is_macos; then
        # curl is pre-installed on macOS
        echo "curl should be pre-installed on macOS."
        return 0
    elif is_ubuntu_debian; then
        sudo apt-get update -y
        sudo apt-get install -y curl || { echo "Error: curl installation failed."; exit 1; }
    elif is_centos_rhel; then
        sudo yum install -y curl || { echo "Error: curl installation failed."; exit 1; }
    elif is_fedora; then
        sudo dnf install -y curl || { echo "Error: curl installation failed."; exit 1; }
    else
        echo "Unsupported OS for automatic curl installation. Please install manually."
        exit 1
    fi
    echo "curl installed successfully."
}

install_jq() {
    echo "--- Installing jq ---"
    if command_exists jq; then
        echo "jq is already installed."
        return 0
    fi

    if is_macos; then
        if command_exists brew; then
            brew install jq || { echo "Error: jq installation failed."; exit 1; }
        else
            echo "Homebrew not found. Please install jq manually: brew install jq"
            exit 1
        fi
    elif is_ubuntu_debian; then
        sudo apt-get update -y
        sudo apt-get install -y jq || { echo "Error: jq installation failed."; exit 1; }
    elif is_centos_rhel; then
        sudo yum install -y jq || { echo "Error: jq installation failed."; exit 1; }
    elif is_fedora; then
        sudo dnf install -y jq || { echo "Error: jq installation failed."; exit 1; }
    else
        echo "Unsupported OS for automatic jq installation. Please install manually."
        exit 1
    fi
    echo "jq installed successfully."
}

install_docker() {
    echo "--- Installing Docker ---"

    if is_macos; then
        if command_exists docker; then
            echo "Docker is already installed."
            return 0
        else
            echo "Docker Desktop is required on macOS."
            echo "Please download and install from: https://www.docker.com/products/docker-desktop"
            echo "After installation, start Docker Desktop and re-run this script."
            exit 1
        fi
    fi

    # Linux installation
    if command_exists docker; then
        echo "Docker is already installed."
    else
        if is_ubuntu_debian; then
            sudo apt-get update -y
            sudo apt-get install -y ca-certificates curl gnupg lsb-release || { echo "Error: Docker prerequisites failed."; exit 1; }
            sudo mkdir -m 0755 -p /etc/apt/keyrings
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg || { echo "Error: Docker GPG key download failed."; exit 1; }
            echo \
                "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
                $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null || { echo "Error: Docker repository setup failed."; exit 1; }
            sudo apt-get update -y
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { echo "Error: Docker installation failed."; exit 1; }
        elif is_centos_rhel || is_fedora; then
            sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || { echo "Error: Docker repo setup failed."; exit 1; }
            sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || { echo "Error: Docker installation failed."; exit 1; }
        else
            echo "Unsupported OS for automatic Docker installation. Please install manually."
            exit 1
        fi
        echo "Docker installed."
    fi

    # Start and enable docker service (Linux only)
    if ! is_macos; then
        # First check if docker is already working (user might have access without sudo)
        if docker ps >/dev/null 2>&1; then
            echo "Docker is running and accessible."
        else
            # Need to start Docker service with sudo
            if ! sudo systemctl is-active --quiet docker; then
                echo "Starting Docker service..."
                sudo systemctl start docker || { echo "Error: Failed to start Docker service."; exit 1; }
            fi
            if ! sudo systemctl is-enabled --quiet docker; then
                echo "Enabling Docker service to start on boot..."
                sudo systemctl enable docker || { echo "Error: Failed to enable Docker service."; exit 1; }
            fi
            echo "Docker service started and enabled."
        fi

        # Add user to docker group if not already there
        if ! id -nG "$ORIGINAL_USER" | grep -qw "docker"; then
            echo "Adding user '$ORIGINAL_USER' to the docker group..."
            sudo usermod -aG docker "$ORIGINAL_USER"
            DOCKER_GROUP_ADDED="true"
            echo "User '$ORIGINAL_USER' added to 'docker' group."
        else
            echo "User '$ORIGINAL_USER' is already in the 'docker' group."
        fi
    fi
}

install_crontab() {
    echo "--- Installing Crontab (Cron Daemon) ---"

    if is_macos; then
        # macOS has launchd, cron is available but launchd is preferred
        echo "macOS uses launchd for scheduled tasks. Cron is available by default."
        return 0
    fi

    if command_exists crontab; then
        echo "Crontab is already installed."
        return 0
    fi

    if is_ubuntu_debian; then
        sudo apt-get install -y cron || { echo "Error: Cron installation failed."; exit 1; }
        sudo systemctl enable cron || { echo "Error: Failed to enable cron service."; exit 1; }
        sudo systemctl start cron || { echo "Error: Failed to start cron service."; exit 1; }
    elif is_centos_rhel || is_fedora; then
        sudo dnf install -y cronie || { echo "Error: Cronie installation failed."; exit 1; }
        sudo systemctl enable crond || { echo "Error: Failed to enable crond service."; exit 1; }
        sudo systemctl start crond || { echo "Error: Failed to start crond service."; exit 1; }
    else
        echo "Unsupported OS for automatic Crontab installation. Please install manually."
        exit 1
    fi
    echo "Crontab installed and cron service started successfully."
}

install_all_dependencies() {
    echo ""
    echo "=========================================="
    echo "  Installing System Dependencies"
    echo "=========================================="
    echo ""

    install_curl
    install_jq
    install_docker
    install_crontab

    echo ""
    echo "=========================================="
    echo "  All Dependencies Installed"
    echo "=========================================="
    echo ""
}

# --- Main execution of dependency setup ---
install_all_dependencies

# --- Final user prompt for restart if Docker group was modified ---
if [ "$DOCKER_GROUP_ADDED" = "true" ]; then
    echo ""
    echo "========================================================================="
    echo " IMPORTANT: Docker group membership changed for user '$ORIGINAL_USER'."
    echo " You need to log out and log back in (or open a new terminal session)"
    echo " for these changes to take full effect and use 'docker' without 'sudo'."
    echo " Once you've done that, please re-run the setup script."
    echo "========================================================================="
    echo ""
    exit 0
fi
