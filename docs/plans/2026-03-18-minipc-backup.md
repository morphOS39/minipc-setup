# MiniPC Backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatisiertes taeglich verschluesseltes Backup aller MiniPC-Projekte und Configs auf rotierende USB-Sticks, plus nicht-kritische Configs im GitHub Repo.

**Architecture:** Bash-Script (`backup-usb.sh`) erkennt USB-Stick per Label, sammelt alle Projektverzeichnisse und Config-Dateien, erstellt ein tar.gz-Archiv, verschluesselt es mit GPG (AES256, symmetrisch), und legt es auf dem Stick ab. Zweites Script (`export-config.sh`) exportiert Service Files und Cronjobs ins Repo. Cronjob um 4:00 triggert das USB-Backup.

**Tech Stack:** Bash, GPG, tar, cron, systemd, git

**Zielumgebung:** MiniPC (brain31@100.123.179.24, Ubuntu 24.04 WSL)

---

### Task 1: Git Repo minipc-setup initialisieren

**Files:**
- Create: `/home/mschlipp/minipc-setup/README.md`
- Create: `/home/mschlipp/minipc-setup/.gitignore`

- [ ] **Step 1: Git Repo initialisieren**

```bash
cd /home/mschlipp/minipc-setup
git init
```

- [ ] **Step 2: .gitignore erstellen**

```
# Keine Credentials oder Passphrasen
*.gpg
.backup-passphrase
```

- [ ] **Step 3: README.md erstellen**

Kurze Beschreibung: Was ist das Repo, was enthaelt es, wie nutzt man die Scripts.

- [ ] **Step 4: Initial Commit + Remote**

```bash
git add -A
git commit -m "feat: initial minipc-setup repo structure"
git remote add origin https://github.com/morphOS39/minipc-setup.git
git branch -M main
```

Hinweis: GitHub Repo muss vorher erstellt werden (privat!). Push erst nach Erstellung.

---

### Task 2: Config-Export-Script (Saeule 1)

**Files:**
- Create: `scripts/export-config.sh`
- Create: `service-files/` (Verzeichnis)
- Create: `cronjobs/` (Verzeichnis)

- [ ] **Step 1: Export-Script schreiben**

`scripts/export-config.sh` — Dieses Script wird auf dem MiniPC ausgefuehrt und:
1. Kopiert alle systemd Service Files nach `service-files/`
2. Exportiert Cronjob-Liste nach `cronjobs/crontab-brain31.txt`
3. Zeigt Diff an damit man weiss was sich geaendert hat

```bash
#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_DIR="$REPO_DIR/service-files"
CRON_DIR="$REPO_DIR/cronjobs"

mkdir -p "$SERVICE_DIR" "$CRON_DIR"

# Systemd Service Files exportieren
echo "=== Exporting service files ==="
for svc in family-hub family-hub-test; do
    SVC_FILE="/etc/systemd/system/${svc}.service"
    if [ -f "$SVC_FILE" ]; then
        cp "$SVC_FILE" "$SERVICE_DIR/"
        echo "  Copied $SVC_FILE"
    else
        echo "  WARNING: $SVC_FILE not found"
    fi
done

# Cronjobs exportieren
echo "=== Exporting cronjobs ==="
crontab -l > "$CRON_DIR/crontab-brain31.txt" 2>/dev/null || echo "  No crontab found"
echo "  Saved to $CRON_DIR/crontab-brain31.txt"

# Diff anzeigen
echo ""
echo "=== Changes ==="
cd "$REPO_DIR"
git diff --stat 2>/dev/null || true
echo ""
echo "Review changes, then: git add -A && git commit -m 'update config export' && git push"
```

- [ ] **Step 2: Script ausfuehrbar machen**

```bash
chmod +x scripts/export-config.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/export-config.sh
git commit -m "feat: add config export script for service files and cronjobs"
```

---

### Task 3: USB-Backup-Script (Saeule 2)

**Files:**
- Create: `scripts/backup-usb.sh`

- [ ] **Step 1: Backup-Script schreiben**

`scripts/backup-usb.sh`:

```bash
#!/bin/bash
set -euo pipefail

LOGFILE="$HOME/backup.log"
PASSPHRASE_FILE="$HOME/.backup-passphrase"
TIMESTAMP=$(date +%Y-%m-%d)
BACKUP_SOURCES=(
    "$HOME/family-hub"
    "$HOME/family-hub-test"
    "$HOME/business-lunch"
    "$HOME/vega-memory"
    "$HOME/.ssh"
)
# Config-Dateien einzeln (liegen in Projektverzeichnissen, evtl. in .gitignore)
CONFIG_FILES=(
    "$HOME/family-hub/config.yaml"
    "$HOME/family-hub/config-test.yaml"
    "$HOME/family-hub-test/config.yaml"
    "$HOME/family-hub-test/config-test.yaml"
)
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
trap "rm -rf $STAGING" EXIT

# Projekte kopieren
for src in "${BACKUP_SOURCES[@]}"; do
    if [ -e "$src" ]; then
        cp -a "$src" "$STAGING/"
    else
        log "WARNING: $src not found, skipping"
    fi
done

# Config-Dateien (werden in staging/configs/ gesammelt)
mkdir -p "$STAGING/configs"
for cfg in "${CONFIG_FILES[@]}"; do
    if [ -f "$cfg" ]; then
        cp "$cfg" "$STAGING/configs/$(basename "$cfg").$(echo "$cfg" | md5sum | head -c 8)"
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
        | while read old; do
            log "Deleting old backup: $(basename "$old")"
            rm -f "$old"
        done
fi

# --- Unmount ---
sudo umount "$STICK_MOUNT" 2>/dev/null || true
log "Backup finished. Stick $STICK_LABEL unmounted."
```

- [ ] **Step 2: Script ausfuehrbar machen**

```bash
chmod +x scripts/backup-usb.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/backup-usb.sh
git commit -m "feat: add encrypted USB backup script with dual-stick rotation"
```

---

### Task 4: Setup-Script fuer Ersteinrichtung

**Files:**
- Create: `scripts/setup-backup.sh`

- [ ] **Step 1: Setup-Script schreiben**

Einmaliges Script das auf dem MiniPC ausgefuehrt wird:

```bash
#!/bin/bash
set -euo pipefail

echo "=== MiniPC Backup Setup ==="

# 1. GPG installieren falls noetig
if ! command -v gpg &>/dev/null; then
    echo "Installing GPG..."
    sudo apt-get update && sudo apt-get install -y gnupg
fi

# 2. Passphrase generieren
PASSPHRASE_FILE="$HOME/.backup-passphrase"
if [ ! -f "$PASSPHRASE_FILE" ]; then
    echo "Generating backup passphrase..."
    openssl rand -base64 32 > "$PASSPHRASE_FILE"
    chmod 600 "$PASSPHRASE_FILE"
    echo ""
    echo "=========================================="
    echo "  WICHTIG: Passphrase im Passwort-Manager speichern!"
    echo "  Datei: $PASSPHRASE_FILE"
    echo "  Inhalt:"
    cat "$PASSPHRASE_FILE"
    echo ""
    echo "=========================================="
    echo ""
    read -p "Passphrase gespeichert? (j/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Jj]$ ]]; then
        echo "Bitte zuerst Passphrase sichern. Abbruch."
        exit 1
    fi
else
    echo "Passphrase already exists at $PASSPHRASE_FILE"
fi

# 3. USB-Stick pruefen
echo ""
echo "Bitte USB-Stick einstecken und mit BACKUP-A oder BACKUP-B labeln."
echo ""
echo "USB-Stick labeln (Beispiel fuer /dev/sdX1):"
echo "  sudo e2label /dev/sdX1 BACKUP-A"
echo "  (oder: sudo fatlabel /dev/sdX1 BACKUP-A fuer FAT32)"
echo ""
echo "Verfuegbare Geraete:"
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
echo ""

# 4. Cronjob einrichten
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/backup-usb.sh"
CRON_LINE="0 4 * * * $SCRIPT_PATH >> $HOME/backup.log 2>&1"

if crontab -l 2>/dev/null | grep -qF "backup-usb.sh"; then
    echo "Backup cronjob already exists."
else
    (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
    echo "Cronjob installed: $CRON_LINE"
fi

echo ""
echo "=== Setup complete ==="
echo "Teste mit: $SCRIPT_PATH"
```

- [ ] **Step 2: Script ausfuehrbar machen**

```bash
chmod +x scripts/setup-backup.sh
```

- [ ] **Step 3: Commit**

```bash
git add scripts/setup-backup.sh
git commit -m "feat: add one-time backup setup script"
```

---

### Task 5: Setup-Anleitung (README)

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README schreiben**

Vollstaendige Anleitung mit:
- Was ist dieses Repo
- Voraussetzungen
- Ersteinrichtung (Setup-Script)
- USB-Stick vorbereiten (formatieren, labeln)
- Wie Backup funktioniert
- Wie man ein Backup wiederherstellt (entschluesseln + entpacken)
- Restore-Befehl:
  ```bash
  gpg --decrypt backup-2026-03-18-A.tar.gz.gpg | tar -xzf - -C /tmp/restore/
  ```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add complete setup and restore instructions"
```

---

### Task 6: Auf MiniPC deployen

- [ ] **Step 1: GitHub Repo erstellen (privat)**

```bash
gh repo create morphOS39/minipc-setup --private --source=/home/mschlipp/minipc-setup --push
```

Oder manuell auf GitHub erstellen und pushen:
```bash
cd /home/mschlipp/minipc-setup
git push -u origin main
```

- [ ] **Step 2: Auf MiniPC klonen**

```bash
ssh brain31@100.123.179.24 "cd ~ && git clone https://github.com/morphOS39/minipc-setup.git"
```

- [ ] **Step 3: Setup-Script ausfuehren**

```bash
ssh brain31@100.123.179.24 "cd ~/minipc-setup && bash scripts/setup-backup.sh"
```

Interaktiv: Passphrase wird angezeigt — im Passwort-Manager speichern!

- [ ] **Step 4: USB-Stick vorbereiten (manuell auf MiniPC)**

Ward steckt den Stick ein, dann:
```bash
# Stick finden
lsblk
# Formatieren (ext4 empfohlen) — ACHTUNG: loescht alle Daten!
sudo mkfs.ext4 -L BACKUP-A /dev/sdX1
# Zweiten Stick spaeter genauso mit BACKUP-B
```

- [ ] **Step 5: Testlauf**

```bash
ssh brain31@100.123.179.24 "bash ~/minipc-setup/scripts/backup-usb.sh"
```

Pruefen:
```bash
ssh brain31@100.123.179.24 "cat ~/backup.log | tail -5"
```

- [ ] **Step 6: Config-Export ausfuehren und pushen**

```bash
ssh brain31@100.123.179.24 "cd ~/minipc-setup && bash scripts/export-config.sh && git add -A && git commit -m 'update: config export' && git push"
```

---

### Task 7: Memory aktualisieren

- [ ] **Step 1: MEMORY.md aktualisieren**

Neuen Abschnitt hinzufuegen:
```
## MiniPC Backup
- **Repo:** https://github.com/morphOS39/minipc-setup (private)
- **USB-Sticks:** BACKUP-A und BACKUP-B, GPG-verschluesselt (AES256)
- **Cronjob:** 4:00 taeglich, Script: ~/minipc-setup/scripts/backup-usb.sh
- **Passphrase:** In ~/.backup-passphrase (chmod 600) + Passwort-Manager
- **Restore:** gpg --decrypt backup-DATUM-X.tar.gz.gpg | tar -xzf - -C /tmp/restore/
- **Config-Export:** ~/minipc-setup/scripts/export-config.sh (manuell, dann commit+push)
```

- [ ] **Step 2: Commit Memory**

---

### Zusammenfassung der Dateien

```
minipc-setup/
  README.md
  .gitignore
  scripts/
    backup-usb.sh        # Taegliches USB-Backup (Cronjob)
    export-config.sh     # Service Files + Cronjobs exportieren
    setup-backup.sh      # Ersteinrichtung (einmalig)
  service-files/         # Exportierte .service Dateien
  cronjobs/              # Exportierte Cronjob-Listen
  docs/
    specs/               # Design-Spec
    plans/               # Dieser Plan
```
