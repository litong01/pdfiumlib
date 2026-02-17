/*
 * Minimal string.h for iOS cross-compilation from Linux.
 * Only declares the functions used by pdfium_wrapper.c.
 */
#ifndef _CROSS_STRING_H
#define _CROSS_STRING_H

#include <stddef.h> /* size_t — provided by clang built-ins */

extern void *memset(void *__s, int __c, size_t __n);
extern void *memcpy(void *__dest, const void *__src, size_t __n);

#endif
