#!/bin/bash
set -euo pipefail

LOGFILE="$HOME/backup.log"
PASSPHRASE_FILE="$HOME/.backup-passphrase"
TIMESTAMP=$(date +%Y-%m-%d)

# Komplette Projektverzeichnisse
BACKUP_SOURCES=(
    "$HOME/family-hub"
    "$HOME/family-hub-test"
    "$HOME/business-lunch"
    "$HOME/vega-memory"
    "$HOME/minipc-setup"
    "$HOME/.ssh"
)

# Systemd Service Files
SERVICE_FILES=(
    "/etc/systemd/system/family-hub.service"
    "/etc/systemd/system/family-hub-test.service"
)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOGFILE"
}

# --- Passphrase pruefen ---
if [ ! -f "$PASSPHRASE_FILE" ]; then
    log "ERROR: Passphrase file $PASSPHRASE_FILE not found. Aborting."
    exit 1
fi

# --- USB-Stick finden ---
STICK_LABEL=""
STICK_MOUNT=""

for label in BACKUP-A BACKUP-B; do
    MOUNT_POINT="/mnt/$label"
    DEV=$(blkid -L "$label" 2>/dev/null || true)
    if [ -n "$DEV" ]; then
        STICK_LABEL="$label"
        STICK_MOUNT="$MOUNT_POINT"
        # Mounten falls noetig
        if ! mountpoint -q "$STICK_MOUNT" 2>/dev/null; then
            sudo mkdir -p "$STICK_MOUNT"
            sudo mount "$DEV" "$STICK_MOUNT"
            log "Mounted $DEV ($STICK_LABEL) at $STICK_MOUNT"
        fi
        break
    fi
done

if [ -z "$STICK_LABEL" ]; then
    log "WARNING: No USB stick found (BACKUP-A / BACKUP-B). Skipping backup."
    exit 0
fi

STICK_ID=$(echo "$STICK_LABEL" | tail -c 2)  # A or B
BACKUP_NAME="backup-${TIMESTAMP}-${STICK_ID}.tar.gz.gpg"
BACKUP_PATH="${STICK_MOUNT}/${BACKUP_NAME}"

log "Starting backup to $STICK_LABEL ($BACKUP_PATH)"

# --- Temporaeres Verzeichnis fuer Staging ---
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

# Projekte und Verzeichnisse kopieren
for src in "${BACKUP_SOURCES[@]}"; do
    if [ -e "$src" ]; then
        DIRNAME=$(basename "$src")
        cp -a "$src" "$STAGING/$DIRNAME"
        log "  Added $src"
    else
        log "  WARNING: $src not found, skipping"
    fi
done

# Service Files
mkdir -p "$STAGING/service-files"
for svc in "${SERVICE_FILES[@]}"; do
    if [ -f "$svc" ]; then
        cp "$svc" "$STAGING/service-files/"
    fi
done

# Cronjob
crontab -l > "$STAGING/crontab-brain31.txt" 2>/dev/null || true

# --- Tar + GPG ---
log "Creating encrypted archive..."
tar -czf - -C "$STAGING" . \
    | gpg --batch --yes --symmetric --cipher-algo AES256 \
          --passphrase-file "$PASSPHRASE_FILE" \
          -o "$BACKUP_PATH"

BACKUP_SIZE=$(du -h "$BACKUP_PATH" | cut -f1)
log "Backup complete: $BACKUP_NAME ($BACKUP_SIZE)"

# --- Alte Backups aufraeumen (gleicher Stick-Buchstabe, aelteste zuerst) ---
# Behalte mindestens 3 Backups, loesche aelteste wenn weniger als 500MB frei
STICK_FREE=$(df --output=avail "$STICK_MOUNT" | tail -1 | tr -d ' ')
MIN_FREE_KB=512000  # 500MB

if [ "$STICK_FREE" -lt "$MIN_FREE_KB" ]; then
    log "Low disk space on $STICK_LABEL, cleaning old backups..."
    ls -t "${STICK_MOUNT}"/backup-*-${STICK_ID}.tar.gz.gpg 2>/dev/null \
        | tail -n +4 \
        | while read -r old; do
            log "  Deleting old backup: $(basename "$old")"
            rm -f "$old"
        done
fi

# --- Unmount ---
sudo umount "$STICK_MOUNT" 2>/dev/null || true
log "Backup finished. Stick $STICK_LABEL unmounted."
