##############################################################################
# Dockerfile — Unified build environment for pdfium_wrapper
#
# Contains everything needed for both Android and iOS cross-compilation:
#   - Ubuntu 24.04
#   - CMake + Ninja
#   - Android NDK r27c (for Android builds via CMake)
#   - LLVM/clang       (for iOS cross-compilation via direct clang invocation)
#   - curl              (for downloading pre-built PDFium)
#
# For iOS builds the host must volume-mount the Xcode iOS SDKs:
#   -v "<iphoneos-sdk>:/ios-sdk-device:ro"
#   -v "<iphonesimulator-sdk>:/ios-sdk-simulator:ro"
##############################################################################

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# ── System packages ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        ninja-build \
        clang \
        llvm \
        lld \
        curl \
        ca-certificates \
        unzip \
    && rm -rf /var/lib/apt/lists/*

# ── Android NDK (pinned for reproducibility) ──────────────────────────────
ARG NDK_VERSION=r27c
ENV ANDROID_NDK_HOME=/opt/android-ndk

RUN curl -fSL "https://dl.google.com/android/repository/android-ndk-${NDK_VERSION}-linux.zip" \
        -o /tmp/ndk.zip \
    && unzip -q /tmp/ndk.zip -d /opt \
    && mv /opt/android-ndk-* "${ANDROID_NDK_HOME}" \
    && rm /tmp/ndk.zip

WORKDIR /src
