#!/bin/bash
# Build bản release và đóng gói thành ClipCut.app (chỉ dùng cá nhân, ký ad-hoc).
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/ClipCut.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClipCut "$APP/Contents/MacOS/ClipCut"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ClipCut</string>
    <key>CFBundleDisplayName</key><string>ClipCut</string>
    <key>CFBundleIdentifier</key><string>local.softech.clipcut</string>
    <key>CFBundleExecutable</key><string>ClipCut</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Xong: $(pwd)/$APP"
echo "Cài: cp -R $APP /Applications/"
