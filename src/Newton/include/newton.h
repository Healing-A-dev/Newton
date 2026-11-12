/*
 * Newton C FFI Header (newton.h)
 * -------------------------------------------------------------
 * Provides ABI definitions, type-tagging macros, collection
 * inspection helpers, and caller macros to invoke exposed Newton
 * functions from C.
 */

#ifndef NEWTON_H
#define NEWTON_H

#include <stdint.h>
#include <stddef.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

/* =============================================================
 * Type Tagging & Unboxing / Boxing
 * =============================================================
 */

#define NEWTON_IS_INT(v)      (((uintptr_t)(v) & 1) != 0)
#define NEWTON_IS_PTR(v)      (((uintptr_t)(v) & 1) == 0 && (v) != 0)
#define NEWTON_INT(v)         (((int64_t)(v)) >> 1)
#define NEWTON_BOX_INT(v)     ((((int64_t)(v)) << 1) | 1)
#define NEWTON_STR(v)         ((const char*)(v))


/* =============================================================
 * Newton Arrays / Lists Inspection
 * =============================================================
 */

/**
 * In Newton's runtime (linux64/types.s):
 * Array pointer 'arr' points to offset 8 of the allocated block.
 * - offset -8: .quad 3 (type tag for array)
 * - offset  0: .quad length
 * - offset  8: .quad capacity
 * - offset 16: pointer to data buffer (tag 7, elements 0..length-1)
 */

static inline int64_t newton_array_len(const void *arr) {
    if (!arr) return 0;
    return *(const int64_t*)arr;
}

static inline int64_t newton_array_get_raw(const void *arr, int64_t index) {
    if (!arr) return 0;
    const int64_t *p = (const int64_t*)arr;
    if (index < 0 || index >= p[0]) return 0;
    const int64_t *data = (const int64_t*)p[2];
    if (!data) return 0;
    return data[index];
}

static inline int64_t newton_array_get_int(const void *arr, int64_t index) {
    int64_t raw = newton_array_get_raw(arr, index);
    return NEWTON_INT(raw);
}

static inline const char* newton_array_get_str(const void *arr, int64_t index) {
    int64_t raw = newton_array_get_raw(arr, index);
    return NEWTON_STR(raw);
}


/* =============================================================
 * Newton Maps Inspection
 * =============================================================
 */

/*
 * In Newton's runtime (linux64/types.s):
 * Map pointer points to head pointer: *(newton_node_t**)map.
 * Each node in the map:
 * - offset  0: key (tagged int or string pointer)
 * - offset  8: value (tagged int or string/collection pointer)
 * - offset 16: next node pointer
 */

typedef struct newton_node {
    int64_t key;
    int64_t val;
    struct newton_node *next;
} newton_node_t;

static inline newton_node_t* newton_map_head(const void *map) {
    if (!map) return NULL;
    return *(newton_node_t**)map;
}

static inline int64_t newton_map_find_raw(const void *map, const char *key_str) {
    newton_node_t *node = newton_map_head(map);
    while (node) {
        if (!NEWTON_IS_INT(node->key) && node->key != 0) {
            const char *curr_key = NEWTON_STR(node->key);
            if (strcmp(curr_key, key_str) == 0) {
                return node->val;
            }
        }
        node = node->next;
    }
    return 0;
}


/* =============================================================
 * Calling Exposed Newton Functions from C
 * =============================================================
 * Functions exposed in Newton via `exposed fun <name>:` are compiled
 * to global symbols `F_<name>`.
 * Newton functions use stack-based argument passing (arguments pushed
 * right-to-left) with caller stack cleanup and return value in %rax.
 */

static inline int64_t newton_call_0(void *fn) {
    int64_t ret;
    __asm__ volatile (
        "call *%1\n\t"
        : "=a"(ret)
        : "r"(fn)
        : "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11", "memory"
    );
    return ret;
}

static inline int64_t newton_call_1(void *fn, int64_t a) {
    int64_t ret;
    __asm__ volatile (
        "pushq %1\n\t"
        "call *%2\n\t"
        "addq $8, %%rsp\n\t"
        : "=a"(ret)
        : "r"(a), "r"(fn)
        : "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11", "memory"
    );
    return ret;
}

static inline int64_t newton_call_2(void *fn, int64_t a, int64_t b) {
    int64_t ret;
    __asm__ volatile (
        "pushq %2\n\t"
        "pushq %1\n\t"
        "call *%3\n\t"
        "addq $16, %%rsp\n\t"
        : "=a"(ret)
        : "r"(a), "r"(b), "r"(fn)
        : "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11", "memory"
    );
    return ret;
}

static inline int64_t newton_call_3(void *fn, int64_t a, int64_t b, int64_t c) {
    int64_t ret;
    __asm__ volatile (
        "pushq %3\n\t"
        "pushq %2\n\t"
        "pushq %1\n\t"
        "call *%4\n\t"
        "addq $24, %%rsp\n\t"
        : "=a"(ret)
        : "r"(a), "r"(b), "r"(c), "r"(fn)
        : "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11", "memory"
    );
    return ret;
}

static inline int64_t newton_call_4(void *fn, int64_t a, int64_t b, int64_t c, int64_t d) {
    int64_t ret;
    __asm__ volatile (
        "pushq %4\n\t"
        "pushq %3\n\t"
        "pushq %2\n\t"
        "pushq %1\n\t"
        "call *%5\n\t"
        "addq $32, %%rsp\n\t"
        : "=a"(ret)
        : "r"(a), "r"(b), "r"(c), "r"(d), "r"(fn)
        : "rcx", "rdx", "rsi", "rdi", "r8", "r9", "r10", "r11", "memory"
    );
    return ret;
}

#define NEWTON_CALL_0(fn)             newton_call_0((void*)(fn))
#define NEWTON_CALL_1(fn, a)          newton_call_1((void*)(fn), (int64_t)(a))
#define NEWTON_CALL_2(fn, a, b)       newton_call_2((void*)(fn), (int64_t)(a), (int64_t)(b))
#define NEWTON_CALL_3(fn, a, b, c)    newton_call_3((void*)(fn), (int64_t)(a), (int64_t)(b), (int64_t)(c))
#define NEWTON_CALL_4(fn, a, b, c, d) newton_call_4((void*)(fn), (int64_t)(a), (int64_t)(b), (int64_t)(c), (int64_t)(d))

#ifdef __cplusplus
}
#endif
#endif

