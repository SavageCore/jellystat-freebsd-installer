# Jellystat FreeBSD Installer

An installer script for [Jellystat](https://github.com/CyferShepard/Jellystat) on TrueNAS Core / FreeBSD.

Jellystat is a free and open source Statistics App for Jellyfin!

## Features

- Automated installation of all dependencies (PostgreSQL, Node.js)
- Creates dedicated service user for security
- Generates secure random passwords and JWT secrets
- Creates FreeBSD rc.d service for automatic startup
- Includes update and uninstall scripts

## Requirements

- TrueNAS Core or FreeBSD 13.x/14.x
- Root access
- Internet connection
- A running Jellyfin server to connect to

## Quick Start

### 1. Create a Jail (TrueNAS Core)

1. Go to **Jails** → **Add**
2. Name: `jellystat`
3. Release: Select your FreeBSD version
4. Configure networking (DHCP or static IP)
5. Click **Save**

### 2. Enter the Jail

```bash
# From TrueNAS shell
iocage console jellystat

# Or if using warden
jexec <jail_id> /bin/sh
```

### 3. Download and Run the Installer

```bash
# Install git first
pkg install -y git

# Clone this repository
git clone https://github.com/YOUR_USERNAME/jellystat-freebsd-installer.git
cd jellystat-freebsd-installer

# Make scripts executable
chmod +x install.sh update.sh uninstall.sh

# Run the installer
./install.sh
```

## Installation Details

The installer will:

1. **Install dependencies:**
   - PostgreSQL 16
   - Node.js 20
   - Git and other required packages

2. **Configure PostgreSQL:**
   - Initialize database cluster
   - Create `jellystat` user and `jfstat` database
   - Generate secure password

3. **Install Jellystat:**
   - Clone from GitHub
   - Install npm dependencies
   - Build the application

4. **Create service:**
   - FreeBSD rc.d service script
   - Automatic startup on boot

## Post-Installation

After installation completes, you'll see:

- **URL** to access Jellystat (http://JAIL_IP:3000)
- **PostgreSQL credentials** (save these!)
- **Service commands**

### First Time Setup

1. Open the Jellystat URL in your browser
2. Create an admin account
3. Add your Jellyfin server:
   - Jellyfin URL (e.g., `http://192.168.1.100:8096`)
   - API key from Jellyfin (Dashboard → API Keys → Add)

## Scripts

### install.sh

Full installation of Jellystat and all dependencies.

```bash
./install.sh
```

### update.sh

Updates Jellystat to the latest version while preserving your configuration.

```bash
./update.sh
```

### uninstall.sh

Removes Jellystat with options to keep or remove data.

```bash
./uninstall.sh
```

## Service Management

```bash
# Start Jellystat
service jellystat start

# Stop Jellystat
service jellystat stop

# Restart Jellystat
service jellystat restart

# Check status
service jellystat status

# View logs
tail -f /var/log/jellystat.log
```

## Configuration

The configuration file is located at `/usr/local/jellystat/.env`

### Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `POSTGRES_USER` | Yes | - | PostgreSQL username |
| `POSTGRES_PASSWORD` | Yes | - | PostgreSQL password |
| `POSTGRES_IP` | Yes | localhost | PostgreSQL host |
| `POSTGRES_PORT` | Yes | 5432 | PostgreSQL port |
| `POSTGRES_DB` | No | jfstat | Database name |
| `JWT_SECRET` | Yes | - | JWT encryption key |
| `TZ` | Yes | Etc/UTC | Timezone |
| `JS_LISTEN_IP` | No | 0.0.0.0 | Listen IP address |
| `JS_BASE_URL` | No | / | Base URL path |
| `REJECT_SELF_SIGNED_CERTIFICATES` | No | true | SSL certificate validation |

### Editing Configuration

```bash
# Edit the configuration
nano /usr/local/jellystat/.env

# Restart to apply changes
service jellystat restart
```

## Troubleshooting

### Service won't start

Check the log file:
```bash
cat /var/log/jellystat.log
```

### Database connection issues

Verify PostgreSQL is running:
```bash
service postgresql status
```

Test database connection:
```bash
su -m postgres -c "psql -U jellystat -d jfstat -c '\l'"
```

### Port already in use

Check what's using port 3000:
```bash
sockstat -l | grep 3000
```

### Permission issues

Reset ownership:
```bash
chown -R jellystat:jellystat /usr/local/jellystat
```

## Backup

### Database Backup

```bash
su -m postgres -c "pg_dump jfstat" > jellystat_backup.sql
```

### Database Restore

```bash
su -m postgres -c "psql jfstat" < jellystat_backup.sql
```

### Full Backup

```bash
# Stop service
service jellystat stop

# Backup database
su -m postgres -c "pg_dump jfstat" > jellystat_db.sql

# Backup config
cp /usr/local/jellystat/.env jellystat_env.backup

# Start service
service jellystat start
```

## Reverse Proxy (Optional)

If you want to run Jellystat behind a reverse proxy (like nginx), set the `JS_BASE_URL` environment variable:

```bash
# In /usr/local/jellystat/.env
JS_BASE_URL=/jellystat
```

Example nginx configuration:

```nginx
location /jellystat {
    proxy_pass http://JAIL_IP:3000;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## License

MIT License - See [LICENSE](LICENSE)

## Credits

- [Jellystat](https://github.com/CyferShepard/Jellystat) by CyferShepard
- [Jellyfin](https://jellyfin.org/) - The Free Software Media System

## Support

- For Jellystat issues: [Jellystat GitHub Issues](https://github.com/CyferShepard/Jellystat/issues)
- For installer issues: Create an issue in this repository
