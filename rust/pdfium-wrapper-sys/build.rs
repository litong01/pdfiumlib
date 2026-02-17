use std::env;
use std::path::PathBuf;

fn main() {
    // ── Locate the library directory ─────────────────────────────────────
    //
    // Priority:
    //   1. PDFIUM_LIB_DIR environment variable  (explicit override)
    //   2. Auto-detect from PDFIUM_ROOT + Cargo target triple

    let lib_dir = if let Ok(dir) = env::var("PDFIUM_LIB_DIR") {
        PathBuf::from(dir)
    } else if let Ok(root) = env::var("PDFIUM_ROOT") {
        let target = env::var("TARGET").unwrap();
        let subdir = target_to_subdir(&target);
        PathBuf::from(root).join(subdir).join("lib")
    } else {
        panic!(
            "\n\
            ╔══════════════════════════════════════════════════════════════╗\n\
            ║  pdfium-wrapper-sys: cannot find native libraries.         ║\n\
            ║                                                            ║\n\
            ║  Set one of:                                               ║\n\
            ║    PDFIUM_LIB_DIR=/path/to/<arch>/lib                      ║\n\
            ║    PDFIUM_ROOT=/path/to/extracted/pdf-engine                ║\n\
            ╚══════════════════════════════════════════════════════════════╝\n"
        );
    };

    if !lib_dir.exists() {
        panic!(
            "pdfium-wrapper-sys: library directory does not exist: {}",
            lib_dir.display()
        );
    }

    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rustc-link-lib=static=pdfium_wrapper");
    println!("cargo:rustc-link-lib=dylib=pdfium");

    // Re-run if the env vars change.
    println!("cargo:rerun-if-env-changed=PDFIUM_LIB_DIR");
    println!("cargo:rerun-if-env-changed=PDFIUM_ROOT");
}

/// Map a Cargo target triple to the subdirectory inside the pdf-engine bundle.
fn target_to_subdir(target: &str) -> &'static str {
    match target {
        // Android
        "aarch64-linux-android" => "android/arm64-v8a",
        "armv7-linux-androideabi" => "android/armeabi-v7a",
        "x86_64-linux-android" => "android/x86_64",
        "i686-linux-android" => "android/x86",

        // iOS
        "aarch64-apple-ios" => "ios/arm64",
        "x86_64-apple-ios" => "ios/x86_64",
        "aarch64-apple-ios-sim" => "ios/x86_64", // arm64 simulator uses same libs

        _ => panic!(
            "pdfium-wrapper-sys: unsupported target '{}'. \
             Set PDFIUM_LIB_DIR manually.",
            target
        ),
    }
}
