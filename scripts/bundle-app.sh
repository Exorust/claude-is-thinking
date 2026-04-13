#!/bin/bash
# Creates a proper macOS .app bundle from the SPM build output
set -e

APP_NAME="TimeSpend"
DISPLAY_NAME="Claude Still Thinking?"
BUNDLE_ID="dev.timespend.app"
BUILD_DIR=".build/debug"
APP_DIR="build/${DISPLAY_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"

echo "Building ${APP_NAME}..."
swift build

echo "Creating app bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

# Copy binary
cp "${BUILD_DIR}/${APP_NAME}" "${MACOS}/${APP_NAME}"

# Copy SPM resource bundle
if [ -d "${BUILD_DIR}/TimeSpend_TimeSpend.bundle" ]; then
    cp -R "${BUILD_DIR}/TimeSpend_TimeSpend.bundle" "${RESOURCES}/TimeSpend_TimeSpend.bundle"
fi

# Copy app icon
ICON_SRC="Sources/TimeSpend/Resources/AppIcon.icns"
if [ -f "${ICON_SRC}" ]; then
    cp "${ICON_SRC}" "${RESOURCES}/AppIcon.icns"
fi

# Create Info.plist
cat > "${CONTENTS}/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>TimeSpend</string>
    <key>CFBundleIdentifier</key>
    <string>dev.timespend.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Claude Still Thinking?</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Still Thinking?</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.3.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2026. MIT License.</string>
</dict>
</plist>
PLIST

echo "App bundle created at: ${APP_DIR}"
echo "Run with: open ${APP_DIR}"
