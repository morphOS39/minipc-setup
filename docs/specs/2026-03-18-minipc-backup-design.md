# MiniPC Backup-Strategie: Design-Spec

**Datum:** 2026-03-18
**Ziel:** Automatisiertes Backup aller MiniPC-Daten mit zwei Saeulen: GitHub Repo (nicht-kritisch) + verschluesselter USB-Stick (alles inkl. Credentials).

---

## Saeule 1: GitHub Repo (minipc-setup, privat)

### Inhalt
- Systemd Service Files (family-hub.service, family-hub-test.service)
- Cronjob-Export (crontab -l Output)
- Setup-Anleitung (MiniPC von Null aufsetzen)
- WSL/Tailscale/SSH Konfig-Dokumentation
- Backup-Scripts selbst

### Sync
- Manuell oder per Script: Service Files + Cronjobs exportieren, committen, pushen
- Kein automatischer Push (aendert sich selten)

---

## Saeule 2: Verschluesselter USB-Stick (taeglich)

### Inhalt — Komplette Projekte + Credentials
- ~/family-hub/ (komplett)
- ~/family-hub-test/ (komplett)
- ~/business-lunch/ (komplett)
- ~/vega-memory/ (komplett)
- config.yaml + config-test.yaml (Credentials)
- ~/.ssh/ (SSH Keys)
- Cronjob-Export
- Systemd Service Files

### Zwei-Stick-Rotation
- Zwei USB-Sticks mit Labels: BACKUP-A und BACKUP-B
- Script erkennt automatisch welcher Stick steckt (nach Label)
- Backup-Dateiname: backup-YYYY-MM-DD-A.tar.gz.gpg bzw. -B
- Alte Backups bleiben drauf, aelteste werden bei Platzmangel geloescht (min. 1 behalten)

### Verschluesselung
- GPG symmetrisch (gpg --symmetric --cipher-algo AES256)
- Passphrase wird aus Datei gelesen (~/.backup-passphrase, chmod 600)
- Passphrase zusaetzlich im Passwort-Manager hinterlegen

### Timing
- Cronjob taeglich um 4:00
- Falls kein Stick steckt: Warnung ins Log, kein Fehler, Exit 0

### Logging
- Logfile: ~/backup.log
- Jeder Lauf: Timestamp, welcher Stick, Groesse, Erfolg/Fehler
- Bei Fehler: kein stiller Abbruch, Fehlermeldung ins Log

---

## Sicherheit
- Passphrase-Datei nur fuer brain31 lesbar (chmod 600)
- USB-Stick-Inhalt ist ohne Passphrase wertlos
- Repo minipc-setup ist privat
- Keine Credentials im Repo

---

## Offsite-Rotation
- Zwei Sticks: einer steckt im MiniPC, einer liegt extern (z.B. Buero)
- Regelmaessig tauschen fuer echtes Offsite-Backup
