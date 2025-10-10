# VaultWarden-OCI-Slim Troubleshooting Guide

Common issues, solutions, and diagnostic procedures for SQLite-based VaultWarden deployments with standardized naming conventions.

---

## 🚨 Emergency Quick Fixes

| Issue | Quick Fix | Full Solution |
|-------|-----------|---------------|
| Can't access web interface | `./startup.sh --force` | [Web Access Issues](#web-access-issues) |
| OCI Vault not working | `./oci-setup.sh test` | [OCI Vault Issues](#oci-vault-issues) |
| SQLite backup failing | `./backup/db-backup.sh --force` | [SQLite Backup Issues](#sqlite-backup-issues) |
| Monthly DR test failing | `./backup/dr-monthly-test.sh` | [DR Testing Issues](#dr-testing-issues) |

---

## 🗃️ SQLite Database Issues

### Symptoms
- Database locked errors
- Corruption warnings
- Performance degradation
- Startup failures

### Diagnostic Steps
```bash
# 1. Check SQLite database integrity
sqlite3 ./data/bwdata/db.sqlite3 "PRAGMA integrity_check;"

# 2. Check database file permissions and size
ls -la ./data/bwdata/db.sqlite3
du -h ./data/bwdata/db.sqlite3

# 3. Test database connectivity from VaultWarden container
docker compose exec vaultwarden sqlite3 /data/db.sqlite3 ".tables"

# 4. Check WAL mode status (should be enabled for performance)
sqlite3 ./data/bwdata/db.sqlite3 "PRAGMA journal_mode;"
```

### Solutions

#### Issue: Database Locked Errors
```bash
# Check for lingering connections or processes
lsof ./data/bwdata/db.sqlite3

# Stop all VaultWarden services
docker compose down

# Wait for file locks to clear
sleep 5

# Restart services
./startup.sh
```

#### Issue: Database Corruption
```bash
# Create backup of corrupted database
cp ./data/bwdata/db.sqlite3 ./data/bwdata/db.sqlite3.corrupted

# Attempt to repair using SQLite dump and restore
sqlite3 ./data/bwdata/db.sqlite3.corrupted ".dump" | sqlite3 ./data/bwdata/db.sqlite3.repaired

# If repair successful, replace database
mv ./data/bwdata/db.sqlite3.repaired ./data/bwdata/db.sqlite3

# If repair fails, restore from backup
./backup/db-restore.sh --latest
```

---

## ☁️ OCI Vault Issues  

### Diagnostic Steps
```bash
# 1. Test OCI CLI authentication
oci iam user get --user-id $(oci iam user list --query 'data[0].id' --raw-output)

# 2. Test vault access with standardized variable  
oci vault secret-bundle get --secret-id "$OCISECRET_OCID"

# 3. Test oci-setup.sh functionality
./oci-setup.sh test
```

### Solutions

#### Issue: OCISECRET_OCID Not Set
```bash
# Check if environment variable exists
echo "$OCISECRET_OCID"

# If not set:
export OCISECRET_OCID=ocid1.vaultsecret.oc1..your-secret-id

# Test after setting:
./oci-setup.sh test
```

---

## 💾 SQLite Backup Issues

### Symptoms
- Backup script failures
- Empty or corrupted backup files
- Restore operation failures
- GPG encryption/decryption errors

### Diagnostic Steps
```bash
# 1. Check SQLite backup directory
ls -la data/backups/

# 2. Test manual SQLite dump
sqlite3 ./data/bwdata/db.sqlite3 ".backup ./data/backups/manual_backup.sqlite3"

# 3. Validate backup integrity
sqlite3 ./data/backups/manual_backup.sqlite3 "PRAGMA integrity_check;"

# 4. Test GPG encryption (if enabled)
echo "test" | gpg --batch --yes --symmetric --cipher-algo AES256 --compress-algo 2 --s2k-mode 3 --s2k-digest-algo SHA512 --s2k-count 65536 --passphrase "$BACKUP_PASSPHRASE" > test.gpg
gpg --batch --yes --passphrase "$BACKUP_PASSPHRASE" --decrypt test.gpg
rm test.gpg
```

### Solutions

#### Issue: SQLite Database Busy During Backup
```bash
# Enable WAL mode for concurrent access
sqlite3 ./data/bwdata/db.sqlite3 "PRAGMA journal_mode=WAL;"

# Verify WAL mode is active
sqlite3 ./data/bwdata/db.sqlite3 "PRAGMA journal_mode;"

# Run backup during low usage periods
./backup/db-backup.sh --force
```

---

## 🧪 DR Testing Issues

### Symptoms
- Monthly DR test script fails
- BACKUP_PASSPHRASE not found errors
- SQLite restore validation failures
- Email notifications not sent

### Diagnostic Steps
```bash
# 1. Check DR test logs
cat logs/dr-monthly-test.log

# 2. Test backup passphrase sourcing
echo "$BACKUP_PASSPHRASE"              # Environment variable
./oci-setup.sh get                     # OCI Vault access
source settings.env && echo "$BACKUP_PASSPHRASE"  # Local config

# 3. Check SQLite backup availability
ls -la data/backups/*.sqlite3*
ls -la data/backups/*.sql.gz*

# 4. Test email configuration
./alerts.sh --test-email
```

### Solutions

#### Issue: DR Test Can't Find BACKUP_PASSPHRASE
```bash
# The script tries multiple methods automatically:

# Method 1: OCI Vault (if OCISECRET_OCID is set)
./oci-setup.sh test                    # Verify vault access
./oci-setup.sh get --output test.env  # Download vault config

# Method 2: settings.env file
ls -la settings.env                   # Check file exists
source settings.env && echo "$BACKUP_PASSPHRASE"

# Method 3: Environment variable
export BACKUP_PASSPHRASE=your-passphrase
./backup/dr-monthly-test.sh
```

---

## 🎛️ Performance Issues

### SQLite Performance Optimization
```bash
# Check current SQLite configuration
sqlite3 ./data/bwdata/db.sqlite3 "PRAGMA compile_options;"

# Optimize SQLite settings (already configured in VaultWarden)
# These are set automatically in settings.env:
# DATABASE_URL=sqlite:///data/db.sqlite3
# ROCKET_WORKERS=1
# WEBSOCKET_ENABLED=false

# Monitor SQLite performance
./perf-monitor.sh status
```

### Resource Usage Monitoring
```bash
# Check container resource usage (optimized for 1 OCPU/6GB)
docker stats --no-stream

# Expected usage on OCI A1 Flex:
# vaultwarden: ~15% CPU, ~200MB RAM
# caddy:       ~2% CPU, ~50MB RAM  
# backup:      ~1% CPU, ~30MB RAM
# fail2ban:    ~1% CPU, ~25MB RAM
```

---

The VaultWarden-OCI-Slim troubleshooting system focuses on SQLite database management with standardized `oci-setup.sh` script naming and `OCISECRET_OCID` variable conventions throughout.
