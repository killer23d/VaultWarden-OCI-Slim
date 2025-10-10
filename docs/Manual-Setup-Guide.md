# VaultWarden-OCI-Slim Manual Setup Guide

**Alternative setup method for SQLite-based VaultWarden without using `init-setup.sh`**

This guide provides step-by-step manual setup instructions for users who prefer to configure their SQLite-optimized system manually rather than using the automated `init-setup.sh` script.

---

## 📋 Table of Contents

- [Prerequisites](#prerequisites)
- [System Preparation](#system-preparation)
- [Project Setup](#project-setup)
- [Directory Structure Creation](#directory-structure-creation)
- [SQLite Configuration](#sqlite-configuration)
- [Configuration File Creation](#configuration-file-creation)
- [Security and Permissions](#security-and-permissions)
- [Network and DNS Setup](#network-and-dns-setup)
- [Pre-Startup Validation](#pre-startup-validation)
- [Starting the SQLite-Based Stack](#starting-the-sqlite-based-stack)

---

## 🔧 Prerequisites

### System Requirements
- **Operating System**: Ubuntu 22.04+ LTS (recommended) or compatible Linux distribution
- **Resources**: Minimum 4GB RAM, 20GB disk space (optimized for OCI A1 Flex 1 OCPU/6GB)
- **Network**: Internet connectivity for container image downloads and Let's Encrypt certificates
- **Domain**: Valid domain name with DNS pointing to your server
- **Email**: SMTP account for notifications and password resets

### OCI A1 Flex Optimization
This guide is specifically optimized for Oracle Cloud Infrastructure A1 Flex instances:
- **CPU**: 1 OCPU (4 ARM cores)
- **Memory**: 6GB RAM
- **Storage**: 20GB+ boot volume
- **Network**: Public IP with security groups configured

### Software Prerequisites
```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install required utilities
sudo apt install -y curl wget git unzip sqlite3 gpg

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo apt install -y docker-compose-plugin

# Logout and login to apply Docker group changes
```

---

## 🚀 System Preparation

### 1. Create VaultWarden User (Optional but Recommended)
```bash
# Create dedicated user for VaultWarden
sudo useradd -m -s /bin/bash vaultwarden
sudo usermod -aG docker vaultwarden

# Switch to vaultwarden user for setup
sudo su - vaultwarden
```

### 2. Configure System Limits for SQLite Performance
```bash
# Optimize system limits for SQLite and OCI A1 Flex
sudo tee -a /etc/security/limits.conf << EOF
# VaultWarden-OCI-Slim SQLite optimizations
vaultwarden soft nofile 65536
vaultwarden hard nofile 65536
vaultwarden soft nproc 32768
vaultwarden hard nproc 32768
EOF

# Apply limits immediately
ulimit -n 65536
ulimit -u 32768
```

### 3. Configure Firewall (if using UFW)
```bash
# Configure firewall for VaultWarden services
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP (for Let's Encrypt)
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

---

## 📁 Project Setup

### 1. Clone Repository
```bash
# Clone the VaultWarden-OCI-Slim repository
git clone https://github.com/killer23d/VaultWarden-OCI-Slim.git
cd VaultWarden-OCI-Slim

# Make all scripts executable
chmod +x *.sh
find . -name "*.sh" -type f -exec chmod +x {} \;
```

### 2. Verify Repository Structure
```bash
# Verify key SQLite-optimized files exist
ls -la | grep -E "(startup|diagnose|monitor|oci-setup)\.sh"
ls -la backup/
ls -la backup/full-backup/

# Expected structure for SQLite deployment:
# ./startup.sh - Main service startup with SQLite auto-init
# ./diagnose.sh - System health checks including SQLite
# ./monitor.sh - Real-time monitoring with SQLite metrics
# ./oci-setup.sh - OCI Vault integration with OCISECRET_OCID
# ./backup/ - SQLite backup system
```

---

## 🗂️ Directory Structure Creation

### 1. Create Required Directories
```bash
# Create directory structure for SQLite-based deployment
mkdir -p data/{bwdata,backups,logs}
mkdir -p data/caddy/{data,config}
mkdir -p data/fail2ban
mkdir -p logs

# SQLite-specific directories
mkdir -p data/sqlite-backups
mkdir -p data/sqlite-temp

# Set appropriate ownership
chown -R $(id -u):$(id -g) data/
chown -R $(id -u):$(id -g) logs/
```

### 2. Verify Directory Permissions
```bash
# Check directory structure and permissions
tree data/ 2>/dev/null || find data/ -type d

# Ensure proper permissions for SQLite database
chmod 755 data/bwdata
chmod 755 data/backups
chmod 755 data/logs
```

---

## 🗃️ SQLite Configuration

### 1. SQLite Database Optimization
```bash
# Create SQLite optimization configuration
cat > data/sqlite-config.conf << EOF
# SQLite configuration for OCI A1 Flex (1 OCPU/6GB)
# Applied automatically by VaultWarden

# Performance settings
journal_mode = WAL
synchronous = NORMAL
cache_size = 10000
page_size = 4096

# Security settings
foreign_keys = ON
secure_delete = ON

# Optimization settings
temp_store = memory
mmap_size = 268435456
EOF

echo "✅ SQLite configuration created"
```

### 2. Pre-create SQLite Database Directory
```bash
# Ensure SQLite database directory exists with proper permissions
mkdir -p data/bwdata
touch data/bwdata/.keep

# Verify SQLite can create databases in this location
sqlite3 data/bwdata/test.sqlite3 "CREATE TABLE test (id INTEGER); DROP TABLE test;"
rm data/bwdata/test.sqlite3

echo "✅ SQLite database directory prepared"
```

---

## ⚙️ Configuration File Creation

### 1. Generate Required Secrets
```bash
# Generate secure secrets for SQLite-based deployment
ADMIN_TOKEN=$(openssl rand -hex 32)
BACKUP_PASSPHRASE=$(openssl rand -base64 32)
JWT_SECRET=$(openssl rand -base64 64)

echo "Generated secrets:"
echo "ADMIN_TOKEN: $ADMIN_TOKEN"
echo "BACKUP_PASSPHRASE: $BACKUP_PASSPHRASE"
echo "JWT_SECRET: $JWT_SECRET"
echo ""
echo "⚠️ SAVE THESE SECRETS SECURELY - THEY CANNOT BE RECOVERED"
```

### 2. Create settings.env File
```bash
# Create SQLite-optimized configuration file
cat > settings.env << EOF
# VaultWarden-OCI-Slim SQLite Configuration
# Optimized for Oracle Cloud Infrastructure A1 Flex (1 OCPU/6GB)

# Domain Configuration
DOMAIN_NAME=yourdomain.com
APP_DOMAIN=vault.yourdomain.com
DOMAIN=https://vault.yourdomain.com

# Admin Configuration
ADMIN_EMAIL=your-email@yourdomain.com
ADMIN_TOKEN=$ADMIN_TOKEN

# SQLite Database Configuration (OPTIMIZED FOR OCI A1 FLEX)
DATABASE_URL=sqlite:///data/db.sqlite3
ROCKET_WORKERS=1
WEBSOCKET_ENABLED=false

# Security Configuration
JWT_SECRET=$JWT_SECRET
BACKUP_PASSPHRASE=$BACKUP_PASSPHRASE

# SMTP Configuration (Required for password resets)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURITY=starttls
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_FROM=noreply@yourdomain.com

# Backup Configuration for SQLite
BACKUP_ENABLED=true
BACKUP_SCHEDULE=0 3 * * *
BACKUP_RETENTION_DAYS=30
BACKUP_FORMAT=both

# Performance Settings for OCI A1 Flex
ROCKET_ADDRESS=0.0.0.0
ROCKET_PORT=8080
ROCKET_LOG_LEVEL=warn

# Security Settings
INVITATIONS_ALLOWED=true
SIGNUPS_ALLOWED=false
SHOW_PASSWORD_HINT=false
PASSWORD_ITERATIONS=100000

# OCI Vault Integration (Optional)
# OCISECRET_OCID=ocid1.vaultsecret.oc1..your-secret-id

# Email Notifications
SEND_EMAIL_NOTIFICATION=true
EMAIL_ATTEMPTS=3
EMAIL_EXPIRATION_TIME=600

# Fail2ban Integration
FAIL2BAN_ENABLED=true
FAIL2BAN_BANTIME=86400
FAIL2BAN_FINDTIME=600
FAIL2BAN_MAXRETRY=3
EOF

echo "✅ settings.env file created with SQLite optimizations"
```

### 3. Customize Configuration
```bash
# Edit the configuration file with your actual values
nano settings.env

# Required changes:
# - Replace yourdomain.com with your actual domain
# - Replace email addresses with your actual email
# - Replace SMTP settings with your actual SMTP configuration
# - Keep the generated ADMIN_TOKEN and BACKUP_PASSPHRASE values
# - Ensure DATABASE_URL remains sqlite:///data/db.sqlite3
# - Keep ROCKET_WORKERS=1 for SQLite optimization
```

### 4. Validate Configuration
```bash
# Validate configuration file syntax
source settings.env

# Check critical SQLite settings
echo "Database URL: $DATABASE_URL"
echo "Rocket Workers: $ROCKET_WORKERS"
echo "WebSocket Enabled: $WEBSOCKET_ENABLED"
echo "Domain: $DOMAIN"
echo "Admin Token Length: ${#ADMIN_TOKEN}"

# Ensure SQLite-specific settings are correct
if [[ "$DATABASE_URL" == *"sqlite"* ]]; then
    echo "✅ SQLite database configuration detected"
else
    echo "❌ Database URL does not specify SQLite"
fi

if [[ "$ROCKET_WORKERS" == "1" ]]; then
    echo "✅ Single worker configuration (SQLite optimized)"
else
    echo "⚠️ Multiple workers detected - not optimal for SQLite"
fi
```

---

## 🔒 Security and Permissions

### 1. Secure Configuration Files
```bash
# Set secure permissions on configuration files
chmod 600 settings.env
chown $(id -u):$(id -g) settings.env

# Verify permissions
ls -la settings.env
```

### 2. Create Docker Compose Override (Optional)
```bash
# Create override for additional SQLite-specific settings
cat > docker-compose.override.yml << EOF
version: '3.8'

services:
  vaultwarden:
    environment:
      # SQLite-specific optimizations for OCI A1 Flex
      - ROCKET_WORKERS=1
      - WEBSOCKET_ENABLED=false
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
        reservations:
          memory: 200M
          cpus: '0.2'

  caddy:
    deploy:
      resources:
        limits:
          memory: 128M
          cpus: '0.2'
        reservations:
          memory: 50M
          cpus: '0.1'
EOF

echo "✅ Docker Compose override created with resource limits"
```

---

## 🌐 Network and DNS Setup

### 1. Verify DNS Configuration
```bash
# Check DNS resolution for your domain
dig +short vault.yourdomain.com
nslookup vault.yourdomain.com

# Verify DNS points to your server's public IP
curl -s ifconfig.me  # Your public IP
```

### 2. Test Network Connectivity
```bash
# Test outbound connectivity (required for Let's Encrypt)
curl -s https://acme-v02.api.letsencrypt.org/directory > /dev/null && echo "✅ Let's Encrypt connectivity OK"

# Test Docker registry connectivity
curl -s https://registry-1.docker.io/v2/ > /dev/null && echo "✅ Docker registry connectivity OK"
```

---

## 🔍 Pre-Startup Validation

### 1. Run System Diagnostics
```bash
# Run comprehensive pre-startup checks
./diagnose.sh --quick

# Expected output should show:
# ✅ Docker daemon running
# ✅ Docker Compose available
# ✅ Configuration file valid
# ✅ Required directories exist
# ✅ DNS resolution working
# ✅ SQLite database directory writable
```

### 2. Validate SQLite Readiness
```bash
# Test SQLite installation and functionality
sqlite3 --version

# Test SQLite database creation in target directory
sqlite3 data/bwdata/startup_test.sqlite3 "
CREATE TABLE test_table (id INTEGER PRIMARY KEY, name TEXT);
INSERT INTO test_table (name) VALUES ('startup_test');
SELECT COUNT(*) FROM test_table;
PRAGMA integrity_check;
"

# Clean up test database
rm data/bwdata/startup_test.sqlite3

echo "✅ SQLite functionality validated"
```

### 3. Pre-validate Docker Images
```bash
# Pre-pull required Docker images
docker compose pull

# Verify images are available
docker images | grep -E "(vaultwarden|caddy)"

echo "✅ Docker images ready"
```

---

## 🚀 Starting the SQLite-Based Stack

### 1. Initial Startup with SQLite Auto-Initialization
```bash
# Start VaultWarden with automatic SQLite database creation
echo "🚀 Starting VaultWarden-OCI-Slim with SQLite..."
./startup.sh

# The startup process automatically:
# 1. 🗃️ Creates SQLite database file at data/bwdata/db.sqlite3
# 2. ⚙️ Configures optimal SQLite settings (WAL mode, cache size, etc.)
# 3. 🚀 Initializes VaultWarden schema on first startup
# 4. 🔧 Applies OCI A1 Flex performance optimizations
# 5. ⚡ Starts all supporting services (Caddy, Fail2ban)
# 6. 🔍 Validates service health and SQLite connectivity
```

### 2. Monitor Startup Progress
```bash
# Monitor the startup process
./monitor.sh

# Watch Docker container logs
docker compose logs -f --tail 50

# Check specific SQLite startup logs
docker compose logs vaultwarden | grep -i sqlite
docker compose logs vaultwarden | grep -i database
```

### 3. Validate SQLite Database Creation
```bash
# Wait for startup to complete (30-60 seconds)
sleep 60

# Verify SQLite database was created and initialized
ls -la data/bwdata/db.sqlite3
sqlite3 data/bwdata/db.sqlite3 "
.tables
SELECT COUNT(*) FROM users;
PRAGMA journal_mode;
PRAGMA integrity_check;
"

echo "✅ SQLite database initialized successfully"
```

### 4. Verify Service Health
```bash
# Run comprehensive health check
./diagnose.sh

# Test web access
curl -k https://localhost/alive
curl -k https://vault.yourdomain.com/alive

# Test admin panel access
curl -k https://vault.yourdomain.com/admin

echo "✅ VaultWarden services healthy"
```

### 5. Initial Configuration Tasks
```bash
# Create first admin user (do this via web interface)
echo "📝 Next steps:"
echo "1. Visit https://vault.yourdomain.com/admin"
echo "2. Use ADMIN_TOKEN from settings.env to login"
echo "3. Create your first user account"
echo "4. Configure backup schedules"
echo "5. Test email functionality"

# Setup automated backups
./backup/full-backup/setup-automated-full-backup.sh

# Test backup system
./backup/db-backup.sh --force
```

---

## 🎯 Post-Setup Optimization for OCI A1 Flex

### 1. Resource Usage Validation
```bash
# Monitor resource usage (should be under OCI A1 Flex limits)
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

# Expected resource usage:
# vaultwarden: ~15% CPU, ~200MB RAM
# caddy: ~2% CPU, ~50MB RAM
# fail2ban: ~1% CPU, ~25MB RAM
# Total: ~18% CPU, ~275MB RAM (well under 1 OCPU/6GB limits)
```

### 2. SQLite Performance Optimization
```bash
# Apply SQLite optimizations (these should already be configured)
sqlite3 data/bwdata/db.sqlite3 "
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA cache_size=10000;
PRAGMA foreign_keys=ON;
PRAGMA temp_store=memory;
ANALYZE;
PRAGMA optimize;
"

# Verify optimizations applied
sqlite3 data/bwdata/db.sqlite3 "
SELECT name, value FROM pragma_compile_options() WHERE name LIKE '%WAL%';
PRAGMA journal_mode;
PRAGMA cache_size;
"
```

### 3. Setup Automated Monitoring
```bash
# Setup monthly disaster recovery testing
crontab -e
# Add: 0 3 1 * * /full/path/to/VaultWarden-OCI-Slim/backup/dr-monthly-test.sh

# Setup performance monitoring alerts
./alerts.sh --setup-monitoring

# Test email notifications
./alerts.sh --test-email
```

---

## ✅ Manual Setup Completion Checklist

### Essential Validations
- [ ] SQLite database created at `data/bwdata/db.sqlite3`
- [ ] WAL mode enabled (`PRAGMA journal_mode` returns `wal`)
- [ ] VaultWarden accessible at `https://vault.yourdomain.com`
- [ ] Admin panel accessible at `https://vault.yourdomain.com/admin`
- [ ] SSL certificate automatically provisioned via Let's Encrypt
- [ ] Resource usage under OCI A1 Flex limits (~300MB RAM, ~0.5 OCPU)

### Security Validations
- [ ] `settings.env` file has secure permissions (600)
- [ ] ADMIN_TOKEN is 64 characters (32 bytes hex)
- [ ] BACKUP_PASSPHRASE is securely generated
- [ ] Fail2ban active and configured
- [ ] Firewall configured (ports 80, 443, 22 only)

### Backup System Validations
- [ ] Daily SQLite backup scheduled
- [ ] Backup encryption working with BACKUP_PASSPHRASE
- [ ] Monthly disaster recovery test scheduled
- [ ] Cloud storage configured (if desired)
- [ ] Email notifications working

### Performance Validations
- [ ] ROCKET_WORKERS=1 (single worker for SQLite efficiency)
- [ ] WEBSOCKET_ENABLED=false (disabled for resource optimization)
- [ ] SQLite WAL mode enabled for concurrent read performance
- [ ] Total memory usage < 500MB (leaves room for OS)

---

## 🔧 Troubleshooting Manual Setup

### Common SQLite Issues
```bash
# Issue: SQLite database not created
# Solution: Check directory permissions
ls -la data/bwdata/
chmod 755 data/bwdata/

# Issue: Database locked errors
# Solution: Ensure single worker configuration
grep ROCKET_WORKERS settings.env  # Should be 1

# Issue: Poor SQLite performance
# Solution: Verify WAL mode enabled
sqlite3 data/bwdata/db.sqlite3 "PRAGMA journal_mode;"
```

### Resource Usage Issues
```bash
# Issue: High memory usage on OCI A1 Flex
# Solution: Verify resource limits in docker-compose.override.yml
docker stats --no-stream

# Issue: CPU usage too high
# Solution: Check worker configuration
docker compose logs vaultwarden | grep -i worker
```

### Configuration Issues
```bash
# Issue: Can't access web interface
# Solution: Check domain/DNS configuration
./diagnose.sh --quick

# Issue: SMTP not working
# Solution: Test SMTP settings
./alerts.sh --test-email
```

---

The manual setup process provides complete control over VaultWarden-OCI-Slim configuration with SQLite optimization for Oracle Cloud Infrastructure A1 Flex instances, using standardized `oci-setup.sh` script and `OCISECRET_OCID` variable naming throughout.
