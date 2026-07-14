# 3. Functions, Scope, and TCO

Newton treats functions as first-class citizens. Thanks to the `Base.nt` prelude, core modules like `IO`, `String`, and `File` are automatically included in every project (unless you compile with `--noStdlib`), keeping your code clean and free of boilerplate.

## Defining Functions and Arguments

Functions are defined using the `fun` keyword and closed with `end`.

To define parameters, use the `@args` macro immediately after the function declaration. Multiple arguments are separated by commas.

```asm


fun greet_user: @args name, role
    @println "Welcome back, {}! Your role is: {}", $name, $role
end

fun example:
    ; This is also valid function declaration syntax (although not preferd).
    ; As long @args is the first uncommented line of code within the function, it is valid.
    @args arg1, arg2, arg3

    ; <Documentation Stuff>
    @println "{} {} {}", $arg1, $arg2, $arg3
end

fun main:
    ; Calling a statically defined function
    greet_user "Alice", "Admin"
    example "Foo", "Bar", "Baz"
end
```

## Scope and Empty Blocks

By default, any variable declared inside a function (using `set`) is strictly scoped to that function. It is destroyed when the function returns, ensuring Newton's memory footprint remains incredibly low.

If you need to define an empty function or an empty `if` block (for example, while scaffolding a project), you can leave it entirely blank. Optionally, you can use the `pass` function provided by the standard library.

```asm
fun future_feature:
end

fun main:
    set data: "pending"

    if $data == "pending":
        pass
    else:
        @println "Processing data..."
    end
end
```

## Tail Call Optimization (TCO)

One of Newton's most powerful architectural features is AST-level Tail Call Optimization (TCO).

In most languages, recursive functions add a new frame to the call stack every time they recurse, eventually causing a stack overflow. Newton's compiler detects when a function calls itself as its final action (a *tail call*) and transforms it into a highly optimized hardware `JMP` instruction.

This means you can write deeply recursive functions in Newton without consuming additional stack frames, allowing recursion that would overflow the stack in many other languages.

```asm
fun countdown: @args n
    if $n == 0:
        @println "Liftoff!"
        return [@ok, 1]
    end

    ; Because this is the very last operation, the Newton compiler
    ; optimizes it into a flat jump. No stack frames are consumed!
    return countdown ($n - 1)
end

fun main:
    ; This would overflow the stack in many scripting languages,
    ; but Newton optimizes it into an iterative jump.
    countdown 10000000
end
```
