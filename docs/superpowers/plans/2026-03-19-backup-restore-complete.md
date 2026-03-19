# MiniPC Backup & Restore - Komplettierung

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** MiniPC-Backup vervollstaendigen und Restore-Runbook schreiben, damit ein toter MiniPC from scratch komplett neu aufgesetzt werden kann.

**Architecture:** Zwei-Saeulen-Backup (GitHub + verschluesselter USB-Stick). Restore-Runbook als Markdown-Anleitung im Repo.

**Tech Stack:** Bash, GPG, systemd, WSL2

---

### Task 1: backup-usb.sh updaten

**Files:**
- Modify: `scripts/backup-usb.sh`

- [ ] **Step 1: BACKUP_SOURCES erweitern**

Hinzufuegen:
- `$HOME/crypto-monitor`
- `$HOME/organize-board.sh`

- [ ] **Step 2: Einzelne Credential-/Config-Dateien sichern**

Neues Array BACKUP_FILES fuer einzelne Dateien:
- `$HOME/.vega-telegram-token`
- `$HOME/.vega-telegram-offset`
- `$HOME/.gitconfig`
- `$HOME/.git-credentials`
- `$HOME/.bashrc`
- `$HOME/.profile`

- [ ] **Step 3: Service Files dynamisch statt hardcoded**

Alle custom Service Files aus /etc/systemd/system/ sichern (family-hub, family-hub-test, crypto-monitor), statt hardcoded Liste.

- [ ] **Step 4: Caddy-Config sichern**

`/etc/caddy/Caddyfile` ins Backup aufnehmen.

- [ ] **Step 5: Paketliste exportieren**

`apt-mark showmanual` ins Backup-Staging schreiben als `installed-packages.txt`.

- [ ] **Step 6: .venv-Verzeichnisse ausschliessen**

Beim Kopieren der Repos `.venv/` Verzeichnisse ueberspringen (spart ~470MB).

- [ ] **Step 7: Commit**

### Task 2: export-config.sh updaten

**Files:**
- Modify: `scripts/export-config.sh`

- [ ] **Step 1: crypto-monitor Service File hinzufuegen**
- [ ] **Step 2: Commit**

### Task 3: Restore-Runbook schreiben

**Files:**
- Create: `docs/restore-runbook.md`

- [ ] **Step 1: Runbook schreiben**

Komplette Schritt-fuer-Schritt-Anleitung:
1. BIOS (Restore on AC Power Loss)
2. Windows installieren + AutoLogin + Active Hours
3. WSL + Ubuntu installieren
4. User brain31 + sudo NOPASSWD
5. Pakete installieren (aus installed-packages.txt)
6. SSH-Server + Windows Portproxy + Firewall
7. Tailscale installieren + einloggen + Funnel
8. Backup entschluesseln + Dateien zurueckkopieren
9. Git Repos: Remotes pruefen, venvs rebuilden
10. Service Files kopieren + aktivieren
11. Cronjobs wiederherstellen
12. Caddy Config + Service
13. VEGA einrichten (Claude Code, Memory-Symlink)
14. Verifizierungs-Checkliste

- [ ] **Step 2: Commit**

### Task 4: README.md updaten

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README aktualisieren** (neue Backup-Quellen, Verweis auf Runbook)
- [ ] **Step 2: Commit**

### Task 5: Deploy auf MiniPC

- [ ] **Step 1: Repo auf MiniPC klonen**
- [ ] **Step 2: setup-backup.sh ausfuehren** (Passphrase generieren, Cronjob einrichten)
- [ ] **Step 3: Passphrase im Passwort-Manager sichern** (Ward manuell)
- [ ] **Step 4: USB-Stick-Thematik klaeren** (usbipd-win fuer WSL2)
