# pdf-engine

A standalone build system that produces pre-compiled **PDFium** static libraries and a minimal **C wrapper** for iOS and Android. The output artifacts are designed to be linked by a Rust (or any other) application — no Rust code lives here.

All builds run inside a **single Docker container** by default so your host system stays clean.

## Repository Layout

```
pdf-engine/
├── Dockerfile                  # Single build container (Ubuntu + NDK + clang + CMake)
├── CMakeLists.txt              # Top-level CMake (imports PDFium, adds wrapper/)
├── .dockerignore
├── wrapper/
│   ├── CMakeLists.txt          # Builds libpdfium_wrapper.a
│   ├── pdfium_wrapper.h        # Public C API header
│   └── pdfium_wrapper.c        # Implementation
├── scripts/
│   ├── build.sh                # Single build script (iOS + Android)
│   └── download_pdfium.sh      # Fetches pre-built PDFium for all targets
├── dist/                       # (generated) final artifacts
│   ├── ios/<arch>/lib/
│   ├── android/<arch>/lib/
│   └── include/pdfium_wrapper.h
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
| **Docker** | Required for containerized builds (the default) |
| **Xcode** | Required on macOS for the iOS SDK, which is volume-mounted into the container |

Everything else (CMake, Android NDK r27c, LLVM/clang) is provided by the Docker image.

## Quick Start

### Build everything (iOS + Android)

```bash
./scripts/build.sh
```

This single command will:
1. Build the `pdf-engine-builder` Docker image (once, then cached)
2. Locate the iOS SDKs on the macOS host and mount them read-only
3. Download pre-built PDFium inside the container
4. Cross-compile the wrapper for all 6 architectures
5. Write artifacts to `dist/` on the host

### Build one platform only

```bash
./scripts/build.sh android    # Android only (no Xcode needed)
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
| `PDFIUM_VERSION` | `6721` | pdfium-binaries release number |
| `USE_DOCKER` | `1` | Set to `0` to build natively (no Docker) |

### Output

```
dist/
├── android/
│   ├── arm64-v8a/lib/   (libpdfium_wrapper.a + libpdfium.a)
│   ├── armeabi-v7a/lib/
│   ├── x86_64/lib/
│   └── x86/lib/
├── ios/
│   ├── arm64/lib/       (libpdfium_wrapper.a + libpdfium.a)
│   └── x86_64/lib/
└── include/
    └── pdfium_wrapper.h
```

## Native Builds (no Docker)

If you prefer to build without Docker (e.g. on CI with tools pre-installed), set `USE_DOCKER=0`:

```bash
# Both platforms
USE_DOCKER=0 ANDROID_NDK_HOME=/path/to/ndk ./scripts/build.sh

# Android only
USE_DOCKER=0 ANDROID_NDK_HOME=/path/to/ndk ./scripts/build.sh android

# iOS only (requires macOS + Xcode + CMake)
USE_DOCKER=0 ./scripts/build.sh ios
```

## How It Works

A single Docker image (`Dockerfile`) contains both the Android NDK and LLVM/clang. The build script (`scripts/build.sh`) uses a self-re-invoking pattern:

1. **On the host** — detects it's outside Docker, builds the image, and re-runs itself inside a container with the project directory mounted at `/src`.
2. **Inside the container** — detects `_IN_DOCKER=1` and performs the actual compilation.

| Platform | Build method inside the container |
|---|---|
| **Android** | CMake with the NDK toolchain file |
| **iOS** | Direct `clang -target arm64-apple-ios13.0 -isysroot /ios-sdk-device` cross-compilation |

The iOS build uses direct `clang` invocation rather than CMake's iOS platform module because the latter requires `xcrun`/Xcode inside the container. Since we compile a single C file into a static archive, direct invocation is simpler and fully reliable.

## Download PDFium Only

```bash
./scripts/download_pdfium.sh
PDFIUM_VERSION=6721 ./scripts/download_pdfium.sh
```

## Linking from Rust

In your Rust project's `build.rs`:

```rust
fn main() {
    let target_arch = std::env::var("CARGO_CFG_TARGET_ARCH").unwrap();
    let target_os   = std::env::var("CARGO_CFG_TARGET_OS").unwrap();

    let pdf_engine = std::env::var("PDF_ENGINE_DIR")
        .unwrap_or_else(|_| "../pdf-engine/dist".to_string());

    let lib_dir = match (target_os.as_str(), target_arch.as_str()) {
        ("ios", "aarch64")     => format!("{pdf_engine}/ios/arm64/lib"),
        ("ios", "x86_64")     => format!("{pdf_engine}/ios/x86_64/lib"),
        ("android", "aarch64") => format!("{pdf_engine}/android/arm64-v8a/lib"),
        ("android", "arm")     => format!("{pdf_engine}/android/armeabi-v7a/lib"),
        ("android", "x86_64")  => format!("{pdf_engine}/android/x86_64/lib"),
        ("android", "x86")     => format!("{pdf_engine}/android/x86/lib"),
        _ => panic!("Unsupported target: {target_os}-{target_arch}"),
    };

    println!("cargo:rustc-link-search=native={lib_dir}");
    println!("cargo:rustc-link-lib=static=pdfium_wrapper");
    println!("cargo:rustc-link-lib=static=pdfium");
}
```

## Clean

```bash
rm -rf build/ dist/ third_party/
docker rmi pdf-engine-builder
```

## License

See [LICENSE](LICENSE).
