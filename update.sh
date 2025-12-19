#!/bin/sh

#####################################################################
# Jellystat Updater for TrueNAS Core / FreeBSD
#####################################################################

set -e

# Configuration - Should match install.sh
JELLYSTAT_DIR="/usr/local/jellystat"
JELLYSTAT_USER="jellystat"
JELLYSTAT_GROUP="jellystat"
JELLYSTAT_BRANCH="main"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    printf "%b[INFO]%b %s\n" "${GREEN}" "${NC}" "$1"
}

log_warn() {
    printf "%b[WARN]%b %s\n" "${YELLOW}" "${NC}" "$1"
}

log_error() {
    printf "%b[ERROR]%b %s\n" "${RED}" "${NC}" "$1"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

main() {
    check_root

    printf "%b\n" "${BLUE}"
    printf "%s\n" "╔═══════════════════════════════════════════════════════════════╗"
    printf "%s\n" "║         Jellystat Updater for TrueNAS Core / FreeBSD          ║"
    printf "%s\n" "╚═══════════════════════════════════════════════════════════════╝"
    printf "%b\n" "${NC}"
    printf "\n"

    # Check if Jellystat is installed
    if [ ! -d "${JELLYSTAT_DIR}" ]; then
        log_error "Jellystat installation not found at ${JELLYSTAT_DIR}"
        log_error "Please run install.sh first"
        exit 1
    fi

    # Check if it's a git repository
    if [ ! -d "${JELLYSTAT_DIR}/.git" ]; then
        log_error "Jellystat directory is not a git repository"
        log_error "Cannot update. Please reinstall using install.sh"
        exit 1
    fi

    cd "${JELLYSTAT_DIR}"

    # Get current version info
    CURRENT_COMMIT=$(git rev-parse --short HEAD)
    log_info "Current version: ${CURRENT_COMMIT}"

    # Fetch latest changes
    log_info "Fetching latest changes..."
    git fetch origin "${JELLYSTAT_BRANCH}"

    # Check if update is available
    LOCAL=$(git rev-parse HEAD)
    REMOTE=$(git rev-parse origin/${JELLYSTAT_BRANCH})

    if [ "$LOCAL" = "$REMOTE" ]; then
        log_info "Jellystat is already up to date!"
        exit 0
    fi

    NEW_COMMIT=$(git rev-parse --short origin/${JELLYSTAT_BRANCH})
    log_info "New version available: ${NEW_COMMIT}"
    echo ""

    # Confirm update
    printf "Do you want to update Jellystat? [y/N]: "
    read -r response

    if [ "$response" != "y" ] && [ "$response" != "Y" ]; then
        echo "Update cancelled."
        exit 0
    fi

    # Backup .env file
    if [ -f "${JELLYSTAT_DIR}/.env" ]; then
        log_info "Backing up environment configuration..."
        cp "${JELLYSTAT_DIR}/.env" "${JELLYSTAT_DIR}/.env.backup"
    fi

    # Stop service
    log_info "Stopping Jellystat service..."
    service jellystat stop 2>/dev/null || true

    # Pull latest changes
    log_info "Pulling latest changes..."
    git reset --hard origin/${JELLYSTAT_BRANCH}

    # Restore .env file
    if [ -f "${JELLYSTAT_DIR}/.env.backup" ]; then
        log_info "Restoring environment configuration..."
        mv "${JELLYSTAT_DIR}/.env.backup" "${JELLYSTAT_DIR}/.env"
    fi

    # Update npm dependencies
    log_info "Updating npm dependencies..."
    npm install --production=false

    # Rebuild application
    log_info "Rebuilding Jellystat..."
    npm run build

    # Fix ownership
    chown -R "${JELLYSTAT_USER}:${JELLYSTAT_GROUP}" "${JELLYSTAT_DIR}"

    # Start service
    log_info "Starting Jellystat service..."
    service jellystat start

    sleep 3

    if service jellystat status >/dev/null 2>&1; then
        echo ""
        log_info "Jellystat updated successfully!"
        log_info "Updated from ${CURRENT_COMMIT} to ${NEW_COMMIT}"
        echo ""
    else
        log_error "Failed to start Jellystat after update"
        log_error "Check /var/log/jellystat.log for details"
        exit 1
    fi
}

main "$@"
