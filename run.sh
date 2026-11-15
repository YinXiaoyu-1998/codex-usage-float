#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$ROOT/CodexUsageFloat"
APP_CONTENTS="$ROOT/CodexUsageFloat.app/Contents"
APP_BIN="$ROOT/CodexUsageFloat.app/Contents/MacOS/CodexUsageFloat"
APP_RESOURCES="$ROOT/CodexUsageFloat.app/Contents/Resources"

# Pin the deployment target: newer toolchains default to the SDK's macOS version
# (e.g. macosx28.0), and LaunchServices refuses to `open` an app whose Mach-O
# minimum OS is newer than the running system. Match Info.plist's 13.0.
# Override with CUF_DEPLOYMENT_TARGET=<arch>-apple-macos<version> to target
# another macOS, and lower LSMinimumSystemVersion in Info.plist to match.
DEPLOYMENT_TARGET="${CUF_DEPLOYMENT_TARGET:-$(uname -m)-apple-macos13.0}"
HOST_MACOS="$(sw_vers -productVersion)"

# Returns success when $1 (host version) is at least $2 (required version).
version_at_least() {
  local -a host=("${(@s:.:)1}") required=("${(@s:.:)2}")
  integer i
  for i in 1 2 3; do
    local -i h=${host[i]:-0} r=${required[i]:-0}
    (( h > r )) && return 0
    (( h < r )) && return 1
  done
  return 0
}

echo "Building for $DEPLOYMENT_TARGET (host macOS $HOST_MACOS)"

swiftc -target "$DEPLOYMENT_TARGET" \
  -framework Cocoa -framework UserNotifications -framework ApplicationServices \
  "$ROOT/UsageModels.swift" "$ROOT/RestartPolicy.swift" "$ROOT/FollowOverlayController.swift" \
  "$ROOT/CodexWindowTracker.swift" "$ROOT/FollowOverlayWindow.swift" \
  "$ROOT/FollowAccessibilityHelp.swift" "$ROOT/CodexUsageFloat.swift" -o "$BIN"

# A binary that demands a newer macOS builds fine and runs when executed
# directly, but LaunchServices then refuses `open` with error -10825. Fail here
# instead of shipping an app that cannot be launched by clicking it.
BUILT_MINOS="$(otool -l "$BIN" | awk '/LC_BUILD_VERSION/{found=1} found && /minos/{print $2; exit}')"
if [[ -z "$BUILT_MINOS" ]]; then
  print -u2 "Cannot read LC_BUILD_VERSION from $BIN"
  exit 1
fi
if ! version_at_least "$HOST_MACOS" "$BUILT_MINOS"; then
  print -u2 "Built with minos $BUILT_MINOS, but this Mac runs macOS $HOST_MACOS."
  print -u2 "LaunchServices will refuse to open it (error -10825)."
  print -u2 "Lower the target, e.g. CUF_DEPLOYMENT_TARGET=arm64-apple-macos13.0 ./run.sh --build-only"
  exit 1
fi
echo "Binary minimum macOS: $BUILT_MINOS (compatible with this Mac)"
mkdir -p "$ROOT/CodexUsageFloat.app/Contents/MacOS"
mkdir -p "$APP_RESOURCES"
cp "$BIN" "$APP_BIN"
cp "$ROOT/Info.plist" "$APP_CONTENTS/Info.plist"
cp "$ROOT/Resources/codex-logo.png" "$APP_RESOURCES/codex-logo.png"
cp "$ROOT/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
cp "$ROOT/Resources/codex_logo.svg" "$APP_RESOURCES/codex_logo.svg"
cp "$ROOT/Resources/openai-codex-seeklogo.svg" "$APP_RESOURCES/openai-codex-seeklogo.svg"

# Replacing resources invalidates the linker's ad-hoc signature; macOS then SIGKILLs
# the app on launch ("cs_invalid_page"). Re-sign the bundle after every build.
codesign --force --sign - "$ROOT/CodexUsageFloat.app"

if [[ "${1:-}" != "--build-only" ]]; then
  open -n "$ROOT/CodexUsageFloat.app"
fi
