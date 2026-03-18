# VEGA tmux + Telegram-Inbox Design

## Uebersicht

Zwei Features fuer bessere VEGA-Nutzung:
1. **tmux Session Management** — Dedizierte, persistente Claude-Code-Sessions pro Repo
2. **Telegram-Inbox** — Nachrichten (Text, Bilder, Dateien) ueber `@VEGA_KeepHerBusy_bot` hinterlassen, VEGA liest sie beim Start oder auf Abruf

## Komponenten

| Komponente | Ort | Typ |
|---|---|---|
| `vega` Bash-Funktion | Firmenrechner `~/.bashrc` | Shell-Funktion |
| SessionStart-Hook | Firmenrechner `~/.claude/settings.json` | Claude Code Hook |
| `@VEGA_KeepHerBusy_bot` | Telegram | Ausgangskanal + Inbox |
| Token-Datei | MiniPC `~/.vega-telegram-token` | chmod 600 |

## 1. `vega` Bash-Funktion

Shell-Funktion in `~/.bashrc` auf dem Firmenrechner.

### Verhalten

- `vega family-hub` → tmux-Session "family-hub" in `/home/mschlipp/family-hub/`, startet `claude`
- `vega crypto-monitor` → tmux-Session "crypto-monitor" in `/home/mschlipp/crypto-monitor/`
- `vega business-lunch` → tmux-Session "business-lunch" in `/home/mschlipp/business-lunch/`
- `vega minipc-setup` → tmux-Session "minipc-setup" in `/home/mschlipp/minipc-setup/`
- `vega` (ohne Argument) → allgemeine Session "vega" in `/home/mschlipp/`
- Session existiert bereits → `tmux attach -t <name>`
- Session existiert nicht → `tmux new -s <name> -c <dir> "claude"`

### Implementierung

```bash
vega() {
  local session="${1:-vega}"
  local dir
  case "$session" in
    family-hub)      dir="/home/mschlipp/family-hub" ;;
    crypto-monitor)  dir="/home/mschlipp/crypto-monitor" ;;
    business-lunch)  dir="/home/mschlipp/business-lunch" ;;
    minipc-setup)    dir="/home/mschlipp/minipc-setup" ;;
    *)               dir="/home/mschlipp" ;;
  esac

  if tmux has-session -t "$session" 2>/dev/null; then
    tmux attach -t "$session"
  else
    tmux new -s "$session" -c "$dir" "claude"
  fi
}
```

## 2. SessionStart-Hook

Claude Code Hook in `~/.claude/settings.json`. Wird bei jedem Claude-Code-Start ausgefuehrt, unabhaengig vom Repo.

### Verhalten

1. Ruft `getUpdates` auf dem VEGA-Bot auf (via SSH ueber MiniPC)
2. Wenn neue Nachrichten vorhanden → zeigt sie als Kontext an
3. Setzt den Offset, damit Nachrichten nicht doppelt gelesen werden

### Hook-Konfiguration

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "ssh brain31@100.123.179.24 'TOKEN=$(cat ~/.vega-telegram-token) && curl -s \"https://api.telegram.org/bot${TOKEN}/getUpdates\"' 2>/dev/null | python3 -c \"import sys,json; data=json.load(sys.stdin); msgs=[m['message'] for m in data.get('result',[]) if 'message' in m]; print(json.dumps({'hookSpecificOutput':{'hookEventName':'SessionStart','additionalContext':'Telegram-Inbox: ' + chr(10).join([m['from'].get('first_name','?')+': '+m.get('text','[Datei/Bild]') for m in msgs])}}) if msgs else '')\"",
            "timeout": 15,
            "statusMessage": "Checking Telegram inbox..."
          }
        ]
      }
    ]
  }
}
```

### Offset-Management

Nach dem Lesen wird der hoechste `update_id + 1` als Offset gespeichert, damit beim naechsten Check nur neue Nachrichten gelesen werden. Der Offset wird als Parameter an `getUpdates` uebergeben und auf dem MiniPC in `~/.vega-telegram-offset` gespeichert.

## 3. On-Demand "check Telegram"

Ward sagt im Terminal "check Telegram" (oder aehnlich). VEGA fuehrt dann denselben Check wie beim SessionStart durch, aber zusaetzlich mit Datei/Bild-Download.

### Text-Nachrichten

Gleich wie SessionStart: `getUpdates` aufrufen, Nachrichten anzeigen, Offset setzen.

### Bilder und Dateien

1. `getUpdates` liefert `photo` oder `document` Felder mit `file_id`
2. `getFile` aufrufen um `file_path` zu erhalten
3. Datei per SSH vom MiniPC herunterladen:
   ```bash
   ssh brain31@100.123.179.24 "TOKEN=\$(cat ~/.vega-telegram-token) && curl -s 'https://api.telegram.org/file/bot\${TOKEN}/<file_path>' -o /tmp/<filename>"
   scp brain31@100.123.179.24:/tmp/<filename> /tmp/<filename>
   ```
4. Datei ist lokal unter `/tmp/<filename>` verfuegbar
5. VEGA zeigt an: "Datei empfangen: /tmp/<filename>"

## 4. VEGA-Bot Ausgangskanal

Bereits funktionsfaehig. VEGA sendet Nachrichten an Ward ueber:

```bash
ssh brain31@100.123.179.24 'TOKEN=$(cat ~/.vega-telegram-token) && curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" -d "chat_id=895154565" -d "text=NACHRICHT"'
```

Anwendungsfaelle: Reminder, Status-Updates, Benachrichtigungen.

## Nicht im Scope

- Live-Chat ueber Telegram (vertagt, benoetigt Loesung fuer Push zum Firmenrechner)
- Mehrere Telegram-User (nur Ward, chat_id 895154565)
- Telegram-Bot-Commands (kein /start Handler etc.)

## Dateiaenderungen

1. **Firmenrechner `~/.bashrc`**: `vega` Funktion hinzufuegen
2. **Firmenrechner `~/.claude/settings.json`**: SessionStart-Hook hinzufuegen
3. **MiniPC `~/.vega-telegram-offset`**: Wird automatisch erstellt (Offset-Speicher)

## Abhaengigkeiten

- tmux auf Firmenrechner (vorhanden, v3.4)
- SSH Firmenrechner → MiniPC (vorhanden, passwortlos)
- Python 3 auf Firmenrechner (vorhanden)
- `@VEGA_KeepHerBusy_bot` Token auf MiniPC (vorhanden, `~/.vega-telegram-token`)
