#!/bin/bash
set -e

echo "📦 Loading environment..."
set -a # automatically export all variables
source .env
set +a

BUILD_DIR="build"

echo "🧹 Cleaning..."
rm -rf build dmg_* ${APP_NAME}_*.dmg

mkdir -p ${BUILD_DIR}

echo "🔨 Compiling Swift for arm64 (Apple Silicon)..."
swiftc \
-sdk $(xcrun --show-sdk-path --sdk macosx) \
-target arm64-apple-macosx${DEPLOY_TARGET} \
-parse-as-library \
-framework Cocoa \
-framework SwiftUI \
-framework Carbon \
*.swift Models/*.swift Services/*.swift Views/*.swift \
-o ${BUILD_DIR}/${APP_NAME}_arm64

echo "🔨 Compiling Swift for x86_64 (Intel)..."
swiftc \
-sdk $(xcrun --show-sdk-path --sdk macosx) \
-target x86_64-apple-macosx${DEPLOY_TARGET} \
-parse-as-library \
-framework Cocoa \
-framework SwiftUI \
-framework Carbon \
*.swift Models/*.swift Services/*.swift Views/*.swift \
-o ${BUILD_DIR}/${APP_NAME}_x86_64

package_app() {
    local ARCH_BIN=$1
    local SUFFIX=$2
    
    echo ""
    echo "======================================"
    echo "🚀 Packaging ${APP_NAME} for ${SUFFIX}..."
    echo "======================================"
    
    local ARCH_BUILD_DIR="${BUILD_DIR}/${SUFFIX}"
    local APP_DIR="${ARCH_BUILD_DIR}/${APP_NAME}.app"
    local DMG_DIR="dmg_${SUFFIX}"
    local DMG_NAME="${APP_NAME}_${SUFFIX}.dmg"
    
    mkdir -p ${ARCH_BUILD_DIR}
    mkdir -p ${APP_DIR}/Contents/MacOS
    mkdir -p ${APP_DIR}/Contents/Resources
    
    cp ${ARCH_BIN} ${APP_DIR}/Contents/MacOS/${APP_NAME}
    
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
    --output-partial-info-plist ${BUILD_DIR}/partial_${SUFFIX}.plist 2>/dev/null

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
    -volname "${APP_NAME} ${SUFFIX}" \
    -srcfolder ${DMG_DIR} \
    -ov \
    -format UDZO \
    ${DMG_NAME}

    echo "🔏 Signing DMG..."
    codesign \
    --force \
    --sign "${SIGN_IDENTITY}" \
    ${DMG_NAME}

    echo "📤 Notarizing DMG..."
    xcrun notarytool submit ${DMG_NAME} \
    --keychain-profile "${NOTARY_PROFILE}" \
    --wait

    echo "📎 Stapling DMG..."
    xcrun stapler staple ${DMG_NAME}

    echo "🧼 Cleanup..."
    rm -rf ${DMG_DIR}
    
    echo "✅ Finished ${SUFFIX}: ${DMG_NAME}"
}

package_app "${BUILD_DIR}/${APP_NAME}_arm64" "Silicon"
package_app "${BUILD_DIR}/${APP_NAME}_x86_64" "Intel"

echo ""
echo "🎉 ALL BUILDS COMPLETE"