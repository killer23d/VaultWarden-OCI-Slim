# VaultWarden-OCI-Slim SQLite Backup & Restore Guide

Comprehensive documentation for the SQLite-based automated backup system with cloud storage integration, disaster recovery, and enterprise-grade secret management.

---

## 📋 Table of Contents

- [SQLite Backup System Overview](#sqlite-backup-system-overview)
- [SQLite Database Initialization](#sqlite-database-initialization)
- [Daily SQLite Backups](#daily-sqlite-backups)
- [Full System Backups (VM-level)](#full-system-backups-vm-level)
- [Full System Disaster Recovery](#full-system-disaster-recovery)
- [Monthly Disaster Recovery Testing](#monthly-disaster-recovery-testing)
- [Cloud Storage Integration](#cloud-storage-integration)
- [OCI Vault Integration](#oci-vault-integration)
- [SQLite Backup Management](#sqlite-backup-management)
- [Troubleshooting](#troubleshooting)

---

## 🔄 SQLite Backup System Overview

VaultWarden-OCI-Slim implements a comprehensive two-tier backup strategy optimized for SQLite databases with automated monthly disaster recovery testing.

### Backup Architecture

The system provides two complementary backup levels:

1. **Database Backups (Daily)**: SQLite database files with multiple formats
2. **Full System Backups (Weekly)**: Complete VM state including configuration and system files

### SQLite-Specific Backup Features
- **SQL Dump Format** - Maximum portability across systems
- **Compressed Backups** - Efficient storage with gzip compression
- **Encrypted Backups** - GPG encryption with configurable passphrase
- **Integrity Validation** - Built-in SQLite integrity checks
- **Cross-Platform Restore** - Works on Linux, macOS, and other platforms

### Quick Commands Reference

| Operation | Command | Use Case |
|-----------|---------|----------|
| **Manual SQLite Backup** | `./backup/db-backup.sh --force` | Manual SQLite database backup |
| **Full System Backup** | `./backup/full-backup/create-full-backup.sh` | Complete system backup |  
| **Setup Automation** | `./backup/full-backup/setup-automated-full-backup.sh` | Configure automated backups |
| **Restore SQLite DB** | `./backup/db-restore.sh backup.sql.gpg` | Restore from daily SQLite backup |
| **Disaster Recovery** | `./backup/full-backup/rebuild-vm.sh backup.tar.gz` | Complete VM rebuild |
| **Validate Backups** | `./backup/verify-backup.sh --latest` | Test backup integrity |
| **Monthly DR Test** | `./backup/dr-monthly-test.sh` | Automated disaster recovery validation |

---

## 🗃️ SQLite Database Initialization

### Automatic SQLite Database Creation

The VaultWarden deployment **automatically handles all SQLite database setup**:

```bash
# The startup.sh script automatically:
# 1. 🗃️ Creates SQLite database file at /data/bwdata/db.sqlite3
# 2. 🏗️ Initializes VaultWarden schema on first startup
# 3. ⚡ Configures SQLite for optimal OCI A1 Flex performance
# 4. 🔧 Enables WAL mode for concurrent read performance
# 5. 💾 Sets up backup-friendly configuration

./startup.sh  # Handles complete SQLite database initialization
```

❌ **You do NOT need to:**
- Manually create SQLite database files
- Run SQL initialization scripts  
- Configure database connections
- Set up database schemas
- Install SQLite server software

✅ **The system automatically:**
- Creates SQLite database file
- Sets up optimal SQLite configuration
- Enables WAL mode for performance
- Configures automated backup capabilities
- Applies OCI A1 Flex optimizations

### SQLite Configuration Details

The deployment uses these optimized SQLite settings:
```bash
# In settings.env (already configured):
DATABASE_URL=sqlite:///data/db.sqlite3
ROCKET_WORKERS=1          # Single worker optimized for SQLite
WEBSOCKET_ENABLED=false   # Disabled for efficiency

# SQLite File Location:
# Host: ./data/bwdata/db.sqlite3
# Container: /data/db.sqlite3

# Automatic SQLite Optimizations:
# - WAL mode for concurrent reads
# - Optimized cache_size for 6GB RAM systems
# - Optimized page_size for OCI storage
# - Foreign key constraints enabled
# - Secure_delete enabled for data protection
```

---

## 💾 Daily SQLite Backups

### Automated SQLite Backup Process

```bash
# SQLite backup runs automatically with these features:
# 🗃️ Online backup using SQLite .backup command (no downtime)
# 📦 SQL dump format for maximum portability
# 🗜️ Gzip compression to reduce storage requirements
# 🔐 GPG encryption for security
# ☁️ Cloud storage upload (rclone integration)
# 🧹 Automatic old backup cleanup with retention policy

# Manual backup execution:
./backup/db-backup.sh --force
```

### SQLite Backup Format Options

The system creates multiple backup formats:

1. **Binary Backup** (`.sqlite3.gz`):
   - Fast, compact binary copy
   - Best for same-version SQLite restores
   - Preserves all SQLite-specific features

2. **SQL Dump Backup** (`.sql.gz`):
   - Human-readable SQL statements
   - Maximum portability across SQLite versions
   - Easy to inspect and modify

3. **Encrypted Backups** (`.gpg` extension):
   - Any backup can be GPG-encrypted
   - Uses AES256 encryption with secure parameters
   - Requires BACKUP_PASSPHRASE for decryption

---

## 📦 Full System Backups (VM-level)

### Overview

Full system backups provide complete VM-level disaster recovery capabilities, capturing the entire VaultWarden deployment state including SQLite database, configuration files, scripts, and system state.

### Full System Backup Features

- **📦 Complete System Archive**: Entire VM state, configuration, and data
- **🔄 Automated VM Rebuild**: Disaster recovery with automated VM reconstruction
- **🔐 Encrypted Archives**: GPG-encrypted full system backups
- **☁️ Cloud Storage Integration**: Upload to OCI Object Storage or other cloud providers
- **🧪 Automated Testing**: Monthly DR validation with complete system restore
- **📧 Comprehensive Reporting**: Detailed backup status and validation reports

### Setting Up Full System Backups

#### 1. Interactive Setup

```bash
# Configure automated full system backups
./backup/full-backup/setup-automated-full-backup.sh

# This interactive setup will configure:
# - Weekly backup schedule (default: Sunday 3 AM)
# - Cloud storage integration (rclone)
# - GPG encryption keys
# - Email notifications
# - Retention policies
# - Integration with existing database backups
```

#### 2. Manual Configuration

```bash
# Edit settings.env to add full backup settings
nano settings.env

# Add full system backup configuration:
FULL_BACKUP_ENABLED=true
FULL_BACKUP_SCHEDULE="0 3 * * 0"        # Weekly on Sunday 3 AM
FULL_BACKUP_RETENTION_WEEKS=4           # Keep 4 weekly backups
FULL_BACKUP_RETENTION_MONTHS=12         # Keep 12 monthly backups
FULL_BACKUP_CLOUD_STORAGE=true          # Upload to cloud storage
FULL_BACKUP_ENCRYPTION=true             # GPG encrypt archives
```

### On-Demand Full System Backup

```bash
# Create manual full system backup
./backup/full-backup/create-full-backup.sh

# Full system backup process:
# 1. 📊 Creates SQLite database backup
# 2. 📁 Archives all configuration files
# 3. 🔧 Backs up scripts and customizations
# 4. 📊 Captures container configurations
# 5. 🔐 Encrypts complete archive with GPG
# 6. 🗜️ Compresses for storage efficiency
# 7. ☁️ Uploads to configured cloud storage
# 8. 📝 Generates backup manifest and metadata
# 9. ✅ Validates archive integrity
# 10. 📧 Sends completion notification
```

### Full System Backup Contents

A complete full system backup includes:

```bash
# Database Components
./data/bwdata/db.sqlite3          # SQLite database file
./data/bwdata/db.sqlite3-wal      # WAL file (if exists)
./data/bwdata/db.sqlite3-shm      # Shared memory file (if exists)

# Configuration Files
./settings.env                    # Main configuration
./docker-compose.yml              # Container orchestration
./caddy/Caddyfile                # Reverse proxy configuration
./fail2ban/                      # Security configuration
./ddclient/                      # Dynamic DNS configuration

# Scripts and Tools
./*.sh                           # All management scripts
./backup/                        # Complete backup system
./lib/                          # Shared libraries and functions

# SSL/TLS Certificates
./caddy/data/                    # Automatic HTTPS certificates
./caddy/config/                  # Caddy configuration data

# Logs (Recent)
./logs/                          # System and application logs (last 30 days)

# Custom Configurations
./config/                        # Custom configuration overrides
```

### Full Backup Validation

```bash
# Validate latest full system backup
./backup/full-backup/validate-backup.sh latest

# Comprehensive validation includes:
# 🔍 Archive integrity verification (checksums, signatures)
# 📦 Decompression and decryption testing
# 🗃️ SQLite database integrity validation
# 📁 Configuration file completeness check
# 🔧 Script and permission validation
# 🐳 Container restore testing (disposable environment)
# ⚡ Service startup validation in test environment
# 📊 Performance benchmarking of restored system

# Deep validation with restore testing
./backup/full-backup/validate-backup.sh --deep latest
```

### Full System Backup Scheduling

```bash
# Set up automated weekly full system backups
crontab -e

# Add weekly full system backup (Sunday 3 AM)
0 3 * * 0 /full/path/to/VaultWarden-OCI-Slim/backup/full-backup/create-full-backup.sh --automated

# Coordinate with existing backup schedule:
# - Daily database backups: 2 AM
# - Weekly full system backups: 3 AM Sunday
# - Monthly DR testing: 3:30 AM first Sunday
```

### Full System Backup Management

```bash
# Backup management interface
./backup/full-backup/backup-manager.sh status    # Show backup status
./backup/full-backup/backup-manager.sh list      # List available backups
./backup/full-backup/backup-manager.sh cleanup   # Remove old backups

# Manual backup operations
./backup/full-backup/create-full-backup.sh --compress-only  # Skip encryption
./backup/full-backup/create-full-backup.sh --automated     # Silent mode for cron

# Backup validation
./backup/full-backup/validate-backup.sh --all              # Test all backups
```

### Full System Backup Retention

The system implements intelligent retention policies:

```bash
# Default retention policy:
# - Keep all backups for 30 days
# - Keep weekly backups for 4 weeks (1 month)
# - Keep monthly backups for 12 months (1 year)
# - Keep yearly backups indefinitely (until manual cleanup)

# Configure retention in settings.env:
FULL_BACKUP_RETENTION_DAYS=30           # Daily retention
FULL_BACKUP_RETENTION_WEEKS=4           # Weekly retention
FULL_BACKUP_RETENTION_MONTHS=12         # Monthly retention
FULL_BACKUP_RETENTION_YEARS=0           # Yearly retention (0=keep all)
```

---

## 🧪 Monthly Disaster Recovery Testing

### SQLite-Specific DR Testing

```bash
# Run monthly SQLite DR test  
./backup/dr-monthly-test.sh

# SQLite DR Test Features:
# 🐳 Uses disposable SQLite container (no production impact)
# 🗃️ Tests SQLite backup restoration and integrity
# 🔓 Intelligent secret sourcing (OCI Vault, settings.env, environment)
# 📧 Email notifications with SQLite-specific metrics
# 🧹 Automatic cleanup to save disk space
# 🖥️ Cross-platform compatible (Linux, macOS, BSD)
# 📊 Generates JSON reports with SQLite performance metrics
```

### SQLite DR Test Process

1. **Backup Discovery**: Locates latest SQLite backup files
2. **Container Spin-up**: Creates temporary SQLite-compatible container
3. **Restoration Test**: Restores SQLite database from backup
4. **Integrity Check**: Runs `PRAGMA integrity_check` on restored database
5. **Data Validation**: Verifies key tables and record counts
6. **Performance Test**: Basic SQLite query performance validation
7. **Cleanup**: Removes temporary containers and files
8. **Reporting**: Generates detailed JSON report with metrics

### Setup Monthly Automation

```bash
# Add to crontab for automated monthly testing
crontab -e

# Run on 1st of each month at 3 AM
0 3 1 * * /full/path/to/VaultWarden-OCI-Slim/backup/dr-monthly-test.sh

# Configure email notifications in settings.env:
SEND_EMAIL_NOTIFICATION=true
ADMIN_EMAIL=your-email@domain.com

# Test manually first:
./backup/dr-monthly-test.sh
```

---

## 🚨 Full System Disaster Recovery

### Complete VM Recovery Process

In case of complete VM failure, use the full system backup to rebuild:

```bash
# 1. Provision new VM (OCI A1 Flex recommended)
# 2. Install basic dependencies (automated by rebuild script)
# 3. Download full system backup from cloud storage
# 4. Run automated rebuild process

./backup/full-backup/rebuild-vm.sh latest

# Automated VM rebuild includes:
# 🏗️ Fresh system preparation and dependency installation
# 📦 Automated Docker and Docker Compose installation
# 🗃️ Complete system restoration from backup archive
# ⚙️ Configuration adaptation for new environment
# 🔧 Permission and ownership restoration
# 🌐 Network and firewall configuration
# ⚡ Service startup with health validation
# 📊 Post-rebuild system validation and testing
# 📧 Rebuild completion notification with system status
```

### Manual Full System Restoration

```bash
# Alternative manual restoration process
./backup/full-backup/restore-full-backup.sh backup.tar.gz

# Manual restoration process:
# 1. 🛑 Stops all running services gracefully
# 2. 🗃️ Backs up current system state
# 3. 📦 Decompresses and decrypts full backup archive
# 4. 🔄 Restores all system components systematically
# 5. 🗃️ Restores SQLite database with integrity verification
# 6. ⚙️ Restores configuration files and settings
# 7. 🔧 Restores scripts with proper permissions
# 8. ⚡ Restarts all services with health monitoring
# 9. ✅ Validates complete system functionality
# 10. 📧 Sends restoration completion notification
```

---

## 🔐 OCI Vault Integration

### SQLite Backup with OCI Vault

```bash
# All SQLite backup scripts automatically use OCISECRET_OCID:
./backup/db-backup.sh --force           # Uses vault settings
./backup/full-backup/create-full-backup.sh  # Uses vault settings
./backup/dr-monthly-test.sh             # Intelligent vault secret sourcing
```

### Vault-Aware Configuration

```bash
# Download backup configuration from vault
./oci-setup.sh get --output current-backup-config.env

# Update backup settings in vault
./oci-setup.sh update --file updated-backup-config.env

# Test vault connectivity for backup operations
./oci-setup.sh test
```

### SQLite-Specific Vault Secrets

Store these SQLite-related secrets in OCI Vault:
```bash
# Core backup settings
BACKUP_PASSPHRASE=your-secure-passphrase
BACKUP_REMOTE=your-rclone-remote
BACKUP_PATH=vaultwarden-sqlite-backups

# SQLite-specific settings
SQLITE_BACKUP_FORMAT=both               # both, sql, binary
SQLITE_INTEGRITY_CHECK=true            # Verify backup integrity
SQLITE_BACKUP_RETENTION_DAYS=30        # Local backup retention

# Full system backup settings
FULL_BACKUP_PASSPHRASE=your-full-backup-passphrase
FULL_BACKUP_REMOTE=your-rclone-remote
FULL_BACKUP_PATH=vaultwarden-full-backups
```

---

## 🎛️ SQLite Backup Management

### Command Line Management

```bash
# Status and monitoring
./monitor.sh | grep -i backup             # Quick backup status
docker compose logs backup --tail 50      # Recent backup logs (if backup container used)

# SQLite-specific monitoring
ls -la data/backups/*.sqlite3*             # Binary backups
ls -la data/backups/*.sql.gz*             # SQL dump backups
du -h data/backups/                       # Backup storage usage

# Full system backup monitoring
ls -la data/full-backups/*.tar.gz*        # Full system archives
du -h data/full-backups/                  # Full backup storage usage

# Monthly disaster recovery testing
./backup/dr-monthly-test.sh                # Comprehensive SQLite DR validation

# Troubleshooting
./diagnose.sh --backup                    # Backup system diagnosis
./diagnose.sh --database                  # SQLite-specific checks
```

### SQLite Backup Monitoring

```bash
# Check SQLite database size and growth
sqlite3 ./data/bwdata/db.sqlite3 "
SELECT 
    page_count * page_size as size_bytes,
    page_count,
    page_size,
    freelist_count
FROM pragma_page_count(), pragma_page_size(), pragma_freelist_count();
"

# Monitor backup efficiency
ls -lah data/backups/ | grep $(date +%Y-%m-%d)

# Validate latest backup integrity
latest_backup=$(ls -t data/backups/*.sqlite3 2>/dev/null | head -n1)
if [ -n "$latest_backup" ]; then
    sqlite3 "$latest_backup" "PRAGMA integrity_check;"
fi
```

---

## 🔄 SQLite Restore Operations

### Automated SQLite Restore

```bash
# Restore from latest backup
./backup/db-restore.sh --latest

# Restore from specific backup
./backup/db-restore.sh data/backups/vaultwarden_20241006_030001.sql.gz

# Restore process for SQLite:
# 1. 🛑 Stops VaultWarden service
# 2. 🗃️ Backs up current SQLite database
# 3. 📦 Decompresses and decrypts backup if needed
# 4. 🔄 Restores SQLite database from backup
# 5. 🔍 Runs integrity check on restored database
# 6. ⚡ Restarts VaultWarden service
# 7. ✅ Validates service health
```

### Manual SQLite Restore

```bash
# Stop services
docker compose down

# Backup current database
cp ./data/bwdata/db.sqlite3 ./data/bwdata/db.sqlite3.backup

# For SQL dump restore:
zcat data/backups/vaultwarden_20241006_030001.sql.gz | sqlite3 ./data/bwdata/db.sqlite3

# For binary backup restore:
zcat data/backups/vaultwarden_20241006_030001.sqlite3.gz > ./data/bwdata/db.sqlite3

# Verify integrity
sqlite3 ./data/bwdata/db.sqlite3 "PRAGMA integrity_check;"

# Start services
./startup.sh
```

---

## 🔧 Troubleshooting

### SQLite Backup Issues

```bash
# Check SQLite database is accessible
sqlite3 ./data/bwdata/db.sqlite3 "SELECT COUNT(*) FROM users;"

# Check backup script logs
cat logs/backup.log

# Test manual SQLite backup
sqlite3 ./data/bwdata/db.sqlite3 ".backup /tmp/manual_backup.sqlite3"
sqlite3 /tmp/manual_backup.sqlite3 "PRAGMA integrity_check;"
```

### Full System Backup Issues

```bash
# Check full system backup logs
cat logs/full-backup.log

# Test manual archive creation
tar -czf /tmp/test-archive.tar.gz ./data ./settings.env ./docker-compose.yml
tar -tzf /tmp/test-archive.tar.gz | head -20

# Validate cloud storage connectivity (if configured)
rclone ls your-remote: | head -10
```

### Monthly DR Test Issues

```bash
# Check DR test logs
cat logs/dr-monthly-test.log

# Test vault access for BACKUP_PASSPHRASE
./oci-setup.sh test
source settings.env && echo "$BACKUP_PASSPHRASE"

# Check SQLite backup availability
ls -la data/backups/*.sqlite3*
ls -la data/backups/*.sql.gz*

# Check full system backup availability
ls -la data/full-backups/*.tar.gz*

# Test SQLite restore manually
latest_backup=$(ls -t data/backups/*.sql.gz 2>/dev/null | head -n1)
if [ -n "$latest_backup" ]; then
    echo "Testing restore of: $latest_backup"
    zcat "$latest_backup" | sqlite3 /tmp/test_restore.sqlite3
    sqlite3 /tmp/test_restore.sqlite3 "PRAGMA integrity_check;"
    rm /tmp/test_restore.sqlite3
fi
```

### SQLite Performance Issues

```bash
# Check WAL mode (should be enabled)
sqlite3 ./data/bwdata/db.sqlite3 "PRAGMA journal_mode;"

# Check SQLite cache settings
sqlite3 ./data/bwdata/db.sqlite3 "PRAGMA cache_size;"

# Analyze SQLite database
sqlite3 ./data/bwdata/db.sqlite3 "ANALYZE; PRAGMA optimize;"

# Check for database bloat
sqlite3 ./data/bwdata/db.sqlite3 "VACUUM;"
```

---

The VaultWarden-OCI-Slim backup system provides enterprise-grade SQLite database protection with comprehensive full system backup capabilities, automated monthly disaster recovery testing, comprehensive monitoring, and OCI Vault integration using standardized `oci-setup.sh` script and `OCISECRET_OCID` variable naming throughout.
