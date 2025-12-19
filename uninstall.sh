#!/bin/sh

#####################################################################
# Jellystat Uninstaller for TrueNAS Core / FreeBSD
#####################################################################

set -e

# Configuration - Should match install.sh
JELLYSTAT_DIR="/usr/local/jellystat"
JELLYSTAT_USER="jellystat"
JELLYSTAT_GROUP="jellystat"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

main() {
    check_root

    echo "${YELLOW}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║         Jellystat Uninstaller for TrueNAS Core / FreeBSD      ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo "${NC}"
    echo ""

    # Confirm uninstallation
    echo "${YELLOW}WARNING: This will remove Jellystat and optionally its database.${NC}"
    echo ""
    printf "Do you want to continue? [y/N]: "
    read -r response
    
    if [ "$response" != "y" ] && [ "$response" != "Y" ]; then
        echo "Uninstallation cancelled."
        exit 0
    fi

    # Stop Jellystat service
    log_info "Stopping Jellystat service..."
    service jellystat stop 2>/dev/null || true

    # Disable and remove service
    log_info "Removing service configuration..."
    sysrc -x jellystat_enable 2>/dev/null || true
    rm -f /usr/local/etc/rc.d/jellystat

    # Remove log file
    rm -f /var/log/jellystat.log

    # Remove PID file
    rm -f /var/run/jellystat.pid

    # Ask about removing the installation directory
    echo ""
    printf "Remove Jellystat installation directory (${JELLYSTAT_DIR})? [y/N]: "
    read -r response
    
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        log_info "Removing Jellystat installation directory..."
        rm -rf "${JELLYSTAT_DIR}"
        rm -rf "${JELLYSTAT_DIR}.backup."* 2>/dev/null || true
    else
        log_info "Keeping Jellystat installation directory"
    fi

    # Ask about removing the user
    echo ""
    printf "Remove Jellystat system user (${JELLYSTAT_USER})? [y/N]: "
    read -r response
    
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        log_info "Removing Jellystat user and group..."
        pw userdel "${JELLYSTAT_USER}" 2>/dev/null || true
        pw groupdel "${JELLYSTAT_GROUP}" 2>/dev/null || true
    else
        log_info "Keeping Jellystat user"
    fi

    # Ask about removing database
    echo ""
    printf "Remove PostgreSQL database and user? [y/N]: "
    read -r response
    
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        log_info "Removing PostgreSQL database and user..."
        su -m postgres -c "psql -c 'DROP DATABASE IF EXISTS jfstat;'" 2>/dev/null || true
        su -m postgres -c "psql -c 'DROP USER IF EXISTS jellystat;'" 2>/dev/null || true
    else
        log_info "Keeping PostgreSQL database"
    fi

    # Ask about removing PostgreSQL completely
    echo ""
    printf "Remove PostgreSQL server completely? [y/N]: "
    read -r response
    
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        log_info "Stopping and removing PostgreSQL..."
        service postgresql stop 2>/dev/null || true
        sysrc -x postgresql_enable 2>/dev/null || true
        pkg remove -y postgresql16-server postgresql16-client 2>/dev/null || true
        
        echo ""
        printf "Also remove PostgreSQL data directory? [y/N]: "
        read -r response2
        if [ "$response2" = "y" ] || [ "$response2" = "Y" ]; then
            rm -rf /var/db/postgres
        fi
    fi

    # Ask about removing Node.js
    echo ""
    printf "Remove Node.js? [y/N]: "
    read -r response
    
    if [ "$response" = "y" ] || [ "$response" = "Y" ]; then
        log_info "Removing Node.js..."
        pkg remove -y node20 npm-node20 2>/dev/null || true
    fi

    echo ""
    log_info "Uninstallation complete!"
    echo ""
}

main "$@"
