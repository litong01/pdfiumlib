cmake_minimum_required(VERSION 3.18)
project(pdf_engine C)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Path to the pre-built PDFium distribution (set by the build scripts).
# Expected layout:
#   PDFIUM_ROOT/lib/libpdfium.so    (Android)
#   PDFIUM_ROOT/lib/libpdfium.dylib (iOS)
#   PDFIUM_ROOT/include/            (public headers: fpdfview.h, fpdf_doc.h, …)
if(NOT DEFINED PDFIUM_ROOT)
    message(FATAL_ERROR "PDFIUM_ROOT must be set (path to pre-built PDFium)")
endif()

# ---------------------------------------------------------------------------
# Import pre-built PDFium as a shared library
# ---------------------------------------------------------------------------

add_library(pdfium SHARED IMPORTED)

if(ANDROID)
    set(_pdfium_lib "${PDFIUM_ROOT}/lib/libpdfium.so")
elseif(CMAKE_SYSTEM_NAME STREQUAL "iOS" OR CMAKE_SYSTEM_NAME STREQUAL "Darwin")
    set(_pdfium_lib "${PDFIUM_ROOT}/lib/libpdfium.dylib")
else()
    # Fallback: try .so first, then .dylib
    if(EXISTS "${PDFIUM_ROOT}/lib/libpdfium.so")
        set(_pdfium_lib "${PDFIUM_ROOT}/lib/libpdfium.so")
    else()
        set(_pdfium_lib "${PDFIUM_ROOT}/lib/libpdfium.dylib")
    endif()
endif()

set_target_properties(pdfium PROPERTIES
    IMPORTED_LOCATION "${_pdfium_lib}"
    INTERFACE_INCLUDE_DIRECTORIES "${PDFIUM_ROOT}/include"
)

# ---------------------------------------------------------------------------
# Wrapper library
# ---------------------------------------------------------------------------

add_subdirectory(wrapper)
