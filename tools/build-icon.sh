#!/bin/zsh
# Rebuilds Resources/AppIcon.icns from the vector sources.
#
#   Resources/AppIcon.svg        1024 master (full detail, transparent margin)
#   Resources/AppIcon-small.svg  simplified art for the 16/32 px slots
#
# Needs Google Chrome (headless) or rsvg-convert to rasterise the SVG;
# sips and iconutil ship with macOS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MASTER_SVG="$ROOT/Resources/AppIcon.svg"
SMALL_SVG="$ROOT/Resources/AppIcon-small.svg"
ICNS="$ROOT/Resources/AppIcon.icns"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

render() { # $1 = svg, $2 = png
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w 1024 -h 1024 "$1" -o "$2"
  elif [[ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]]; then
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
      --headless=new --disable-gpu --hide-scrollbars \
      --default-background-color=00000000 --force-device-scale-factor=1 \
      --window-size=1024,1024 --virtual-time-budget=1500 \
      --screenshot="$2" "file://$1" >/dev/null 2>&1
  else
    echo "error: need rsvg-convert or Google Chrome to rasterise the SVG" >&2
    exit 1
  fi
}

render "$MASTER_SVG" "$WORK/master.png"
render "$SMALL_SVG" "$WORK/small.png"
cp "$WORK/master.png" "$ROOT/Resources/AppIcon-1024.png"

SET="$WORK/AppIcon.iconset"
mkdir -p "$SET"
# 16 / 32 px slots use the simplified artwork; 64 px and up use the master.
sips -z 16 16   "$WORK/small.png"  --out "$SET/icon_16x16.png" >/dev/null
sips -z 32 32   "$WORK/small.png"  --out "$SET/icon_16x16@2x.png" >/dev/null
sips -z 32 32   "$WORK/small.png"  --out "$SET/icon_32x32.png" >/dev/null
sips -z 64 64   "$WORK/master.png" --out "$SET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$WORK/master.png" --out "$SET/icon_128x128.png" >/dev/null
sips -z 256 256 "$WORK/master.png" --out "$SET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$WORK/master.png" --out "$SET/icon_256x256.png" >/dev/null
sips -z 512 512 "$WORK/master.png" --out "$SET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$WORK/master.png" --out "$SET/icon_512x512.png" >/dev/null
cp "$WORK/master.png" "$SET/icon_512x512@2x.png"

iconutil -c icns "$SET" -o "$ICNS"
echo "wrote $ICNS"
