#!/usr/bin/env bash
#
# build_ios.sh — Build pdfium_wrapper for iOS (arm64 device + x86_64 simulator).
#
# Prerequisites:
#   - Xcode Command Line Tools installed
#   - Pre-built PDFium in third_party/pdfium/ (run download_pdfium.sh first)
#
# Usage:
#   ./scripts/build_ios.sh
#
# Output:
#   dist/ios/arm64/libpdfium_wrapper.a
#   dist/ios/arm64/libpdfium.a
#   dist/ios/x86_64/libpdfium_wrapper.a
#   dist/ios/x86_64/libpdfium.a
#   dist/include/pdfium_wrapper.h
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
THIRD_PARTY="${PROJECT_ROOT}/third_party/pdfium"
DIST="${PROJECT_ROOT}/dist"

# ---------------------------------------------------------------------------
# Helper: build one architecture
#   build_arch <arch> <pdfium_dir> <sdk> <cmake_system_name> <cmake_osx_archs>
# ---------------------------------------------------------------------------
build_arch() {
    local ARCH="$1"
    local PDFIUM_DIR="$2"
    local SDK="$3"
    local OSX_ARCH="$4"

    local BUILD_DIR="${PROJECT_ROOT}/build/ios-${ARCH}"
    local INSTALL_DIR="${DIST}/ios/${ARCH}"

    echo "============================================"
    echo "  Building iOS — ${ARCH}"
    echo "============================================"

    local SDK_PATH
    SDK_PATH="$(xcrun --sdk "${SDK}" --show-sdk-path)"

    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"

    cmake -S "${PROJECT_ROOT}" -B "${BUILD_DIR}" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES="${OSX_ARCH}" \
        -DCMAKE_OSX_SYSROOT="${SDK_PATH}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="13.0" \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DPDFIUM_ROOT="${PDFIUM_DIR}"

    cmake --build "${BUILD_DIR}" --config Release --parallel
    cmake --install "${BUILD_DIR}" --config Release

    # Also copy the pre-built PDFium static lib so consumers have everything.
    cp "${PDFIUM_DIR}/lib/libpdfium.a" "${INSTALL_DIR}/lib/"

    echo "✓ iOS ${ARCH} artifacts in ${INSTALL_DIR}"
    echo ""
}

# ---------------------------------------------------------------------------
# Build each architecture
# ---------------------------------------------------------------------------

# arm64 (device)
build_arch "arm64" "${THIRD_PARTY}/ios-arm64" "iphoneos" "arm64"

# x86_64 (simulator)
build_arch "x86_64" "${THIRD_PARTY}/ios-x64" "iphonesimulator" "x86_64"

# ---------------------------------------------------------------------------
# Copy header to dist/include/
# ---------------------------------------------------------------------------

mkdir -p "${DIST}/include"
cp "${PROJECT_ROOT}/wrapper/pdfium_wrapper.h" "${DIST}/include/"

echo "============================================"
echo "  iOS build complete"
echo "============================================"
echo ""
echo "Artifacts:"
echo "  ${DIST}/ios/arm64/lib/libpdfium_wrapper.a"
echo "  ${DIST}/ios/arm64/lib/libpdfium.a"
echo "  ${DIST}/ios/x86_64/lib/libpdfium_wrapper.a"
echo "  ${DIST}/ios/x86_64/lib/libpdfium.a"
echo "  ${DIST}/include/pdfium_wrapper.h"
