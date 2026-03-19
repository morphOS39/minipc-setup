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

# 3. USB-Stick Info
echo ""
echo "=== USB-Stick vorbereiten ==="
echo ""
echo "Sticks als exFAT formatieren (Windows: Rechtsklick -> Formatieren)."
echo "Dann Marker-Datei im Root des Sticks erstellen:"
echo ""
echo "  Erster Stick:  Leere Datei 'BACKUP-A.marker' anlegen"
echo "  Zweiter Stick: Leere Datei 'BACKUP-B.marker' anlegen"
echo ""
echo "Windows mountet die Sticks automatisch, WSL sieht sie unter /mnt/<laufwerk>/."
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
echo ""
echo "Naechste Schritte:"
echo "  1. USB-Sticks als exFAT formatieren + Marker-Datei anlegen (siehe oben)"
echo "  2. Stick einstecken, Testlauf: $SCRIPT_PATH"
echo "  3. Log pruefen: cat ~/backup.log"
