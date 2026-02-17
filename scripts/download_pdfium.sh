#!/usr/bin/env bash
#
# download_pdfium.sh — Download pre-built PDFium binaries for iOS and Android.
#
# Uses bblanchon/pdfium-binaries GitHub releases which provide ready-made
# static libraries for many platforms.
#
# Usage:
#   ./scripts/download_pdfium.sh
#
# This will create:
#   third_party/pdfium/ios-arm64/
#   third_party/pdfium/ios-x64/
#   third_party/pdfium/android-arm64/
#   third_party/pdfium/android-arm/
#   third_party/pdfium/android-x64/
#   third_party/pdfium/android-x86/
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
THIRD_PARTY="${PROJECT_ROOT}/third_party/pdfium"

# ---------------------------------------------------------------------------
# PDFium release version (from bblanchon/pdfium-binaries).
# Update this when you want a newer build.
# See: https://github.com/bblanchon/pdfium-binaries/releases
# ---------------------------------------------------------------------------
PDFIUM_VERSION="${PDFIUM_VERSION:-7690}"
BASE_URL="https://github.com/bblanchon/pdfium-binaries/releases/download/chromium/${PDFIUM_VERSION}"

# Map of <local-dir-name> -> <archive-filename>
declare -A TARGETS=(
    ["ios-arm64"]="pdfium-ios-device-arm64.tgz"
    ["ios-x64"]="pdfium-ios-simulator-x64.tgz"
    ["android-arm64"]="pdfium-android-arm64.tgz"
    ["android-arm"]="pdfium-android-arm.tgz"
    ["android-x64"]="pdfium-android-x64.tgz"
    ["android-x86"]="pdfium-android-x86.tgz"
)

mkdir -p "${THIRD_PARTY}"

for dir_name in "${!TARGETS[@]}"; do
    archive="${TARGETS[$dir_name]}"
    url="${BASE_URL}/${archive}"
    dest="${THIRD_PARTY}/${dir_name}"

    if [[ -d "${dest}" ]]; then
        echo "✓ ${dir_name} already exists, skipping."
        continue
    fi

    echo "⬇ Downloading ${archive} …"
    tmp_archive="/tmp/pdfium_${dir_name}.tgz"
    curl -fSL --retry 3 -o "${tmp_archive}" "${url}"

    echo "  Extracting to ${dest} …"
    mkdir -p "${dest}"
    tar xzf "${tmp_archive}" -C "${dest}"
    rm -f "${tmp_archive}"
    echo "✓ ${dir_name} ready."
done

echo ""
echo "All PDFium binaries downloaded to: ${THIRD_PARTY}"
echo ""
echo "Expected layout per target:"
echo "  <target>/lib/libpdfium.a"
echo "  <target>/include/fpdfview.h"
