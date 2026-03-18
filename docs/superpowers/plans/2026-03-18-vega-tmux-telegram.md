# VEGA tmux + Telegram-Inbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persistente tmux-Sessions pro Repo mit `vega` Alias + Telegram-Inbox (SessionStart-Hook und on-demand Check mit Datei-Download).

**Architecture:** Bash-Funktion `vega` verwaltet tmux-Sessions. `check-telegram.sh` Script kommuniziert via SSH mit dem MiniPC um Telegram-Nachrichten abzurufen. SessionStart-Hook ruft das Script automatisch auf. On-demand "check Telegram" laedt zusaetzlich Bilder/Dateien herunter.

**Tech Stack:** Bash, tmux, Python 3 (inline), SSH, Telegram Bot API, Claude Code Hooks

**Spec:** `docs/superpowers/specs/2026-03-18-vega-tmux-telegram-design.md`

---

### Task 0: Voraussetzungen pruefen

- [ ] **Step 1: tmux installiert?**

```bash
tmux -V
```

Expected: `tmux 3.4` (oder hoeher)

- [ ] **Step 2: SSH zum MiniPC funktioniert?**

```bash
ssh brain31@100.123.179.24 "echo OK"
```

Expected: `OK`

- [ ] **Step 3: Token-Datei auf MiniPC vorhanden?**

```bash
ssh brain31@100.123.179.24 "test -f ~/.vega-telegram-token && stat -c '%a' ~/.vega-telegram-token"
```

Expected: `600`

- [ ] **Step 4: Bot erreichbar?**

```bash
ssh brain31@100.123.179.24 'TOKEN=$(cat ~/.vega-telegram-token) && curl -s "https://api.telegram.org/bot${TOKEN}/getMe"' | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['result']['username'])"
```

Expected: `VEGA_KeepHerBusy_bot`

- [ ] **Step 5: BotFather Group Privacy pruefen**

In Telegram: @BotFather → `/mybots` → @VEGA_KeepHerBusy_bot → Bot Settings → Group Privacy → sollte "enabled" sein (Default). Falls nicht, aktivieren.

---

### Task 1: `vega` Bash-Funktion

**Files:**
- Modify: `~/.bashrc` (append)
- Create: `/home/mschlipp/minipc-setup/scripts/vega-function.sh` (Backup im Repo)

- [ ] **Step 1: Add `vega` function to .bashrc**

Append to `~/.bashrc`:

```bash
# VEGA tmux session manager
vega() {
  local session="${1:-vega}"
  local dir
  case "$session" in
    family-hub)      dir="/home/mschlipp/family-hub" ;;
    crypto-monitor)  dir="/home/mschlipp/crypto-monitor" ;;
    business-lunch)  dir="/home/mschlipp/business-lunch" ;;
    minipc-setup)    dir="/home/mschlipp/minipc-setup" ;;
    vega)            dir="/home/mschlipp" ;;
    *)
      echo "Unbekanntes Projekt: $session"
      echo "Bekannt: family-hub, crypto-monitor, business-lunch, minipc-setup"
      return 1
      ;;
  esac

  if tmux has-session -t "$session" 2>/dev/null; then
    tmux attach -t "$session"
  else
    tmux new -s "$session" -c "$dir" \; send-keys "claude" Enter
  fi
}
```

- [ ] **Step 2: Copy function to repo for backup**

```bash
mkdir -p /home/mschlipp/minipc-setup/scripts
# Extract vega function from .bashrc into standalone file
cat > /home/mschlipp/minipc-setup/scripts/vega-function.sh << 'ENDOFFILE'
# VEGA tmux session manager
# Source this file from ~/.bashrc or copy the function there
vega() {
  local session="${1:-vega}"
  local dir
  case "$session" in
    family-hub)      dir="/home/mschlipp/family-hub" ;;
    crypto-monitor)  dir="/home/mschlipp/crypto-monitor" ;;
    business-lunch)  dir="/home/mschlipp/business-lunch" ;;
    minipc-setup)    dir="/home/mschlipp/minipc-setup" ;;
    vega)            dir="/home/mschlipp" ;;
    *)
      echo "Unbekanntes Projekt: $session"
      echo "Bekannt: family-hub, crypto-monitor, business-lunch, minipc-setup"
      return 1
      ;;
  esac

  if tmux has-session -t "$session" 2>/dev/null; then
    tmux attach -t "$session"
  else
    tmux new -s "$session" -c "$dir" \; send-keys "claude" Enter
  fi
}
ENDOFFILE
```

- [ ] **Step 3: Reload and test known project**

```bash
source ~/.bashrc
vega family-hub
```

Expected: tmux-Session "family-hub" startet in `/home/mschlipp/family-hub/`, Claude wird gestartet. Detach mit `Ctrl-b d`.

- [ ] **Step 4: Test reattach**

```bash
vega family-hub
```

Expected: Verbindet sich zur bestehenden Session (Claude laeuft noch). Detach mit `Ctrl-b d`.

- [ ] **Step 5: Test unknown project**

```bash
vega foobar
```

Expected: Output `Unbekanntes Projekt: foobar` + bekannte Projekte. Exit code 1.

- [ ] **Step 6: Test Claude exit survives session**

```bash
vega family-hub
```

In der Session: `/exit` um Claude zu beenden.
Expected: Shell bleibt offen (Session stirbt nicht). `claude` eingeben um neu zu starten.

- [ ] **Step 7: Cleanup test session**

```bash
tmux kill-session -t family-hub
```

- [ ] **Step 8: Commit**

```bash
cd /home/mschlipp/minipc-setup
git add scripts/vega-function.sh
git commit -m "feat: vega tmux session manager function"
```

---

### Task 2: `check-telegram.sh` Script

**Files:**
- Create: `/home/mschlipp/.claude/scripts/check-telegram.sh`
- Create: `/home/mschlipp/minipc-setup/scripts/check-telegram.sh` (Backup)

- [ ] **Step 1: Create scripts directory**

```bash
mkdir -p /home/mschlipp/.claude/scripts
```

- [ ] **Step 2: Write check-telegram.sh**

Create `/home/mschlipp/.claude/scripts/check-telegram.sh`:

```bash
#!/bin/bash
# Check VEGA Telegram bot for new messages from Ward
# Used by SessionStart hook and on-demand "check Telegram"
# Communicates via SSH with MiniPC where the bot token lives

MINIPC="brain31@100.123.179.24"
WARD_CHAT_ID=895154565

# Read current offset from MiniPC (0 if not set)
OFFSET=$(ssh -o ConnectTimeout=5 "$MINIPC" "cat ~/.vega-telegram-offset 2>/dev/null || echo 0" 2>/dev/null) || exit 0

# Fetch updates from Telegram via MiniPC
UPDATES=$(ssh -o ConnectTimeout=5 "$MINIPC" "TOKEN=\$(cat ~/.vega-telegram-token) && curl -s \"https://api.telegram.org/bot\${TOKEN}/getUpdates?offset=${OFFSET}&timeout=1\"" 2>/dev/null) || exit 0

# Parse with Python: filter by chat_id, extract text/captions, update offset
echo "$UPDATES" | python3 -c "
import json, sys

try:
    data = json.load(sys.stdin)
except:
    sys.exit(0)

results = data.get('result', [])
if not results:
    sys.exit(0)

WARD = $WARD_CHAT_ID
msgs = []
max_id = 0
for r in results:
    uid = r.get('update_id', 0)
    if uid > max_id:
        max_id = uid
    m = r.get('message', {})
    if m.get('chat', {}).get('id') != WARD:
        continue
    text = m.get('text', '')
    caption = m.get('caption', '')
    has_photo = bool(m.get('photo'))
    has_doc = m.get('document', {}).get('file_name', '')

    if text:
        msgs.append(text)
    elif caption and has_photo:
        msgs.append(f'[Bild] {caption}')
    elif has_photo:
        msgs.append('[Bild]')
    elif caption and has_doc:
        msgs.append(f'[Datei: {has_doc}] {caption}')
    elif has_doc:
        msgs.append(f'[Datei: {has_doc}]')
    else:
        msgs.append('[Nachricht]')

if not msgs:
    print(f'OFFSET:{max_id + 1}')
    sys.exit(0)

inbox = 'Telegram-Inbox von Ward:\n' + '\n'.join(f'  - {m}' for m in msgs)
output = {
    'hookSpecificOutput': {
        'hookEventName': 'SessionStart',
        'additionalContext': inbox
    }
}
print(json.dumps(output))
print(f'OFFSET:{max_id + 1}')
" 2>/dev/null | {
    # Separate JSON output from OFFSET line
    json_out=""
    new_offset=""
    while IFS= read -r line; do
        if [[ "$line" == OFFSET:* ]]; then
            new_offset="${line#OFFSET:}"
        elif [[ -n "$line" ]]; then
            json_out="$line"
        fi
    done

    # Update offset on MiniPC
    if [[ -n "$new_offset" ]]; then
        ssh -o ConnectTimeout=5 "$MINIPC" "echo $new_offset > ~/.vega-telegram-offset" 2>/dev/null || true
    fi

    # Output JSON for hook
    if [[ -n "$json_out" ]]; then
        echo "$json_out"
    fi
}
```

- [ ] **Step 3: Make executable**

```bash
chmod +x /home/mschlipp/.claude/scripts/check-telegram.sh
```

- [ ] **Step 4: Set offset to current max (clean start)**

```bash
ssh brain31@100.123.179.24 'TOKEN=$(cat ~/.vega-telegram-token) && curl -s "https://api.telegram.org/bot${TOKEN}/getUpdates"' | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('result',[]); print(max(x['update_id'] for x in r)+1 if r else 0)"
```

Use the output number:

```bash
ssh brain31@100.123.179.24 "echo <NUMBER> > ~/.vega-telegram-offset"
```

- [ ] **Step 5: Test with no messages**

```bash
/home/mschlipp/.claude/scripts/check-telegram.sh
```

Expected: No output (no new messages).

- [ ] **Step 6: Test with a text message**

1. Send "Test Nachricht von Ward" to `@VEGA_KeepHerBusy_bot` via Telegram
2. Run: `/home/mschlipp/.claude/scripts/check-telegram.sh`

Expected: JSON output containing `"additionalContext": "Telegram-Inbox von Ward:\n  - Test Nachricht von Ward"`

- [ ] **Step 7: Test offset works (no duplicate)**

Run again: `/home/mschlipp/.claude/scripts/check-telegram.sh`

Expected: No output (message already consumed by offset).

- [ ] **Step 8: Test with MiniPC offline (graceful failure)**

```bash
MINIPC_BAK="brain31@100.123.179.24"
# Override MINIPC in a subshell with unreachable IP
(export MINIPC="brain31@192.168.99.99"; /home/mschlipp/.claude/scripts/check-telegram.sh); echo "Exit: $?"
```

Expected: No output, exit 0 (silent failure). Note: This test only works if the script reads MINIPC from env. If it doesn't, skip this test — the `|| exit 0` guards in the script handle this.

- [ ] **Step 9: Copy script to repo for backup + commit**

```bash
cp /home/mschlipp/.claude/scripts/check-telegram.sh /home/mschlipp/minipc-setup/scripts/
cd /home/mschlipp/minipc-setup
git add scripts/check-telegram.sh
git commit -m "feat: check-telegram.sh for VEGA inbox"
```

---

### Task 3: SessionStart-Hook

**Files:**
- Modify: `/home/mschlipp/.claude/settings.json`

- [ ] **Step 1: Read current settings.json**

```bash
cat /home/mschlipp/.claude/settings.json
```

Verify structure before modifying.

- [ ] **Step 2: Add SessionStart hook**

Add `hooks` key to existing settings.json (merge with existing content, don't replace). Use absolute path (tilde may not expand in hooks):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/mschlipp/.claude/scripts/check-telegram.sh",
            "timeout": 15,
            "statusMessage": "Checking Telegram inbox..."
          }
        ]
      }
    ]
  }
}
```

Use Edit tool to add this after the `enabledPlugins` block, before the final `}`.

- [ ] **Step 3: Validate JSON syntax**

```bash
jq -e '.hooks.SessionStart[0].hooks[0].command' /home/mschlipp/.claude/settings.json
```

Expected: Prints `/home/mschlipp/.claude/scripts/check-telegram.sh`, exit 0.

- [ ] **Step 4: Test hook fires**

Start a new Claude Code session (or restart current). Watch for "Checking Telegram inbox..." in the spinner.

If there are unread Telegram messages, they should appear as context.

- [ ] **Step 5: Commit hook config backup to repo**

```bash
cd /home/mschlipp/minipc-setup
# Save just the hook config snippet for documentation
cat > /home/mschlipp/minipc-setup/scripts/sessionstart-hook.json << 'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/home/mschlipp/.claude/scripts/check-telegram.sh",
            "timeout": 15,
            "statusMessage": "Checking Telegram inbox..."
          }
        ]
      }
    ]
  }
}
EOF
git add scripts/sessionstart-hook.json
git commit -m "docs: SessionStart hook config for Telegram inbox"
```

---

### Task 4: On-Demand Datei/Bild-Download

Wenn VEGA on-demand "check Telegram" ausfuehrt und Bilder/Dateien findet, werden diese heruntergeladen. Dies passiert manuell durch VEGA (nicht im Hook), da der Hook nur Text-Zusammenfassungen liefert.

**Files:**
- Keine neuen Dateien. VEGA fuehrt die Bash-Befehle direkt aus.

- [ ] **Step 1: Dokumentiere den Download-Ablauf**

Wenn `check-telegram.sh` `[Bild]` oder `[Datei: ...]` meldet, fuehrt VEGA folgende Schritte aus:

1. `getUpdates` nochmal aufrufen (vor Offset-Update) um `file_id` zu extrahieren:

```bash
ssh brain31@100.123.179.24 'TOKEN=$(cat ~/.vega-telegram-token) && curl -s "https://api.telegram.org/bot${TOKEN}/getUpdates?offset=<OFFSET>"' | python3 -c "
import json, sys
data = json.load(sys.stdin)
for r in data.get('result', []):
    m = r.get('message', {})
    if m.get('photo'):
        fid = m['photo'][-1]['file_id']  # largest photo
        print(f'PHOTO:{fid}')
    if m.get('document'):
        fid = m['document']['file_id']
        fname = m['document'].get('file_name', 'unknown')
        print(f'DOC:{fid}:{fname}')
"
```

2. Fuer jede `file_id`, Datei herunterladen:

```bash
# Get file path
FILE_PATH=$(ssh brain31@100.123.179.24 "TOKEN=\$(cat ~/.vega-telegram-token) && curl -s \"https://api.telegram.org/bot\${TOKEN}/getFile?file_id=<FILE_ID>\"" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['file_path'])")

# Download to MiniPC, then SCP to local
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOCAL_NAME="/tmp/vega-${TIMESTAMP}-<original_filename>"
ssh brain31@100.123.179.24 "TOKEN=\$(cat ~/.vega-telegram-token) && curl -s \"https://api.telegram.org/file/bot\${TOKEN}/${FILE_PATH}\" -o /tmp/vega-download"
scp brain31@100.123.179.24:/tmp/vega-download "$LOCAL_NAME"
```

3. Datei ist lokal verfuegbar unter `/tmp/vega-<timestamp>-<filename>`.

- [ ] **Step 2: Test mit Bild**

1. Sende ein Bild an `@VEGA_KeepHerBusy_bot`
2. Sage in Claude: "check Telegram"
3. VEGA meldet `[Bild]` und laedt es herunter
4. Pruefen: `file /tmp/vega-*` zeigt das Bild

- [ ] **Step 3: Test mit Dokument**

1. Sende ein PDF an `@VEGA_KeepHerBusy_bot`
2. Sage in Claude: "check Telegram"
3. VEGA meldet `[Datei: name.pdf]` und laedt es herunter
4. Pruefen: `file /tmp/vega-*` zeigt das PDF

---

### Task 5: End-to-End Test

- [ ] **Step 1: Reset offset to current max**

```bash
ssh brain31@100.123.179.24 'TOKEN=$(cat ~/.vega-telegram-token) && curl -s "https://api.telegram.org/bot${TOKEN}/getUpdates"' | python3 -c "import sys,json; d=json.load(sys.stdin); r=d.get('result',[]); print(max(x['update_id'] for x in r)+1 if r else 0)"
ssh brain31@100.123.179.24 "echo <NUMBER> > ~/.vega-telegram-offset"
```

Kill any test tmux sessions:

```bash
tmux kill-server 2>/dev/null || true
```

- [ ] **Step 2: Send test message via Telegram**

Send "Hallo VEGA, bitte family-hub Issue #37 anschauen" to `@VEGA_KeepHerBusy_bot`.

- [ ] **Step 3: Start session via vega alias**

```bash
source ~/.bashrc
vega family-hub
```

Expected:
1. tmux-Session "family-hub" startet
2. Claude startet
3. SessionStart-Hook feuert: "Checking Telegram inbox..."
4. Claude sieht Kontext: "Telegram-Inbox von Ward: - Hallo VEGA, bitte family-hub Issue #37 anschauen"

- [ ] **Step 4: Test outgoing message**

In Claude session, ask VEGA to send a Telegram message:

```bash
ssh brain31@100.123.179.24 'TOKEN=$(cat ~/.vega-telegram-token) && curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" -d "chat_id=895154565" -d "text=End-to-End Test erfolgreich!"'
```

Expected: Message arrives in Telegram from @VEGA_KeepHerBusy_bot.

- [ ] **Step 5: Test on-demand check with image**

1. Send a photo with caption "Testbild" to `@VEGA_KeepHerBusy_bot`
2. In Claude session, type: "check Telegram"
3. VEGA runs check-telegram.sh, sees `[Bild] Testbild`
4. VEGA downloads the image and shows local path

- [ ] **Step 6: Final commit + push**

```bash
cd /home/mschlipp/minipc-setup
git add -A
git commit -m "feat: VEGA tmux + Telegram-Inbox complete"
git push
```
