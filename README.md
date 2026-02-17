# pdf-engine

A standalone build system that produces pre-compiled **PDFium** static libraries and a minimal **C wrapper** for iOS and Android. The output artifacts are designed to be linked by a Rust (or any other) application — no Rust code lives here.

All builds run inside a **single Docker container** by default. The only host requirement is Docker — no Xcode, no NDK, no CMake.

## CI

A GitHub Actions workflow builds both platforms on every push to `main` and on pull requests. Everything runs on a single `ubuntu-latest` runner — no macOS runner needed. When you push a version tag (`v*`), a release is created automatically with a `pdf-engine-<tag>.tar.gz` archive.

| Job | Runner | Method |
|---|---|---|
| `build` | `ubuntu-latest` | clang cross-compile (iOS) + CMake/NDK (Android) |
| `release` | `ubuntu-latest` | Packages and uploads artifacts when a `v*` tag is pushed |

## Repository Layout

```
pdf-engine/
├── Dockerfile                  # Single build container (Ubuntu + NDK + clang + CMake)
├── CMakeLists.txt              # Top-level CMake (imports PDFium, adds wrapper/)
├── .dockerignore
├── .github/workflows/build.yml # CI: build + release
├── wrapper/
│   ├── CMakeLists.txt          # Builds libpdfium_wrapper.a
│   ├── pdfium_wrapper.h        # Public C API header
│   └── pdfium_wrapper.c        # Implementation
├── rust/
│   └── pdfium-wrapper-sys/     # Rust FFI crate (included in bundle)
│       ├── Cargo.toml
│       ├── build.rs            # Auto-detects target arch → lib dir
│       └── src/lib.rs          # extern "C" bindings + PdfiumBitmap
├── scripts/
│   ├── build.sh                # Single build script (iOS + Android)
│   └── download_pdfium.sh      # Fetches pre-built PDFium for all targets
├── dist/                       # (generated) final artifacts + bundle
├── third_party/                # (generated) downloaded PDFium binaries
└── build/                      # (generated) CMake build directories
```

## C Wrapper API

The wrapper exposes a minimal, stable C interface for PDF rasterization:

```c
void  pdfium_init(void);
void  pdfium_destroy(void);

void* pdfium_load_document(const char* path);
void  pdfium_close_document(void* doc);

void* pdfium_render_page(void* doc, int page_index, int target_width);
void  pdfium_free_bitmap(void* bitmap);
```

`pdfium_render_page` returns a pointer to a `PdfiumBitmap` struct containing an RGBA pixel buffer, width, height, and stride. See `wrapper/pdfium_wrapper.h` for the full definition.

## Prerequisites

| Requirement | Notes |
|---|---|
| **Docker** | The only requirement for the default build |

Everything (CMake, Android NDK r27c, LLVM/clang) is provided by the Docker image. No Xcode, no macOS, no host toolchains needed.

## Quick Start

### Build everything (iOS + Android)

```bash
./scripts/build.sh
```

This single command will:
1. Build the `pdf-engine-builder` Docker image (once, then cached)
2. Download pre-built PDFium inside the container
3. Cross-compile the wrapper for all 6 architectures
4. Write artifacts to `dist/` on the host

### Build one platform only

```bash
./scripts/build.sh android    # Android only
./scripts/build.sh ios        # iOS only
```

### Configuration

Override settings via environment variables:

```bash
ANDROID_API=24 PDFIUM_VERSION=6721 ./scripts/build.sh
```

| Variable | Default | Description |
|---|---|---|
| `ANDROID_API` | `21` | Minimum Android API level |
| `PDFIUM_VERSION` | `7690` | pdfium-binaries release number |
| `USE_DOCKER` | `1` | Set to `0` to build natively (no Docker) |

### Output

The build produces `dist/pdf-engine.tar.gz` — a single bundle with everything:

```
dist/
├── android/
│   ├── arm64-v8a/lib/             libpdfium_wrapper.a + libpdfium.so
│   ├── armeabi-v7a/lib/
│   ├── x86_64/lib/
│   └── x86/lib/
├── ios/
│   ├── arm64/lib/                 libpdfium_wrapper.a + libpdfium.dylib
│   └── x86_64/lib/
├── include/                       pdfium_wrapper.h + PDFium headers
├── rust/pdfium-wrapper-sys/       Rust FFI crate (drop-in)
└── pdf-engine.tar.gz              ← this archive contains all of the above
```

## Native Builds (no Docker)

If you prefer to build without Docker (e.g. on CI with tools pre-installed), set `USE_DOCKER=0`:

```bash
# On Linux (clang + NDK required)
USE_DOCKER=0 ANDROID_NDK_HOME=/path/to/ndk ./scripts/build.sh

# On macOS (Xcode + CMake + NDK required)
USE_DOCKER=0 ANDROID_NDK_HOME=/path/to/ndk ./scripts/build.sh
```

On macOS with Xcode, iOS builds use CMake + the Xcode SDK. On Linux, iOS builds use `clang` cross-compilation.

## How It Works

A single Docker image (`Dockerfile`) contains both the Android NDK and LLVM/clang. The build script (`scripts/build.sh`) uses a self-re-invoking pattern:

1. **On the host** — detects it's outside Docker, builds the image, and re-runs itself inside a container with the project directory mounted at `/src`.
2. **Inside the container** — detects `_IN_DOCKER=1` and performs the actual compilation.

| Platform | Build method |
|---|---|
| **Android** | CMake with the NDK toolchain file |
| **iOS** | `clang -target arm64-apple-ios13.0 --sysroot=/ -c` cross-compilation |

The iOS build compiles with `clang` using the correct Apple target triple. Since our wrapper only uses standard C functions (`malloc`, `free`, `memcpy`, `ceil`) and PDFium headers, the Linux system headers provide correct declarations — no iOS SDK is needed at compile time. The target triple controls the ABI, calling convention, and Mach-O object format. Only compilation occurs (no linking), so no Apple linker is required either.

## Download PDFium Only

```bash
./scripts/download_pdfium.sh
PDFIUM_VERSION=6721 ./scripts/download_pdfium.sh
```

## Using from Rust

The bundle includes a ready-to-use Rust FFI crate at `rust/pdfium-wrapper-sys/`.

### 1. Extract the bundle and add the crate as a dependency

```bash
tar xzf pdf-engine.tar.gz -C vendor/pdf-engine
```

In your `Cargo.toml`:

```toml
[dependencies]
pdfium-wrapper-sys = { path = "vendor/pdf-engine/rust/pdfium-wrapper-sys" }
```

### 2. Point it at the libraries

The `build.rs` in the crate auto-detects the right architecture from Cargo's target triple. Just set `PDFIUM_ROOT` to the extracted bundle:

```bash
# Builds for Android arm64 — the crate picks android/arm64-v8a/lib automatically
PDFIUM_ROOT=vendor/pdf-engine cargo build --target aarch64-linux-android
```

Or override with a specific directory:

```bash
PDFIUM_LIB_DIR=vendor/pdf-engine/ios/arm64/lib cargo build --target aarch64-apple-ios
```

### 3. Call the API

```rust
use pdfium_wrapper_sys::*;
use std::ffi::CString;

unsafe {
    pdfium_init();

    let path = CString::new("/path/to/document.pdf").unwrap();
    let doc = pdfium_load_document(path.as_ptr());
    if !doc.is_null() {
        let bmp = pdfium_render_page(doc, 0, 1024);
        if !bmp.is_null() {
            let bitmap = &*bmp;
            // bitmap.data  → *mut u8 (RGBA pixels)
            // bitmap.width, bitmap.height, bitmap.stride
            pdfium_free_bitmap(bmp as *mut _);
        }
        pdfium_close_document(doc);
    }

    pdfium_destroy();
}
```

### Supported Cargo targets

| Cargo target | Bundle directory |
|---|---|
| `aarch64-linux-android` | `android/arm64-v8a` |
| `armv7-linux-androideabi` | `android/armeabi-v7a` |
| `x86_64-linux-android` | `android/x86_64` |
| `i686-linux-android` | `android/x86` |
| `aarch64-apple-ios` | `ios/arm64` |
| `x86_64-apple-ios` | `ios/x86_64` |

## Clean

```bash
rm -rf build/ dist/ third_party/
docker rmi pdf-engine-builder
```

## License

See [LICENSE](LICENSE).
