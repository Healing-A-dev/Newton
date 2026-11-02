# 3. Functions, Scope, and TCO

Newton treats functions as first-class citizens. Functions can be called directly, passed as arguments, assigned to variables, and exported directly to external C libraries.

---

## Defining Functions and Arguments

Functions are defined using the `fun` keyword and closed with `end`.

To declare parameters, use the `@args` macro immediately after the function declaration. Multiple arguments are separated by commas:

```crystal
fun greetUser: @args name, role
    @println "Welcome back, {}! Your role is: {}", $name, $role
end

fun calculateTotal: @args price, quantity, tax_rate
    set subtotal: $price * $quantity
    set total: $subtotal + ($subtotal * $tax_rate)
    return $total
end

fun main:
    greetUser "Alice", "Admin"
    set total: calculateTotal 100, 2, 0.05
    @println "Final Total: {}", $total
end
```

### Parameter-Free Functions

Functions that do not take arguments omit the `@args` statement entirely:

```crystal
fun printHeader:
    @println "=============================="
    @println "   Newton Application v1.0    "
    @println "=============================="
end

fun main:
    printHeader
end
```

---

## Return Values

Use the `return` keyword to pass values back to the caller:

```crystal
fun add: @args a, b
    return $a + $b
end

fun getStatus:
    return "ready"
end
```

If a function reaches `end` without an explicit `return`, it implicitly returns 0 (false).

---

## Scope and Lifetime

Variables declared with `set` inside a function are strictly local to that function. Local variables live in the function's stack frame and are destroyed upon returning.

```crystal
fun compute:
    set local_val: 42
    @println "Local value: {}", $local_val
end

fun main:
    compute
    ; $local_val is not accessible here
end
```

---

## Exporting Functions to C (`exposed fun`)

To make a Newton function callable from external C libraries or native host code, use the `exposed fun` keyword:

```crystal
exposed fun newton_add: @args a, b
    @println "[Newton] Adding {} and {}...", $a, $b
    return $a + $b
end
```

When you declare an `exposed fun`:
1. The compiler emits a globally visible symbol named `F_<name>` (e.g. `F_newton_add`).
2. Arguments are passed via standard CDECL stack conventions (pushed right-to-left).
3. The return value is placed in the `%rax` register.
4. C code can invoke the function directly using Newton's integration macros:
   ```c
   #include <newton.h>
   extern void F_newton_add(void);

   int64_t res = NEWTON_CALL_2(F_newton_add, NEWTON_BOX_INT(10), NEWTON_BOX_INT(20));
   printf("Result from Newton: %ld\n", NEWTON_INT(res)); // Prints 30
   ```

*(See Chapter 7 for complete documentation on C FFI integration).*

---

## Tail Call Optimization (TCO)

One of Newton's signature architectural features is AST-level Tail Call Optimization (TCO).

When a function calls itself as its final action (a *tail call*), Newton's compiler optimizes the call into an in-place hardware jump (`JMP`), completely reusing the existing stack frame.

This allows you to write recursive algorithms without risk of stack overflow:

```crystal
fun countdown: @args n
    if $n == 0:
        @println "Liftoff!"
        return 0
    end

    ; Tail call: compiler replaces this with a flat jump!
    return countdown $n - 1
end

fun main:
    ; Executes in O(1) stack space:
    countdown 1000000
end
```

---

Next: [4. Meta-Programming](04_Meta-Programming.md)

