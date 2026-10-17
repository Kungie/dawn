#!/bin/bash
# Builds build/Dawn.app from source. Needs macOS 13+ and Swift 5.9+ (Xcode or the Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Dawn"

APP=build/Dawn.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Fonts"
cp "$BIN" "$APP/Contents/MacOS/Dawn"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Fonts/*.woff2 Resources/Fonts/OFL-*.txt "$APP/Contents/Resources/Fonts/"

# App icon, drawn by Dawn itself.
ICONSET=build/Dawn.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
"$BIN" icon build/icon-1024.png
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Dawn.icns"

# Ad-hoc signature, so macOS runs it locally. Not notarized.
xattr -cr "$APP"
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"
