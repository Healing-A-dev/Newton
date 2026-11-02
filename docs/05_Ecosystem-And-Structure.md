# 5. Ecosystem & Project Structure

Newton is more than a compiler; it is a full, self-contained development toolchain. Whether writing a rapid automation script or engineering a multi-module systems application, the ecosystem is built to support your workflow.

---

## Modules & Namespacing

To keep the global namespace clean and predictable, Newton uses module-based namespacing.

```crystal
using std::web
using std::string

fun main:
    set server: web.tcpServer 8080
    @println "Server initialized."
end
```

### Case-Insensitive Module Resolution

Newton's module resolver is case-insensitive on all platforms. All of the following import variations resolve seamlessly:

```crystal
using std::math
using std::Math
using std::web
using std::Web
```

### Strict Internal Namespacing

Newton enforces an explicit architectural rule: **Inside a non-entry module, calls to sibling functions or global variables within that same module must use the module's namespace.**

The namespace matches the file name without extension. For example, inside `src/Newton/lib/std/web.nt`, functions calling peer functions in `web.nt` prefix them with `web.`:

```crystal
; File: web.nt

fun tcpServer: @args port
    set fd: net_create
    net_bind $fd, $port
    net_listen $fd
    return $fd
end

fun httpServer: @args port
    ; Sibling function call uses 'web.' namespace
    return web.tcpServer $port
end
```

This prevents accidental variable shadowing and ensures 100% clarity when multiple modules are amalgamated during native compilation.

---

## Importing Local Project Files

To import other `.nt` files from your project, use the `using` keyword followed by the path (separated by `::` or directory notation, without `.nt` extension):

```crystal
; Imports 'helper.nt' from current directory
using helper

; Imports 'models/user.nt'
using models::user

fun main:
    set u: user.createUser "Alice"
    helper.log "User created."
end
```

---

## Project Structure & Configuration (`.Newtonproj.toml`)

Newton includes built-in project scaffolding via the `newton init` command:

```bash
newton init my_app
```

This creates a standard project layout:

```
my_app/
├── .Newtonproj.toml   # Project configuration
├── .gitignore
├── bin/               # Compiled binaries
├── lib/               # Local libraries & packages
└── src/
    └── main.nt        # Application entry point
```

### Project Configuration (`.Newtonproj.toml`)

```toml
[Project]
name = "my_app"
version = "0.1.0"
entrypoint = "src/main.nt"

[Flags]
verbose = "false"
link-C = "true"

[Build]
# Optional custom pre-build commands
# gcc -c -fPIC -Isrc/include -o lib/c_helper.o src/c_helper.c

[LinkerFiles]
# Additional libraries or object files to link
lib/c_helper.o
```

When building inside a directory containing `.Newtonproj.toml`, simply running `newton build` or `newton run` automatically applies all configured build steps and linker files.

---

## Compiler CLI Reference

```
Usage: newton <command> [<args>] [<flags>]

Commands:
   init <name>     Initialize a new project skeleton.
   build <file>    Compile a Newton file or project to a native binary.
   run <file>      Compile and immediately run the program.
   lsp             Launch the Newton Language Server Protocol (LSP) daemon.
   help            Display usage instructions.
   version         Display the compiler build version.

Options:
   -o, --output <file>    Specify output binary path/name.
   -b, --build <target>   Specify compiler backend (native, c).
   -f, --fallback <tgt>   Specify a fallback backend on compilation error.
   -p, --platform <os>    Specify target platform (linux, win64).
   -v, --verbose          Enable verbose compiler and linker commands.
   -r, --run              Compile and execute immediately.

Advanced Flags:
   -l <file.o|lib>        Specify an object file or library to link with.
   -L <dir>               Specify a library search directory for the linker.
   --link-C               Automatically link standard C runtime (libc, libm, dynamic linker).
   --noStdlib             Prevent the standard library prelude from being imported.
   --script               Treat file as an automated Newton script (.nts).
   --keep-intermidiates   Preserve generated assembly and intermediate files.
   -O                     Compile directly to a native object file (.o).
   -GVM                   Stop compilation after generating GravityVM bytecode (.gvt).
```

---

## Execution Modes: Compiled (`.nt`) vs Scripting (`.nts`)

Newton supports two distinct execution modes:

### 1. Standard Compiled Mode (`.nt`)
- Requires a `main` function as the execution entry point.
- Compiles down to an optimized native x86_64 binary with zero external dependencies.
- Supports external linking, C FFI, and cross-compilation.

### 2. Scripting Mode (`.nts`)
- Files ending in `.nts` (or executed with `--script`) execute immediately.
- Does not require a `main` function; loose top-level statements are automatically wrapped.
- Ideal for system administration, build automation, and rapid testing.

---

## Language Server Protocol (LSP)

Newton includes a built-in Language Server Protocol daemon supporting real-time diagnostics, hover tooltips, autocompletion, symbol outlines, and definition jumping.

Start the LSP server directly via:

```bash
newton lsp
# or using the dedicated binary:
newton-lsp
```

### Editor Integration

#### Neovim (`nvim-lspconfig` or raw LSP)

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "newton",
  callback = function()
    vim.lsp.start({
      name = "newton-lsp",
      cmd = { "newton", "lsp" },
      root_dir = vim.fs.dirname(vim.fs.find({ ".Newtonproj.toml", ".git" }, { upward = true })[1]),
    })
  end,
})
```

#### Helix (`languages.toml`)

```toml
[[language]]
name = "newton"
scope = "source.newton"
file-types = ["nt", "nts"]
language-servers = ["newton-lsp"]

[language-server.newton-lsp]
command = "newton"
args = ["lsp"]
```

#### VS Code (`settings.json` or custom extension)

Configure the language server client to execute `newton lsp` or `newton-lsp` over standard I/O pipes.

---

Next: [6. Style Guide & Conventions](06_Convention.md)

