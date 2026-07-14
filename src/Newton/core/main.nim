import strutils, os, osproc, streams
import lexer, parser, codegen, ast, cli, errors, optimizer

var ERRNO: int = 0
var SCRIPT_PATH: string = "/usr/local/lib/newton/bin/newton@core__script.component"

proc parseOpcode(op: string): uint8 =
  var val = 0
  for c in op:
    val *= 36
    if c >= '0' and c <= '9': val += ord(c) - ord('0')
    elif c >= 'A' and c <= 'Z': val += ord(c) - ord('A') + 10
  return uint8(val)


proc serializeToBinary(filename: string, bytecode: seq[string]) =
  var strm = newFileStream(filename, fmWrite)
  defer: strm.close()

  strm.write("GVM")
  strm.write(1'u8)
  strm.write(uint32(bytecode.len))

  for instr in bytecode:
    let parts = instr.split(' ')
    let opcodeByte = parseOpcode(parts[0])
    strm.write(opcodeByte)

    for i in 1 .. 3:
      let arg = if i < parts.len: parts[i] else: "00"
      strm.write(uint8(arg.len))
      strm.write(arg)


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


proc main(INPUT_FILE, OUTPUT_FILE: string, e: STATES) =
  if INPUT_FILE.endsWith(".nts") or e.isScript:
    quit(execCmd(SCRIPT_PATH & " " & INPUT_FILE))

  errors.currentCompilingFile = INPUT_FILE
  let source = readFileContent(INPUT_FILE)
  let tokens = lex(source)
  let p = newParser(tokens)
  var astRoot = parseProgram(p)
  astRoot = optimize(astRoot)

  # std::Base Injection
  if not e.noStdlib:
    injectPrelude(astRoot.stmts)

  if astRoot.stmts.len == 0:
    echo  "Warning: AST is empty! Check your source file or parser logic."
  else:
    discard
  let bytecode = compile(astRoot)

  if ERRCOUNT > 0:
      echo "Compiliation Failed With <" & $ERRCOUNT & "> Errors"
      quit(1)

  if bytecode.len == 0:
    echo "ERROR: Codegen produced 0 instructions."
    echo "This usually means 'codegen.nim' switch case does not match 'ast.nim' node kinds."
  else:
    serializeToBinary(OUTPUT_FILE & ".gvt", bytecode)

when isMainModule:
  var data: STATES = parseArgs(commandLineParams())
  if data.Output == "":
    data.Output = stripFileExtension(data.Input)

  # Compile file to bytecode
  main(data.Input, data.Output, data)

  # Building compiled file with gravity backend
  if data.Backend != "-b:gravity":
      if data.TargetOS[3..^1] != hostOS and data.TargetOS != hostOS:
        case data.TargetOS[3..^1]
        of "win64":
          ERRNO = execCmd("gvm " & data.State & " -i:" & data.Output & ".gvt -o:" & data.Output & " " & data.Intermidiates & " " & data.Backend & " " & data.Fallback & " -L:/usr/local/lib/newton/lib/libnewton.a " & data.LinkerFiles.join(" ") & " " & data.Verbose & " "  & data.TargetOS & " " & data.ObjectOutput)
        of "darwin":
          echo "TODO: IMPLEMENT DARWIN (MACOS) SUPPORT"
          discard
        else:
          ERR("Unsupported platform <\e[1;31m" & data.TargetOS[3..^1] & "\e[0m\e[1m>", 0, "", "Supported platforms linux|win64|darwin")
      else:
        ERRNO = execCmd("gvm " & data.State & " -i:" & data.Output & ".gvt -o:" & data.Output & " " & data.Intermidiates & " " & data.Backend & " " & data.Fallback & " -L:/usr/local/lib/newton/lib/libnewton.o " & data.LinkerFiles.join(" ") & " " & data.Verbose & " " & data.ObjectOutput)
  else:
    echo "Genereated bytecode file <\e[96m" & data.Output & ".gvt\e[0m>"

  # Cleanup
  if data.Intermidiates == "":
    if fileExists(data.Output & ".gvt") and data.Backend != "-b:gravity":
      ERRNO.inc(execCmd("rm " & data.Output & ".gvt"))

  quit(ERRNO)
