# MiniPC Setup & Backup

Konfiguration, Service Files und Backup-Scripts fuer den MiniPC (brain31, Ubuntu 24.04 WSL).

## Inhalt

```
minipc-setup/
  scripts/
    backup-usb.sh        # Taegliches verschluesseltes USB-Backup (Cronjob 4:00)
    export-config.sh     # Service Files + Cronjobs ins Repo exportieren
    setup-backup.sh      # Ersteinrichtung (einmalig ausfuehren)
  service-files/         # Exportierte systemd .service Dateien
  cronjobs/              # Exportierte Cronjob-Listen
```

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
- Sichert alle Projekte komplett: family-hub, family-hub-test, business-lunch, vega-memory, minipc-setup
- Sichert SSH-Keys, Config-Dateien mit Credentials, Service Files, Cronjobs
- Erstellt ein tar.gz-Archiv, verschluesselt mit GPG (AES256)
- Dateiname: `backup-YYYY-MM-DD-A.tar.gz.gpg` (bzw. -B)
- Alte Backups werden bei Platzmangel aufgeraeumt (min. 3 behalten)
- Falls kein Stick steckt: Warnung im Log, kein Fehler

### Stick-Rotation

Zwei Sticks im Wechsel nutzen — einer steckt im MiniPC, einer liegt extern.
So hat man immer ein Offsite-Backup.

## Backup wiederherstellen

```bash
# Archiv entschluesseln und entpacken:
mkdir -p /tmp/restore
gpg --decrypt backup-2026-03-18-A.tar.gz.gpg | tar -xzf - -C /tmp/restore/

# Inhalt pruefen:
ls /tmp/restore/

# Einzelne Dateien zurueckkopieren, z.B.:
cp -a /tmp/restore/family-hub ~/family-hub
cp /tmp/restore/family-hub/config.yaml ~/family-hub/config.yaml
cp -a /tmp/restore/.ssh ~/.ssh
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
