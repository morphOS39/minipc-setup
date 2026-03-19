# MiniPC Restore Runbook

Komplette Anleitung zum Neuaufsetzen des MiniPC von Null.

**Voraussetzungen:**
- Neuer MiniPC (oder reparierter alter)
- USB-Stick mit verschluesseltem Backup (BACKUP-A oder BACKUP-B)
- Backup-Passphrase (aus Passwort-Manager)
- Internet-Verbindung (LAN-Kabel am Telekom-Router)
- Zweiter Rechner fuer SSH-Zugriff (optional, erleichtert Copy-Paste)

---

## Phase 1: BIOS & Windows

### 1.1 BIOS

- Taste: **Del** beim Booten
- Einstellen: **Restore on AC Power Loss → Power On**
  (MiniPC startet automatisch nach Stromausfall)

### 1.2 Windows installieren

- Windows 11 (oder was auf dem Geraet war) installieren
- Username: `brain31`

### 1.3 Windows AutoLogin

Registry (`regedit`):
```
HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon
```
- `AutoAdminLogon` = `1` (String)
- `DefaultUserName` = `brain31`
- `DefaultPassword` = `<Windows-Passwort>`

### 1.4 Windows Active Hours

Einstellungen → Windows Update → Erweiterte Optionen:
- Nutzungszeit: **06:00 - 02:00** (Updates/Restart nur 02:00-06:00)

---

## Phase 2: WSL einrichten

### 2.1 WSL + Ubuntu installieren

PowerShell (Admin):
```powershell
wsl --install -d Ubuntu-24.04
```
Neustart, dann Ubuntu-Setup: User `brain31`, Passwort setzen.

### 2.2 sudo ohne Passwort

```bash
sudo visudo
```
Zeile hinzufuegen:
```
brain31 ALL=(ALL) NOPASSWD: ALL
```

### 2.3 systemd aktivieren

Datei `/etc/wsl.conf` erstellen/bearbeiten:
```ini
[boot]
systemd=true

[user]
default=brain31
```
WSL neu starten (PowerShell: `wsl --shutdown`, dann `wsl`).

---

## Phase 3: Pakete installieren

### 3.1 System updaten

```bash
sudo apt update && sudo apt upgrade -y
```

### 3.2 Basis-Pakete

```bash
sudo apt install -y \
    openssh-server \
    python3-venv \
    git \
    gnupg \
    gh \
    graphviz \
    fail2ban \
    ufw \
    unattended-upgrades
```

Falls `installed-packages.txt` im Backup vorhanden, abgleichen:
```bash
# Im entpackten Backup:
cat installed-packages.txt
```

### 3.3 Tailscale installieren

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh
```
Im Browser einloggen (GitHub Account: morphOS39).

### 3.4 Caddy installieren

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update
sudo apt install caddy
```

---

## Phase 4: SSH-Zugang (von aussen via Tailscale)

### 4.1 SSH-Server in WSL

```bash
sudo systemctl enable ssh
sudo systemctl start ssh
```

### 4.2 Windows Portproxy

Die WSL-IP aendern sich bei jedem WSL-Neustart. Aktuelle IP ermitteln:
```bash
hostname -I | awk '{print $1}'
```

PowerShell (Admin):
```powershell
netsh interface portproxy add v4tov4 listenport=22 listenaddress=0.0.0.0 connectport=22 connectaddress=<WSL-IP>
```

### 4.3 Windows Firewall

PowerShell (Admin):
```powershell
New-NetFirewallRule -DisplayName "SSH WSL" -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow
```

### 4.4 Testen

Von einem anderen Rechner im Tailscale-Netz:
```bash
ssh brain31@100.123.179.24
```

**Hinweis:** Bei WSL-IP-Aenderung muss der Portproxy aktualisiert werden.

---

## Phase 5: Backup entschluesseln

### 5.1 USB-Stick mounten

USB-Stick einstecken. In WSL2 braucht man `usbipd-win`:

**Windows (PowerShell Admin):**
```powershell
# usbipd installieren (einmalig):
winget install usbipd

# USB-Geraete auflisten:
usbipd list

# Stick an WSL binden:
usbipd bind --busid <BUS-ID>
usbipd attach --wsl --busid <BUS-ID>
```

**WSL:**
```bash
# Device finden:
lsblk

# Mounten:
sudo mkdir -p /mnt/usb
sudo mount /dev/sdX1 /mnt/usb
ls /mnt/usb/
```

### 5.2 Backup entschluesseln

```bash
mkdir -p /tmp/restore

# Neuestes Backup finden:
ls -lt /mnt/usb/backup-*.tar.gz.gpg

# Entschluesseln + entpacken:
gpg --decrypt /mnt/usb/backup-YYYY-MM-DD-X.tar.gz.gpg | tar -xzf - -C /tmp/restore/

# Inhalt pruefen:
ls /tmp/restore/
```

Die Passphrase wird abgefragt → aus Passwort-Manager.

---

## Phase 6: Dateien zurueckkopieren

### 6.1 SSH-Keys

```bash
cp -a /tmp/restore/.ssh ~/
chmod 700 ~/.ssh
chmod 600 ~/.ssh/id_*
```

### 6.2 Git-Credentials & Dotfiles

```bash
cp /tmp/restore/dotfiles/.gitconfig ~/
cp /tmp/restore/dotfiles/.git-credentials ~/
cp /tmp/restore/dotfiles/.bashrc ~/
cp /tmp/restore/dotfiles/.profile ~/
cp /tmp/restore/dotfiles/.vega-telegram-token ~/
cp /tmp/restore/dotfiles/.vega-telegram-offset ~/
chmod 600 ~/.vega-telegram-token
chmod 600 ~/.git-credentials
```

### 6.3 Projekte

```bash
cp -a /tmp/restore/family-hub ~/
cp -a /tmp/restore/family-hub-test ~/
cp -a /tmp/restore/business-lunch ~/
cp -a /tmp/restore/crypto-monitor ~/
cp -a /tmp/restore/vega-memory ~/
cp -a /tmp/restore/minipc-setup ~/
```

### 6.4 Standalone Scripts

```bash
cp /tmp/restore/dotfiles/organize-board.sh ~/
chmod +x ~/organize-board.sh
```

---

## Phase 7: Python venvs rebuilden

```bash
cd ~/family-hub && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
cd ~/family-hub-test && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
cd ~/business-lunch && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
cd ~/crypto-monitor && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

---

## Phase 8: Services einrichten

### 8.1 Service Files kopieren

```bash
sudo cp /tmp/restore/service-files/*.service /etc/systemd/system/
sudo systemctl daemon-reload
```

### 8.2 Services aktivieren + starten

```bash
sudo systemctl enable --now family-hub
sudo systemctl enable --now family-hub-test
sudo systemctl enable --now crypto-monitor
```

### 8.3 Caddy Config

```bash
sudo cp /tmp/restore/caddy/Caddyfile /etc/caddy/Caddyfile
sudo systemctl enable --now caddy
```

### 8.4 Tailscale Funnel (business-lunch)

```bash
sudo tailscale serve --bg --https=443 http://127.0.0.1:8080
sudo tailscale funnel --bg 443
```

---

## Phase 9: Cronjobs & Automatisierung

### 9.1 Cronjobs wiederherstellen

```bash
crontab /tmp/restore/crontab-brain31.txt
crontab -l  # Pruefen
```

Erwartete Cronjobs:
```
0 4 * * * ~/minipc-setup/scripts/backup-usb.sh >> ~/backup.log 2>&1
0 5 * * * cd ~/business-lunch && .venv/bin/python3 scrape.py && .venv/bin/python3 generate.py >> /tmp/business-lunch.log 2>&1
0 3 * * * sudo /usr/bin/unattended-upgrade -v >> /var/log/unattended-upgrades-cron.log 2>&1
0 6 * * * ~/organize-board.sh
0 12 * * * cd ~/vega-memory && git pull --ff-only >> /tmp/vega-memory-pull.log 2>&1
```

### 9.2 WSL Autostart (Windows)

Windows Task Scheduler:
1. Task erstellen: "WSL Autostart"
2. Trigger: "At logon" (Benutzer: brain31)
3. Action: Programm starten
   - Programm: `wsl.exe`
   - Argumente: `-d Ubuntu`
4. Haken bei "Run whether user is logged on or not" ist NICHT noetig (AutoLogin)

### 9.3 Unattended Upgrades

```bash
sudo dpkg-reconfigure -plow unattended-upgrades
```

### 9.4 UFW Firewall

```bash
sudo ufw allow 22/tcp
sudo ufw enable
```

### 9.5 Fail2ban

```bash
sudo systemctl enable --now fail2ban
```

---

## Phase 10: VEGA einrichten

### 10.1 Claude Code installieren

Siehe https://docs.anthropic.com/en/docs/claude-code — aktuelle Installationsanleitung befolgen.

### 10.2 Memory-Symlink

```bash
# Pfad haengt von der Claude-Code-Version ab, Muster:
ln -s ~/vega-memory ~/.claude/projects/-home-brain31/memory
```

### 10.3 Backup-Passphrase

```bash
# Passphrase aus Passwort-Manager in Datei schreiben:
echo "PASSPHRASE_HIER" > ~/.backup-passphrase
chmod 600 ~/.backup-passphrase
```

---

## Phase 11: Verifizierung

Alle Punkte abarbeiten:

- [ ] SSH von extern: `ssh brain31@100.123.179.24`
- [ ] Tailscale: `tailscale status` zeigt Geraet
- [ ] family-hub laeuft: `sudo systemctl status family-hub`
- [ ] family-hub-test laeuft: `sudo systemctl status family-hub-test`
- [ ] crypto-monitor laeuft: `sudo systemctl status crypto-monitor`
- [ ] Caddy/Mittagstisch: `curl http://127.0.0.1:8080`
- [ ] Funnel erreichbar: `curl https://mittagstisch.tail18046a.ts.net`
- [ ] Cronjobs vorhanden: `crontab -l`
- [ ] Git push funktioniert: `cd ~/family-hub && git fetch`
- [ ] VEGA Memory-Sync: `cd ~/vega-memory && git pull`
- [ ] UFW aktiv: `sudo ufw status`
- [ ] Fail2ban aktiv: `sudo fail2ban-client status`
- [ ] Backup-Cronjob: Log pruefen nach naechstem 4:00-Lauf

---

## Netzwerk-Hinweise

- MiniPC haengt **direkt am Telekom-Router** (LAN-Kabel), NICHT hinter dem Deco
- NAS und Familien-Geraete sind **hinter dem Deco** (eigenes Subnetz)
- Diese Trennung ist gewollt! Keine Geraete ins gleiche Subnetz wie den MiniPC bringen
- Tailscale-IP: `100.123.179.24` (kann sich bei Neuinstallation aendern — im Tailscale Admin Panel pruefen)
