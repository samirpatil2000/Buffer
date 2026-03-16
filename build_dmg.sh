#!/bin/bash
set -e

echo "📦 Loading environment..."
set -a # automatically export all variables
source .env
set +a

BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
DMG_DIR="dmg"

echo "🧹 Cleaning..."
rm -rf build dmg ${APP_NAME}_Release.dmg

mkdir -p ${APP_DIR}/Contents/MacOS
mkdir -p ${APP_DIR}/Contents/Resources

echo "🔨 Compiling Swift..."
swiftc \
-sdk $(xcrun --show-sdk-path --sdk macosx) \
-target $(uname -m)-apple-macosx${DEPLOY_TARGET} \
-parse-as-library \
-framework Cocoa \
-framework SwiftUI \
-framework Carbon \
*.swift Models/*.swift Services/*.swift Views/*.swift \
-o ${APP_DIR}/Contents/MacOS/${APP_NAME}

echo "📋 Creating Info.plist..."

cat > ${APP_DIR}/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN">
<plist version="1.0">
<dict>

<key>CFBundleExecutable</key>
<string>${APP_NAME}</string>

<key>CFBundleIconFile</key>
<string>AppIcon</string>

<key>CFBundleIconName</key>
<string>AppIcon</string>

<key>CFBundleIdentifier</key>
<string>${BUNDLE_ID}</string>

<key>CFBundleName</key>
<string>${APP_NAME}</string>

<key>CFBundlePackageType</key>
<string>APPL</string>

<key>CFBundleShortVersionString</key>
<string>1.0</string>

<key>CFBundleVersion</key>
<string>1</string>

<key>LSMinimumSystemVersion</key>
<string>${DEPLOY_TARGET}</string>

<key>LSUIElement</key>
<true/>

<key>NSPrincipalClass</key>
<string>NSApplication</string>

</dict>
</plist>
EOF

echo "🎨 Building assets..."

xcrun actool Assets.xcassets \
--compile ${APP_DIR}/Contents/Resources \
--platform macosx \
--minimum-deployment-target ${DEPLOY_TARGET} \
--app-icon AppIcon \
--output-partial-info-plist ${BUILD_DIR}/partial.plist 2>/dev/null

echo "📦 Creating PkgInfo..."

echo "APPL????" > ${APP_DIR}/Contents/PkgInfo

echo "🔏 Signing..."

codesign \
--force \
--deep \
--timestamp \
--options runtime \
--sign "${SIGN_IDENTITY}" \
--entitlements Buffer.entitlements \
${APP_DIR}

echo "🔍 Verifying..."

codesign --verify --deep --strict ${APP_DIR}

echo "📂 Preparing DMG..."

mkdir -p ${DMG_DIR}

cp -R ${APP_DIR} ${DMG_DIR}/

ln -s /Applications ${DMG_DIR}/Applications

echo "💿 Creating DMG..."

hdiutil create \
-volname "${APP_NAME}" \
-srcfolder ${DMG_DIR} \
-ov \
-format UDZO \
${APP_NAME}_Release.dmg

echo "📤 Notarizing DMG..."
xcrun notarytool submit ${APP_NAME}_Release.dmg \
--keychain-profile "${NOTARY_PROFILE}" \
--wait

echo "📎 Stapling DMG..."

xcrun stapler staple ${APP_NAME}_Release.dmg

echo "🧼 Cleanup..."

rm -rf ${DMG_DIR}

echo ""
echo "✅ BUILD COMPLETE"
echo "DMG: ${APP_NAME}_Release.dmg"