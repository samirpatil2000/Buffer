#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 4 ]]; then
  echo "Usage: $0 <version> [arm64-dmg] [intel-dmg] [output-path]"
  echo "Example: $0 1.6 Buffer_Silicon.dmg Buffer_Intel.dmg Casks/buffer.rb"
  exit 1
fi

VERSION="$1"
ARM_DMG="${2:-Buffer_Silicon.dmg}"
INTEL_DMG="${3:-Buffer_Intel.dmg}"
OUTPUT_PATH="${4:-Casks/buffer.rb}"

if [[ ! -f "$ARM_DMG" ]]; then
  echo "Missing arm64 DMG: $ARM_DMG" >&2
  exit 1
fi

if [[ ! -f "$INTEL_DMG" ]]; then
  echo "Missing Intel DMG: $INTEL_DMG" >&2
  exit 1
fi

ARM_SHA="$(shasum -a 256 "$ARM_DMG" | awk '{print $1}')"
INTEL_SHA="$(shasum -a 256 "$INTEL_DMG" | awk '{print $1}')"

mkdir -p "$(dirname "$OUTPUT_PATH")"

cat > "$OUTPUT_PATH" <<EOF
cask "buffer" do
  version "${VERSION}"

  if Hardware::CPU.arm?
    sha256 "${ARM_SHA}"
    url "https://github.com/samirpatil2000/Buffer/releases/download/buffer-v#{version}/Buffer_Silicon.dmg"
  else
    sha256 "${INTEL_SHA}"
    url "https://github.com/samirpatil2000/Buffer/releases/download/buffer-v#{version}/Buffer_Intel.dmg"
  end

  name "Buffer"
  desc "Lightweight clipboard manager for macOS"
  homepage "https://github.com/samirpatil2000/Buffer"

  depends_on macos: ">= :ventura"

  app "Buffer.app"

  zap trash: [
    "~/Library/Application Support/Buffer",
    "~/Library/Preferences/com.samirpatil.Buffer.plist",
  ]
end
EOF

echo "Wrote ${OUTPUT_PATH}"
echo "arm64 sha256: ${ARM_SHA}"
echo "intel sha256: ${INTEL_SHA}"
