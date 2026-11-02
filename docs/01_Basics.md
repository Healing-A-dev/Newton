# 1. The Basics

Newton is designed to be instantly readable while remaining mechanically transparent. It uses strict variable scoping, an explicit dynamic dispatch system, and a robust error-handling pattern out of the box.

## Comments

In Newton, comments begin with a semicolon (`;`) and continue to the end of the line.

```crystal
; This is a single-line comment in Newton
set x: 10 ; Comments can also appear after code
```

> **Important:** The `#` symbol is **not** a comment in Newton; `#` is reserved for foreign function interface calls (e.g. `#c_function $arg`). Always use `;` for comments.

---

## The Entry Point

In standard Newton code (`.nt`), all executable code must live inside the `main` function. This function serves as the entry point for execution. The only exception to this rule is global variable declarations.

*(Note: Newton also offers a `.nts` scripting mode for quick, single-file scripts that auto-generates the `main` function [See Chapter 5]).*

```crystal
fun main:
    @println "Hello, Newton!"
end
```

---

## Variables & Globals

Variables are declared using the `set` keyword and assigned with a colon (`:`). To reassign an existing variable, omit `set`. To read any variable, you must explicitly prefix it with a dollar sign (`$`).

```crystal
fun main:
    ; Declaring and reassigning a local variable
    set my_age: 25
    my_age: 26

    ; Reading a variable requires the '$' prefix
    @println "My age is: {}", $my_age
end
```

### Global Variables

To declare a global variable accessible across functions and modules, append an asterisk (`*`) to the variable name.

```crystal
; Global variable declaration
set MAX_RETRIES*: 5
set SERVER_PORT*: 8080

fun main:
    @println "Connecting on port {}...", $SERVER_PORT
end
```

---

## Namespace Separation (Variables vs. Functions)

Because reading a variable strictly requires the `$` prefix, variables and functions can share the exact same name without conflict. The Newton compiler knows exactly which one you mean based on your syntax.

```crystal
; Define a function called 'build'
fun build:
    @println "Building the project..."
end

fun main:
    ; Define a variable also called 'build'
    set build: "v1.0.0"

    build             ; Calls the function
    @println $build   ; Reads the variable
end
```

---

## Functions as Variables (Dynamic Dispatch)

Because Newton supports first-class functions, you can assign a function reference to a variable. To execute a dynamic function from a variable, use the `call` keyword followed by the variable and arguments in parentheses.

```crystal
fun greet: @args name
    @println "Hello, {}!", $name
end

fun main:
    set fn: $greet
    call $fn("Alice")
end
```

---

## Expression Grouping (Parentheses)

Newton uses parentheses `()` to enforce the order of operations and group expressions. Because the Newton compiler parses linearly, parentheses are crucial for explicitly enforcing math precedence.

```crystal
fun main:
    set base: 10
    set multiplier: 5

    ; Enforcing math precedence
    set result: ($base + $multiplier) * 2
    @println "Result: {}", $result

    ; Grouping expressions inside function arguments
    @println "Half of base is: {}", (string ($base / 2))
end
```

---

## Data Types & Interpolation

Newton natively supports heavily optimized primitive types:

- **Integers** (`42`, `-10`) — Fast-path tagged numbers.
- **Floats** (`3.14`, `-0.5`) — Double-precision floating-point numbers.
- **Strings** (`"Hello, world!"`) — Null-terminated character sequences.

Newton provides built-in string interpolation using `{}` via the global `@println` and `@print` macros, alongside traditional concatenation (`<<`).

```crystal
fun main:
    set name: "Alice"
    set age: 30

    ; String Interpolation via @println
    @println "My name is {} and I am {} years old.", $name, $age

    ; String Concatenation using '<<'
    set greeting: "Hello, " << $name
    @println $greeting
end
```

---

## Collections & Destructuring

Newton provides two primary collection types, implemented as high-speed memory structures.

### Lists & Maps

- **Lists** are declared using square brackets `[]`.
- **Maps** (key-value pairs) are declared using parentheses `()`.

```crystal
fun main:
    ; Lists
    set numbers: [10, 20, 30]

    ; Key-Value Map
    set user: (name: "Alice", role: "Admin", id: 101)

    ; Accessing elements with {}
    @println "User {} is an {}", $user{"name"}, $user{"role"}
    @println "First number is: {}", $numbers{0}

    ; Polymorphic Collection Printing
    ; Newton recursively prints entire maps and lists with accurate formatting
    @println $user     ; Output: (name: "Alice", role: "Admin", id: 101)
    @println $numbers  ; Output: [10, 20, 30]
end
```

### Destructuring

You can unpack lists directly into individual variables in a single statement:

```crystal
fun main:
    set coordinates: [45, 90]
    set [x, y]: $coordinates
    @println "X: {}, Y: {}", $x, $y
end
```

---

## The Standard Library Pattern: Ok / Error

To prevent unexpected runtime crashes, Newton's standard library avoids throwing unhandled exceptions. Instead, it relies on a tupled result pattern. Functions return a two-element array: the status (`"ok"` or `"error"`) and the resulting payload (or error message).

```crystal
using std::file

fun main:
    set file_result: @capture file.readEntireFile "config.txt"

    if $file_result{0} == "error":
        @println "Failed to read file: {}", $file_result{1}
    else:
        @println "File contents: {}", $file_result{1}
    end
end
```

---

Next: [2. Control Flow](02_Control-Flow.md)

