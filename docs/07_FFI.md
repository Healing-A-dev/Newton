# 7. C Foreign Function Interface (FFI)

Newton provides a high-performance, bidirectional Foreign Function Interface (FFI) with C. You can call arbitrary C library functions from Newton, pass strings, numbers, and native collections, and expose Newton functions back to C.

---

## Calling C Functions from Newton

In Newton, any function name prefixed with `#` invokes an external C symbol:

```crystal
fun main:
    ; Calls C function 'c_greet' with a string argument
    #c_greet "Newton Developer"

    ; Calls C function 'c_add' and captures the return value
    set result: #c_add 10, 20
    @println "Result from C: {}", $result
end
```

### Argument Passing & Calling Convention

When calling a `#c_function`:
- On **Linux x86_64** (System V AMD64 ABI), the first 6 arguments are placed in hardware registers:
  `%rdi`, `%rsi`, `%rdx`, `%rcx`, `%r8`, `%r9`.
- GravityVM wraps the call with an FFI shield that aligns the stack to 16 bytes (`and $-16, %rsp`) and preserves callee-saved registers (`%r15`).
- The return value in `%rax` is automatically tagged as a Newton integer.

---

## Compiling & Linking C Code

To compile and link external C code with your Newton program:

### 1. Compile the C Source to an Object File

```bash
gcc -c -fPIC -Isrc/Newton/include -o my_c_lib.o my_c_lib.c
```

### 2. Compile and Run with Newton

Use the `-l` flag to link the object file and `--link-C` to include the standard C runtime (libc, libm, and dynamic linker):

```bash
# Compile and run immediately:
newton run main.nt -l my_c_lib.o --link-C

# Or compile to a standalone executable:
newton build main.nt -o my_app -l my_c_lib.o --link-C
./my_app
```

> **Tip:** If your C library depends on libraries in custom directories, use the `-L <dir>` flag to supply library search directories.

---

## The Integration Header: `newton.h`

Newton provides a canonical C header located at `src/Newton/include/newton.h` (and installed globally to `~/.newton/include/newton.h`). Include this header in your C code:

```c
#include <newton.h>
```

### 1. Integer Tagging & Conversions

Newton represents integers as tagged values: `(val << 1) | 1`. GravityVM's FFI automatically re-tags the return value from C. When receiving integer arguments from Newton in C, use the unboxing macros:

| Macro | Description |
|---|---|
| `NEWTON_INT(v)` | Unboxes a Newton tagged integer to a native C `int64_t`. |
| `NEWTON_BOX_INT(v)` | Boxes a native C `int64_t` into a Newton tagged integer. |
| `NEWTON_IS_INT(v)` | Returns non-zero if the value is a tagged integer. |
| `NEWTON_IS_PTR(v)` | Returns non-zero if the value is a heap pointer. |

```c
#include <newton.h>

int64_t c_add(int64_t a, int64_t b) {
    int64_t x = NEWTON_INT(a);
    int64_t y = NEWTON_INT(b);
    return x + y; /* GravityVM ETRN tags this return value automatically */
}
```

### 2. String Handling

In Newton's runtime, string values are heap pointers that point directly to null-terminated ASCII/UTF-8 character buffers:

| Macro | Description |
|---|---|
| `NEWTON_STR(v)` | Casts the Newton string argument to a C `const char*`. |

```c
#include <stdio.h>
#include <newton.h>

void c_greet(const char *name) {
    printf("Hello %s from C!\n", NEWTON_STR(name));
}
```

---

## Passing Newton Collections to C

Newton collections (arrays/lists and maps) can be passed directly as arguments to C functions. `newton.h` provides helper inspection functions to read collection lengths and elements.

### 1. Arrays and Lists

In Newton, lists are flat memory buffers where offset 0 contains the length and offset `8 + (i * 8)` contains element `i`.

| Function | Signature | Description |
|---|---|---|
| `newton_array_len` | `int64_t newton_array_len(const void *arr)` | Returns the element count. |
| `newton_array_get_raw` | `int64_t newton_array_get_raw(const void *arr, int64_t idx)` | Returns the raw 64-bit element. |
| `newton_array_get_int` | `int64_t newton_array_get_int(const void *arr, int64_t idx)` | Returns the unboxed integer element. |
| `newton_array_get_str` | `const char* newton_array_get_str(const void *arr, int64_t idx)` | Returns the element as a C string. |

#### C Example:

```c
#include <stdio.h>
#include <newton.h>

int64_t c_sum_array(void *arr) {
    int64_t len = newton_array_len(arr);
    int64_t sum = 0;
    for (int64_t i = 0; i < len; i++) {
        sum += newton_array_get_int(arr, i);
    }
    return sum;
}
```

#### Newton Caller:

```crystal
fun main:
    set numbers: [5, 10, 15, 20]
    set sum: #c_sum_array $numbers
    @println "Array Sum: {}", $sum ; Output: 50
end
```

### 2. Maps (Key-Value)

In Newton, maps are represented as linked lists of key-value nodes. `newton.h` exposes the node structure:

```c
typedef struct newton_node {
    int64_t key;
    int64_t val;
    struct newton_node *next;
} newton_node_t;
```

| Function | Signature | Description |
|---|---|---|
| `newton_map_head` | `newton_node_t* newton_map_head(const void *map)` | Returns the head node of the map. |
| `newton_map_find_raw` | `int64_t newton_map_find_raw(const void *map, const char *key)` | Looks up a value by string key. |

#### C Example:

```c
#include <stdio.h>
#include <newton.h>

void c_inspect_map(void *map) {
    newton_node_t *curr = newton_map_head(map);
    while (curr) {
        if (!NEWTON_IS_INT(curr->key)) {
            printf("Key: %s => ", NEWTON_STR(curr->key));
        } else {
            printf("Key: %ld => ", NEWTON_INT(curr->key));
        }

        if (NEWTON_IS_INT(curr->val)) {
            printf("%ld (int)\n", NEWTON_INT(curr->val));
        } else {
            printf("\"%s\" (string)\n", NEWTON_STR(curr->val));
        }
        curr = curr->next;
    }
}
```

#### Newton Caller:

```crystal
fun main:
    set config: (app: "Newton", version: 1, active: 1)
    #c_inspect_map $config
end
```

---

## Calling Newton Functions from C (Callbacks)

You can expose Newton functions so they can be invoked directly from C code.

### Step 1: Declare the Newton Function as `exposed`

```crystal
exposed fun newton_multiply: @args a, b
    @println "  [Newton Callback] Computing {} * {}", $a, $b
    return $a * $b
end
```

When declared with `exposed fun`, the compiler creates a global symbol named `F_<name>` (e.g., `F_newton_multiply`). Newton functions expect arguments passed on the stack (CDECL convention) and return results in `%rax`.

### Step 2: Invoke from C Using `NEWTON_CALL`

`newton.h` provides safe calling macros that push arguments right-to-left onto the stack, call the function pointer, and restore the stack pointer:

| Macro | Signature |
|---|---|
| `NEWTON_CALL_0(fn)` | Calls an exposed Newton function with 0 arguments. |
| `NEWTON_CALL_1(fn, a)` | Calls an exposed Newton function with 1 argument. |
| `NEWTON_CALL_2(fn, a, b)` | Calls an exposed Newton function with 2 arguments. |
| `NEWTON_CALL_3(fn, a, b, c)` | Calls an exposed Newton function with 3 arguments. |
| `NEWTON_CALL_4(fn, a, b, c, d)` | Calls an exposed Newton function with 4 arguments. |

```c
#include <stdio.h>
#include <newton.h>

extern void F_newton_multiply(void);

int64_t c_run_multiplier(int64_t x, int64_t y) {
    /* Pass arguments as Newton tagged integers */
    int64_t boxed_result = NEWTON_CALL_2(F_newton_multiply, x, y);
    int64_t unboxed_result = NEWTON_INT(boxed_result);
    printf("[C] Result from Newton callback: %ld\n", unboxed_result);
    return unboxed_result;
}
```

---

## Complete Working Showcase

See the working showcase in the repository:
- C Implementation: [`src/Newton/examples/ffi_showcase.c`](../src/Newton/examples/ffi_showcase.c)
- Newton Program: [`src/Newton/examples/ffi_showcase.nt`](../src/Newton/examples/ffi_showcase.nt)

Run the showcase:

```bash
gcc -c -fPIC -Isrc/Newton/include -o src/Newton/examples/ffi_showcase.o src/Newton/examples/ffi_showcase.c
./src/Newton/newton run src/Newton/examples/ffi_showcase.nt -l src/Newton/examples/ffi_showcase.o --link-C
```

---

Next: [8. Web & Networking](08_Web_and_Networking.md)

