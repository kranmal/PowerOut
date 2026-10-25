#!/bin/bash
# Builds PowerOut.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

ARCHS="--arch arm64 --arch x86_64"   # universal: Apple silicon + Intel
swift build -c release $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/PowerOut"

APP="build/PowerOut.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/PowerOut"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>PowerOut</string>
    <key>CFBundleDisplayName</key><string>PowerOut</string>
    <key>CFBundleIdentifier</key><string>com.kranmal.PowerOut</string>
    <key>CFBundleExecutable</key><string>PowerOut</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>PowerOut switches dark mode on to save battery.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>PowerOut turns Bluetooth off to save battery.</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
