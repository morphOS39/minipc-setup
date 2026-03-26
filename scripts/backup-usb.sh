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
    "$HOME/vps-backup"
    "$HOME/flomily-web"
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
    "flomily-beta.service"
    "wsl-keepalive.service"
)

TELEGRAM_TOKEN_FILE="$HOME/.vega-telegram-token"
TELEGRAM_CHAT_ID="895154565"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOGFILE"
}

notify() {
    local msg="$1"
    if [ -f "$TELEGRAM_TOKEN_FILE" ]; then
        local token
        token=$(cat "$TELEGRAM_TOKEN_FILE")
        curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=${msg}" > /dev/null 2>&1 || true
    fi
}

# --- Passphrase pruefen ---
if [ ! -f "$PASSPHRASE_FILE" ]; then
    log "ERROR: Passphrase file $PASSPHRASE_FILE not found. Aborting."
    notify "BACKUP FEHLER: Passphrase-Datei nicht gefunden!"
    exit 1
fi

# --- USB-Stick finden (exFAT, Windows-Laufwerk via drvfs) ---
# Erkennung ueber Marker-Datei: BACKUP-A.marker oder BACKUP-B.marker im Root
# WSL mountet nur C: automatisch — andere Laufwerke muessen wir selbst mounten
STICK_LABEL=""
STICK_MOUNT=""

for letter in D E F G H; do
    mountpoint="/mnt/${letter,,}"
    # Laufwerk mounten falls noch nicht gemountet
    if ! mountpoint -q "$mountpoint" 2>/dev/null; then
        sudo mkdir -p "$mountpoint"
        sudo mount -t drvfs "${letter}:" "$mountpoint" 2>/dev/null || continue
    fi
    for marker in BACKUP-A BACKUP-B; do
        if [ -f "$mountpoint/${marker}.marker" ]; then
            STICK_LABEL="$marker"
            STICK_MOUNT="$mountpoint"
            break 2
        fi
    done
    # Kein Backup-Stick auf diesem Laufwerk — wieder unmounten
    sudo umount "$mountpoint" 2>/dev/null || true
done

if [ -z "$STICK_LABEL" ]; then
    log "WARNING: No USB stick found (BACKUP-A / BACKUP-B marker). Skipping backup."
    notify "BACKUP: Kein USB-Stick gefunden. Bitte Stick einstecken!"
    exit 0
fi

STICK_ID=$(echo "$STICK_LABEL" | tail -c 2)  # A or B
BACKUP_NAME="backup-${TIMESTAMP}-${STICK_ID}.tar.gz.gpg"
BACKUP_PATH="${STICK_MOUNT}/${BACKUP_NAME}"

log "Starting backup to $STICK_LABEL ($BACKUP_PATH)"

# --- Temporaeres Verzeichnis fuer Staging ---
STAGING=$(mktemp -d)
trap 'rc=$?; rm -rf "$STAGING"; if [ $rc -ne 0 ]; then notify "BACKUP FEHLER: Script abgebrochen (Exit $rc) auf ${STICK_LABEL:-unbekannt}!"; fi' EXIT

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
notify "BACKUP OK: ${BACKUP_NAME} (${BACKUP_SIZE}) auf ${STICK_LABEL}"
