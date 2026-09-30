# 6. Style Guide & Conventions

The Newton compiler is completely agnostic to how you format or case your code. However, to maintain consistency across the ecosystem and make community packages easier to read, we highly recommend following the official Newton Style Guide.

## Functions & Macros

All user-defined functions and macros should use **lower camelCase**.

```asm
; User-defined function (lower camelCase)
fun calculateTotal: @args a, b
    return $a + $b
end

; User-defined macro (lower camelCase)
defmacro logWarning:
    @println "[WARN] {}", $M_ARGV{0}
end
```

## Global Variables

Global variables (those ending in `*`) follow two different naming conventions depending on how they are used.

### Pseudo-Constants

If a global variable acts as a constant and is never intended to be reassigned, use **UPPER_SNAKE_CASE**. Although Newton does not currently provide a `const` keyword, this convention signals to other developers that the value should remain unchanged.

```asm
; Pseudo-Constant (Never reassigned)
set MAX_BUFFER_SIZE*: 1024
```

### Mutable Globals

If a global variable represents state that changes during execution, use **lower camelCase**.

```asm
; Mutable Global State
set activeConnectionCount*: 0
```

## Local Variables

Local variables declared inside functions or other scoped blocks should use **snake_case**. This visually distinguishes local state from functions and global variables.

```asm
fun processData:
    ; Local variables in snake_case
    set user_name: "Alice"
    set retry_count: 3
end
```

## Temporary / Internal Variables

If you need a temporary or implementation-detail variable—such as a loop index or an intermediate value used within a function—surround the variable name with double underscores (`__`).

This convention makes it immediately obvious that the variable is not intended for use outside the current implementation.

```asm
fun reverseList: @args list
    ; Temporary internal array
    set __temp_arr__: []

    ; Temporary internal index
    set __idx__: (sizeof $list) - 1

    while $__idx__ >= 0:
        __temp_arr__{(sizeof $__temp_arr__)}: $list{$__idx__}
        __idx__: $__idx__ - 1
    end

    return $__temp_arr__
end
```
