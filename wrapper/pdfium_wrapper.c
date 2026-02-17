#include "pdfium_wrapper.h"

#include <stdlib.h>
#include <string.h>
#include <math.h>

/* PDFium public headers */
#include "fpdfview.h"
#include "fpdf_doc.h"

/* ------------------------------------------------------------------ */
/*  Lifecycle                                                         */
/* ------------------------------------------------------------------ */

void pdfium_init(void) {
    FPDF_LIBRARY_CONFIG config;
    memset(&config, 0, sizeof(config));
    config.version = 2;
    FPDF_InitLibraryWithConfig(&config);
}

void pdfium_destroy(void) {
    FPDF_DestroyLibrary();
}

/* ------------------------------------------------------------------ */
/*  Document                                                          */
/* ------------------------------------------------------------------ */

void* pdfium_load_document(const char* path) {
    if (!path) return NULL;
    FPDF_DOCUMENT doc = FPDF_LoadDocument(path, NULL);
    return (void*)doc;
}

void pdfium_close_document(void* doc) {
    if (doc) {
        FPDF_CloseDocument((FPDF_DOCUMENT)doc);
    }
}

/* ------------------------------------------------------------------ */
/*  Rendering                                                         */
/* ------------------------------------------------------------------ */

void* pdfium_render_page(void* doc, int page_index, int target_width) {
    if (!doc || target_width <= 0) return NULL;

    FPDF_DOCUMENT pdf_doc = (FPDF_DOCUMENT)doc;
    int page_count = FPDF_GetPageCount(pdf_doc);
    if (page_index < 0 || page_index >= page_count) return NULL;

    FPDF_PAGE page = FPDF_LoadPage(pdf_doc, page_index);
    if (!page) return NULL;

    double page_width  = FPDF_GetPageWidth(page);
    double page_height = FPDF_GetPageHeight(page);
    if (page_width <= 0.0 || page_height <= 0.0) {
        FPDF_ClosePage(page);
        return NULL;
    }

    double scale = (double)target_width / page_width;
    int bmp_width  = target_width;
    int bmp_height = (int)ceil(page_height * scale);
    int stride     = bmp_width * 4; /* RGBA = 4 bytes per pixel */

    /* Create PDFium bitmap */
    FPDF_BITMAP bitmap = FPDFBitmap_Create(bmp_width, bmp_height, 1 /* alpha */);
    if (!bitmap) {
        FPDF_ClosePage(page);
        return NULL;
    }

    /* Fill with white + full alpha */
    FPDFBitmap_FillRect(bitmap, 0, 0, bmp_width, bmp_height, 0xFFFFFFFF);

    /* Render page into bitmap */
    FPDF_RenderPageBitmap(
        bitmap, page,
        0, 0,             /* x, y offset */
        bmp_width, bmp_height,
        0,                /* rotation (0 = normal) */
        FPDF_ANNOT | FPDF_PRINTING
    );

    /* Copy pixel data out of PDFium's internal buffer */
    void* src = FPDFBitmap_GetBuffer(bitmap);
    size_t buf_size = (size_t)stride * (size_t)bmp_height;
    unsigned char* pixels = (unsigned char*)malloc(buf_size);
    if (!pixels) {
        FPDFBitmap_Destroy(bitmap);
        FPDF_ClosePage(page);
        return NULL;
    }
    memcpy(pixels, src, buf_size);

    /*
     * PDFium renders in BGRA order.  Convert to RGBA by swapping R and B
     * for every pixel.
     */
    for (size_t i = 0; i < buf_size; i += 4) {
        unsigned char tmp = pixels[i];       /* B */
        pixels[i]     = pixels[i + 2];      /* R -> slot 0 */
        pixels[i + 2] = tmp;                /* B -> slot 2 */
    }

    FPDFBitmap_Destroy(bitmap);
    FPDF_ClosePage(page);

    /* Build the result struct */
    PdfiumBitmap* result = (PdfiumBitmap*)malloc(sizeof(PdfiumBitmap));
    if (!result) {
        free(pixels);
        return NULL;
    }
    result->data   = pixels;
    result->width  = bmp_width;
    result->height = bmp_height;
    result->stride = stride;

    return (void*)result;
}

void pdfium_free_bitmap(void* bitmap) {
    if (!bitmap) return;
    PdfiumBitmap* bmp = (PdfiumBitmap*)bitmap;
    free(bmp->data);
    free(bmp);
}
