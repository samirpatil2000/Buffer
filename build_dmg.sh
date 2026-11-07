#!/bin/bash
set -e

echo "📦 Loading environment..."
set -a # automatically export all variables
source .env
set +a

BUILD_DIR="build"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Info.plist)
echo "🔖 Version: ${VERSION} (Build: ${BUILD})"


echo "🧹 Cleaning..."
rm -rf build dmg_* ${APP_NAME}_*.dmg ${APP_NAME}_*.zip

mkdir -p ${BUILD_DIR}

echo "🔨 Compiling universal application with Xcode..."
xcodebuild \
  -scheme "${APP_NAME}" \
  -configuration Release \
  -derivedDataPath "${BUILD_DIR}/DerivedData" \
  -destination 'generic/platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build

BASE_APP="${BUILD_DIR}/DerivedData/Build/Products/Release/${APP_NAME}.app"

package_app() {
    local ARCH=$1
    local SUFFIX=$2
    
    echo ""
    echo "======================================"
    echo "🚀 Packaging ${APP_NAME} for ${SUFFIX} (${ARCH})..."
    echo "======================================"
    
    local ARCH_BUILD_DIR="${BUILD_DIR}/${SUFFIX}"
    local APP_DIR="${ARCH_BUILD_DIR}/${APP_NAME}.app"
    local DMG_DIR="dmg_${SUFFIX}"
    local DMG_NAME="${APP_NAME}_${SUFFIX}.dmg"
    
    mkdir -p ${ARCH_BUILD_DIR}
    cp -R "${BASE_APP}" "${APP_DIR}"

    echo "✂️ Thinning binary for ${ARCH}..."
    lipo "${APP_DIR}/Contents/MacOS/${APP_NAME}" -thin "${ARCH}" -output "${APP_DIR}/Contents/MacOS/${APP_NAME}"

    echo "🔏 Signing..."
    SIGN_OK=false
    for attempt in 1 2 3; do
        if codesign \
            --force \
            --deep \
            --timestamp \
            --options runtime \
            --sign "${SIGN_IDENTITY}" \
            --entitlements Buffer.entitlements \
            ${APP_DIR}; then
            SIGN_OK=true
            break
        fi
        echo "⚠️  Signing attempt ${attempt} failed (timestamp server unreachable?), retrying in 3s..."
        sleep 3
    done
    if [ "$SIGN_OK" = false ]; then
        echo "❌ Signing failed after 3 attempts. Check internet connectivity to timestamp.apple.com"
        exit 1
    fi

    echo "🔍 Verifying..."
    codesign --verify --deep --strict ${APP_DIR}

    echo "🗜️ Creating ZIP..."
    local ZIP_NAME="${APP_NAME}_${SUFFIX}.zip"
    ditto -ck --rsrc --sequesterRsrc --keepParent ${APP_DIR} ${ZIP_NAME}
    echo "✅ ZIP: ${ZIP_NAME}"

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
    if xcrun notarytool submit ${DMG_NAME} --keychain-profile "${NOTARY_PROFILE}" --wait; then
        echo "📎 Stapling DMG..."
        xcrun stapler staple ${DMG_NAME}
    else
        echo "⚠️  Notarization failed or skipped. Continuing with unnotarized DMG..."
    fi

    echo "🧼 Cleanup..."
    rm -rf ${DMG_DIR}
    
    echo "✅ Finished ${SUFFIX}: ${DMG_NAME}"
}

package_app "arm64" "Silicon"
package_app "x86_64" "Intel"

echo ""
echo "🎉 ALL BUILDS COMPLETE"