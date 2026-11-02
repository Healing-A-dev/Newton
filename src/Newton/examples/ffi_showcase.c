/**
 * ffi_showcase.c
 * -------------------------------------------------------------
 * Demonstrates how C integrates with Newton using newton.h:
 * 1. Primitive arithmetic and strings.
 * 2. Receiving and inspecting Newton arrays (lists).
 * 3. Receiving and inspecting Newton maps.
 * 4. Invoking exposed Newton functions from C with arguments.
 */

#include <stdio.h>
#include <math.h>
#include "../include/newton.h"

int64_t c_add(int64_t a, int64_t b) {
    int64_t x = NEWTON_INT(a);
    int64_t y = NEWTON_INT(b);
    printf("[C] c_add: %ld + %ld = %ld\n", x, y, x + y);
    return x + y;
}

void c_greet(const char *name) {
    printf("[C] Hello %s from C!\n", NEWTON_STR(name));
}

int64_t c_hypot(int64_t a, int64_t b) {
    double x = (double)NEWTON_INT(a);
    double y = (double)NEWTON_INT(b);
    double res = hypot(x, y);
    printf("[C] c_hypot(%f, %f) = %f\n", x, y, res);
    return (int64_t)res;
}

int64_t c_sum_array(void *arr) {
    int64_t len = newton_array_len(arr);
    printf("[C] c_sum_array: received array of length %ld\n", len);
    int64_t sum = 0;
    for (int64_t i = 0; i < len; i++) {
        int64_t val = newton_array_get_int(arr, i);
        printf("[C]   arr[%ld] = %ld\n", i, val);
        sum += val;
    }
    return sum;
}

void c_print_map(void *map) {
    newton_node_t *node = newton_map_head(map);
    printf("[C] c_print_map: iterating key-value entries\n");
    while (node) {
        if (!NEWTON_IS_INT(node->key) && node->key != 0) {
            printf("[C]   \"%s\" => ", NEWTON_STR(node->key));
        } else {
            printf("[C]   %ld => ", NEWTON_INT(node->key));
        }

        if (NEWTON_IS_INT(node->val)) {
            printf("%ld (int)\n", NEWTON_INT(node->val));
        } else {
            printf("\"%s\" (string)\n", NEWTON_STR(node->val));
        }
        node = node->next;
    }
}

extern void F_newton_multiply(void);

int64_t c_call_multiply(int64_t a, int64_t b) {
    printf("[C] Calling Newton function F_newton_multiply(%ld, %ld)...\n", NEWTON_INT(a), NEWTON_INT(b));
    int64_t boxed_result = NEWTON_CALL_2(F_newton_multiply, a, b);
    int64_t unboxed_result = NEWTON_INT(boxed_result);
    printf("[C] Newton returned: %ld\n", unboxed_result);
    return unboxed_result;
}

