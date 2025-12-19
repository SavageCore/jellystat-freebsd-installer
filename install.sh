#!/bin/sh

#####################################################################
# Jellystat Installer for TrueNAS Core / FreeBSD
# https://github.com/CyferShepard/Jellystat
#
# This script installs Jellystat and its dependencies:
# - PostgreSQL database
# - Node.js runtime
# - Jellystat application
#####################################################################

set -e

# Configuration - Modify these variables as needed
JELLYSTAT_DIR="/usr/local/jellystat"
JELLYSTAT_USER="jellystat"
JELLYSTAT_GROUP="jellystat"
JELLYSTAT_PORT="3000"
JELLYSTAT_REPO="https://github.com/CyferShepard/Jellystat.git"
JELLYSTAT_BRANCH="main"

# PostgreSQL Configuration
POSTGRES_USER="jellystat"
POSTGRES_PASSWORD=""
POSTGRES_DB="jfstat"
POSTGRES_HOST="localhost"
POSTGRES_PORT="5432"

# JWT Secret (will be auto-generated if empty)
JWT_SECRET=""

# Timezone
TZ="Etc/UTC"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

#####################################################################
# Helper Functions
#####################################################################

print_banner() {
    printf "%b\n" "${BLUE}"
    printf "%s\n" "╔═══════════════════════════════════════════════════════════════╗"
    printf "%s\n" "║         Jellystat Installer for TrueNAS Core / FreeBSD        ║"
    printf "%s\n" "║                                                               ║"
    printf "%s\n" "║  A free and open source Statistics App for Jellyfin           ║"
    printf "%s\n" "╚═══════════════════════════════════════════════════════════════╝"
    printf "%b\n" "${NC}"
}

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

generate_password() {
    # Generate a random password
    openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24
}

generate_jwt_secret() {
    # Generate a random JWT secret
    openssl rand -base64 64 | tr -dc 'a-zA-Z0-9' | head -c 64
}

#####################################################################
# Installation Functions
#####################################################################

install_dependencies() {
    log_info "Updating package repository..."
    pkg update -f

    log_info "Installing required packages..."
    pkg install -y \
        git \
        node20 \
        npm-node20 \
        postgresql16-server \
        postgresql16-client \
        openssl \
        ca_root_nss

    log_info "Dependencies installed successfully"
}

setup_postgresql() {
    log_info "Setting up PostgreSQL..."

    # Enable PostgreSQL
    sysrc postgresql_enable="YES"

    # Initialize PostgreSQL if not already done
    if [ ! -d "/var/db/postgres/data16" ]; then
        log_info "Initializing PostgreSQL database cluster..."
        /usr/local/etc/rc.d/postgresql initdb
    fi

    # Start PostgreSQL
    log_info "Starting PostgreSQL..."
    service postgresql start || service postgresql restart

    # Wait for PostgreSQL to be ready
    log_info "Waiting for PostgreSQL to be ready..."
    sleep 3

    # Generate password if not set
    if [ -z "$POSTGRES_PASSWORD" ]; then
        POSTGRES_PASSWORD=$(generate_password)
        log_info "Generated PostgreSQL password: $POSTGRES_PASSWORD"
    fi

    # Create database user and database
    log_info "Creating PostgreSQL user and database..."

    # Check if user exists
    if ! su -m postgres -c "psql -tAc \"SELECT 1 FROM pg_roles WHERE rolname='${POSTGRES_USER}'\"" | grep -q 1; then
        su -m postgres -c "psql -c \"CREATE USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';\""
        log_info "Created PostgreSQL user: ${POSTGRES_USER}"
    else
        log_warn "PostgreSQL user ${POSTGRES_USER} already exists, updating password..."
        su -m postgres -c "psql -c \"ALTER USER ${POSTGRES_USER} WITH PASSWORD '${POSTGRES_PASSWORD}';\""
    fi

    # Check if database exists
    if ! su -m postgres -c "psql -tAc \"SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB}'\"" | grep -q 1; then
        su -m postgres -c "psql -c \"CREATE DATABASE ${POSTGRES_DB} OWNER ${POSTGRES_USER};\""
        log_info "Created PostgreSQL database: ${POSTGRES_DB}"
    else
        log_warn "PostgreSQL database ${POSTGRES_DB} already exists"
    fi

    # Grant privileges
    su -m postgres -c "psql -c \"GRANT ALL PRIVILEGES ON DATABASE ${POSTGRES_DB} TO ${POSTGRES_USER};\""

    log_info "PostgreSQL setup completed"
}

create_jellystat_user() {
    log_info "Creating Jellystat system user..."

    # Create group if it doesn't exist
    if ! pw groupshow "${JELLYSTAT_GROUP}" >/dev/null 2>&1; then
        pw groupadd "${JELLYSTAT_GROUP}"
        log_info "Created group: ${JELLYSTAT_GROUP}"
    fi

    # Create user if it doesn't exist
    if ! pw usershow "${JELLYSTAT_USER}" >/dev/null 2>&1; then
        pw useradd "${JELLYSTAT_USER}" -g "${JELLYSTAT_GROUP}" -d "${JELLYSTAT_DIR}" -s /usr/sbin/nologin -c "Jellystat Service User"
        log_info "Created user: ${JELLYSTAT_USER}"
    fi
}

install_jellystat() {
    log_info "Installing Jellystat..."

    # Create installation directory
    if [ -d "${JELLYSTAT_DIR}" ]; then
        log_warn "Jellystat directory already exists. Backing up..."
        mv "${JELLYSTAT_DIR}" "${JELLYSTAT_DIR}.backup.$(date +%Y%m%d%H%M%S)"
    fi

    mkdir -p "${JELLYSTAT_DIR}"

    # Clone Jellystat repository
    log_info "Cloning Jellystat repository..."
    git clone --branch "${JELLYSTAT_BRANCH}" --depth 1 "${JELLYSTAT_REPO}" "${JELLYSTAT_DIR}"

    # Change to Jellystat directory
    cd "${JELLYSTAT_DIR}"

    # Install npm dependencies
    log_info "Installing npm dependencies (this may take a while)..."
    npm install --production=false

    # Build the application
    log_info "Building Jellystat..."
    npm run build

    # Set ownership
    chown -R "${JELLYSTAT_USER}:${JELLYSTAT_GROUP}" "${JELLYSTAT_DIR}"

    log_info "Jellystat installed successfully"
}

create_env_file() {
    log_info "Creating environment configuration..."

    # Generate JWT secret if not set
    if [ -z "$JWT_SECRET" ]; then
        JWT_SECRET=$(generate_jwt_secret)
        log_info "Generated JWT secret"
    fi

    # Create .env file
    cat > "${JELLYSTAT_DIR}/.env" << EOF
# Jellystat Environment Configuration
# Generated by installer on $(date)

# PostgreSQL Configuration (REQUIRED)
POSTGRES_USER=${POSTGRES_USER}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_IP=${POSTGRES_HOST}
POSTGRES_PORT=${POSTGRES_PORT}
POSTGRES_DB=${POSTGRES_DB}

# JWT Secret (REQUIRED)
JWT_SECRET=${JWT_SECRET}

# Timezone (REQUIRED)
TZ=${TZ}

# Server Configuration
JS_LISTEN_IP=0.0.0.0

# Optional: Base URL (uncomment if using reverse proxy with base path)
# JS_BASE_URL=/jellystat

# Optional: Master Override Credentials (uncomment if needed)
# JS_USER=admin
# JS_PASSWORD=your_password

# Optional: Allow self-signed certificates
REJECT_SELF_SIGNED_CERTIFICATES=true

# Optional: MaxMind GeoLite2 (for IP geolocation)
# JS_GEOLITE_ACCOUNT_ID=
# JS_GEOLITE_LICENSE_KEY=

# Optional: Minimum playback time to record (in seconds)
MINIMUM_SECONDS_TO_INCLUDE_PLAYBACK=1

# Set to true if using Emby instead of Jellyfin
IS_EMBY_API=false
EOF

    # Secure the .env file
    chmod 600 "${JELLYSTAT_DIR}/.env"
    chown "${JELLYSTAT_USER}:${JELLYSTAT_GROUP}" "${JELLYSTAT_DIR}/.env"

    log_info "Environment file created at ${JELLYSTAT_DIR}/.env"
}

create_rc_script() {
    log_info "Creating rc.d service script..."

    cat > /usr/local/etc/rc.d/jellystat << 'EOF'
#!/bin/sh

# PROVIDE: jellystat
# REQUIRE: LOGIN postgresql
# KEYWORD: shutdown

. /etc/rc.subr

name="jellystat"
rcvar="jellystat_enable"

load_rc_config $name

: ${jellystat_enable:="NO"}
: ${jellystat_user:="jellystat"}
: ${jellystat_group:="jellystat"}
: ${jellystat_dir:="/usr/local/jellystat"}
: ${jellystat_env:="${jellystat_dir}/.env"}

pidfile="/var/run/${name}.pid"
logfile="/var/log/${name}.log"

# Node.js path
node_path="/usr/local/bin/node"

start_cmd="${name}_start"
stop_cmd="${name}_stop"
status_cmd="${name}_status"
restart_cmd="${name}_restart"

jellystat_start()
{
    if [ -f "${pidfile}" ]; then
        if kill -0 $(cat ${pidfile}) 2>/dev/null; then
            echo "${name} is already running."
            return 1
        fi
    fi

    echo "Starting ${name}..."

    # Source environment file
    if [ -f "${jellystat_env}" ]; then
        set -a
        . "${jellystat_env}"
        set +a
    fi

    cd "${jellystat_dir}"

    /usr/sbin/daemon -p ${pidfile} -u ${jellystat_user} \
        -o ${logfile} \
        ${node_path} ${jellystat_dir}/backend/server.js

    sleep 2

    if [ -f "${pidfile}" ] && kill -0 $(cat ${pidfile}) 2>/dev/null; then
        echo "${name} started successfully (PID: $(cat ${pidfile}))"
    else
        echo "Failed to start ${name}"
        return 1
    fi
}

jellystat_stop()
{
    if [ -f "${pidfile}" ]; then
        echo "Stopping ${name}..."
        kill $(cat ${pidfile}) 2>/dev/null
        rm -f ${pidfile}
        echo "${name} stopped."
    else
        echo "${name} is not running."
    fi
}

jellystat_status()
{
    if [ -f "${pidfile}" ]; then
        if kill -0 $(cat ${pidfile}) 2>/dev/null; then
            echo "${name} is running (PID: $(cat ${pidfile}))"
            return 0
        fi
    fi
    echo "${name} is not running."
    return 1
}

jellystat_restart()
{
    jellystat_stop
    sleep 2
    jellystat_start
}

run_rc_command "$1"
EOF

    chmod +x /usr/local/etc/rc.d/jellystat

    # Enable the service
    sysrc jellystat_enable="YES"

    log_info "Service script created and enabled"
}

start_jellystat() {
    log_info "Starting Jellystat service..."
    service jellystat start

    sleep 3

    if service jellystat status >/dev/null 2>&1; then
        log_info "Jellystat is running!"
    else
        log_error "Failed to start Jellystat. Check /var/log/jellystat.log for details."
        exit 1
    fi
}

print_summary() {
    # Get the jail/server IP
    IP_ADDR=$(ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}')

    printf "\n"
    printf "%b╔═══════════════════════════════════════════════════════════════╗%b\n" "${GREEN}" "${NC}"
    printf "%b║              Installation Complete!                           ║%b\n" "${GREEN}" "${NC}"
    printf "%b╚═══════════════════════════════════════════════════════════════╝%b\n" "${GREEN}" "${NC}"
    printf "\n"
    printf "%bAccess Jellystat:%b\n" "${BLUE}" "${NC}"
    printf "  URL: http://%s:%s\n" "${IP_ADDR}" "${JELLYSTAT_PORT}"
    printf "\n"
    printf "%bPostgreSQL Credentials:%b\n" "${BLUE}" "${NC}"
    printf "  Host:     %s\n" "${POSTGRES_HOST}"
    printf "  Port:     %s\n" "${POSTGRES_PORT}"
    printf "  Database: %s\n" "${POSTGRES_DB}"
    printf "  User:     %s\n" "${POSTGRES_USER}"
    printf "  Password: %s\n" "${POSTGRES_PASSWORD}"
    printf "\n"
    printf "%bImportant Files:%b\n" "${BLUE}" "${NC}"
    printf "  Installation:  %s\n" "${JELLYSTAT_DIR}"
    printf "  Config:        %s/.env\n" "${JELLYSTAT_DIR}"
    printf "  Log:           /var/log/jellystat.log\n"
    printf "  Service:       /usr/local/etc/rc.d/jellystat\n"
    printf "\n"
    printf "%bService Commands:%b\n" "${BLUE}" "${NC}"
    printf "  Start:    service jellystat start\n"
    printf "  Stop:     service jellystat stop\n"
    printf "  Restart:  service jellystat restart\n"
    printf "  Status:   service jellystat status\n"
    printf "\n"
    printf "%bIMPORTANT: Save the PostgreSQL password shown above!%b\n" "${YELLOW}" "${NC}"
    printf "\n"
    printf "%bPlease visit the URL above to complete the setup.%b\n" "${GREEN}" "${NC}"
    printf "\n"
}

#####################################################################
# Main Installation
#####################################################################

main() {
    print_banner
    check_root

    log_info "Starting Jellystat installation..."
    echo ""

    install_dependencies
    setup_postgresql
    create_jellystat_user
    install_jellystat
    create_env_file
    create_rc_script
    start_jellystat

    print_summary
}

# Run main function
main "$@"
