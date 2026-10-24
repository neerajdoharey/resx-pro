#!/usr/bin/env bash
set -e

echo "🔨 Building ResX Pro in Release configuration..."
swift build -c release

APP_NAME="ResX Pro"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "📦 Creating macOS .app bundle structure..."
rm -rf "${APP_DIR}" BetterDisplayClone.app
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

# Copy compiled executable
cp ".build/release/BetterDisplayClone" "${MACOS_DIR}/ResX Pro"

# Copy app resources (AppIcon.icns, MenuBarIcon.png, etc.)
if [ -d "Resources" ]; then
    cp -R Resources/* "${RESOURCES_DIR}/"
fi

# Create Info.plist
cat << 'EOF' > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ResX Pro</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.neeraj.ResXPro</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ResX Pro</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026. All rights reserved.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>ResX Pro requires accessibility and event permissions to intercept brightness keys and adjust displays.</string>
</dict>
</plist>
EOF

SIGN_IDENTITY=$(security find-identity -v -p codesigning | grep "Blueant Local Development" | head -n 1 | awk -F'"' '{print $2}')
if [ -z "$SIGN_IDENTITY" ]; then
    SIGN_IDENTITY="-"
    echo "✍️ Ad-hoc codesigning app bundle..."
else
    echo "✍️ Codesigning with stable identity: ${SIGN_IDENTITY}..."
fi

codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_DIR}"

if [ -d "/Applications/${APP_DIR}" ]; then
    echo "📲 Updating /Applications/${APP_DIR}..."
    rm -rf "/Applications/${APP_DIR}"
    cp -R "${APP_DIR}" "/Applications/${APP_DIR}"
    codesign --force --deep --sign "${SIGN_IDENTITY}" "/Applications/${APP_DIR}"
fi

echo "✅ Successfully built ${APP_DIR}!"
echo "You can launch it via: open \"${APP_DIR}\""
