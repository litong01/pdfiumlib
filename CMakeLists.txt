cmake_minimum_required(VERSION 3.18)
project(pdf_engine C)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Path to the pre-built PDFium distribution (set by the build scripts).
# Expected layout:
#   PDFIUM_ROOT/lib/libpdfium.a   (static library)
#   PDFIUM_ROOT/include/           (public headers: fpdfview.h, fpdf_doc.h, …)
if(NOT DEFINED PDFIUM_ROOT)
    message(FATAL_ERROR "PDFIUM_ROOT must be set (path to pre-built PDFium)")
endif()

# ---------------------------------------------------------------------------
# Import pre-built PDFium as a static library
# ---------------------------------------------------------------------------

add_library(pdfium STATIC IMPORTED)
set_target_properties(pdfium PROPERTIES
    IMPORTED_LOCATION "${PDFIUM_ROOT}/lib/libpdfium.a"
    INTERFACE_INCLUDE_DIRECTORIES "${PDFIUM_ROOT}/include"
)

# ---------------------------------------------------------------------------
# Wrapper library
# ---------------------------------------------------------------------------

add_subdirectory(wrapper)
