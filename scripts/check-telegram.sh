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
