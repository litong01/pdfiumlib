#!/usr/bin/env bash
#
# build.sh — Build pdfium_wrapper for iOS and Android.
#
# Everything runs inside a single Docker container by default so nothing
# (NDK, CMake, clang …) needs to be installed on the host.  The only host
# requirement is Docker — plus Xcode on macOS for the iOS SDK that gets
# volume-mounted into the container.
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

    # ── Resolve iOS SDK mounts (only needed when building iOS) ────────────
    DOCKER_SDK_MOUNTS=()
    if [[ "${TARGET}" == "all" || "${TARGET}" == "ios" ]]; then
        if ! command -v xcrun &>/dev/null; then
            echo "ERROR: xcrun not found.  Install Xcode Command Line Tools."
            echo "       The iOS SDK is required even for Docker builds."
            exit 1
        fi

        IPHONEOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
        IPHONESIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path 2>/dev/null || true)"

        if [[ -z "${IPHONEOS_SDK}" ]] || [[ ! -d "${IPHONEOS_SDK}" ]]; then
            echo "ERROR: Could not locate iPhoneOS SDK via xcrun."
            echo "       Make sure Xcode is installed and xcode-select points to it."
            exit 1
        fi
        if [[ -z "${IPHONESIM_SDK}" ]] || [[ ! -d "${IPHONESIM_SDK}" ]]; then
            echo "ERROR: Could not locate iPhoneSimulator SDK via xcrun."
            exit 1
        fi

        echo "  iOS SDK (device):    ${IPHONEOS_SDK}"
        echo "  iOS SDK (simulator): ${IPHONESIM_SDK}"
        DOCKER_SDK_MOUNTS=(-v "${IPHONEOS_SDK}:/ios-sdk-device:ro"
                           -v "${IPHONESIM_SDK}:/ios-sdk-simulator:ro")
    fi

    # ── Build the image ───────────────────────────────────────────────────
    echo ""
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
        "${DOCKER_SDK_MOUNTS[@]+"${DOCKER_SDK_MOUNTS[@]}"}" \
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
#  Android
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
#  iOS  (two code paths: Docker uses direct clang; native uses CMake+Xcode)
# ───────────────────────────────────────────────────────────────────────────

build_ios_arch_docker() {
    local ARCH="$1" PDFIUM_DIR="$2" SDK_PATH="$3" TARGET="$4" INSTALL_DIR="$5"

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
        -target "${TARGET}" \
        -isysroot "${SDK_PATH}" \
        -I"${SRC}/wrapper" \
        -I"${PDFIUM_DIR}/include" \
        -O2 -DNDEBUG -fPIC \
        -c "${SRC}/wrapper/pdfium_wrapper.c" \
        -o "${OBJ_DIR}/pdfium_wrapper.o"

    llvm-ar rcs "${INSTALL_DIR}/lib/libpdfium_wrapper.a" "${OBJ_DIR}/pdfium_wrapper.o"
    cp "${PDFIUM_DIR}/lib/libpdfium.a" "${INSTALL_DIR}/lib/"
    echo "  ✓ ${ARCH}"
}

build_ios_arch_native() {
    local ARCH="$1" PDFIUM_DIR="$2" SDK_NAME="$3" OSX_ARCH="$4" INSTALL_DIR="$5"

    echo ""
    echo "============================================"
    echo "  iOS — ${ARCH}  (native CMake)"
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
    if [[ "${_IN_DOCKER:-}" == "1" ]]; then
        build_ios_arch_docker "arm64"  "${THIRD_PARTY}/ios-arm64" "/ios-sdk-device"    "arm64-apple-ios13.0"              "${DIST}/ios/arm64"
        build_ios_arch_docker "x86_64" "${THIRD_PARTY}/ios-x64"   "/ios-sdk-simulator" "x86_64-apple-ios13.0-simulator"   "${DIST}/ios/x86_64"
    else
        build_ios_arch_native "arm64"  "${THIRD_PARTY}/ios-arm64" "iphoneos"        "arm64"  "${DIST}/ios/arm64"
        build_ios_arch_native "x86_64" "${THIRD_PARTY}/ios-x64"   "iphonesimulator" "x86_64" "${DIST}/ios/x86_64"
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
