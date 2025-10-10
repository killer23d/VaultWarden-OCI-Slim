# VaultWarden-OCI-Slim OCI Vault Integration Guide

Enterprise-grade secret management for SQLite-based VaultWarden using Oracle Cloud Infrastructure Vault with standardized naming conventions.

---

## 📋 Table of Contents

- [OCI Vault Overview](#oci-vault-overview)
- [Setup and Configuration](#setup-and-configuration)
- [Environment Variables](#environment-variables)
- [SQLite Integration with VaultWarden](#sqlite-integration-with-vaultwarden)
- [SQLite Backup System Integration](#sqlite-backup-system-integration)
- [Security Best Practices](#security-best-practices)
- [Error Handling and Troubleshooting](#error-handling-and-troubleshooting)
- [Monitoring and Audit](#monitoring-and-audit)

---

## 🔐 OCI Vault Overview

Oracle Cloud Infrastructure Vault provides enterprise-grade secret management for VaultWarden-OCI-Slim deployments, ensuring sensitive SQLite configuration data never exists as plaintext on VM storage.

### SQLite-Specific Benefits
- **BACKUP_PASSPHRASE Security**: SQLite backup encryption keys stored securely in OCI Vault
- **Database Credentials**: SQLite connection parameters managed centrally
- **Configuration Management**: All SQLite-specific settings stored in vault
- **OCI A1 Flex Optimized**: Minimal resource overhead for 1 OCPU/6GB constraint
- **Automated Rotation**: Support for rotating SQLite backup encryption keys

---

## 🛠️ Setup and Configuration

### Prerequisites for OCI A1 Flex Instance

#### Network Requirements
- **Outbound HTTPS (443)** to OCI Vault endpoints for your region
- **Private Subnets**: Require Service Gateway or NAT Gateway for OCI API access
- **DNS Resolution**: Must resolve `*.{region}.oci.oraclecloud.com`
- **NTP Synchronization**: Clock skew can cause authentication failures (critical for OCI A1 ARM)

#### Test Network Connectivity on OCI A1 Flex
```bash
# Test DNS resolution (ARM-compatible)
nslookup secrets.vaults.us-ashburn-1.oci.oraclecloud.com

# Test HTTPS connectivity
curl -I https://secrets.vaults.us-ashburn-1.oci.oraclecloud.com

# For private subnets, verify Service Gateway
oci network service-gateway list --compartment-id $COMPARTMENT_OCID

# ARM-specific: Verify time synchronization (critical for OCI authentication)
timedatectl status
sudo systemctl status systemd-timesyncd
```

### OCI CLI Installation for ARM64 (OCI A1 Flex)
```bash
# Install OCI CLI on ARM64 Ubuntu
bash -c "$(curl -L https://raw.githubusercontent.com/oracle/oci-cli/master/scripts/install/install.sh)"

# Configure OCI CLI with your credentials
oci setup config

# Test OCI connectivity
oci iam region list
oci iam user get --user-id $(oci iam user list --query 'data[0].id' --raw-output)
```

### Initialize VaultWarden-OCI-Slim with OCI Vault

```bash
# Run the OCI setup script (standardized naming for SQLite deployment)
./oci-setup.sh setup

# Interactive setup prompts for SQLite-specific configuration:
# - Vault selection/creation
# - Master key creation for SQLite backup encryption
# - Secret creation with SQLite-optimized parameters
# - Permission configuration for OCI A1 Flex instance
# - BACKUP_PASSPHRASE generation for SQLite backups
```

---

## 🌐 Environment Variables

### Standardized Variables for SQLite Deployment

```bash
# OCI Configuration - Standardized Naming for VaultWarden-OCI-Slim
export OCI_TENANCY_OCID="ocid1.tenancy.oc1..aaaaaaaa..."
export OCI_USER_OCID="ocid1.user.oc1..aaaaaaaa..."
export OCI_FINGERPRINT="aa:bb:cc:dd:ee:ff:..."
export OCI_KEY_FILE="/home/ubuntu/.oci/oci_api_key.pem"
export OCI_REGION="us-ashburn-1"
export OCISECRET_OCID="ocid1.vaultsecret.oc1..aaaaaaaa..."

# SQLite-Specific VaultWarden Configuration
export OCI_VAULT_ENABLED=true
export SQLITE_BACKUP_ENCRYPTION=true
export OCI_A1_OPTIMIZED=true
```

### Environment File Configuration for SQLite

Add to your `settings.env` for SQLite-optimized deployment:

```bash
# OCI Vault Configuration - Standardized Variables for SQLite
OCI_VAULT_ENABLED=true
OCI_TENANCY_OCID=ocid1.tenancy.oc1..aaaaaaaa...
OCI_USER_OCID=ocid1.user.oc1..aaaaaaaa...
OCI_FINGERPRINT=aa:bb:cc:dd:ee:ff:...
OCI_KEY_FILE=/home/ubuntu/.oci/oci_api_key.pem
OCI_REGION=us-ashburn-1
OCISECRET_OCID=ocid1.vaultsecret.oc1..aaaaaaaa...

# SQLite Database Configuration (stored in vault)
DATABASE_URL=sqlite:///data/db.sqlite3
ROCKET_WORKERS=1
WEBSOCKET_ENABLED=false

# SQLite Backup Configuration (vault-managed)
BACKUP_PASSPHRASE=vault-managed
BACKUP_FORMAT=both
SQLITE_BACKUP_ENCRYPTION=true
SQLITE_INTEGRITY_CHECK=true

# OCI A1 Flex Resource Optimization
OCI_A1_OPTIMIZED=true
MEMORY_LIMIT=512M
CPU_LIMIT=0.5
```

### Vault-Managed SQLite Configuration
```json
{
  "database_config": {
    "database_url": "sqlite:///data/db.sqlite3",
    "rocket_workers": 1,
    "websocket_enabled": false,
    "sqlite_optimizations": {
      "wal_mode": true,
      "cache_size": 10000,
      "synchronous": "NORMAL",
      "foreign_keys": true
    }
  },
  "backup_config": {
    "backup_passphrase": "generated-secure-passphrase",
    "backup_format": "both",
    "encryption_enabled": true,
    "integrity_check": true,
    "retention_days": 30
  },
  "performance_config": {
    "oci_a1_optimized": true,
    "memory_limit": "512M",
    "cpu_limit": "0.5",
    "sqlite_page_size": 4096,
    "sqlite_cache_pages": 2500
  }
}
```

---

## 🗃️ SQLite Integration with VaultWarden

### Configuration Management for SQLite
```bash
# Download current SQLite configuration from vault
./oci-setup.sh get --output current-sqlite-settings.env

# Update vault with new SQLite configuration
./oci-setup.sh update --file updated-sqlite-settings.env

# Show vault configuration (safe - no secrets displayed)
./oci-setup.sh show

# Test vault connectivity and SQLite parameter retrieval
./oci-setup.sh test

# Specifically test SQLite backup passphrase retrieval
./oci-setup.sh test --backup-passphrase
```

### SQLite Database Initialization with Vault Secrets
```bash
# The startup.sh script automatically retrieves SQLite configuration from vault:
# 1. 🔐 Loads DATABASE_URL from vault (sqlite:///data/db.sqlite3)
# 2. ⚙️ Applies ROCKET_WORKERS=1 for SQLite optimization
# 3. 🗃️ Configures SQLite WAL mode and cache settings
# 4. 🔑 Retrieves BACKUP_PASSPHRASE for SQLite backup encryption
# 5. 📊 Sets performance parameters for OCI A1 Flex

./startup.sh --vault-mode  # Explicit vault-aware startup
```

### Vault-Aware SQLite Operations
```bash
# SQLite backup with vault-managed encryption
./backup/db-backup.sh --vault-passphrase

# SQLite restore using vault-stored passphrase
./backup/db-restore.sh --vault-decrypt backup.sql.gz.gpg

# SQLite integrity check with vault logging
sqlite3 ./data/bwdata/db.sqlite3 "PRAGMA integrity_check;" | ./oci-setup.sh log-audit
```

---

## 💾 SQLite Backup System Integration

### Vault-Aware SQLite Backup Operations

```bash
# All SQLite backup scripts automatically use OCISECRET_OCID:
# 1. 🔐 Load BACKUP_PASSPHRASE from OCI Vault for SQLite encryption
# 2. ☁️ Load BACKUP_REMOTE configuration from vault for cloud storage
# 3. 🗃️ Execute SQLite backup with vault-stored settings
# 4. 📊 Log backup metrics to OCI Audit for compliance

./backup/db-backup.sh                   # Uses vault settings automatically
./backup/full-backup/create-full-backup.sh  # Uses vault for full system backup
./backup/dr-monthly-test.sh             # Intelligent SQLite secret sourcing from vault
```

### SQLite-Specific Vault Backup Features
- **Encrypted SQLite Dumps**: SQL dumps encrypted with vault-managed passphrase
- **Binary SQLite Backups**: .sqlite3 files encrypted for cross-platform restore
- **Integrity Validation**: Vault-logged SQLite PRAGMA integrity_check results
- **Performance Metrics**: Backup duration and size metrics stored in vault
- **Automated Rotation**: BACKUP_PASSPHRASE rotation with SQLite backup re-encryption

### Vault-Managed SQLite Backup Configuration
```bash
# SQLite backup configuration stored in OCI Vault
SQLITE_BACKUP_CONFIG='{
  "formats": ["sql_dump", "binary", "encrypted"],
  "compression": "gzip",
  "encryption": {
    "algorithm": "AES256",
    "key_source": "oci_vault",
    "passphrase_rotation": "monthly"
  },
  "validation": {
    "integrity_check": true,
    "test_restore": true,
    "cross_platform_test": false
  },
  "retention": {
    "local_days": 7,
    "cloud_days": 30,
    "archive_days": 365
  },
  "performance": {
    "oci_a1_optimized": true,
    "concurrent_backups": 1,
    "memory_limit": "200MB"
  }
}'

# Update vault with SQLite backup configuration
echo "$SQLITE_BACKUP_CONFIG" | ./oci-setup.sh update-backup-config
```

---

## 🚨 Error Handling and Troubleshooting

### Enhanced Error Messages with SQLite-Specific Diagnostic Steps

#### SQLite + OCI Vault Authentication Errors (401/403)
```
ERROR: Authentication failed (401 Unauthorized) during SQLite backup
CAUSE: API key authentication issue affecting SQLite backup encryption

SQLITE-SPECIFIC DIAGNOSTIC STEPS:
1. Test SQLite backup without vault encryption:
   ./backup/db-backup.sh --no-encryption

2. Verify vault access for BACKUP_PASSPHRASE:
   ./oci-setup.sh get --key backup_passphrase

3. Test manual SQLite backup with vault passphrase:
   PASSPHRASE=$(./oci-setup.sh get --key backup_passphrase)
   sqlite3 ./data/bwdata/db.sqlite3 ".dump" | gzip | gpg --symmetric --passphrase "$PASSPHRASE"

4. Check OCI authentication for ARM64 (OCI A1 Flex):
   oci iam user get --user-id $OCI_USER_OCID

5. Verify time sync on ARM architecture:
   timedatectl status
   sudo systemctl restart systemd-timesyncd

6. Test vault connectivity from SQLite backup script:
   ./backup/db-backup.sh --test-vault-only
```

#### SQLite Database + Vault Integration Issues
```
ERROR: Cannot retrieve SQLite configuration from OCI Vault
CAUSE: Vault integration issue affecting SQLite database startup

SQLITE DIAGNOSTIC STEPS:
1. Test SQLite database without vault configuration:
   DATABASE_URL=sqlite:///data/db.sqlite3 ./startup.sh --no-vault

2. Verify SQLite database file accessibility:
   ls -la data/bwdata/db.sqlite3
   sqlite3 data/bwdata/db.sqlite3 "PRAGMA integrity_check;"

3. Test vault SQLite configuration retrieval:
   ./oci-setup.sh get --output test-sqlite-config.env
   source test-sqlite-config.env
   echo "DATABASE_URL: $DATABASE_URL"
   echo "ROCKET_WORKERS: $ROCKET_WORKERS"

4. Validate SQLite-specific vault secrets:
   ./oci-setup.sh test --sqlite-config

5. Check OCI A1 Flex resource constraints:
   free -h
   df -h data/
   docker stats --no-stream
```

#### SQLite Backup Passphrase Issues with Vault
```
ERROR: Cannot decrypt SQLite backup - invalid passphrase from vault
CAUSE: Vault passphrase mismatch or rotation issue

SQLITE BACKUP DIAGNOSTIC STEPS:
1. Test current vault passphrase:
   VAULT_PASSPHRASE=$(./oci-setup.sh get --key backup_passphrase)
   echo "test" | gpg --symmetric --passphrase "$VAULT_PASSPHRASE" | gpg --decrypt --passphrase "$VAULT_PASSPHRASE"

2. List available SQLite backup files:
   ls -la data/backups/*.sql.gz*
   ls -la data/backups/*.sqlite3*

3. Test decryption with different passphrase sources:
   # Try settings.env fallback
   source settings.env
   gpg --decrypt --passphrase "$BACKUP_PASSPHRASE" data/backups/latest.sql.gz.gpg

4. Check passphrase rotation history:
   ./oci-setup.sh audit --key backup_passphrase --days 30

5. Re-encrypt backup with current vault passphrase:
   ./backup/db-backup.sh --re-encrypt-with-vault
```

---

## 🛡️ Security Best Practices with SQLite and Fail2ban Integration

### Fail2ban Configuration with SQLite-Specific OCI Vault Settings

```bash
# Enhanced Fail2ban settings for SQLite deployment stored in OCI Vault
FAIL2BAN_ENABLED=true
FAIL2BAN_BANTIME=3600                    # Ban duration (1 hour)
FAIL2BAN_FINDTIME=600                    # Time window (10 minutes)  
FAIL2BAN_MAXRETRY=5                      # Failed attempts before ban
FAIL2BAN_IGNOREIP=127.0.0.1,10.0.0.0/8  # Whitelist internal networks

# SQLite-specific security monitoring
SQLITE_SECURITY_MONITORING=true          # Monitor SQLite file access
SQLITE_BACKUP_MONITORING=true            # Alert on backup failures
OCI_A1_SECURITY_OPTIMIZED=true          # ARM-specific security settings

# Advanced security monitoring for SQLite
FAIL2BAN_ALERT_WEBHOOK=true              # Integration with alerts.sh
FAIL2BAN_EMAIL_ALERTS=true               # Email notifications for bans
FAIL2BAN_OCI_INTEGRATION=true            # Log ban events to OCI Audit
SQLITE_AUDIT_LOGGING=true                # Log SQLite operations to vault

# Store in OCI Vault via:
./oci-setup.sh update --security-config  # Upload security config to vault
```

### SQLite-Aware Fail2ban Jail Configuration
```ini
# Enhanced VaultWarden SQLite jail configuration
[vaultwarden-sqlite-auth]
enabled = true
port = 80,443,8080
protocol = tcp
filter = vaultwarden-auth
logpath = /data/caddy_logs/access.log
maxretry = 5
bantime = 3600
findtime = 600
ignoreip = 127.0.0.1 10.0.0.0/8
action = %(action_mwl)s
         webhook-alert[webhook_url="%(webhook_url)s"]
         sqlite-security-log[db_path="/data/bwdata/security.sqlite3"]

[vaultwarden-sqlite-admin]  
enabled = true
port = 80,443,8080
protocol = tcp
filter = vaultwarden-admin
logpath = /data/caddy_logs/access.log
maxretry = 3
bantime = 7200
findtime = 300
action = %(action_mwl)s
         oci-audit-log[ocid="%(ocisecret_ocid)s"]
         sqlite-admin-alert[db_path="/data/bwdata/admin_security.sqlite3"]

[sqlite-backup-monitor]
# Monitor SQLite backup process for security issues
enabled = true
filter = sqlite-backup-security
logpath = /data/logs/backup.log
maxretry = 2
bantime = 1800
findtime = 3600
action = oci-security-alert[ocid="%(ocisecret_ocid)s"]
```

### SQLite Security Monitoring Integration
```bash
# Configure alerts.sh for SQLite security events (stored in OCI Vault)
SQLITE_SECURITY_CONFIG='{
  "alerts_enabled": true,
  "monitoring": {
    "database_access": true,
    "backup_operations": true,
    "file_modifications": true,
    "integrity_checks": true
  },
  "thresholds": {
    "failed_backup_attempts": 3,
    "database_lock_duration_seconds": 300,
    "integrity_check_failures": 1,
    "unauthorized_file_access": 1
  },
  "actions": {
    "email_alerts": true,
    "webhook_notifications": true,
    "oci_audit_logging": true,
    "fail2ban_integration": true
  }
}'

# Store SQLite security configuration in vault
echo "$SQLITE_SECURITY_CONFIG" | ./oci-setup.sh update --security-sqlite

# Test SQLite security alert integration
./alerts.sh --test-sqlite-security
./alerts.sh --test-backup-monitoring
```

---

## 📊 Monitoring and Audit

### OCI Vault Audit Configuration for SQLite Operations

```bash
# Enable comprehensive audit logging for SQLite operations
oci audit configuration update --compartment-id $COMPARTMENT_OCID --is-enabled true

# Monitor key SQLite vault events
oci audit event list \
  --compartment-id $COMPARTMENT_OCID \
  --start-time "$(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%SZ)" \
  --query 'data[?eventName==`GetSecretBundle` && contains(requestMetadata.clientInfo, `sqlite`)]'

# Monitor SQLite backup-related vault access
oci audit event list \
  --compartment-id $COMPARTMENT_OCID \
  --start-time "$(date -d '7 days ago' -u +%Y-%m-%dT%H:%M:%SZ)" \
  --query 'data[?contains(requestMetadata.requestAction, `backup`) && contains(data.resourceName, `sqlite`)]'
```

### Automated SQLite Security Monitoring

```bash
# Daily SQLite + OCI Vault security validation (add to cron)
#!/bin/bash
# check-sqlite-vault-security.sh

# Load OCISECRET_OCID from vault or environment
if [[ -n "$OCISECRET_OCID" ]]; then
    # Check for unexpected SQLite-related secret updates
    SQLITE_UPDATES_TODAY=$(oci audit event list \
      --compartment-id $COMPARTMENT_OCID \
      --start-time "$(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%SZ)" \
      --query 'data[?eventName==`UpdateSecret` && contains(data.resourceName, `sqlite`)].length(@)')

    if [[ $SQLITE_UPDATES_TODAY -gt 2 ]]; then
        echo "ALERT: $SQLITE_UPDATES_TODAY SQLite vault secret updates in last 24h" | ./alerts.sh --send-security-alert
    fi

    # Monitor SQLite database integrity with vault logging
    INTEGRITY_RESULT=$(sqlite3 ./data/bwdata/db.sqlite3 "PRAGMA integrity_check;")
    if [[ "$INTEGRITY_RESULT" != "ok" ]]; then
        echo "CRITICAL: SQLite integrity check failed: $INTEGRITY_RESULT" | ./alerts.sh --send-critical-alert
        # Log to OCI Vault audit
        echo "SQLite integrity failure: $INTEGRITY_RESULT" | ./oci-setup.sh log-security-event
    fi

    # Monitor SQLite backup encryption with vault
    LATEST_BACKUP=$(ls -t data/backups/*.sql.gz.gpg 2>/dev/null | head -n1)
    if [[ -n "$LATEST_BACKUP" ]]; then
        # Test backup decryption with vault passphrase
        VAULT_PASSPHRASE=$(./oci-setup.sh get --key backup_passphrase 2>/dev/null)
        if ! echo "test" | gpg --decrypt --batch --yes --passphrase "$VAULT_PASSPHRASE" "$LATEST_BACKUP" >/dev/null 2>&1; then
            echo "ERROR: Cannot decrypt latest SQLite backup with vault passphrase" | ./alerts.sh --send-security-alert
        fi
    fi
fi

# Check OCI A1 Flex resource usage for SQLite operations
MEMORY_USAGE=$(free | awk '/^Mem:/{printf "%.1f", $3/$2 * 100.0}')
if (( $(echo "$MEMORY_USAGE > 80.0" | bc -l) )); then
    echo "WARNING: High memory usage ${MEMORY_USAGE}% on OCI A1 Flex may affect SQLite performance" | ./alerts.sh --send-warning-alert
fi
```

### SQLite Performance Monitoring with OCI Vault Integration
```bash
# SQLite performance metrics stored in OCI Vault
SQLITE_PERFORMANCE_CONFIG='{
  "monitoring_enabled": true,
  "metrics": {
    "database_size_mb": "SELECT page_count * page_size / 1024 / 1024 FROM pragma_page_count(), pragma_page_size()",
    "wal_file_size_kb": "SELECT name, size FROM pragma_wal_checkpoint(PASSIVE)",
    "cache_hit_ratio": "SELECT (cache_hit * 100.0 / (cache_hit + cache_miss)) FROM pragma_cache_spill(-1)",
    "query_performance": "EXPLAIN QUERY PLAN SELECT COUNT(*) FROM users"
  },
  "thresholds": {
    "max_database_size_mb": 500,
    "max_wal_size_kb": 10240,
    "min_cache_hit_ratio": 90.0,
    "max_query_time_ms": 1000
  },
  "oci_a1_optimizations": {
    "memory_limit_mb": 512,
    "cpu_limit_percent": 50,
    "io_priority": "normal"
  }
}'

# Store performance configuration in vault
echo "$SQLITE_PERFORMANCE_CONFIG" | ./oci-setup.sh update --performance-config

# Run performance monitoring with vault integration
./perf-monitor.sh --sqlite --vault-logging
```

---

The VaultWarden-OCI-Slim OCI Vault integration provides enterprise-grade secret management specifically optimized for SQLite databases with standardized naming conventions, comprehensive SQLite-specific error handling, security monitoring, and Fail2ban integration. All configuration uses the `OCISECRET_OCID` variable consistently and the `oci-setup.sh` script for all SQLite-related vault operations on OCI A1 Flex instances.
