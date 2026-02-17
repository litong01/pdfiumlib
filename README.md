# pdf-engine

A standalone build system that produces pre-compiled **PDFium** static libraries and a minimal **C wrapper** for iOS and Android. The output artifacts are designed to be linked by a Rust (or any other) application — no Rust code lives here.

## Repository Layout

```
pdf-engine/
├── CMakeLists.txt              # Top-level CMake (imports PDFium, adds wrapper/)
├── wrapper/
│   ├── CMakeLists.txt          # Builds libpdfium_wrapper.a
│   ├── pdfium_wrapper.h        # Public C API header
│   └── pdfium_wrapper.c        # Implementation
├── scripts/
│   ├── download_pdfium.sh      # Fetches pre-built PDFium for all targets
│   ├── build_ios.sh            # Builds wrapper for iOS arm64 + x86_64
│   └── build_android.sh        # Builds wrapper for Android (4 ABIs)
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

| Platform | Requirements |
|----------|-------------|
| **iOS** | macOS, Xcode Command Line Tools, CMake 3.18+ |
| **Android** | Android NDK (r21+), CMake 3.18+ |

Install CMake via Homebrew if needed:

```bash
brew install cmake
```

## Quick Start

### 1. Download PDFium

```bash
./scripts/download_pdfium.sh
```

This fetches pre-built static libraries from the [pdfium-binaries](https://github.com/ArtifexSoftware/pdfium-binaries) project for every supported target architecture. Binaries are placed in `third_party/pdfium/`.

You can control the PDFium version:

```bash
PDFIUM_VERSION=6721 ./scripts/download_pdfium.sh
```

### 2. Build for iOS

```bash
./scripts/build_ios.sh
```

Builds for:
- `arm64` — physical devices
- `x86_64` — Simulator

Output:

```
dist/ios/arm64/lib/libpdfium_wrapper.a
dist/ios/arm64/lib/libpdfium.a
dist/ios/x86_64/lib/libpdfium_wrapper.a
dist/ios/x86_64/lib/libpdfium.a
dist/include/pdfium_wrapper.h
```

### 3. Build for Android

```bash
ANDROID_NDK_HOME=/path/to/ndk ./scripts/build_android.sh
```

Or, if your NDK is at the default macOS SDK location (`~/Library/Android/sdk/ndk/<version>`), the script will find it automatically.

Set a custom minimum API level (default 21):

```bash
ANDROID_API=24 ./scripts/build_android.sh
```

Builds for:
- `arm64-v8a`
- `armeabi-v7a`
- `x86_64`
- `x86`

Output:

```
dist/android/arm64-v8a/lib/libpdfium_wrapper.a
dist/android/arm64-v8a/lib/libpdfium.a
dist/android/armeabi-v7a/lib/...
dist/android/x86_64/lib/...
dist/android/x86/lib/...
dist/include/pdfium_wrapper.h
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
```

## License

See [LICENSE](LICENSE).
