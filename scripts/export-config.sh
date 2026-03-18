#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SERVICE_DIR="$REPO_DIR/service-files"
CRON_DIR="$REPO_DIR/cronjobs"

mkdir -p "$SERVICE_DIR" "$CRON_DIR"

# Systemd Service Files exportieren
echo "=== Exporting service files ==="
for svc in family-hub family-hub-test; do
    SVC_FILE="/etc/systemd/system/${svc}.service"
    if [ -f "$SVC_FILE" ]; then
        cp "$SVC_FILE" "$SERVICE_DIR/"
        echo "  Copied $SVC_FILE"
    else
        echo "  WARNING: $SVC_FILE not found"
    fi
done

# Cronjobs exportieren
echo "=== Exporting cronjobs ==="
crontab -l > "$CRON_DIR/crontab-brain31.txt" 2>/dev/null || echo "  No crontab found"
echo "  Saved to $CRON_DIR/crontab-brain31.txt"

# Diff anzeigen
echo ""
echo "=== Changes ==="
cd "$REPO_DIR"
git diff --stat 2>/dev/null || true
echo ""
echo "Review changes, then: git add -A && git commit -m 'update: config export' && git push"
