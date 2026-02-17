/*
 * Minimal stdlib.h for iOS cross-compilation from Linux.
 * Only declares the functions used by pdfium_wrapper.c.
 */
#ifndef _CROSS_STDLIB_H
#define _CROSS_STDLIB_H

#include <stddef.h> /* size_t, NULL — provided by clang built-ins */

extern void *malloc(size_t __size);
extern void  free(void *__ptr);

#endif
