#!/usr/bin/env bash
#
# build_android.sh — Build pdfium_wrapper for Android (4 architectures).
#
# Prerequisites:
#   - Android NDK installed (set ANDROID_NDK_HOME or let the script find it)
#   - Pre-built PDFium in third_party/pdfium/ (run download_pdfium.sh first)
#
# Usage:
#   ANDROID_NDK_HOME=/path/to/ndk ./scripts/build_android.sh
#
# Output:
#   dist/android/arm64-v8a/libpdfium_wrapper.a
#   dist/android/arm64-v8a/libpdfium.a
#   dist/android/armeabi-v7a/...
#   dist/android/x86_64/...
#   dist/android/x86/...
#   dist/include/pdfium_wrapper.h
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
THIRD_PARTY="${PROJECT_ROOT}/third_party/pdfium"
DIST="${PROJECT_ROOT}/dist"

# ---------------------------------------------------------------------------
# Locate the Android NDK
# ---------------------------------------------------------------------------

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
    # Try common locations
    if [[ -d "${HOME}/Library/Android/sdk/ndk" ]]; then
        # Pick the newest NDK version available
        ANDROID_NDK_HOME="$(ls -d "${HOME}/Library/Android/sdk/ndk/"* 2>/dev/null | sort -V | tail -1)"
    elif [[ -d "${ANDROID_HOME:-}/ndk" ]]; then
        ANDROID_NDK_HOME="$(ls -d "${ANDROID_HOME}/ndk/"* 2>/dev/null | sort -V | tail -1)"
    fi
fi

if [[ -z "${ANDROID_NDK_HOME:-}" ]] || [[ ! -d "${ANDROID_NDK_HOME}" ]]; then
    echo "ERROR: Cannot find Android NDK."
    echo "Set ANDROID_NDK_HOME to the path of your NDK installation."
    exit 1
fi

TOOLCHAIN="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"
if [[ ! -f "${TOOLCHAIN}" ]]; then
    echo "ERROR: NDK toolchain file not found at ${TOOLCHAIN}"
    exit 1
fi

echo "Using Android NDK: ${ANDROID_NDK_HOME}"
echo ""

# Minimum API level
ANDROID_API="${ANDROID_API:-21}"

# ---------------------------------------------------------------------------
# Map: <android_abi> -> <pdfium_dir_name>
# ---------------------------------------------------------------------------
declare -A ABI_TO_PDFIUM=(
    ["arm64-v8a"]="android-arm64"
    ["armeabi-v7a"]="android-arm"
    ["x86_64"]="android-x64"
    ["x86"]="android-x86"
)

# ---------------------------------------------------------------------------
# Helper: build one ABI
# ---------------------------------------------------------------------------
build_abi() {
    local ABI="$1"
    local PDFIUM_NAME="${ABI_TO_PDFIUM[$ABI]}"
    local PDFIUM_DIR="${THIRD_PARTY}/${PDFIUM_NAME}"

    local BUILD_DIR="${PROJECT_ROOT}/build/android-${ABI}"
    local INSTALL_DIR="${DIST}/android/${ABI}"

    echo "============================================"
    echo "  Building Android — ${ABI}"
    echo "============================================"

    if [[ ! -d "${PDFIUM_DIR}" ]]; then
        echo "ERROR: PDFium not found at ${PDFIUM_DIR}"
        echo "Run download_pdfium.sh first."
        exit 1
    fi

    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"

    cmake -S "${PROJECT_ROOT}" -B "${BUILD_DIR}" \
        -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
        -DANDROID_ABI="${ABI}" \
        -DANDROID_NATIVE_API_LEVEL="${ANDROID_API}" \
        -DANDROID_STL=c++_static \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DPDFIUM_ROOT="${PDFIUM_DIR}"

    cmake --build "${BUILD_DIR}" --config Release --parallel
    cmake --install "${BUILD_DIR}" --config Release

    # Copy the pre-built PDFium static lib alongside the wrapper.
    cp "${PDFIUM_DIR}/lib/libpdfium.a" "${INSTALL_DIR}/lib/"

    echo "✓ Android ${ABI} artifacts in ${INSTALL_DIR}"
    echo ""
}

# ---------------------------------------------------------------------------
# Build all ABIs
# ---------------------------------------------------------------------------

for ABI in arm64-v8a armeabi-v7a x86_64 x86; do
    build_abi "${ABI}"
done

# ---------------------------------------------------------------------------
# Copy header to dist/include/
# ---------------------------------------------------------------------------

mkdir -p "${DIST}/include"
cp "${PROJECT_ROOT}/wrapper/pdfium_wrapper.h" "${DIST}/include/"

echo "============================================"
echo "  Android build complete"
echo "============================================"
echo ""
echo "Artifacts:"
for ABI in arm64-v8a armeabi-v7a x86_64 x86; do
    echo "  ${DIST}/android/${ABI}/lib/libpdfium_wrapper.a"
    echo "  ${DIST}/android/${ABI}/lib/libpdfium.a"
done
echo "  ${DIST}/include/pdfium_wrapper.h"
