#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build -c release
app=build/ForkyardBar.app
rm -rf build
mkdir -p "$app/Contents/MacOS"
cp .build/release/ForkyardBar "$app/Contents/MacOS/ForkyardBar"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>dev.seethruhead.forkyard-bar</string>
  <key>CFBundleName</key><string>Forkyard</string>
  <key>CFBundleExecutable</key><string>ForkyardBar</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAppleEventsUsageDescription</key><string>Forkyard opens the terminal UI in iTerm or Terminal when kitty is not installed.</string>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
echo "$app"
