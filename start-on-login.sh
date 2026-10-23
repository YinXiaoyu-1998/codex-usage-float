#!/bin/zsh
set -euo pipefail

APP_PATH="/Applications/CodexUsageFloat.app"
APP_BIN="$APP_PATH/Contents/MacOS/CodexUsageFloat"
PLIST="$HOME/Library/LaunchAgents/local.codex.usagefloat.plist"
LOG_DIR="$HOME/Library/Logs/CodexUsageFloat"

if [[ ! -x "$APP_BIN" ]]; then
  print -u2 "Install CodexUsageFloat.app in /Applications before enabling start on login."
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents" "$LOG_DIR"
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
    <string>-c</string>
    <string>sleep 20; /usr/bin/pgrep -fx "\$1" >/dev/null || /usr/bin/open -n "\$2"</string>
    <string>codex-usage-login</string>
    <string>$APP_BIN</string>
    <string>$APP_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/launchagent.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/launchagent.err.log</string>
</dict>
</plist>
PLIST

/bin/launchctl bootout "gui/$(id -u)" "$PLIST" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$(id -u)" "$PLIST"
/bin/launchctl enable "gui/$(id -u)/local.codex.usagefloat"

echo "Installed LaunchAgent: $PLIST"
