#ifndef PDFIUM_WRAPPER_H
#define PDFIUM_WRAPPER_H

#ifdef __cplusplus
extern "C" {
#endif

/**
 * pdfium_wrapper.h — Minimal stable C API for PDFium rasterization.
 *
 * This wrapper exposes only the functions needed to load a PDF document
 * and render individual pages to RGBA bitmaps.
 */

/** Returned by pdfium_render_page(). Holds the pixel buffer and dimensions. */
typedef struct {
    unsigned char* data;   /* RGBA pixel buffer (owned by this struct) */
    int            width;  /* Bitmap width in pixels */
    int            height; /* Bitmap height in pixels */
    int            stride; /* Bytes per row (width * 4 for RGBA) */
} PdfiumBitmap;

/**
 * Initialize the PDFium library.  Must be called once before any other
 * wrapper function.
 */
void pdfium_init(void);

/**
 * Tear down the PDFium library.  Call once when completely done.
 */
void pdfium_destroy(void);

/**
 * Load a PDF document from a file path.
 *
 * @param path  Filesystem path to the PDF file (UTF-8).
 * @return Opaque document handle, or NULL on failure.
 */
void* pdfium_load_document(const char* path);

/**
 * Close a previously loaded document and free its resources.
 *
 * @param doc  Document handle returned by pdfium_load_document().
 */
void pdfium_close_document(void* doc);

/**
 * Render a single page to an RGBA bitmap.
 *
 * The page is scaled so that its width equals @p target_width pixels;
 * the height is computed to preserve the aspect ratio.
 *
 * @param doc          Document handle.
 * @param page_index   Zero-based page index.
 * @param target_width Desired bitmap width in pixels.
 * @return Pointer to a PdfiumBitmap, or NULL on failure.
 *         The caller must free it with pdfium_free_bitmap().
 */
void* pdfium_render_page(void* doc, int page_index, int target_width);

/**
 * Free a bitmap previously returned by pdfium_render_page().
 *
 * @param bitmap  Pointer to the PdfiumBitmap to free.
 */
void pdfium_free_bitmap(void* bitmap);

#ifdef __cplusplus
}
#endif

#endif /* PDFIUM_WRAPPER_H */
