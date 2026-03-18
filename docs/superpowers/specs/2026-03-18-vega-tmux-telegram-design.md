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
| `check-telegram.sh` | Firmenrechner `~/.claude/scripts/` | Helper-Script fuer Hook + on-demand |
| `@VEGA_KeepHerBusy_bot` | Telegram | Ausgangskanal + Inbox |
| Token-Datei | MiniPC `~/.vega-telegram-token` | chmod 600 |
| Offset-Datei | MiniPC `~/.vega-telegram-offset` | Automatisch erstellt |

## 1. `vega` Bash-Funktion

Shell-Funktion in `~/.bashrc` auf dem Firmenrechner.

### Verhalten

- `vega family-hub` → tmux-Session "family-hub" in `/home/mschlipp/family-hub/`, startet `claude`
- `vega crypto-monitor` → tmux-Session "crypto-monitor" in `/home/mschlipp/crypto-monitor/`
- `vega business-lunch` → tmux-Session "business-lunch" in `/home/mschlipp/business-lunch/`
- `vega minipc-setup` → tmux-Session "minipc-setup" in `/home/mschlipp/minipc-setup/`
- `vega` (ohne Argument) → allgemeine Session "vega" in `/home/mschlipp/`
- Unbekannter Name → Fehlermeldung: "Unbekanntes Projekt: <name>. Bekannt: family-hub, crypto-monitor, business-lunch, minipc-setup"
- Session existiert bereits → `tmux attach -t <name>`
- Session existiert nicht → `tmux new -s <name> -c <dir>` mit Shell (Claude wird per `send-keys` gestartet, damit die Shell ueberlebt wenn Claude beendet wird)

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

## 2. SessionStart-Hook

Claude Code Hook in `~/.claude/settings.json`. Wird bei jedem Claude-Code-Start ausgefuehrt, unabhaengig vom Repo.

### Verhalten

1. Ruft `getUpdates` auf dem VEGA-Bot auf (via SSH ueber MiniPC)
2. Filtert nur Nachrichten von Ward (chat_id 895154565)
3. Wenn neue Nachrichten vorhanden → zeigt sie als Kontext an (Text + Captions)
4. Setzt den Offset, damit Nachrichten nicht doppelt gelesen werden

### Hook-Konfiguration

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/scripts/check-telegram.sh",
            "timeout": 15,
            "statusMessage": "Checking Telegram inbox..."
          }
        ]
      }
    ]
  }
}
```

### `check-telegram.sh`

Separates Script statt Inline-Einzeiler fuer Wartbarkeit. Ablauf:

1. Liest Offset von MiniPC: `ssh brain31@minipc "cat ~/.vega-telegram-offset 2>/dev/null || echo 0"`
2. Ruft `getUpdates?offset=<offset>` auf (via SSH/MiniPC)
3. Filtert Nachrichten nach `chat_id == 895154565`
4. Fuer jede Nachricht: Text oder Caption extrahieren, Fotos/Dokumente als `[Bild]`/`[Datei: name]` markieren
5. Berechnet neuen Offset: `max(update_id) + 1`
6. Schreibt neuen Offset zurueck: `ssh brain31@minipc "echo <offset> > ~/.vega-telegram-offset"`
7. Gibt JSON mit `hookSpecificOutput.additionalContext` aus (oder nichts wenn keine Nachrichten)
8. Bei SSH/Curl-Fehler: gibt nichts aus (kein Fehler-Output, Hook schlaegt still fehl)

## 3. On-Demand "check Telegram"

Ward sagt im Terminal "check Telegram" (oder aehnlich). VEGA fuehrt denselben Check durch wie beim SessionStart, aber zusaetzlich mit Datei/Bild-Download.

### Text-Nachrichten

Gleich wie SessionStart: `getUpdates` aufrufen, Nachrichten anzeigen (inkl. Captions), Offset setzen.

### Bilder und Dateien

1. `getUpdates` liefert `photo` oder `document` Felder mit `file_id`
2. `getFile` aufrufen um `file_path` zu erhalten (via SSH/MiniPC)
3. Datei per SSH vom MiniPC herunterladen:
   ```bash
   ssh brain31@100.123.179.24 "TOKEN=\$(cat ~/.vega-telegram-token) && curl -s 'https://api.telegram.org/file/bot\${TOKEN}/<file_path>' -o /tmp/vega-<timestamp>-<original_filename>"
   scp brain31@100.123.179.24:/tmp/vega-<timestamp>-<original_filename> /tmp/vega-<timestamp>-<original_filename>
   ```
4. Dateinamen enthalten Timestamp um Kollisionen zu vermeiden
5. VEGA zeigt an: "Datei empfangen: /tmp/vega-<timestamp>-<original_filename>"

## 4. VEGA-Bot Ausgangskanal

Bereits funktionsfaehig. VEGA sendet Nachrichten an Ward ueber:

```bash
ssh brain31@100.123.179.24 'TOKEN=$(cat ~/.vega-telegram-token) && curl -s -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" -d "chat_id=895154565" -d "text=NACHRICHT"'
```

Anwendungsfaelle: Reminder, Status-Updates, Benachrichtigungen.

## Sicherheit

- **chat_id-Filter:** Nur Nachrichten von Ward (895154565) werden verarbeitet. Fremde Nachrichten werden ignoriert.
- **Token-Sicherheit:** Token liegt nur auf MiniPC (chmod 600). Wird per Shell-Variable expandiert, nicht als CLI-Argument sichtbar. Akzeptables Restrisiko fuer Single-User-MiniPC.
- **Bot-Privacy:** Bot sollte in BotFather "Group Privacy" aktiviert haben (Default). Bot nicht zu Gruppen hinzufuegen.

## Nicht im Scope

- Live-Chat ueber Telegram (vertagt, benoetigt Loesung fuer Push zum Firmenrechner)
- Mehrere Telegram-User (nur Ward, chat_id 895154565)
- Telegram-Bot-Commands (kein /start Handler etc.)

## Dateiaenderungen

1. **Firmenrechner `~/.bashrc`**: `vega` Funktion hinzufuegen
2. **Firmenrechner `~/.claude/scripts/check-telegram.sh`**: Neues Script
3. **Firmenrechner `~/.claude/settings.json`**: SessionStart-Hook hinzufuegen
4. **MiniPC `~/.vega-telegram-offset`**: Wird automatisch erstellt (Offset-Speicher)

## Abhaengigkeiten

- tmux auf Firmenrechner (vorhanden, v3.4)
- SSH Firmenrechner → MiniPC (vorhanden, passwortlos)
- Python 3 auf Firmenrechner (vorhanden)
- `@VEGA_KeepHerBusy_bot` Token auf MiniPC (vorhanden, `~/.vega-telegram-token`)
