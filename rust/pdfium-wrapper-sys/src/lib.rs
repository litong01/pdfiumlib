//! Raw FFI bindings to `pdfium_wrapper` — a minimal C wrapper around PDFium.
//!
//! # Setup
//!
//! Set the `PDFIUM_LIB_DIR` environment variable to the path containing the
//! libraries for your target architecture, e.g.:
//!
//! ```sh
//! export PDFIUM_LIB_DIR=/path/to/pdf-engine/android/arm64-v8a/lib
//! cargo build --target aarch64-linux-android
//! ```
//!
//! # Safety
//!
//! All functions in this crate are `unsafe extern "C"` — they call directly
//! into C code with no Rust-side validation.

#![allow(non_camel_case_types)]

use std::os::raw::{c_char, c_int, c_uchar, c_void};

/// RGBA bitmap returned by [`pdfium_render_page`].
///
/// The `data` pointer is owned by the C side — free it with
/// [`pdfium_free_bitmap`].
#[repr(C)]
pub struct PdfiumBitmap {
    /// RGBA pixel buffer (width × height × 4 bytes).
    pub data: *mut c_uchar,
    /// Bitmap width in pixels.
    pub width: c_int,
    /// Bitmap height in pixels.
    pub height: c_int,
    /// Bytes per row (`width * 4` for RGBA).
    pub stride: c_int,
}

extern "C" {
    /// Initialize the PDFium library.  Must be called once before any other
    /// wrapper function.
    pub fn pdfium_init();

    /// Tear down the PDFium library.  Call once when completely done.
    pub fn pdfium_destroy();

    /// Load a PDF document from a file path.
    ///
    /// Returns an opaque document handle, or null on failure.
    pub fn pdfium_load_document(path: *const c_char) -> *mut c_void;

    /// Close a previously loaded document and free its resources.
    pub fn pdfium_close_document(doc: *mut c_void);

    /// Render a single page to an RGBA bitmap.
    ///
    /// `target_width` controls the output width in pixels; height is computed
    /// to preserve the page's aspect ratio.
    ///
    /// Returns a pointer to a [`PdfiumBitmap`], or null on failure.
    /// The caller must free it with [`pdfium_free_bitmap`].
    pub fn pdfium_render_page(
        doc: *mut c_void,
        page_index: c_int,
        target_width: c_int,
    ) -> *mut PdfiumBitmap;

    /// Free a bitmap previously returned by [`pdfium_render_page`].
    pub fn pdfium_free_bitmap(bitmap: *mut c_void);
}
