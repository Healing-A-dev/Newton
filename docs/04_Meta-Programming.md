# 4. Advanced Meta-Programming

While Newton's runtime is built for bare-metal execution speed, its compiler provides powerful AST-level meta-programming. This allows developers to write highly dynamic, variadic code that resolves entirely at compile time, resulting in zero runtime overhead.

## The Macro System (`defmacro`)

Standard functions in Newton map directly to hardware-level `CALL` instructions, which require a strict, fixed number of arguments. To bypass this limitation and create flexible APIs, Newton provides the `defmacro` keyword.

Macros are expanded by the compiler before the Virtual Machine ever sees them. To distinguish a macro from a standard function during execution, **macros must be invoked using the `@` prefix**.

```asm
defmacro logBuild:
    IO.println "[BUILD STEP COMPLETED]"
end

fun main:
    ; Standard function call
    compileFiles

    ; Macro invocation requires the '@' prefix
    @logBuild
end
```

## Variadic Arguments and `$M_ARGV`

Because macros do not have a strict `@args` signature, they can accept any number of arguments. Inside a macro, those arguments are automatically packed into a special compile-time array called `$M_ARGV`.

By checking `sizeof $M_ARGV`, you can create highly flexible APIs. The Newton Standard Library relies heavily on this mechanism for macros such as `@println` and `@assert`.

### Example: The `@assert` Macro

Here is a simplified version of Newton's native `@assert` macro. Notice how it uses `$M_ARGV{0}` for the condition and `$M_ARGV{1}` for the optional error message.

```asm
defmacro assert:
    ; Extract the first two arguments from the variadic array
    set stmt: $M_ARGV{0}
    set on_err: $M_ARGV{1}

    ; If the statement evaluates to false (0), handle the error
    if $stmt == 0:
        return ["error", "Failed assertion: " << $on_err]
    end

    return ["ok", 1]
end

fun main:
    set user_age: 16

    ; Calling the macro with two arguments
    @assert ($user_age >= 18), "User is an adult!"
end
```

## Prefix Operators (Zero-Desugar)

Newton's AST handles specific prefix operators directly rather than relying on standard function calls or complex desugaring routines.

When you use a negative sign (`-`) in front of a number, or the `not` keyword in front of a boolean expression, the compiler optimizes these operations directly at the AST level. This ensures that fundamental operations—such as negating a loop counter or inverting a state flag—are processed efficiently without introducing unnecessary runtime overhead.

```asm
fun main:
    set is_valid: 1

    ; The 'not' operator is handled directly by the AST
    if not $is_valid:
        @println "Invalid state."
    end

    ; Negative numbers are parsed natively
    set offset: -50
end
```
