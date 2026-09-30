# 1. The Basics

Newton is designed to be instantly readable while remaining mechanically transparent. It uses strict variable scoping, an explicit dynamic dispatch system, and a robust error-handling pattern out of the box.

## The Entry Point
In standard Newton code (`.nt`), all executable code must live inside the `main` function. This function stands as the entry point for the Virtual Machine. The only exception to this rule is global variables.

*(Note: Newton does offer a `.nts` scripting mode for quick, single-file scripts that auto-generates the `main` function, but standard `.nt` files require it \[See: <ADVANCED STUFF HERE>]).*

```asm
fun main:
    IO.println "Hello, Newton!"
end
```

## Variables & Globals

Variables are declared using the `set` keyword and assigned with a colon (`:`). To read a variable, you must explicitly prefix it with a dollar sign (`$`). All variables and functions in Newton are mutable and can be overriden. 

```asm
fun main:
    ; Declaring and reassigning a local variable
    set my_age: 25
    my_age: 26
    
    ; Reading a variable requires the '$' prefix
    IO.println $my_age
end
```

### Global Variables

To declare a global variable that bypasses block scope, append an asterisk (`*`) to the variable name.

```asm
; Snippet from Std/Base.nt
set fmRead*: 0
set fmWrite*: 577
```

## Namespace Separation (Variables vs. Functions)

Because reading a variable strictly requires the `$` prefix, variables and functions can share the exact same name without conflict. The Newton compiler knows exactly which one you mean based on your syntax.

```asm
; Define a function called 'build'
fun build:
    IO.println "Building the project..."
end

fun main:
    ; Define a variable also called 'build'
    set build: "v1.0.0"
    
    build                 ; Calls the function
    IO.println $build ; Reads the variable
    ; The compiler never gets confused:
end
```

## Functions as Variables (Dynamic Dispatch)

Because Newton supports first-class functions, you can assign a function to a variable. To execute a dynamic function from a variable, you must use the `call` keyword and enclose the arguments in parentheses.

```asm
fun main:
    set my_func: IO.println
    call $my_func("Hello from dynamic dispatch!")
end
```

## Expression Grouping (Parentheses)
Just like in standard mathematics, Newton uses parentheses `()` to enforce the order of operations and group expressions. Because the Newton compiler parses linearly, parentheses are crucial for explicitly telling the AST which operations to evaluate first.

This is especially important when calculating values on the fly to pass as arguments to a function or macro.

```asm
fun main:
    set base: 10
    set multiplier: 5
    
    ; Enforcing math precedence
    set result: ($base + $multiplier) * 2
    
    ; Grouping expressions inside function arguments
    ; The compiler evaluates ($base / 2) before calling the 'string' converter
    @println "Half of the base is: {}", (string ($base / 2))
end
```

## Data Types & Interpolation

Newton natively supports heavily optimized primitive types:

- **Integers & Floats** — Fast-path native numbers.
- **Strings** — Immutable text sequences.

Newton's standard library provides built-in string interpolation using `{}` via the global `println` and `print` macros, alongside traditional concatenation (`<<`).

```asm
fun main:
    set name: "Alice"
    set age: 30
    
    ; String Interpolation (handled by the global println macro)
    @println "My name is {} and I am {} years old.", $name, $age
    
    ; Standard Concatenation
    set greeting: "Hello, " << $name
end
```

## Collections & Destructuring

Newton provides two primary collection types, both implemented as high-speed flat memory structures.

### List & Maps

- **List** are declared using square brackets `[]`.
- **Maps** (key-value pairs) are declared using parentheses `()`.

```asm
fun main:
    set numbers: [1, 2, 3]

    ; Key-Value Map
    set user: (name: "Alice", role: "Admin")

    ; Array-like Map
    set names: ("Alice", "Bob", "Jennifer", "David")
    
    ; Accessing elements
    @println "User {} is an {}", $user{"name"}, $user{"role"}
    @println "User at index 3 is: {}", $names{3}
    @println $names ; This will display the map in its entirety (works with all collection types)
end
```
*(Note: Newton does support the dot (`.`) notation, as that is reserved for namespacing)*

### Destructuring

You can unpack list directly into individual variables in a single line.

```asm
fun main:
    set coordinates: [45, 90]
    set [x, y]: $coordinates
end
```

## The Standard Library Pattern: Ok / Error

To prevent runtime crashes, Newton's standard library avoids throwing exceptions. Instead, it relies on a tupled return pattern. Functions return a two-element array: the status (`"ok"` or `"error"`) and the resulting data (or error message). Alternativly, you can use the `@ok` and `@err` macros.

```asm
fun main:
    set file_result: @capture File.readEntireFile "config.txt"
    
    if $file_result{0} == "error":
        println "Failed to read file: {}", $file_result{1}
    else:
        println "File contents: {}", $file_result{1}
    end
end
```

> **Note:** The standard library provides utility macros like `@isError` and `@getError` to make checking these results even cleaner!

***
