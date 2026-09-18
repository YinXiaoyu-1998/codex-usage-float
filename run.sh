#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$ROOT/CodexUsageFloat"
APP_CONTENTS="$ROOT/CodexUsageFloat.app/Contents"
APP_BIN="$ROOT/CodexUsageFloat.app/Contents/MacOS/CodexUsageFloat"
APP_RESOURCES="$ROOT/CodexUsageFloat.app/Contents/Resources"

swiftc -framework Cocoa "$ROOT/CodexUsageFloat.swift" -o "$BIN"
mkdir -p "$ROOT/CodexUsageFloat.app/Contents/MacOS"
mkdir -p "$APP_RESOURCES"
cp "$BIN" "$APP_BIN"
cp "$ROOT/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$ROOT/Resources/codex-logo.png" "$APP_RESOURCES/codex-logo.png"
cp "$ROOT/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
cp "$ROOT/Resources/codex_logo.svg" "$APP_RESOURCES/codex_logo.svg"
cp "$ROOT/Resources/openai-codex-seeklogo.svg" "$APP_RESOURCES/openai-codex-seeklogo.svg"
open -n "$ROOT/CodexUsageFloat.app"
