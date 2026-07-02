#!/usr/bin/env bash
set -euo pipefail
# Generate (and validate) the weekly launchd agent for graphify-sync-all.sh.
# Does not load it — prints the launchctl command. 2026.
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC="$SELF_DIR/graphify-sync-all.sh"
LABEL="com.${USER}.graphify-sync"
PLIST_DIR="${GRAPHIFY_PLIST_DIR:-$HOME/Library/LaunchAgents}"
PLIST="$PLIST_DIR/$LABEL.plist"
LOGDIR="$HOME/.claude/logs"
mkdir -p "$PLIST_DIR" "$LOGDIR"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$SYNC</string></array>
  <key>StartCalendarInterval</key>
  <dict><key>Weekday</key><integer>0</integer><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>
  <key>RunAtLoad</key><false/>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string></dict>
  <key>StandardOutPath</key><string>$LOGDIR/graphify-sync.out</string>
  <key>StandardErrorPath</key><string>$LOGDIR/graphify-sync.err</string>
</dict>
</plist>
EOF
if command -v plutil >/dev/null 2>&1; then plutil -lint "$PLIST" >/dev/null; fi
echo "wrote $PLIST"
echo "load with: launchctl load -w \"$PLIST\""
