#!/bin/bash
# Builds build/Dawn.app from source. Needs macOS 13+ and Swift 5.9+ (Xcode or the Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."

# Universal binary: Apple silicon and Intel, macOS 13 and later.
mkdir -p build/bin
for arch in arm64 x86_64; do
  swift build -c release --triple "$arch-apple-macosx13.0"
  cp "$(swift build -c release --triple "$arch-apple-macosx13.0" --show-bin-path)/Dawn" "build/bin/Dawn-$arch"
done
lipo -create build/bin/Dawn-arm64 build/bin/Dawn-x86_64 -output build/bin/Dawn
BIN=build/bin/Dawn

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
# Installer: a disk image with the drag-to-Applications window. Needs dmgbuild (pip install dmgbuild);
# without it the zip below is still built.
DMGBUILD="${DMGBUILD:-$(command -v dmgbuild || true)}"
if [ -n "$DMGBUILD" ]; then
  "$BIN" dmg-background build
  rm -f build/Dawn.dmg
  "$DMGBUILD" -s scripts/dmg-settings.py -D app="$APP" -D bg=build/dmg-background.png Dawn build/Dawn.dmg >/dev/null
  echo "Built build/Dawn.dmg"
else
  echo "dmgbuild not found, skipping build/Dawn.dmg (pip install dmgbuild)"
fi

# Zip for a GitHub release.
rm -f build/Dawn.zip
ditto -c -k --keepParent "$APP" build/Dawn.zip
echo "Built $APP and build/Dawn.zip"
