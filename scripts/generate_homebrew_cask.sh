#!/bin/bash
set -euo pipefail

# Usage:
#   ./scripts/generate_homebrew_cask.sh [version] [arm64-dmg] [intel-dmg] [output-path]
# Examples:
#   ./scripts/generate_homebrew_cask.sh
#   ./scripts/generate_homebrew_cask.sh 3.0.0
#   ./scripts/generate_homebrew_cask.sh 3.0.0 Buffer_Silicon.dmg Buffer_Intel.dmg Casks/buffer.rb

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

# 1. Resolve target version
if [[ $# -ge 1 && -n "${1:-}" ]]; then
  VERSION="$1"
elif [[ -f "Info.plist" ]]; then
  VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist 2>/dev/null || echo "3.0.0")"
else
  VERSION="3.0.0"
fi

ARM_DMG="${2:-Buffer_Silicon.dmg}"
INTEL_DMG="${3:-Buffer_Intel.dmg}"
OUTPUT_PATH="${4:-Casks/buffer.rb}"

ARM_SHA=""
INTEL_SHA=""

# 2. Try resolving SHA256 from local DMG files
if [[ -f "${ARM_DMG}" && -f "${INTEL_DMG}" ]]; then
  echo "🔍 Computing SHA256 checksums from local binaries..."
  ARM_SHA="$(shasum -a 256 "${ARM_DMG}" | awk '{print $1}')"
  INTEL_SHA="$(shasum -a 256 "${INTEL_DMG}" | awk '{print $1}')"
# 3. Fallback: Query GitHub Release assets via gh CLI
elif command -v gh >/dev/null 2>&1; then
  TAG_NAME="buffer-v${VERSION}"
  echo "🌐 Local DMGs not found. Fetching SHA256 digests for release tag '${TAG_NAME}' via GitHub CLI..."

  ARM_DIGEST="$(gh release view "${TAG_NAME}" --json assets --jq '.assets[] | select(.name == "Buffer_Silicon.dmg") | .digest' 2>/dev/null | sed 's/sha256://' || true)"
  INTEL_DIGEST="$(gh release view "${TAG_NAME}" --json assets --jq '.assets[] | select(.name == "Buffer_Intel.dmg") | .digest' 2>/dev/null | sed 's/sha256://' || true)"

  if [[ -n "${ARM_DIGEST:-}" && -n "${INTEL_DIGEST:-}" ]]; then
    ARM_SHA="${ARM_DIGEST}"
    INTEL_SHA="${INTEL_DIGEST}"
  fi
fi

if [[ -z "${ARM_SHA}" || -z "${INTEL_SHA}" ]]; then
  echo "❌ Error: Could not resolve SHA256 checksums for both architectures." >&2
  echo "   Please either:" >&2
  echo "   1. Run './build_dmg.sh' first to create local DMGs ('${ARM_DMG}' and '${INTEL_DMG}')." >&2
  echo "   2. Ensure the GitHub release 'buffer-v${VERSION}' is published with DMG assets." >&2
  exit 1
fi

mkdir -p "$(dirname "${OUTPUT_PATH}")"

cat > "${OUTPUT_PATH}" <<EOF
cask "buffer" do
  version "${VERSION}"

  on_arm do
    sha256 "${ARM_SHA}"
    url "https://github.com/samirpatil2000/Buffer/releases/download/buffer-v#{version}/Buffer_Silicon.dmg"
  end
  on_intel do
    sha256 "${INTEL_SHA}"
    url "https://github.com/samirpatil2000/Buffer/releases/download/buffer-v#{version}/Buffer_Intel.dmg"
  end

  name "Buffer"
  desc "Lightweight clipboard manager for macOS"
  homepage "https://github.com/samirpatil2000/Buffer"

  auto_updates true
  depends_on macos: :ventura

  app "Buffer.app"

  zap trash: [
    "~/Library/Application Support/Buffer",
    "~/Library/Caches/com.samirpatil.Buffer",
    "~/Library/Preferences/com.samirpatil.Buffer.plist",
  ]
end
EOF

chmod +x "${SCRIPT_DIR}/generate_homebrew_cask.sh"

echo "✅ Generated ${OUTPUT_PATH}"
echo "   Version:   ${VERSION}"
echo "   Apple Silicon (arm64): ${ARM_SHA}"
echo "   Intel (x86_64):        ${INTEL_SHA}"

# Optional: Run brew audit if brew is installed and tap is available
if command -v brew >/dev/null 2>&1; then
  # If tapped locally, audit the tap token
  if brew tap | grep -qx "samirpatil2000/buffer"; then
    echo "🧪 Validating cask with brew audit..."
    # Sync current cask into local tap if it exists
    TAP_CASK="/opt/homebrew/Library/Taps/samirpatil2000/homebrew-buffer/Casks/buffer.rb"
    if [[ -d "/opt/homebrew/Library/Taps/samirpatil2000/homebrew-buffer/Casks" ]]; then
      cp "${OUTPUT_PATH}" "${TAP_CASK}"
    fi
    if brew audit --cask samirpatil2000/buffer/buffer; then
      echo "✅ Homebrew audit passed with 0 warnings."
    fi
  fi
fi
