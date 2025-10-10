# VaultWarden-OCI-Slim

**Enterprise-grade Vaultwarden deployment with SQLite database, automated backups, disaster recovery, and OCI Vault integration.**

Optimized for **Oracle Cloud Infrastructure (OCI) A1 Flex instances** (1 OCPU/6GB), but portable to any Docker-compatible environment. Perfect for **small teams (<10 users)** with **Cloudflare proxy** frontend.

## ✨ Key Features

- **🗃️ SQLite Database**: No database server overhead - optimized for single-node deployments
- **☁️ OCI Vault Integration**: Secure secret management with automatic rotation support
- **🛡️ Cloudflare Ready**: Built-in IP management and security optimizations
- **🤖 Intelligent Automation**: AI-driven maintenance that only runs needed operations
- **📧 Professional Notifications**: HTML email reports with detailed metrics
- **🔄 Profile System**: Enable/disable services based on your needs
- **💾 Comprehensive Backups**: Encrypted, verified, cloud-stored with disaster recovery testing
- **📦 Full System Backups**: Complete VM backups for disaster recovery scenarios
- **🔧 Smart Management**: Never downgrades components, intelligent version handling

---

## 🚀 Quick Start

### Prerequisites

- Fresh Ubuntu 22.04+ VM (4GB RAM minimum, 6GB recommended)
- Domain name pointing to your server  
- Email account for SMTP notifications
- **(Optional)** Cloudflare account for enhanced security and performance

### 1. Clone and Setup

```bash
# Clone the repository
git clone https://github.com/killer23d/VaultWarden-OCI-Slim.git
cd VaultWarden-OCI-Slim
chmod +x *.sh

# Interactive setup wizard with smart version management
./init-setup.sh
```

### 2. Generate Secure Secrets

**CRITICAL**: Generate secure passwords for all placeholder values:

```bash
# Generate strong secrets (save these outputs)
echo "ADMIN_TOKEN=$(openssl rand -base64 32)"
echo "BACKUP_PASSPHRASE=$(openssl rand -base64 32)"

# Optional JWT secret for advanced features
echo "JWT_SECRET=$(openssl rand -base64 64)"
```

### 3. Configure Your Deployment

**Edit `settings.env`** and replace ALL placeholder values:

```bash
nano settings.env

# Required Configuration
DOMAIN_NAME=yourdomain.com
APP_DOMAIN=vault.yourdomain.com  
DOMAIN=https://vault.yourdomain.com
ADMIN_EMAIL=your-email@yourdomain.com

# Use generated secrets from step 2
ADMIN_TOKEN=your-generated-admin-token
BACKUP_PASSPHRASE=your-generated-backup-passphrase

# SQLite Configuration (already optimized)
DATABASE_URL=sqlite:///data/db.sqlite3
ROCKET_WORKERS=1
WEBSOCKET_ENABLED=false

# SMTP Configuration (required for password resets)
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_SECURITY=starttls
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_FROM=noreply@yourdomain.com
```

### 4. Validate Configuration

```bash
# Comprehensive system validation
./diagnose.sh --quick

# Look for any configuration errors
```

### 5. Deploy Services

```bash
# Start all services with intelligent profile detection
./startup.sh

# Monitor startup progress
./monitor.sh
```

### 6. Access Your VaultWarden

- **🌐 Web Vault**: `https://vault.yourdomain.com`
- **⚙️ Admin Panel**: `https://vault.yourdomain.com/admin` 
- **💚 Health Check**: `https://vault.yourdomain.com/alive`

---

## 🗃️ SQLite Database Architecture

### Why SQLite for VaultWarden?

- **🚀 Performance**: Faster than client-server databases for single-user workloads
- **💾 Efficiency**: No database server overhead - more resources for your applications  
- **🔧 Simplicity**: Zero configuration database administration
- **📦 Portability**: Single file database - easy backups and migrations
- **🔒 Reliability**: ACID compliance with excellent crash recovery
- **💰 Cost-Effective**: Perfect for cloud deployments with limited resources

### Database Setup

**SQLite database setup is fully automated** by the `startup.sh` script:

- ✅ **Automatic Creation**: Database file created at `./data/bwdata/db.sqlite3`
- ✅ **Schema Initialization**: VaultWarden handles all table creation
- ✅ **WAL Mode**: Write-Ahead Logging enabled for better concurrency
- ✅ **Optimization**: Optimal PRAGMA settings for OCI A1 Flex
- ✅ **Backup Ready**: Configured for online backups without downtime
- ✅ **Robust Health Checks**: Compatible with different VaultWarden images

#### Manual SQLite Database Setup (If Needed)

In rare cases where manual database initialization is required:

```bash
# Create data directory
mkdir -p ./data/bwdata

# Initialize SQLite database with optimal settings
sqlite3 ./data/bwdata/db.sqlite3 << 'EOF'
-- Enable WAL mode for better concurrent performance
PRAGMA journal_mode=WAL;

-- Optimize for performance
PRAGMA synchronous=NORMAL;
PRAGMA cache_size=10000;
PRAGMA temp_store=memory;
PRAGMA mmap_size=268435456;

-- Enable foreign key constraints
PRAGMA foreign_keys=ON;

-- Verify database is ready
SELECT 'Database initialized successfully' as status;
EOF

# Verify database creation
sqlite3 ./data/bwdata/db.sqlite3 "PRAGMA integrity_check;"
```

### Resource Optimization (1 OCPU/6GB)

| Component | CPU Usage | Memory Usage | Purpose |
|-----------|-----------|--------------|----------|
| VaultWarden | ~0.3 OCPU | ~256MB | Core application with SQLite |
| Caddy Proxy | ~0.15 OCPU | ~128MB | HTTPS/reverse proxy |
| Backup Service | ~0.32 OCPU | ~128MB | Automated SQLite backups |
| Fail2ban | ~0.08 OCPU | ~64MB | Security protection |
| Watchtower | ~0.11 OCPU | ~64MB | Auto-updates |
| DDClient | ~0.05 OCPU | ~32MB | Dynamic DNS (optional) |
| **Total** | **~1.0 OCPU** | **~672MB** | **Leaves resources for OS** |

---

## ☁️ OCI Vault Integration

### Why Use OCI Vault?

- **🔐 Secure Secret Storage**: Never store secrets in plain text
- **🔄 Automatic Rotation**: Built-in secret rotation capabilities
- **🏢 Enterprise-Grade**: HSM-backed encryption and access controls
- **💸 Cost-Effective**: Free tier includes 150 secrets

### Setup OCI Vault Integration

#### 1. Create OCI Vault Secret

```bash
# In OCI Console, create a vault secret with JSON content:
{
  "ADMIN_TOKEN": "your-generated-admin-token",
  "BACKUP_PASSPHRASE": "your-generated-backup-passphrase", 
  "SMTP_USERNAME": "your-smtp-username",
  "SMTP_PASSWORD": "your-smtp-password",
  "CF_API_TOKEN": "your-cloudflare-api-token"
}
```

#### 2. Configure OCI Integration

**Enhanced Variable Support**: The system now supports both `OCI_SECRET_OCID` and `OCISECRET_OCID` for backward compatibility.

```bash
# Add to your settings.env (both formats supported)
OCI_SECRET_OCID=ocid1.vaultsecret.oc1.iad.amaaaaaav3k...
# OR (legacy compatibility)
OCISECRET_OCID=ocid1.vaultsecret.oc1.iad.amaaaaaav3k...

# Test OCI Vault connectivity
./oci-setup.sh test

# Retrieve and apply secrets
./oci-setup.sh get
```

#### 3. Automatic Secret Retrieval

```bash
# The startup.sh script automatically retrieves secrets from OCI Vault
# if either OCI_SECRET_OCID or OCISECRET_OCID is configured

# Manual secret management
./oci-setup.sh show           # Display safe configuration info
./oci-setup.sh update         # Upload local config to vault
```

---

## 🛡️ Cloudflare Integration

### Benefits of Cloudflare Proxy

- **🛡️ DDoS Protection**: Automatic protection against attacks
- **⚡ Performance**: Global CDN and caching
- **🔒 SSL/TLS**: Free SSL certificates and edge encryption
- **🌍 Global Reach**: Improved performance worldwide
- **📊 Analytics**: Detailed traffic analytics and security insights

### Cloudflare Configuration

#### 1. DNS Setup

```bash
# In Cloudflare DNS:
# A record: vault.yourdomain.com → your-server-ip (Proxied: ON)
```

#### 2. SSL/TLS Settings

```bash
# Recommended Cloudflare SSL/TLS settings:
# - Encryption mode: Full (strict)
# - Edge Certificates: Universal SSL enabled
# - Origin Server: Generate origin certificate
# - Authenticated Origin Pulls: Enabled
```

#### 3. Security Settings

```bash
# In settings.env:
CLOUDFLARE_ENABLED=true
CF_API_TOKEN=your-cloudflare-api-token

# Automatic Cloudflare IP updates
./startup.sh --force-ip-update
```

The system automatically:
- ✅ Downloads current Cloudflare IP ranges
- ✅ Configures fail2ban for proper IP detection
- ✅ Updates Caddy configuration for real client IPs

---

## 🔧 Management Commands

### Daily Operations

| Command | Purpose |
|---------|----------|
| `./startup.sh` | Start all services with intelligent profiles |
| `./monitor.sh` | Real-time monitoring dashboard |
| `./diagnose.sh --quick` | Quick health check |
| `./backup/db-backup.sh --force` | Manual SQLite backup |

### Weekly Maintenance

| Command | Purpose |
|---------|----------|
| `./sqlite-maintenance.sh` | Intelligent auto maintenance |
| `./backup/verify-backup.sh --latest` | Verify backup integrity |
| `./perf-monitor.sh status` | Performance metrics |

### Monthly Operations

| Command | Purpose |
|---------|----------|
| `./backup/dr-monthly-test.sh` | Disaster recovery test |
| `./benchmark.sh --database` | SQLite performance benchmark |

### Advanced Management

| Command | Purpose |
|---------|----------|
| `./dashboard.sh` | Interactive system dashboard |
| `./alerts.sh --test-email` | Test notification system |
| `./oci-setup.sh test` | Validate OCI Vault integration |

---

## 💾 Backup & Disaster Recovery

### Backup System Overview

The VaultWarden-OCI-Slim deployment includes two complementary backup systems:

1. **Database Backups**: Daily automated SQLite database backups
2. **Full System Backups**: Complete VM backups for disaster recovery scenarios

### SQLite Database Backup Features

- **📦 Multiple Formats**: SQL dumps (portable) and binary backups (fast)
- **🔐 Encryption**: GPG encryption with AES256
- **🗜️ Compression**: Gzip compression for storage efficiency
- **☁️ Cloud Storage**: Automated upload via rclone
- **✅ Verification**: Automated integrity testing
- **📧 Notifications**: HTML email reports with metrics

### Full System Backup Features

- **📦 Complete System Archive**: Entire VM state, configuration, and data
- **🔄 Automated VM Rebuild**: Disaster recovery with automated VM reconstruction
- **🔐 Encrypted Archives**: GPG-encrypted full system backups
- **☁️ Cloud Storage Integration**: Upload to OCI Object Storage or other cloud providers
- **🧪 Automated Testing**: Monthly DR validation with complete system restore
- **📧 Comprehensive Reporting**: Detailed backup status and validation reports

### Quick Backup Setup

```bash
# Setup database backups (automated)
./backup/db-backup.sh --force              # Force SQLite backup now
./backup/verify-backup.sh --latest         # Validate latest backup

# Setup full system backups
./backup/full-backup/setup-automated-full-backup.sh  # Interactive setup
./backup/full-backup/create-full-backup.sh           # Manual full backup
./backup/full-backup/validate-backup.sh             # Validate full backup

# Monthly disaster recovery test
./backup/dr-monthly-test.sh                # Automated DR validation
```

### Backup Schedule (Optimized for OCI A1 Flex)

- **📊 Database Backups**: Daily at 2 AM (automated)
- **📁 Full System Backups**: Weekly on Sunday at 3 AM
- **🧪 DR Testing**: Monthly on first Sunday at 3:30 AM
- **🗑️ Cleanup**: 30-day retention (configurable)

### Full System Backup Commands

| Command | Purpose |
|---------|----------|
| `./backup/full-backup/backup-manager.sh` | Central management interface |
| `./backup/full-backup/create-full-backup.sh` | Create comprehensive system backup |
| `./backup/full-backup/restore-full-backup.sh` | Restore complete system from backup |
| `./backup/full-backup/setup-automated-full-backup.sh` | Configure automated scheduling |
| `./backup/full-backup/validate-backup.sh` | Validate backup integrity |
| `./backup/full-backup/rebuild-vm.sh` | Automated VM rebuild from backup |

---

## 🎛️ Profile System

The project uses Docker Compose profiles to enable/disable services based on your needs:

### Available Profiles

| Profile | Services | Purpose |
|---------|----------|----------|
| **core** | VaultWarden + Caddy | Essential services (always enabled) |
| **backup** | Backup container | Automated SQLite backups |
| **security** | fail2ban | Intrusion prevention |
| **dns** | ddclient | Dynamic DNS updates |
| **maintenance** | watchtower | Auto-updates |

### Profile Management

```bash
# Automatic profile detection (recommended)
./startup.sh

# Manual profile control
export ENABLE_BACKUP=true
export ENABLE_SECURITY=true  
export ENABLE_DNS=false
./startup.sh

# Direct Docker Compose usage
docker compose --profile backup --profile security up -d
```

---

## 📊 Performance Monitoring

### Intelligent Maintenance

The `sqlite-maintenance.sh` script uses AI-driven analysis to determine optimal maintenance operations:

```bash
# Intelligent auto mode (default - recommended)
./sqlite-maintenance.sh

# Analysis only (see what would be done)
./sqlite-maintenance.sh --analyze

# Cron-safe mode (skips VACUUM if VaultWarden running)
./sqlite-maintenance.sh --cron

# Schedule automatic maintenance (done by init-setup.sh)
./sqlite-maintenance.sh --schedule "0 3 * * 0"
```

**Enhanced Decision Matrix**:
- **ANALYZE**: Updates query statistics when stale or missing
- **VACUUM**: Reclaims space when fragmentation >1.3 or free space >10%
- **WAL Checkpoint**: Merges WAL when >10MB or significant relative to DB size
- **PRAGMA Optimize**: Runs on active databases with existing statistics
- **Smart Scheduling**: Automatic setup during initialization

### Performance Metrics

```bash
# Real-time SQLite metrics
./perf-monitor.sh status

# Continuous monitoring mode  
./perf-monitor.sh monitor

# Performance benchmark
./benchmark.sh --database
```

**Key Metrics Monitored**:
- Database size and growth rate
- WAL file size and checkpoint frequency
- Query performance and cache hit ratio
- Resource usage per operation
- Backup performance metrics

---

## 🔒 Security Features

- **🔐 OCI Vault Integration**: Enterprise secret management with dual variable support
- **🛡️ Fail2ban Protection**: Automated intrusion prevention 
- **🔒 Auto-HTTPS**: Automatic SSL certificate management
- **📧 Security Notifications**: Alerts for failed logins and security events
- **💾 Encrypted Backups**: GPG-encrypted database and system backups
- **🌐 Cloudflare Integration**: DDoS protection and security features
- **🔍 Integrity Monitoring**: Continuous SQLite database validation
- **🔧 Enhanced Health Checks**: Robust monitoring compatible with different base images

### Security Best Practices

```bash
# Enable security profile
export ENABLE_SECURITY=true

# Test security notifications
./alerts.sh --test-email

# Monitor security events
./monitor.sh --logs | grep -i security

# Check fail2ban status
docker compose exec bw_fail2ban fail2ban-client status
```

---

## 📚 Documentation

### Comprehensive Guides

- **[📜 Script Reference](docs/Script-Reference.md)** - Complete script documentation
- **[📖 Manual Setup Guide](docs/Manual-Setup-Guide.md)** - Step-by-step manual installation
- **[💾 Backup Guide](docs/Backup-Guide.md)** - SQLite backup system configuration
- **[📦 Full Backup Guide](docs/Full-Backup-Guide.md)** - Complete system backup and disaster recovery
- **[🚨 Disaster Recovery Guide](docs/Disaster-Recovery-Guide.md)** - VM recovery procedures
- **[☁️ OCI Vault Setup Guide](docs/OCI-Vault-Guide.md)** - Enterprise secret management
- **[🔧 Troubleshooting Guide](docs/Troubleshooting-Guide.md)** - Common issues and solutions

### Quick Reference

```bash
# System validation
./diagnose.sh                              # Full diagnostics
./diagnose.sh --quick                      # Essential checks only

# Service management
./startup.sh                               # Start with auto profiles
docker compose restart                     # Restart services
docker compose logs vaultwarden            # View VaultWarden logs

# Database backup operations
./backup/db-backup.sh --force              # Manual SQLite backup
./backup/verify-backup.sh --latest         # Verify backup integrity
./backup/dr-monthly-test.sh --automated    # DR test (silent)

# Full system backup operations
./backup/full-backup/create-full-backup.sh # Manual full system backup
./backup/full-backup/validate-backup.sh    # Validate full backup
./backup/full-backup/setup-automated-full-backup.sh # Setup automation

# Performance monitoring
./perf-monitor.sh status                   # Current metrics
./sqlite-maintenance.sh --analyze          # Maintenance analysis
./benchmark.sh --quick                     # Performance benchmark
```

---

## 🎯 Deployment Scenarios

### Small Team (<10 Users) with Cloudflare

**Perfect fit!** This configuration is optimized for your use case:

```bash
# Recommended settings.env configuration:
ENABLE_BACKUP=true
ENABLE_SECURITY=true
ENABLE_DNS=false          # Not needed with static OCI IP
ENABLE_MAINTENANCE=true
CLOUDFLARE_ENABLED=true

# Resource allocation will be well within limits:
# - Expected CPU: ~56% peak, ~9% idle
# - Expected Memory: ~672MB total
# - Expected Storage: <500MB database for <10 users
```

### OCI Always Free Tier

```bash
# This deployment fits perfectly in OCI Always Free:
# - 1 OCPU ARM processor
# - 6GB RAM (using ~672MB)
# - 200GB storage (using <50GB typically)
# - Automatic backups to OCI Object Storage (free tier)
```

---

## 🏆 Why VaultWarden-OCI-Slim?

### Technical Excellence

- **🧠 Intelligent Automation**: AI-driven maintenance reduces manual intervention
- **📊 Comprehensive Monitoring**: Real-time metrics and alerting
- **🔄 Modern Architecture**: Profile-based service management
- **🎯 Resource Optimized**: Designed specifically for OCI A1 Flex constraints
- **🔧 Smart Management**: Never downgrades components, intelligent version handling

### Production Ready

- **🔐 Enterprise Security**: OCI Vault integration with dual variable support
- **💾 Bulletproof Backups**: Multiple backup formats with automated testing
- **📦 Complete DR Solution**: Full system backups for disaster recovery scenarios
- **📧 Professional Notifications**: HTML email reports with detailed metrics
- **🌐 Cloud Native**: Built for modern cloud deployments
- **🛡️ Robust Health Monitoring**: Compatible with different container base images

### Developer Friendly

- **📚 Comprehensive Documentation**: Every script and feature documented
- **🔧 Easy Configuration**: Interactive setup wizard with smart defaults
- **🐳 Container Ready**: Full Docker Compose orchestration with enhanced health checks
- **⚡ Quick Deployment**: Production-ready in under 10 minutes
- **🔄 Smart Updates**: Intelligent version management that never downgrades

---

## 🚀 Getting Started (Complete Example)

**For a small team with Cloudflare proxy**:

```bash
# 1. Clone and setup with smart version management
git clone https://github.com/killer23d/VaultWarden-OCI-Slim.git
cd VaultWarden-OCI-Slim
chmod +x *.sh

# 2. Generate secrets
echo "ADMIN_TOKEN=$(openssl rand -base64 32)"
echo "BACKUP_PASSPHRASE=$(openssl rand -base64 32)"

# 3. Interactive setup with automatic SQLite maintenance scheduling
./init-setup.sh

# 4. Configure for your domain (edit settings.env)
# DOMAIN_NAME=yourdomain.com
# APP_DOMAIN=vault.yourdomain.com
# CLOUDFLARE_ENABLED=true
# CF_API_TOKEN=your-token
# OCI_SECRET_OCID=your-oci-secret-ocid  # Enhanced variable support

# 5. Validate configuration
./diagnose.sh --quick

# 6. Deploy with enhanced health checks
./startup.sh

# 7. Setup full system backups (optional but recommended)
./backup/full-backup/setup-automated-full-backup.sh

# 8. Access your vault
# https://vault.yourdomain.com
```

**🎉 Enterprise-grade password management with SQLite efficiency, complete backup solutions, and smart automation!**

---

## 📞 Support

- **🐛 Issues**: [GitHub Issues](https://github.com/killer23d/VaultWarden-OCI-Slim/issues)
- **💬 Discussions**: [GitHub Discussions](https://github.com/killer23d/VaultWarden-OCI-Slim/discussions)
- **📚 Documentation**: [Project Wiki](https://github.com/killer23d/VaultWarden-OCI-Slim/wiki)

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## ⭐ Star This Project

If this project helps you deploy VaultWarden efficiently, please give it a star! ⭐
