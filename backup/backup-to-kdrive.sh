#!/usr/bin/env bash
#
# backup-to-kdrive.sh — nightly DB backup for Traccar, offsite to kDrive
#
# What it does:
#   - Dumps the `traccar` MySQL database directly on the host (mysqldump).
#     Unlike Portal/Mgmt Web, Traccar's DB isn't in a container here — it's
#     MySQL installed straight on the VPS (see doc/installation.md) — so
#     there's no `docker compose exec` step, just a local mysqldump.
#   - Uses --single-transaction so InnoDB tables get a consistent snapshot
#     without locking, since Traccar keeps writing positions the whole time.
#   - No password needed: Ubuntu's MySQL packages set up root@localhost
#     with the auth_socket plugin, so mysqldump run as root over the local
#     socket authenticates for free — same "nothing to leak" idea as
#     Portal/Mgmt Web's reliance on Postgres's local trust auth.
#   - Gzips the dump, prunes local backups older than RETENTION_DAYS, then
#     syncs the whole backup directory to kDrive via rclone (WebDAV).
#   - Same overall pattern as Portal/Mgmt Web's backup-to-kdrive.sh, but
#     Traccar uses its own kDrive folder + rclone remote — don't point it
#     at the same remote path as those, or `rclone sync` will delete their
#     backups (see NOTE below).
#
# NOTE on `rclone sync`: it makes the remote match the local directory
# exactly, including deletions — so once a local backup ages out past
# RETENTION_DAYS and gets deleted, the *next* sync run also deletes it from
# kDrive. Intentional, matches Portal/Mgmt Web's design. Switch to `copy`
# below if kDrive should retain backups longer than local disk does.
#
# Must run as root (mysqldump relies on root's local auth_socket access).
#
# One-time server setup: see doc/installation.md, "Backups" section.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DB_NAME="traccar"
BACKUP_DIR="$REPO_DIR/backup/dumps"
RETENTION_DAYS=360   # Traccar's DB is mostly GPS position history and can
                      # grow much faster than Portal/Mgmt Web's — lower this
                      # if local disk or kDrive space becomes a concern.
LOG="$REPO_DIR/backup/kdrive-backup.log"
RCLONE_CONFIG="/root/.config/rclone/rclone.conf"   # hardcoded: plain `sudo`
                                                     # doesn't reset $HOME to
                                                     # /root, so relying on
                                                     # $HOME here silently
                                                     # pointed at the wrong
                                                     # user's config
DATE="$(date +%Y-%m-%d)"

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must run as root (mysqldump needs local root auth_socket access)." >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR" "$(dirname "$LOG")"

{
    echo "=== Backup started: $(date '+%F %T') ==="

    mysqldump --single-transaction --quick --no-tablespaces \
        --databases "$DB_NAME" \
        | gzip > "$BACKUP_DIR/traccar_${DATE}.sql.gz"

    find "$BACKUP_DIR" -name "traccar_*.sql.gz" -mtime +"$RETENTION_DAYS" -delete

    rclone --config "$RCLONE_CONFIG" sync "$BACKUP_DIR" kdrive:/ \
        --log-file="$LOG" --log-level INFO

    echo "=== Backup finished: $(date '+%F %T') ==="
} >> "$LOG" 2>&1
