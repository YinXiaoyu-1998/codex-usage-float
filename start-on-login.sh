#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$ROOT/CodexUsageFloat.app"
APP_BIN="$APP_PATH/Contents/MacOS/CodexUsageFloat"
PLIST="$HOME/Library/LaunchAgents/local.codex.usagefloat.plist"

if [[ ! -x "$APP_BIN" ]]; then
  "$ROOT/run.sh"
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>local.codex.usagefloat</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>sleep 20; /usr/bin/pgrep -f '$APP_BIN' >/dev/null || /usr/bin/open '$APP_PATH'</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$ROOT/launchagent.out.log</string>
  <key>StandardErrorPath</key>
  <string>$ROOT/launchagent.err.log</string>
</dict>
</plist>
PLIST

/bin/launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$(id -u)" "$PLIST"
/bin/launchctl enable "gui/$(id -u)/local.codex.usagefloat"

echo "Installed LaunchAgent: $PLIST"
