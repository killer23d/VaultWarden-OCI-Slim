FROM alpine:3.19

# Install required packages for SQLite backup operations
RUN apk add --no-cache \
    sqlite \
    sqlite-dev \
    rclone \
    gnupg \
    gzip \
    tar \
    curl \
    bash \
    dcron \
    mailx \
    tzdata \
    ca-certificates

# Create backup user and directories
RUN addgroup -g 1000 backup && \
    adduser -D -u 1000 -G backup backup

# Create necessary directories
RUN mkdir -p /backups /var/log/backup /home/backup/.config/rclone && \
    chown -R backup:backup /backups /var/log/backup /home/backup

# Copy backup scripts
COPY --chown=backup:backup db-backup.sh /usr/local/bin/db-backup.sh
COPY --chown=backup:backup db-restore.sh /usr/local/bin/db-restore.sh
COPY --chown=backup:backup verify-backup.sh /usr/local/bin/verify-backup.sh
COPY --chown=backup:backup entrypoint.sh /entrypoint.sh

# Make scripts executable
RUN chmod +x /usr/local/bin/db-backup.sh \
    /usr/local/bin/db-restore.sh \
    /usr/local/bin/verify-backup.sh \
    /entrypoint.sh

# Create SQLite-specific backup directories
RUN mkdir -p /tmp/sqlite-backup && \
    chown backup:backup /tmp/sqlite-backup

# Set up cron for automated backups
RUN echo "# VaultWarden SQLite Backup Cron Jobs" > /etc/crontabs/backup && \
    echo "# Weekly backup - Monday 3 AM" >> /etc/crontabs/backup && \
    echo "0 3 * * 1 /usr/local/bin/db-backup.sh >> /var/log/backup/cron.log 2>&1" >> /etc/crontabs/backup && \
    chown backup:backup /etc/crontabs/backup

# Health check for backup service
HEALTHCHECK --interval=30m --timeout=10s --start-period=1m --retries=3 \
    CMD pgrep crond >/dev/null && test -w /backups || exit 1

# Set working directory
WORKDIR /home/backup

# Switch to backup user
USER backup

# Set environment variables
ENV BACKUP_DIR=/backups \
    LOG_DIR=/var/log/backup \
    DATABASE_TYPE=sqlite \
    SQLITE_DB_PATH=/data/bwdata/db.sqlite3 \
    VAULTWARDEN_DATA_DIR=/data/bwdata

# Expose backup directory as volume
VOLUME ["/backups", "/var/log/backup", "/home/backup/.config/rclone"]

# Entry point
ENTRYPOINT ["/entrypoint.sh"]
CMD ["crond", "-f", "-l", "8"]

# Labels for identification
LABEL maintainer="VaultWarden-OCI-Slim" \
      description="SQLite backup container for VaultWarden" \
      version="1.0" \
      database="sqlite" \
      optimization="1-ocpu-6gb"
