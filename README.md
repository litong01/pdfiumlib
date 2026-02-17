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

```
dist/
├── android/
│   ├── arm64-v8a/lib/   (libpdfium_wrapper.a + libpdfium.so)
│   ├── armeabi-v7a/lib/
│   ├── x86_64/lib/
│   └── x86/lib/
├── ios/
│   ├── arm64/lib/       (libpdfium_wrapper.a + libpdfium.dylib)
│   └── x86_64/lib/
└── include/
    └── pdfium_wrapper.h
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
    println!("cargo:rustc-link-lib=dylib=pdfium");
}
```

## Clean

```bash
rm -rf build/ dist/ third_party/
docker rmi pdf-engine-builder
```

## License

See [LICENSE](LICENSE).
