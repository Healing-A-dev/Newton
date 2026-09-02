# 5. The Ecosystem & Project Structure

Newton is more than just a compiler; it is a complete toolchain. Whether you are writing a quick 10-line script or building a massive systems application, the ecosystem is designed to scale with you.

## Modules and Namespacing

To keep the global scope clean, Newton heavily utilizes namespacing. When you import a module using the `using` keyword, you must prefix its functions with the module name.

```asm
using std::File

fun main:
    ; Standard library functions require their explicit namespace
    set fd: File.Std_Open "config.txt", 0
end
```

### Strict Internal Namespacing
Newton enforces a very strict, predictable rule for modules: **If a file is not the main entry point, you must use its explicit namespace to access its own functions and global variables, even from within the file itself.**

The namespace is derived from the file name. For example, if you are writing a helper module named `Bad_Math.nt`, any function calling another function inside that same file must prefix it with `Bad_Math.`.

```asm
; File: Bad_Math.nt

; A global variable native to this module
set PI*: 3.14 

fun add: @args a, b
    return $a +$b
end

fun multiply: @args a, b
    set sum: 0
    for &s, 0, $b, 1:
        ; Calling 'add' from inside the same file requires the namespace!
        sum: $sum + (Bad_Math.add $a, $a)
    end
    return $sum
end

fun getPI:
    ; Reading a global variable from inside the same file also requires the namespace
    return $Bad_Math.PI
end
```

Why does Newton do this? This explicit internal namespacing ensures that when the compiler links multiple files together, there is zero ambiguity. Since newton amalgomates all files during compilation, it prevents accidental shadowing and makes it instantly clear to any developer reading the file exactly where a function or global state originates.

### Importing Local Files
To import your own modules or other `.nt` files into your project, use the `using` keyword followed by the file name (without the `.nt` extension). 

Once imported, you must use the file's name as the namespace to access its functions and global variables.

```asm
; File: main.nt

; Imports 'Bad_Math.nt' from the same directory
using Bad_Math

; Import follow the following 
; Be sure NOT to include the file extension
using path::to::file

fun main:
    set result: Bad_Math.add 10, 5
    @println "The result is: {}", $result
end
```

## The Prelude and Utility Wrappers

To make development faster, Newton automatically injects a prelude (`Base.nt`) into every project unless you explicitly compile with the `--noStdlib` flag.

The prelude automatically imports core modules (such as `IO`, `String`, and `File`). More importantly, it provides global wrapper functions so you don't have to type the full namespace for common operations.

```asm
fun main:
    ; Without the prelude:
    set data: File.Std_ReadEntireFile "data.txt"

    ; With the prelude's global wrappers:
    set data: readfile "data.txt"
end
```

## Execution Modes: Compiled vs. Scripting

Newton bridges the gap between high-performance systems languages and ergonomic scripting languages by offering two distinct execution modes.

### 1. Standard Compilation (`.nt`)

This is the default mode for Newton. Files ending in `.nt` require a `main` function. When you build a `.nt` file, you have access to the full compiler toolchain, including:

- Cross-compilation to supported platforms.
- Linking external source files.
- Generating static, zero-dependency native executables.
- Using custom build flags (such as `--noStdlib`).

### 2. Scripting Mode (`.nts`)

If you just need to automate a task or write a quick utility, you can use the `.nts` extension (or run a `.nt` file with the `--script` flag).

In scripting mode, Newton behaves more like Python or Bash. You do not need to define a `main` function. Instead, the compiler automatically:

- Hoists function declarations.
- Wraps loose statements in a generated `main` function.
- Executes the resulting program immediately.

> **Note:** Because scripting mode is designed for rapid execution, it does not support linking external files, generating native executables, or using build-specific compiler flags.

## The Package Manager (`nnpm`)

For larger projects, Newton includes its own package and build manager: `nnpm`.

Rather than manually invoking the compiler across multiple source files, `nnpm` allows you to:

- Manage project dependencies.
- Define build targets.
- Organize applications using a configuration-first workflow.
- Produce reproducible, portable builds across different machines.
