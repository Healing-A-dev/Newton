import os, strutils, osproc

const VERSION*: string = "0.6.1 [BETA]"

type STATES* = tuple [
    State: string,
    Input: string,
    Output: string,
    Backend: string,
    Fallback: string,
    Intermidiates: string,
    LinkerFiles: seq[string],
    RunArguments: seq[string],
    ObjectOutput: string,
    Verbose: string,
    TargetOS: string,
    isScript: bool,
    noStdlib: bool,
]

const helpMessage: string = """
Newton Programming Language
-------------------------------
Usage: newton <command> [<args>] [<flags>]

commands:
   init <name>    > Initialize a new Newton project skeleton.
   build <file>   > Compile a Newton file or project. [default]
   run <file>     > Compile and run immediately.
   lsp            > Launch the Newton Language Server Protocol (LSP) daemon.
   help           > Display this message.
   version        > Display the installed build version.

options:
   -b | --build    > Specify the compiler backend (native, c, webasm).
   -f | --fallback > Specify a backend to fallback to in case of compilation errors.
   -o | --output   > Specify the output binary name.
   -p | --platform > Specify the target platform (win64, linux, darwin).
   -r | --run      > Compile and immediately run the specified file.
   -v | --verbose  > Enable verbose compiler output.

advanced flags:
   --keep-intermidiates > Keep all generated intermediate files.
   --debug              > Generate debug information instead of compiling.
   --link-C             > Link with C.
   --script             > Treat the given file as a newton script file (.nts).
   --noStdlib           > Prevents the standard library from being automatically imported.
   -L                   > Specify a library search directory (-L <dir>).
   -l                   > Specify a file or library to link with (-l <file.o>).
   -O                   > Compile to an object file.
   -GVM                 > Stop compilation at GravityVM bytecode generation.
"""

# --- Scaffolding Engine ---
proc initProject(name: string) =
  let dir = if name == "": "newton_project" else: name
  createDir(dir)
  createDir(dir / "src")
  createDir(dir / "lib")
  createDir(dir / "bin")

  # Generate standard library entry point
  let mainCode = "fun main:\n    @println \"Hello World!\"\nend\n"
  writeFile(dir / "src" / "main.nt", mainCode)

  # Generate .gitignore
  let gitignore = "packages/\nbin/\n*.o\n"
  writeFile(dir / ".gitignore", gitignore)

  # Generate project configuration as NPF (Non-Newtonian Format)
  let npfConfig = """
[Project]
name = "$#"
version = "0.1.0"
entrypoint = "src/main.nt"

[Packages]
""" % [dir]

  writeFile(dir / ".Newtonproj.toml", npfConfig)

  echo "\e[1;32mCreated\e[0m project directory `", dir, "`"
  quit(0)

# --- Argument Parsing ---
proc parseArgs*(ARGS: seq[string]): STATES =
  var counter: int = 0
  var linkedC: bool = false

  var DATA: STATES
  DATA.TargetOS = hostOS
  DATA.State = "build"
  DATA.isScript = false
  DATA.noStdlib = false

  proc addLinkCFlags() =
    if not linkedC:
      DATA.LinkerFiles.add("-l:-m")
      DATA.LinkerFiles.add("-l:elf_x86_64")
      DATA.LinkerFiles.add("-l:-L/usr/lib64")
      DATA.LinkerFiles.add("-l:-L/usr/lib/x86_64-linux-gnu")
      DATA.LinkerFiles.add("-l:-L/usr/lib")
      DATA.LinkerFiles.add("-l:-lc")
      DATA.LinkerFiles.add("-l:-lm")
      DATA.LinkerFiles.add("-l:--dynamic-linker")
      DATA.LinkerFiles.add("-l:/lib64/ld-linux-x86-64.so.2")
      linkedC = true

  if ARGS.len == 0:
    echo helpMessage
    quit(1)

  let cmd = ARGS[0]

  if cmd == "init":
     let pName = if ARGS.len > 1: ARGS[1] else: "newton_project"
     initProject(pName)
  elif cmd == "run":
     DATA.State = "run"
     if ARGS.len > 1 and not ARGS[1].startsWith("-"): DATA.Input = ARGS[1]
     counter = 2
  elif cmd == "build":
     DATA.State = "build"
     if ARGS.len > 1 and not ARGS[1].startsWith("-"): DATA.Input = ARGS[1]
     counter = 2
  elif cmd == "help":
    echo helpMessage
    quit(0)
  elif cmd == "version":
    echo "newton " & VERSION
    quit(0)
  elif cmd == "lsp":
    DATA.State = "lsp"
    counter = 1
  elif cmd == "self-update":
    echo "WIP"
    quit(0)
  else:
     # Fallback to old behavior for backwards compatibility
     if not cmd.startsWith("-"): DATA.Input = cmd
     counter = 1

  while counter < ARGS.len:
    let arg = ARGS[counter]
    case arg
    of "-o", "--output":
      DATA.Output = ARGS[counter + 1];
      counter.inc
    of "-b", "--build":
      DATA.Backend = "-b:" & ARGS[counter + 1]
      counter.inc
    of "-f", "--fallback":
      DATA.Fallback = "-f:" & ARGS[counter + 1]
      counter.inc
    of "--keep-intermidiates":
      DATA.Intermidiates = "-intermidiates:true"
    of "--debug":
      DATA.State = "disassemble"
    of "-p", "--platform":
      DATA.TargetOS = "-p:" & ARGS[counter + 1]
      counter.inc
    of "-v", "--verbose":
      DATA.Verbose = "-verbose:true"
    of "-L":
      if counter + 1 < ARGS.len:
        DATA.LinkerFiles.add("-l:-L" & ARGS[counter + 1])
        counter.inc
    of "-l":
      if counter + 1 < ARGS.len:
        let target = ARGS[counter + 1]
        counter.inc
        if target.endsWith(".o") or target.endsWith(".a") or target.contains(".so"):
          DATA.LinkerFiles.add("-l:" & target)
        else:
          addLinkCFlags()
          DATA.LinkerFiles.add("-l:-l" & target)
    of "--link-C":
      addLinkCFlags()
    of "--noStdlib":
      DATA.noStdlib = true
    of "--script":
      DATA.isScript = true
    of "-O":
      DATA.State = "generate-object"
    of "-r", "--run":
      DATA.State = "run"
    of "-GVM":
      DATA.Backend = "-b:gravity"
    else:
      if DATA.Input == "" and not arg.startsWith("-"):
        DATA.Input = arg
      else:
        DATA.RunArguments.add("-a:" & arg)
    counter.inc

  # Auto-detect .Newtonproj.toml and auto-link packages
  if fileExists(".Newtonproj.toml") and DATA.Input == "":
      var currentSection = ""

      for rawLine in lines(".Newtonproj.toml"):
          let line = rawLine.strip()
          if line == "" or line.startsWith("#"): continue

          # Detect section headers like [build] or [Project]
          if line.startsWith("[") and line.endsWith("]"):
              currentSection = line[1 .. ^2].toLowerAscii() # Normalize case to handle [Build] or [build]
              continue

          if currentSection == "build":
              echo "\e[96m[Build-Step]\e[0m ", line
              let exitCode = execCmd(line)
              if exitCode != 0:
                  echo "\e[91m[Newton Build Error]\e[0m Command failed: ", line
                  quit(1)
              continue

          elif currentSection == "linkerfiles":
              DATA.LinkerFiles.add("-l:" & line)
              continue

          let parts = line.split("=", 1)
          if parts.len == 2:
              let key = parts[0].strip()
              let val = parts[1].strip().replace("\"", "")

              if currentSection == "project":
                  if key == "entrypoint" and DATA.Input == "":
                      DATA.Input = val
                  elif key == "name" and DATA.Output == "":
                      DATA.Output = "bin" / val

              elif currentSection == "flags":
                  let flagVal = val.toLowerAscii()
                  if flagVal == "true":
                      if key == "noStdlib":  DATA.noStdlib = true
                      elif key == "script":  DATA.isScript = true
                      elif key == "verbose": DATA.Verbose  = "-verbose:true"
                      elif key == "link-C":
                          addLinkCFlags()

              elif currentSection == "packages":
                  let pkgObj = "packages" / key & ".o"
                  if fileExists(pkgObj):
                      DATA.LinkerFiles.add("-l:" & pkgObj)

  if DATA.Input == "" and DATA.State != "help" and DATA.State != "lsp":
      echo "\e[1;31merror:\e[0m no input file provided or .Newtonproj.toml found."
      quit(1)

  return DATA
