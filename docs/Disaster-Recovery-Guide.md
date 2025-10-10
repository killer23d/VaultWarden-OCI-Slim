# VaultWarden-OCI-Slim Disaster Recovery Guide

Complete VM migration and disaster recovery procedures with automated monthly testing for SQLite-based deployments.

---

## 🚨 Disaster Recovery Overview

VaultWarden-OCI-Slim provides comprehensive disaster recovery optimized for SQLite databases with automated monthly validation testing and complete full system backup capabilities.

### Recovery Objectives
- **RTO (Recovery Time)**: 10-30 minutes for complete VM rebuild (SQLite optimized)
- **RPO (Recovery Point)**: Maximum 7 days data loss (weekly full backup interval)
- **Database RPO**: Maximum 24 hours (daily SQLite backup interval)
- **Database Size**: Optimized for SQLite files up to 500MB

### Recovery Scenarios Supported
1. **SQLite Database Issues**: Corruption, accidental deletion, or performance problems
2. **Complete VM Failure**: Hardware failure, cloud instance termination, or OS corruption
3. **Configuration Loss**: Settings, certificates, or script corruption
4. **Full Disaster**: Complete infrastructure loss requiring rebuild from backups

---

## ⚡ Quick Recovery Commands

| Emergency | Command | Recovery Time |
|-----------|---------|---------------|
| **SQLite Database Issues** | `./backup/db-restore.sh --latest` | 2-10 minutes |
| **Complete VM Failure** | `./backup/full-backup/rebuild-vm.sh backup.tar.gz` | 10-30 minutes |
| **Full System Restore** | `./backup/full-backup/restore-full-backup.sh latest` | 15-45 minutes |
| **SQLite Corruption** | `sqlite3 db.sqlite3.backup ".dump" \| sqlite3 db.sqlite3` | 1-5 minutes |

---

## 🧪 Monthly SQLite Disaster Recovery Testing

### Automated Testing Setup

```bash
# 1. Make script executable
chmod +x ./backup/dr-monthly-test.sh

# 2. Add to crontab (runs 1st of each month at 3 AM)
crontab -e
0 3 1 * * /full/path/to/VaultWarden-OCI-Slim/backup/dr-monthly-test.sh

# 3. Configure email notifications
nano settings.env
SEND_EMAIL_NOTIFICATION=true
ADMIN_EMAIL=your-email@domain.com

# 4. Test manually first
./backup/dr-monthly-test.sh
```

### SQLite DR Test Features

The automated monthly test validates:

- **🗃️ SQLite Backup Discovery** - Locates latest SQLite backup files
- **🐳 Container Testing** - Uses disposable SQLite container (no production impact)
- **🔓 Secret Sourcing** - Intelligent BACKUP_PASSPHRASE discovery (OCI Vault → settings.env → environment)
- **📦 Decompression/Decryption** - Tests GPG decryption and gzip decompression
- **🗃️ SQLite Restoration** - Full database restore from backup
- **🔍 Integrity Validation** - Runs `PRAGMA integrity_check` on restored SQLite database
- **📊 Data Validation** - Verifies key tables and record counts
- **⚡ Performance Testing** - Basic SQLite query performance validation
- **📧 Email Reporting** - Detailed results with SQLite-specific metrics
- **🧹 Cleanup** - Automatic temporary file and container cleanup

### SQLite DR Test Process

1. **Backup Discovery**: Scans for latest SQLite backups (`.sql.gz`, `.sqlite3.gz`)
2. **Passphrase Sourcing**: Tries OCI Vault → settings.env → environment variables
3. **Container Creation**: Spins up temporary SQLite-compatible container
4. **Backup Restoration**: Decompresses and restores SQLite database
5. **Integrity Check**: Validates database with `PRAGMA integrity_check`
6. **Data Validation**: Counts users, organizations, and other key tables
7. **Performance Test**: Executes sample queries to verify functionality
8. **Report Generation**: Creates JSON report with metrics and timestamps
9. **Notification**: Sends email with test results and recommendations
10. **Cleanup**: Removes temporary containers, files, and test data

---

## 🔄 Complete VM Disaster Recovery

### Scenario: Complete OCI A1 Flex VM Loss

**Prerequisites for Recovery:**
- Access to recent full system backup (`.tar.gz` file)
- New OCI A1 Flex instance (1 OCPU/6GB RAM minimum)
- Domain DNS pointing to new instance
- Email access for notifications

### Step-by-Step Recovery Process

#### 1. Provision New OCI A1 Flex Instance
```bash
# Create new Ubuntu 22.04+ instance
# Configure security groups (ports 80, 443, 22)
# Assign public IP
# Update DNS records to point to new IP
```

#### 2. Initial System Setup
```bash
# SSH to new instance
ssh ubuntu@your-new-ip

# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker ubuntu
sudo systemctl enable docker
sudo systemctl start docker

# Install Docker Compose
sudo apt install docker-compose-plugin -y

# Logout and login again for Docker group changes
exit
ssh ubuntu@your-new-ip
```

#### 3. Download and Restore System Backup
```bash
# Download your backup from cloud storage (adjust for your storage)
# Example using rclone (if configured):
rclone copy remote:vaultwarden-backups/latest-full-backup.tar.gz ./

# Or download via scp/wget/curl depending on your storage setup
# wget https://your-cloud-storage/latest-full-backup.tar.gz

# Extract full system backup
tar -xzf latest-full-backup.tar.gz
cd VaultWarden-OCI-Slim

# Make scripts executable
chmod +x *.sh
chmod +x backup/*.sh
chmod +x backup/full-backup/*.sh
```

#### 4. Restore Configuration and Secrets
```bash
# If using OCI Vault:
export OCISECRET_OCID=your-vault-secret-ocid
./oci-setup.sh get --output restored-settings.env
cp restored-settings.env settings.env

# If using local configuration (backup includes settings.env):
# settings.env should already be restored from backup

# Verify critical settings are present:
grep -E "DOMAIN|ADMIN_TOKEN|BACKUP_PASSPHRASE" settings.env

# Update domain/IP if changed:
sed -i 's/old-domain.com/new-domain.com/g' settings.env
sed -i 's/old-ip-address/new-ip-address/g' settings.env
```

#### 5. Restore SQLite Database
```bash
# Locate SQLite database backup in extracted files
ls -la data/backups/*.sqlite3* data/backups/*.sql.gz*

# If database backup exists in backup:
latest_db_backup=$(ls -t data/backups/*.sql.gz 2>/dev/null | head -n1)

# If found, restore will happen automatically during startup
# If not found, download latest SQLite backup separately:
# rclone copy remote:vaultwarden-backups/db/ data/backups/

# Verify SQLite database integrity before startup
if [ -n "$latest_db_backup" ]; then
    echo "Testing SQLite backup integrity..."
    zcat "$latest_db_backup" | sqlite3 /tmp/test_restore.sqlite3
    sqlite3 /tmp/test_restore.sqlite3 "PRAGMA integrity_check;"
    rm /tmp/test_restore.sqlite3
fi
```

#### 6. Start Services and Validate
```bash
# Run pre-startup validation
./diagnose.sh --quick

# Start all services (includes automatic SQLite database restoration if needed)
./startup.sh

# Monitor startup process
./monitor.sh

# Wait for services to be healthy (30-60 seconds)
sleep 60

# Validate service health
./diagnose.sh

# Test web access
curl -k https://your-domain.com/alive
curl -k https://your-domain.com/admin

# Check SQLite database
sqlite3 ./data/bwdata/db.sqlite3 "SELECT COUNT(*) FROM users;"
sqlite3 ./data/bwdata/db.sqlite3 "PRAGMA integrity_check;"
```

#### 7. Post-Recovery Validation
```bash
# Run comprehensive health check
./diagnose.sh --full

# Test backup system
./backup/db-backup.sh --force

# Validate monthly DR testing
./backup/dr-monthly-test.sh

# Check resource usage (should be ~305MB RAM total)
docker stats --no-stream

# Test email notifications
./alerts.sh --test-email

# Verify OCI Vault connectivity (if used)
./oci-setup.sh test
```

### Recovery Time Breakdown

| Phase | Expected Time | SQLite Optimizations |
|-------|---------------|---------------------|
| **VM Provisioning** | 2-5 minutes | OCI A1 Flex fast boot |
| **System Setup** | 3-8 minutes | Automated Docker installation |
| **Backup Download** | 2-10 minutes | Compressed SQLite backups |
| **Configuration Restore** | 1-2 minutes | Single file database |
| **SQLite Database Restore** | 1-5 minutes | Fast SQLite restoration |
| **Service Startup** | 2-5 minutes | Optimized container startup |
| **Validation** | 1-3 minutes | Automated health checks |
| **Total Recovery Time** | **10-30 minutes** | **SQLite efficiency gains** |

---

## 📦 Restoring from Full System Backups (VM-level)

### Automated Full System Restoration

The full system backup provides complete VM-level disaster recovery capabilities:

```bash
# Restore from latest full system backup
./backup/full-backup/restore-full-backup.sh latest

# Restore from specific full system backup
./backup/full-backup/restore-full-backup.sh backup-20241006-030001.tar.gz

# Test restore without applying changes
./backup/full-backup/restore-full-backup.sh --verify-only latest
```

### Full System Restoration Process

The automated restoration performs these steps:

1. **🛑 Service Shutdown**: Gracefully stops all running services
2. **🗃️ Current State Backup**: Creates backup of current system state
3. **📦 Archive Extraction**: Decompresses and decrypts full backup archive
4. **🔄 System Component Restore**: Systematically restores all components:
   - SQLite database with integrity verification
   - Configuration files (settings.env, docker-compose.yml)
   - Scripts and tools with proper permissions
   - SSL certificates and keys
   - Custom configurations and settings
5. **⚙️ Configuration Adaptation**: Updates configuration for new environment if needed
6. **🔧 Permission Restoration**: Restores proper file ownership and permissions
7. **⚡ Service Startup**: Restarts all services with health monitoring
8. **✅ System Validation**: Validates complete system functionality
9. **📧 Notification**: Sends restoration completion notification

### Automated VM Rebuild

For complete infrastructure loss, use the automated VM rebuild capability:

```bash
# Rebuild complete VM from full system backup
./backup/full-backup/rebuild-vm.sh latest

# Rebuild from specific backup
./backup/full-backup/rebuild-vm.sh backup-20241006-030001.tar.gz

# Interactive rebuild with prompts
./backup/full-backup/rebuild-vm.sh --interactive latest
```

### VM Rebuild Process

The automated VM rebuild script performs:

1. **🏗️ System Preparation**: 
   - Installs Docker and Docker Compose
   - Configures system dependencies
   - Sets up user permissions and groups

2. **📦 Backup Processing**:
   - Downloads full system backup from cloud storage (if needed)
   - Validates backup integrity and completeness
   - Extracts archive with proper directory structure

3. **🔄 System Restoration**:
   - Restores complete system state from archive
   - Configures network and firewall settings
   - Adapts configuration for new environment

4. **⚡ Service Initialization**:
   - Starts all services with health monitoring
   - Validates service connectivity and functionality
   - Performs automated system health checks

5. **📊 Post-Rebuild Validation**:
   - Runs comprehensive system diagnostics
   - Validates SQLite database integrity
   - Tests backup system functionality
   - Sends completion notification with system status

### Full System Recovery Scenarios

#### Scenario 1: Configuration Corruption
```bash
# When configuration files are corrupted but data is intact
./backup/full-backup/restore-full-backup.sh --config-only latest

# This restores:
# - settings.env
# - docker-compose.yml
# - Caddyfile and reverse proxy configuration
# - fail2ban and security settings
# - Scripts and tools (preserves current data)
```

#### Scenario 2: Complete Data Loss
```bash
# When both configuration and data are lost
./backup/full-backup/restore-full-backup.sh latest

# This performs complete restoration:
# - SQLite database restoration
# - Configuration restoration
# - Script and tool restoration
# - Certificate restoration
# - Complete system state recovery
```

#### Scenario 3: Infrastructure Migration
```bash
# When migrating to new infrastructure
./backup/full-backup/rebuild-vm.sh --migrate latest

# This performs:
# - Fresh system setup on new infrastructure
# - Complete restoration from backup
# - Configuration adaptation for new environment
# - DNS and network reconfiguration
# - Validation and testing
```

---

## 🔒 SQLite-Specific Recovery Procedures

### SQLite Database Corruption Recovery
```bash
# Stop services
docker compose down

# Backup corrupted database
cp ./data/bwdata/db.sqlite3 ./data/bwdata/db.sqlite3.corrupted

# Attempt SQLite repair via dump/restore
sqlite3 ./data/bwdata/db.sqlite3.corrupted ".dump" > /tmp/recovery.sql
sqlite3 ./data/bwdata/db.sqlite3.repaired < /tmp/recovery.sql

# Validate repaired database
sqlite3 ./data/bwdata/db.sqlite3.repaired "PRAGMA integrity_check;"

# If repair successful, replace database
if [ $? -eq 0 ]; then
    mv ./data/bwdata/db.sqlite3.repaired ./data/bwdata/db.sqlite3
    echo "✅ SQLite database repaired successfully"
else
    echo "❌ Repair failed, restoring from backup"
    ./backup/db-restore.sh --latest
fi

# Restart services
./startup.sh
```

### Performance Optimization Post-Recovery
```bash
# Optimize SQLite database after recovery
sqlite3 ./data/bwdata/db.sqlite3 "
PRAGMA journal_mode=WAL;
PRAGMA synchronous=NORMAL;
PRAGMA cache_size=10000;
PRAGMA foreign_keys=ON;
PRAGMA temp_store=memory;
ANALYZE;
PRAGMA optimize;
"

# Verify optimizations
sqlite3 ./data/bwdata/db.sqlite3 "
SELECT name, value FROM pragma_compile_options() WHERE name LIKE '%WAL%';
PRAGMA journal_mode;
PRAGMA synchronous;
PRAGMA cache_size;
"
```

---

## 📊 Recovery Monitoring and Validation

### SQLite Recovery Health Checks
```bash
# Database integrity and performance
sqlite3 ./data/bwdata/db.sqlite3 "
PRAGMA integrity_check;
PRAGMA foreign_key_check;
SELECT COUNT(*) as user_count FROM users;
SELECT COUNT(*) as cipher_count FROM ciphers;
SELECT page_count * page_size / 1024 / 1024 as size_mb FROM pragma_page_count(), pragma_page_size();
"

# Container resource usage validation
docker stats --no-stream --format "table {{.Container}}	{{.CPUPerc}}	{{.MemUsage}}"

# Expected resource usage post-recovery:
# vaultwarden: <20% CPU, ~200MB RAM
# caddy: <5% CPU, ~50MB RAM
# fail2ban: <2% CPU, ~25MB RAM
```

### Full System Recovery Validation
```bash
# Comprehensive system validation after full restore
./diagnose.sh --full

# Specific validations:
# ✅ SQLite database integrity
# ✅ Configuration file completeness
# ✅ Script permissions and executability
# ✅ SSL certificate validity
# ✅ Service health and connectivity
# ✅ Backup system functionality
# ✅ Email notification system
# ✅ OCI Vault connectivity (if configured)
```

### Automated Recovery Validation Script
```bash
# Create comprehensive recovery validation
cat > validate-recovery.sh << 'EOF'
#!/bin/bash
echo "🔍 Starting Comprehensive Recovery Validation..."

# Test SQLite database
echo "Testing SQLite database integrity..."
if sqlite3 ./data/bwdata/db.sqlite3 "PRAGMA integrity_check;" | grep -q "ok"; then
    echo "✅ SQLite database integrity: OK"
else
    echo "❌ SQLite database integrity: FAILED"
    exit 1
fi

# Test web services
echo "Testing web services..."
if curl -k -s https://localhost/alive | grep -q "ok"; then
    echo "✅ VaultWarden web service: OK"
else
    echo "❌ VaultWarden web service: FAILED"
fi

# Test backup system
echo "Testing backup system..."
if ./backup/db-backup.sh --force; then
    echo "✅ SQLite backup system: OK"
else
    echo "❌ SQLite backup system: FAILED"
fi

# Test full system backup functionality
echo "Testing full system backup..."
if ./backup/full-backup/validate-backup.sh latest; then
    echo "✅ Full system backup validation: OK"
else
    echo "❌ Full system backup validation: FAILED"
fi

# Test OCI Vault integration (if configured)
if [ -n "$OCISECRET_OCID" ] || [ -n "$OCI_SECRET_OCID" ]; then
    echo "Testing OCI Vault connectivity..."
    if ./oci-setup.sh test; then
        echo "✅ OCI Vault integration: OK"
    else
        echo "❌ OCI Vault integration: FAILED"
    fi
fi

echo "🎉 Recovery validation complete!"
EOF

chmod +x validate-recovery.sh
./validate-recovery.sh
```

---

## 📋 Recovery Procedures Checklist

### Pre-Recovery Preparation
- [ ] Identify recovery scenario (database, configuration, or complete system)
- [ ] Locate appropriate backup files (database or full system)
- [ ] Verify backup integrity before restoration
- [ ] Ensure sufficient disk space for restoration
- [ ] Notify users of planned downtime (if applicable)

### During Recovery
- [ ] Follow appropriate recovery procedure for scenario
- [ ] Monitor restoration progress and logs
- [ ] Validate each restoration step before proceeding
- [ ] Document any issues or adaptations required
- [ ] Take screenshots or notes for post-recovery analysis

### Post-Recovery Validation
- [ ] Run comprehensive system diagnostics
- [ ] Validate SQLite database integrity and performance
- [ ] Test all critical functionality (login, vault operations)
- [ ] Verify backup system is operational
- [ ] Confirm email notifications are working
- [ ] Update DNS records if infrastructure changed
- [ ] Notify users of recovery completion
- [ ] Schedule follow-up monitoring

---

The VaultWarden-OCI-Slim disaster recovery system provides rapid recovery capabilities optimized for SQLite databases with comprehensive automated testing, full system backup support, and VM-level disaster recovery using standardized `oci-setup.sh` and `OCISECRET_OCID` variable naming throughout.
