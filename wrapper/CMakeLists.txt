cmake_minimum_required(VERSION 3.18)

# ---------------------------------------------------------------------------
# pdfium_wrapper — thin C API around PDFium
# ---------------------------------------------------------------------------

add_library(pdfium_wrapper STATIC
    pdfium_wrapper.c
)

target_include_directories(pdfium_wrapper
    PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}         # pdfium_wrapper.h
        ${PDFIUM_ROOT}/include              # fpdfview.h, fpdf_doc.h, …
)

target_link_libraries(pdfium_wrapper
    PRIVATE pdfium
)

# ---------------------------------------------------------------------------
# Install rules — used by the build scripts to populate dist/
# ---------------------------------------------------------------------------

install(TARGETS pdfium_wrapper
    ARCHIVE DESTINATION lib
)

install(FILES pdfium_wrapper.h
    DESTINATION include
)
