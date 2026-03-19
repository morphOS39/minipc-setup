#!/bin/bash
set -euo pipefail

LOGFILE="$HOME/backup.log"
PASSPHRASE_FILE="$HOME/.backup-passphrase"
TIMESTAMP=$(date +%Y-%m-%d)

# Komplette Projektverzeichnisse (werden ohne .venv kopiert)
BACKUP_DIRS=(
    "$HOME/family-hub"
    "$HOME/family-hub-test"
    "$HOME/business-lunch"
    "$HOME/crypto-monitor"
    "$HOME/vega-memory"
    "$HOME/minipc-setup"
    "$HOME/.ssh"
)

# Einzelne Dateien (Credentials, Dotfiles, Scripts)
BACKUP_FILES=(
    "$HOME/.vega-telegram-token"
    "$HOME/.vega-telegram-offset"
    "$HOME/.gitconfig"
    "$HOME/.git-credentials"
    "$HOME/.bashrc"
    "$HOME/.profile"
    "$HOME/organize-board.sh"
)

# Custom Service Files (dynamisch alle eigenen)
CUSTOM_SERVICES=(
    "family-hub.service"
    "family-hub-test.service"
    "crypto-monitor.service"
)

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOGFILE"
}

# --- Passphrase pruefen ---
if [ ! -f "$PASSPHRASE_FILE" ]; then
    log "ERROR: Passphrase file $PASSPHRASE_FILE not found. Aborting."
    exit 1
fi

# --- USB-Stick finden (exFAT, von Windows gemountet unter /mnt/<laufwerk>/) ---
# Erkennung ueber Marker-Datei: BACKUP-A.marker oder BACKUP-B.marker im Root
STICK_LABEL=""
STICK_MOUNT=""

for drive in /mnt/[d-z]; do
    [ -d "$drive" ] || continue
    for marker in BACKUP-A BACKUP-B; do
        if [ -f "$drive/${marker}.marker" ]; then
            STICK_LABEL="$marker"
            STICK_MOUNT="$drive"
            break 2
        fi
    done
done

if [ -z "$STICK_LABEL" ]; then
    log "WARNING: No USB stick found (BACKUP-A / BACKUP-B marker). Skipping backup."
    exit 0
fi

STICK_ID=$(echo "$STICK_LABEL" | tail -c 2)  # A or B
BACKUP_NAME="backup-${TIMESTAMP}-${STICK_ID}.tar.gz.gpg"
BACKUP_PATH="${STICK_MOUNT}/${BACKUP_NAME}"

log "Starting backup to $STICK_LABEL ($BACKUP_PATH)"

# --- Temporaeres Verzeichnis fuer Staging ---
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

# Projektverzeichnisse kopieren (ohne .venv, .cache, .vscode-server)
for src in "${BACKUP_DIRS[@]}"; do
    if [ -e "$src" ]; then
        DIRNAME=$(basename "$src")
        rsync -a --exclude='.venv' --exclude='.cache' --exclude='.vscode-server' \
            "$src/" "$STAGING/$DIRNAME/"
        log "  Added $src"
    else
        log "  WARNING: $src not found, skipping"
    fi
done

# Einzelne Dateien kopieren
mkdir -p "$STAGING/dotfiles"
for f in "${BACKUP_FILES[@]}"; do
    if [ -f "$f" ]; then
        cp "$f" "$STAGING/dotfiles/"
        log "  Added $(basename "$f")"
    else
        log "  WARNING: $f not found, skipping"
    fi
done

# Service Files
mkdir -p "$STAGING/service-files"
for svc in "${CUSTOM_SERVICES[@]}"; do
    SVC_PATH="/etc/systemd/system/$svc"
    if [ -f "$SVC_PATH" ]; then
        cp "$SVC_PATH" "$STAGING/service-files/"
    fi
done

# Caddy Config
if [ -f "/etc/caddy/Caddyfile" ]; then
    mkdir -p "$STAGING/caddy"
    cp /etc/caddy/Caddyfile "$STAGING/caddy/"
    log "  Added Caddyfile"
fi

# Cronjob
crontab -l > "$STAGING/crontab-brain31.txt" 2>/dev/null || true

# Installierte Pakete
apt-mark showmanual > "$STAGING/installed-packages.txt" 2>/dev/null || true
log "  Added installed-packages.txt"

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

# Kein Unmount noetig — Windows verwaltet den Mount.
log "Backup finished on $STICK_LABEL ($STICK_MOUNT)."
