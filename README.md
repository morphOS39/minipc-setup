# MiniPC Setup & Backup

Konfiguration, Service Files und Backup-Scripts fuer den MiniPC (brain31, Ubuntu 24.04 WSL).

## Inhalt

```
minipc-setup/
  scripts/
    backup-usb.sh        # Taegliches verschluesseltes USB-Backup (Cronjob 4:00)
    export-config.sh     # Service Files + Cronjobs ins Repo exportieren
    setup-backup.sh      # Ersteinrichtung (einmalig ausfuehren)
  docs/
    restore-runbook.md   # Komplette From-Scratch-Anleitung
  service-files/         # Exportierte systemd .service Dateien
  cronjobs/              # Exportierte Cronjob-Listen
```

## Was wird gesichert?

- **Projekte:** family-hub, family-hub-test, business-lunch, crypto-monitor, vega-memory, minipc-setup (ohne .venv)
- **Credentials:** SSH-Keys, Git-Credentials, Telegram-Tokens, Backup-Passphrase (separat im Passwort-Manager!)
- **Dotfiles:** .bashrc, .profile, .gitconfig
- **Configs:** Systemd Service Files, Caddy Config, Cronjobs
- **System-Info:** Installierte Paketliste

## Ersteinrichtung

### 1. Repo klonen

```bash
cd ~ && git clone https://github.com/morphOS39/minipc-setup.git
```

### 2. Setup-Script ausfuehren

```bash
cd ~/minipc-setup && bash scripts/setup-backup.sh
```

Das Script:
- Installiert GPG (falls noetig)
- Generiert eine Backup-Passphrase (`~/.backup-passphrase`)
- Richtet den Cronjob ein (taeglich 4:00)

**WICHTIG:** Die angezeigte Passphrase sofort im Passwort-Manager speichern!

### 3. USB-Sticks vorbereiten

Zwei USB-Sticks mit ext4 formatieren und labeln:

```bash
# Stick einstecken, Device finden:
lsblk

# Erster Stick (ACHTUNG: loescht alle Daten auf dem Stick!):
sudo mkfs.ext4 -L BACKUP-A /dev/sdX1

# Zweiter Stick:
sudo mkfs.ext4 -L BACKUP-B /dev/sdX1
```

### 4. Testlauf

```bash
# Stick einstecken, dann:
bash ~/minipc-setup/scripts/backup-usb.sh

# Log pruefen:
cat ~/backup.log
```

## Wie das Backup funktioniert

- **Taeglich um 4:00** laeuft `backup-usb.sh` per Cronjob
- Erkennt automatisch welcher Stick steckt (BACKUP-A oder BACKUP-B)
- Sichert alle Projekte (ohne .venv), Credentials, Dotfiles, Configs
- Erstellt ein tar.gz-Archiv, verschluesselt mit GPG (AES256)
- Dateiname: `backup-YYYY-MM-DD-A.tar.gz.gpg` (bzw. -B)
- Alte Backups werden bei Platzmangel aufgeraeumt (min. 3 behalten)
- Falls kein Stick steckt: Warnung im Log, kein Fehler

### Stick-Rotation

Zwei Sticks im Wechsel nutzen — einer steckt im MiniPC, einer liegt extern.
So hat man immer ein Offsite-Backup.

## Backup wiederherstellen

Siehe **[docs/restore-runbook.md](docs/restore-runbook.md)** fuer die komplette From-Scratch-Anleitung.

Kurzversion (nur Daten zurueckspielen):

```bash
# Archiv entschluesseln und entpacken:
mkdir -p /tmp/restore
gpg --decrypt backup-2026-03-18-A.tar.gz.gpg | tar -xzf - -C /tmp/restore/

# Inhalt pruefen:
ls /tmp/restore/
```

Die Passphrase wird bei der Entschluesselung abgefragt (aus Passwort-Manager).

## Config-Export (Saeule 1)

Nicht-kritische Konfiguration (Service Files, Cronjobs) ins Repo exportieren:

```bash
cd ~/minipc-setup
bash scripts/export-config.sh
git add -A && git commit -m "update: config export" && git push
```

Bei Aenderungen an Services oder Cronjobs manuell ausfuehren.
