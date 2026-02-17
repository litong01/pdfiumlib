#!/usr/bin/env bash
#
# build.sh — Build pdfium_wrapper for iOS and Android.
#
# Everything runs inside a single Docker container by default.  The ONLY host
# requirement is Docker.  No Xcode, no NDK, no CMake on the host.
#
# For iOS cross-compilation, the container uses clang with the correct
# -target triple.  The wrapper only uses standard C functions (malloc, memcpy,
# ceil …) and PDFium headers — no iOS SDK is needed at compile time.
#
# Usage:
#   ./scripts/build.sh                      # build both platforms (Docker)
#   ./scripts/build.sh android              # Android only
#   ./scripts/build.sh ios                  # iOS only
#   USE_DOCKER=0 ./scripts/build.sh         # native (no Docker)
#
# Environment variables:
#   USE_DOCKER      0 to skip Docker and build natively (default: 1)
#   ANDROID_API     minimum Android API level              (default: 21)
#   PDFIUM_VERSION  pdfium-binaries release to download    (default: 6721)
#   ANDROID_NDK_HOME  (native mode only) path to the NDK
#
# Output:
#   dist/ios/arm64/lib/         libpdfium_wrapper.a + libpdfium.a
#   dist/ios/x86_64/lib/        libpdfium_wrapper.a + libpdfium.a
#   dist/android/arm64-v8a/lib/ libpdfium_wrapper.a + libpdfium.a
#   dist/android/armeabi-v7a/lib/…
#   dist/android/x86_64/lib/…
#   dist/android/x86/lib/…
#   dist/include/pdfium_wrapper.h
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Which platforms to build — default is both.
TARGET="${1:-all}"

# ═══════════════════════════════════════════════════════════════════════════
#  HOST SIDE — build Docker image and re-invoke this script in the container
# ═══════════════════════════════════════════════════════════════════════════

if [[ "${_IN_DOCKER:-}" != "1" ]] && [[ "${USE_DOCKER:-1}" != "0" ]]; then
    IMAGE="pdf-engine-builder"

    # ── Build the image ───────────────────────────────────────────────────
    echo "══════════════════════════════════════════════"
    echo "  Building Docker image: ${IMAGE}"
    echo "══════════════════════════════════════════════"
    docker build -f "${PROJECT_ROOT}/Dockerfile" -t "${IMAGE}" "${PROJECT_ROOT}"

    # ── Run the build inside the container ────────────────────────────────
    echo ""
    echo "══════════════════════════════════════════════"
    echo "  Launching build inside container …"
    echo "══════════════════════════════════════════════"
    docker run --rm \
        -e _IN_DOCKER=1 \
        -e ANDROID_API="${ANDROID_API:-}" \
        -e PDFIUM_VERSION="${PDFIUM_VERSION:-}" \
        --user "$(id -u):$(id -g)" \
        -v "${PROJECT_ROOT}:/src" \
        "${IMAGE}" \
        bash /src/scripts/build.sh "${TARGET}"

    echo ""
    echo "══════════════════════════════════════════════"
    echo "  Build complete — artifacts in dist/"
    echo "══════════════════════════════════════════════"
    exit 0
fi

# ═══════════════════════════════════════════════════════════════════════════
#  CONTAINER / NATIVE — actual build logic
# ═══════════════════════════════════════════════════════════════════════════

SRC="/src"
THIRD_PARTY="/src/third_party/pdfium"
DIST="/src/dist"

if [[ "${_IN_DOCKER:-}" != "1" ]]; then
    SRC="${PROJECT_ROOT}"
    THIRD_PARTY="${PROJECT_ROOT}/third_party/pdfium"
    DIST="${PROJECT_ROOT}/dist"
fi

# ── Download PDFium ───────────────────────────────────────────────────────

bash "${SRC}/scripts/download_pdfium.sh"

# ───────────────────────────────────────────────────────────────────────────
#  Android  (CMake + NDK toolchain)
# ───────────────────────────────────────────────────────────────────────────

build_android() {
    # ── Locate NDK ────────────────────────────────────────────────────────
    if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
        if [[ -d "/opt/android-ndk" ]]; then
            ANDROID_NDK_HOME="/opt/android-ndk"
        elif [[ -d "${HOME}/Library/Android/sdk/ndk" ]]; then
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

    local TOOLCHAIN="${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake"
    if [[ ! -f "${TOOLCHAIN}" ]]; then
        echo "ERROR: NDK toolchain not found at ${TOOLCHAIN}"
        exit 1
    fi

    echo "Using Android NDK: ${ANDROID_NDK_HOME}"

    local ANDROID_API="${ANDROID_API:-21}"

    declare -A ABI_TO_PDFIUM=(
        ["arm64-v8a"]="android-arm64"
        ["armeabi-v7a"]="android-arm"
        ["x86_64"]="android-x64"
        ["x86"]="android-x86"
    )

    for ABI in arm64-v8a armeabi-v7a x86_64 x86; do
        local PDFIUM_DIR="${THIRD_PARTY}/${ABI_TO_PDFIUM[$ABI]}"
        local BUILD_DIR="/tmp/build/android-${ABI}"
        local INSTALL_DIR="${DIST}/android/${ABI}"

        echo ""
        echo "============================================"
        echo "  Android — ${ABI}"
        echo "============================================"

        if [[ ! -d "${PDFIUM_DIR}" ]]; then
            echo "ERROR: PDFium not found at ${PDFIUM_DIR}"
            exit 1
        fi

        rm -rf "${BUILD_DIR}"
        mkdir -p "${BUILD_DIR}"

        cmake -S "${SRC}" -B "${BUILD_DIR}" \
            -DCMAKE_TOOLCHAIN_FILE="${TOOLCHAIN}" \
            -DANDROID_ABI="${ABI}" \
            -DANDROID_NATIVE_API_LEVEL="${ANDROID_API}" \
            -DANDROID_STL=c++_static \
            -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
            -DCMAKE_BUILD_TYPE=Release \
            -DPDFIUM_ROOT="${PDFIUM_DIR}"

        cmake --build "${BUILD_DIR}" --config Release --parallel
        cmake --install "${BUILD_DIR}" --config Release

        cp "${PDFIUM_DIR}/lib/libpdfium.a" "${INSTALL_DIR}/lib/"
        echo "  ✓ ${ABI}"
    done
}

# ───────────────────────────────────────────────────────────────────────────
#  iOS  (clang cross-compilation — works on any Linux, no Xcode needed)
#
#  We compile with clang -target arm64-apple-ios13.0 using the container's
#  Linux system headers.  This works because:
#    - The C standard functions we use (malloc, free, memcpy, ceil …) have
#      identical signatures on every platform.
#    - The target triple controls the ABI, calling convention, and output
#      object format (Mach-O).  Headers just provide declarations.
#    - We only compile (-c) to .o and archive to .a — no linking occurs.
#
#  On native macOS (USE_DOCKER=0) we use CMake + Xcode SDK instead.
# ───────────────────────────────────────────────────────────────────────────

build_ios_arch_crosscompile() {
    local ARCH="$1" PDFIUM_DIR="$2" CLANG_TARGET="$3" INSTALL_DIR="$4"

    echo ""
    echo "============================================"
    echo "  iOS — ${ARCH}  (clang cross-compile)"
    echo "============================================"

    if [[ ! -d "${PDFIUM_DIR}" ]]; then
        echo "ERROR: PDFium not found at ${PDFIUM_DIR}"
        exit 1
    fi

    mkdir -p "${INSTALL_DIR}/lib"
    local OBJ_DIR="/tmp/build/ios-${ARCH}"
    mkdir -p "${OBJ_DIR}"

    clang \
        -target "${CLANG_TARGET}" \
        --sysroot=/ \
        -I"${SRC}/wrapper" \
        -I"${PDFIUM_DIR}/include" \
        -O2 -DNDEBUG -fPIC \
        -c "${SRC}/wrapper/pdfium_wrapper.c" \
        -o "${OBJ_DIR}/pdfium_wrapper.o"

    llvm-ar rcs "${INSTALL_DIR}/lib/libpdfium_wrapper.a" "${OBJ_DIR}/pdfium_wrapper.o"
    cp "${PDFIUM_DIR}/lib/libpdfium.a" "${INSTALL_DIR}/lib/"
    echo "  ✓ ${ARCH}"
}

build_ios_arch_xcode() {
    local ARCH="$1" PDFIUM_DIR="$2" SDK_NAME="$3" OSX_ARCH="$4" INSTALL_DIR="$5"

    echo ""
    echo "============================================"
    echo "  iOS — ${ARCH}  (native CMake + Xcode)"
    echo "============================================"

    local SDK_PATH
    SDK_PATH="$(xcrun --sdk "${SDK_NAME}" --show-sdk-path)"

    local BUILD_DIR="${SRC}/build/ios-${ARCH}"
    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"

    cmake -S "${SRC}" -B "${BUILD_DIR}" \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_ARCHITECTURES="${OSX_ARCH}" \
        -DCMAKE_OSX_SYSROOT="${SDK_PATH}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET="13.0" \
        -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DPDFIUM_ROOT="${PDFIUM_DIR}"

    cmake --build "${BUILD_DIR}" --config Release --parallel
    cmake --install "${BUILD_DIR}" --config Release

    cp "${PDFIUM_DIR}/lib/libpdfium.a" "${INSTALL_DIR}/lib/"
    echo "  ✓ ${ARCH}"
}

build_ios() {
    # On macOS with Xcode: use CMake + the real iOS SDK.
    # Everywhere else (Docker, Linux CI): use clang cross-compilation.
    if [[ "$(uname)" == "Darwin" ]] && command -v xcrun &>/dev/null; then
        build_ios_arch_xcode "arm64"  "${THIRD_PARTY}/ios-arm64" "iphoneos"        "arm64"  "${DIST}/ios/arm64"
        build_ios_arch_xcode "x86_64" "${THIRD_PARTY}/ios-x64"   "iphonesimulator" "x86_64" "${DIST}/ios/x86_64"
    else
        build_ios_arch_crosscompile "arm64"  "${THIRD_PARTY}/ios-arm64" "arm64-apple-ios13.0"            "${DIST}/ios/arm64"
        build_ios_arch_crosscompile "x86_64" "${THIRD_PARTY}/ios-x64"   "x86_64-apple-ios13.0-simulator" "${DIST}/ios/x86_64"
    fi
}

# ───────────────────────────────────────────────────────────────────────────
#  Dispatch
# ───────────────────────────────────────────────────────────────────────────

case "${TARGET}" in
    all)
        build_android
        build_ios
        ;;
    android)
        build_android
        ;;
    ios)
        build_ios
        ;;
    *)
        echo "Usage: $0 [all|android|ios]"
        exit 1
        ;;
esac

# ── Copy public header ────────────────────────────────────────────────────

mkdir -p "${DIST}/include"
cp "${SRC}/wrapper/pdfium_wrapper.h" "${DIST}/include/"

# ── Summary ───────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════════"
echo "  Build complete — ${TARGET}"
echo "══════════════════════════════════════════════"
echo ""
echo "Artifacts in dist/:"
if [[ "${TARGET}" == "all" || "${TARGET}" == "android" ]]; then
    for ABI in arm64-v8a armeabi-v7a x86_64 x86; do
        echo "  android/${ABI}/lib/  libpdfium_wrapper.a + libpdfium.a"
    done
fi
if [[ "${TARGET}" == "all" || "${TARGET}" == "ios" ]]; then
    echo "  ios/arm64/lib/      libpdfium_wrapper.a + libpdfium.a"
    echo "  ios/x86_64/lib/     libpdfium_wrapper.a + libpdfium.a"
fi
echo "  include/            pdfium_wrapper.h"
