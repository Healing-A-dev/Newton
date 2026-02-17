import strutils, os, osproc
import lexer, parser, codegen, ast

const VERSION: string = "0.0.1 [BETA]"
type STATES = tuple [
  State: string,
  Input: string,
  Output: string,
  Backend: string,
  Fallback: string,
  Intermidiates: string
]

proc stripFileExtension(FILE_NAME: string): string =
  var
    char_array: seq[char] = @[]
    iter: int = 1
    c: char = FILE_NAME[FILE_NAME.len - iter]

  while c != '.':
    char_array.add(c)
    iter.inc()
    c = FILE_NAME[FILE_NAME.len - iter]

  return FILE_NAME[0..<(FILE_NAME.len - (char_array.len + 1))]


proc readFileContent(path: string): string =
  try:
    return readFile(path)
  except IOError:
    echo "Error: Could not read file ", path
    quit(1)

proc parseArgs(ARGS: seq[string]): STATES =
  var DATA: STATES
  DATA.State = "build"
  var counter: int = 0

  if ARGS.len == 0:
    echo "Usage: newton <file.nt or file.ntn>"
    quit(1)

  while counter < ARGS.len:
    let arg: string = ARGS[counter]
    case arg
    of "-o", "--output":
      DATA.Output = ARGS[counter + 1]
      counter.inc()
    of "-b", "--build":
      DATA.Backend = "-b:" & ARGS[counter + 1]
      counter.inc()
    of "-f", "--fallback":
      DATA.Fallback = "-f:" & ARGS[counter + 1]
      counter.inc()
    of "--keep-intermidiates":
      DATA.Intermidiates = "-intermidiates:true"
    of "-r", "--run":
      DATA.State = "run"
    of "--debug":
      Data.State = "disassemble"
    of "-v", "--version":
      echo VERSION
      quit()
    else:
      if DATA.Input == "":
        DATA.Input = arg
      else:
        echo "INVALID ARGUMENT: " & arg
        quit()
    counter.inc()
  return DATA




proc main(INPUT_FILE, OUTPUT_FILE: string) =
  let source = readFileContent(INPUT_FILE)
  let tokens = lex(source)
  let p = newParser(tokens)
  let astRoot = parseProgram(p)

  if astRoot.stmts.len == 0:
    echo  "Warning: AST is empty! Check your source file or parser logic."
  else:
    discard
  let bytecode = compile(astRoot)

  if bytecode.len == 0:
    echo "ERROR: Codegen produced 0 instructions."
    echo "This usually means 'codegen.nim' switch case does not match 'ast.nim' node kinds."
  else:
    writeFile(OUTPUT_FILE & ".gvt", bytecode.join("\n"))


when isMainModule:
  var data = parseArgs(commandLineParams())

  if data.Output == "":
    data.Output = stripFileExtension(data.Input)

  # Compile file to bytecode
  main(data.Input, data.Output)

  # Building compiled file with gravity backend
  var ERRNO: int = execCmd("gravity " & data.State & " -i:" & data.Output & ".gvt -o:" & data.Output & " " & data.Intermidiates & " " & data.Backend & " " & data.Fallback)

  # Cleanup
  if data.Intermidiates == "":
    if fileExists(data.Output & ".gvt"):
      ERRNO.inc(execCmd("rm " & data.Output & ".gvt"))

  quit(ERRNO)
