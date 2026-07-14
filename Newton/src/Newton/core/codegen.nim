import strutils, tables, ast, errors, checks

# --- Custom Addressing Logic (Globals) ---
proc incAddr(T: var string, MAX: int = 122): string =
    var p0: int = T[0].ord()
    var p1: int = T[1].ord()
    if p0 == MAX and p1 == MAX: return T
    p1.inc()
    if p1 == 58: p1 = 65 elif p1 == 91: p1 = 97
    elif p1 == 123: p0.inc(); p1 = 48
    if p0 == 58: p0 = 65 elif p0 == 91: p0 = 97
    T[0] = p0.chr(); T[1] = p1.chr()
    return T

type
  SymbolTable = Table[string, string]

  Compiler* = ref object
    output*: seq[string]
    locals: SymbolTable
    globals: SymbolTable
    localPtr: string
    globalPtr: string
    tempPtr: string
    labelPtr: int
    inFunction: bool
    stackOffset: int
    tempCounter: int
    stringCounter: int
    varTypes: Table[string, string]
    loopStack: seq[string]
    currentFuncName: string
    currentFnArgs: seq[string]
    currentTcoLabel: string

proc newCompiler*(): Compiler =
  new(result)
  result.output = @[]
  result.locals = initTable[string, string]()
  result.globals = initTable[string, string]()
  result.localPtr = "00"
  result.globalPtr = "00"
  result.tempPtr = "00"
  result.labelPtr = 500
  result.inFunction = false
  result.stackOffset = 0
  result.tempCounter = 0
  result.stringCounter = 0
  result.varTypes = initTable[string, string]()
  result.loopStack = @[]

# --- Helper Methods ---

proc emit(c: Compiler, op, arg0, arg1, arg2: string) =
  let a0 = if arg0.len > 0: arg0 else: "00"
  let a1 = if arg1.len > 0: arg1 else: "00"
  let a2 = if arg2.len > 0: arg2 else: "00"
  c.output.add("$# $# $# $#" % [op, a0, a1, a2])

proc newLabel(c: Compiler): string =
  result = "L" & $c.labelPtr
  c.labelPtr.inc

proc toHexStr(s: string): string =
  result = ""
  for c in s:
    result.add(toHex(ord(c), 2))

proc unescape(s: string): string =
  result = ""
  var i = 0
  while i < s.len:
    if s[i] == '\\' and i + 1 < s.len:
      case s[i+1]
      of 'n': result.add('\L')
      of 't': result.add('\t')
      of 'r': result.add('\r')
      of '"': result.add('"')
      of '\\': result.add('\\')
      of '0': result.add('\0')
      of 'x':
        if i + 3 < s.len:
            let hexStr = s[i+2 .. i+3]
            try:
                let charCode = parseHexInt(hexStr)
                result.add(chr(charCode))
                i += 2
            except ValueError:
                result.add('x')
        else:
          result.add('x')
      else:
        result.add(s[i])
        result.add(s[i+1])
      i += 2
    else:
      result.add(s[i])
      i.inc

proc makeTemp(c: Compiler): string =
    c.tempCounter.inc()
    let name = "B" & align($c.tempCounter, 2, '0')
    c.emit("03", "%" & name, "0", "00")
    return "%" & name

proc allocVar(c: Compiler): string =
  if c.inFunction:
    c.stackOffset -= 8
    return "$" & $c.stackOffset & "(%rbp)"
  else:
    return "$" & incAddr(c.localPtr)

proc emitLabel(c: Compiler, label: string) =
  c.emit("0J", "[$#]" % label, "00", "00")

proc allocLabel(c: Compiler): string =
    c.newLabel()

proc allocTemp(c: Compiler): string =
  if c.inFunction:
    c.stackOffset -= 8
    return $c.stackOffset & "(%rbp)"
  else:
    return "%" & incAddr(c.tempPtr)

proc ensureLocation(c: Compiler, val: string): string =
  if val.startsWith("$") or val.startsWith("@") or val.startsWith("%") or val.startsWith("[") or val.endsWith("(%rbp)"):
    return val

  let tempLoc = c.allocTemp()
  var safeVal = val
  if val.startsWith("\""): safeVal = "[$#]" % val.replace("\"", "")
  else:
      if val.len > 2: safeVal = "[$#]" % val
      else: safeVal = val

  c.emit("03", tempLoc, "0", "00")
  c.emit("0G", tempLoc, safeVal, "00")
  return tempLoc

# --- Code Generation ---

proc gen(c: Compiler, node: AstNode): string =
  case node.kind

  of nkProgram:
        # --- Header & Entry Jump ---
        c.emit("0H", "$00", "3843", "00")
        c.emit("0H", "@00", "3843", "00")
        c.emit("0H", "%00", "3843", "00")
        c.emit("0J", "[ENTRY]", "00", "00")

        let mainLabel = c.newLabel()
        c.emit("0B", "[$#]" % mainLabel, "00", "00")

        # --- PASS 0: Register Globals ---
        for stmt in node.stmts:
          if stmt.kind == nkGlobalDecl:
            if not c.globals.hasKey(stmt.varName):
                  let nextAddr = incAddr(c.globalPtr)
                  let addrStr = "@" & nextAddr
                  c.globals[stmt.varName] = addrStr
                  c.emit("03", addrStr, "0", "00")

                  var vType = "int"
                  if stmt.varValue.kind == nkLiteral and stmt.varValue.isString:
                      vType = "string"
                  c.varTypes[stmt.varName] = vType

        proc registerAstFunctions(stmtsList: seq[AstNode]) =
            for s in stmtsList:
                if s.kind == nkFunction:
                    checks.registerFunction(s.fnName, s.fnArgs.len)
                elif s.kind == nkBlock:
                    registerAstFunctions(s.blockStmts)

        registerAstFunctions(node.stmts)

        for stmt in node.stmts:
          if stmt.kind == nkFunction:
            discard c.gen(stmt)

        c.emitLabel(mainLabel)

        c.emit("1A", "%rbp", "00", "00")    # PUSH %rbp
        c.emit("0A", "%rsp", "%rbp", "00")  # MOV %rbp, %rsp
        c.emit("03", "%sp", "0", "00")      # Dummy alloc

        c.inFunction = true
        c.stackOffset = 0

        let mainPrologueIdx = c.output.len
        c.emit("41", "_NULL", "00", "00") # Placeholder

        for stmt in node.stmts:
           if stmt.kind != nkFunction:
            discard c.gen(stmt)

        var mainStackNeeded = -c.stackOffset
        mainStackNeeded = (mainStackNeeded + 15) and not 15
        if mainStackNeeded == 0: mainStackNeeded = 16
        c.output[mainPrologueIdx] = "41 $# 00 00" % $mainStackNeeded

        c.emit("0A", "%rbp", "%rsp", "00")
        c.emit("40", "%rdi", "0", "00")
        c.emit("0L", "0", "00", "00") # EXIT
        # c.emit("1B", "exit_program", "00", "00")
        c.emit("0I", "$00", "00", "00")
        c.emit("0I", "@00", "00", "00")
        c.emit("0I", "%00", "00", "00")
        return ""

  of nkVarDecl:
    var vType = "int"
    if node.varValue.kind == nkLiteral and node.varValue.isString:
        vType = "string"
    elif node.varValue.kind == nkVarRef and c.varTypes.hasKey(node.varValue.refName):
        vType = c.varTypes[node.varValue.refName]

    c.varTypes[node.varName] = vType

    if node.varValue.kind == nkBinaryOp and node.varValue.op == "+":
       let bin = node.varValue
       if bin.right.kind == nkLiteral and bin.right.strVal == "1":
           if bin.left.kind == nkVarRef and bin.left.refName == node.varName:
               var addrStr = ""
               if c.locals.hasKey(node.varName):
                   addrStr = c.locals[node.varName]
                   c.emit("0E", addrStr, "00", "00")
                   return addrStr

    let valLoc = c.gen(node.varValue)
    var addrStr = ""
    if c.locals.hasKey(node.varName):
        addrStr = c.locals[node.varName]
        c.emit("0G", addrStr, valLoc, "00")
    else:
        addrStr = c.allocVar()
        c.locals[node.varName] = addrStr
        c.emit("03", addrStr, "0", "00")
    c.emit("0G", addrStr, valLoc, "00")

    return addrStr

  of nkGlobalDecl:
    let valLoc = c.gen(node.varValue)
    var addrStr = ""
    var vType = "int"
    if node.varValue.kind == nkLiteral and node.varValue.isString: vType = "string"
    c.varTypes[node.varName] = vType

    if c.globals.hasKey(node.varName):
        addrStr = c.globals[node.varName]
        c.emit("0G", addrStr, valLoc, "00")
    else:
        let nextAddr = incAddr(c.globalPtr)
        addrStr = "@" & nextAddr
        c.globals[node.varName] = addrStr
        c.emit("03", addrStr, "0", "00")
        c.emit("0G", addrStr, valLoc, "00")

    return addrStr

  of nkVarRef:
    if c.locals.hasKey(node.refName):
        return c.locals[node.refName]
    elif c.globals.hasKey(node.refName):
        return c.globals[node.refName]
    else:
        let label = "$F_" & node.refName
        return label

  of nkLiteral:
    if node.isString:
      let label = "str_" & $c.stringCounter
      c.stringCounter.inc()
      let realStr = unescape(node.strVal)
      let hexStr = toHexStr(realStr)
      let safeStr = "[" & hexStr & "]"
      c.emit("1E", label, safeStr, "00")
      return "$" & label
    else:
      try:
        let iVal = parseInt(node.strVal)
        let taggedVal = (iVal shl 1) or 1
        return "$" & $taggedVal
      except:
        return node.strVal

  of nkCommand, nkCall:
    validateCall(node.callName, node.callArgs.len, node.line)
    if node.callName == "stdout":
      for arg in node.callArgs:
        let loc = c.gen(arg)
        var isString = false
        if arg.kind == nkLiteral and arg.isString: isString = true
        elif arg.kind == nkVarRef and c.varTypes.getOrDefault(arg.refName, "int") == "string": isString = true

        if isString: c.emit("1F", loc, "00", "00")
        else: c.emit("02", loc, "1", "00")
      return ""

    if node.callName == "break":
        if c.loopStack.len > 0:
            c.emit("0B", c.loopStack[^1], "00", "00")
        return ""

    if node.callName == "__sys_collection_delete":
      let colLoc = c.gen(node.callArgs[0])
      let keyLoc = c.gen(node.callArgs[1])
      c.emit("40", "%rdi", colLoc, "00")
      c.emit("40", "%rsi", keyLoc, "00")
      c.emit("1B", "collection_delete", "0", "00")
      let dest = c.allocTemp()
      if not dest.contains("(%rbp)"): c.emit("03", dest, "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "__proc_sleep_ms":
      let msLoc = c.gen(node.callArgs[0])
      c.emit("40", "%rdi", msLoc, "00")
      c.emit("1B", "sys_sleep_ms", "0", "00")
      let dest = c.allocTemp()
      if not dest.contains("(%rbp)"): c.emit("03", dest, "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "sizeof":
      let mapArg = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", mapArg, "00")
      c.emit("1B", "newton_sizeof", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "__math_random":
      let valLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", valLoc, "00")
      c.emit("1B", "runtime_random", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "string":
      let valLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("0O", dest, valLoc, "00")
      return dest

    if node.callName == "int":
      let valLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", valLoc, "00")
      c.emit("1B", "newton_to_int", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "float":
      let valLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", valLoc, "00")
      c.emit("1B", "runtime_to_float", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "proc_fork":
      let dest = c.allocTemp()
      c.emit("1B", "sys_fork", "00", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "sys_access":
      let pathLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", pathLoc, "00")
      c.emit("1B", "sys_access", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "sys_mkdir":
      let pathLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", pathLoc, "00")
      c.emit("1B", "sys_mkdir", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "__string_ord":
      let pathLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", pathLoc, "00")
      c.emit("1B", "string_ord", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "__string_char":
      let pathLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", pathLoc, "00")
      c.emit("1B", "string_char", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "__math_xor":
      let leftLoc = c.gen(node.callArgs[0])
      let rightLoc = c.gen(node.callArgs[1])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", leftLoc, "00")
      c.emit("40", "%rsi", rightLoc, "00")
      c.emit("1B", "runtime_xor", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "sys_unlink":
      let pathLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", pathLoc, "00")
      c.emit("1B", "sys_unlink", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "proc_pid":
      let dest = c.allocTemp()
      c.emit("1B", "sys_getpid", "00", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "proc_wait":
      let dest = c.allocTemp()
      c.emit("1B", "sys_wait", "00", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "proc_wait_nohang":
      let dest = c.allocTemp()
      c.emit("1B", "sys_wait_nohang", "00", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "__alloc_array":
      let sizeLoc = c.gen(node.callArgs[0])
      let tmp = c.allocTemp()
      c.emit("40", "%rax", sizeLoc, "00")
      c.emit("1B", "alloc_flat_array", "0", "00")
      c.emit("40", tmp, "%rax", "00")
      return tmp

    if node.callName == "proc_sleep":
      let sec = c.gen(node.callArgs[0])
      c.emit("40", "%rdi", sec, "00")
      c.emit("1B", "sys_sleep", "00", "00")
      return ""

    if node.callName == "proc_exit":
      let code = c.gen(node.callArgs[0])
      c.emit("40", "%rdi", code, "00")
      c.emit("1B", "exit_program", "00", "00")
      return ""

    if node.callName == "set_index":
      let listLoc = c.gen(node.callArgs[0])
      let idxLoc = c.gen(node.callArgs[1])
      let valLoc = c.gen(node.callArgs[2])
      c.emit("40", "%rdi", listLoc, "00")
      c.emit("40", "%rsi", idxLoc, "00")
      c.emit("40", "%rdx", valLoc, "00")
      c.emit("1B", "collection_set", "0", "00")
      return ""

    if node.callName == "typeof":
      let valLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("03", dest, "0", "00")
      c.emit("0T", dest, valLoc, "00")
      return dest

    if node.callName == "sys_err":
      # File Information
      var rawSourceLine = "<source code unavailable>"
      try:
        let fileLines = readFile(currentCompilingFile).splitLines()
        if node.line > 0 and node.line <= fileLines.len:
          rawSourceLine = fileLines[node.line - 1].strip()
      except IOError:
          rawSourceLine = "<file not found during runtime>"

      let fileNode = AstNode(kind: nkLiteral, strVal: currentCompilingFile, isString: true)
      let codeNode = AstNode(kind: nkLiteral, strVal: rawSourceLine, isString:true)

      let codeLoc = c.gen(codeNode)
      let filenameLoc = c.gen(fileNode)
      let msgLoc = c.gen(node.callArgs[0])
      let lineNum = node.line
      let taggedLine = (lineNum shl 1) or 1
      let lineLoc = "$" & $taggedLine

      c.emit("40", "%rdi", filenameLoc, "00")
      c.emit("40", "%rsi", lineLoc, "00")
      c.emit("40", "%rdx", codeLoc, "00")
      c.emit("40", "%rcx", msgLoc, "00")
      c.emit("1B", "sys_log_err", "0", "00")
      return ""

    if node.callName == "sys_open":
      let dest = c.allocTemp()
      let path = c.gen(node.callArgs[0])
      let flags = c.gen(node.callArgs[1])
      c.emit("03", dest, "0", "00")
      c.emit("28", dest, path, flags)
      return dest

    if node.callName == "sys_free":
      let varLoc = c.gen(node.callArgs[0])
      c.emit("0I", varLoc, "00", "00")
      return

    if node.callName == "sys_write":
      let fd = c.gen(node.callArgs[0])
      let data = c.gen(node.callArgs[1])
      c.emit("29", fd, data, "00")
      return ""

    if node.callName == "sys_read":
      let dest = c.allocTemp()
      let fd = c.gen(node.callArgs[0])
      let len = c.gen(node.callArgs[1])
      c.emit("03", dest, "0", "00")
      c.emit("2A", dest, fd, len)
      return dest

    if node.callName == "sys_close":
      let fd = c.gen(node.callArgs[0])
      c.emit("2B", fd, "00", "00")
      return ""

    if node.callName == "net_create":
      let dest = c.allocTemp()
      c.emit("1B", "runtime_net_create", "0", dest)
      return dest

    if node.callName == "net_bind":
      let fd = c.gen(node.callArgs[0])
      let port = c.gen(node.callArgs[1])
      let dummy = c.allocTemp()
      c.emit("40", "%rdi", fd, "00")
      c.emit("40", "%rsi", port, "00")
      c.emit("1B", "runtime_net_bind", "0", dummy)
      return fd

    if node.callName == "net_listen":
      let fd = c.gen(node.callArgs[0])
      let dummy = c.allocTemp()
      c.emit("40", "%rdi", fd, "00")
      c.emit("1B", "runtime_net_listen", "0", dummy)
      return fd

    if node.callName == "net_accept":
      let serverFd = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", serverFd, "00")
      c.emit("1B", "runtime_net_accept", "0", dest)
      return dest

    if node.callName == "net_connect":
      let fd = c.gen(node.callArgs[0])
      let port = c.gen(node.callArgs[1])
      let ip = c.gen(node.callArgs[2])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", fd, "00")
      c.emit("40", "%rsi", port, "00")
      c.emit("40", "%rdx", ip, "00")
      c.emit("1B", "runtime_net_connect", "0", dest)
      return dest

    if node.callName == "net_send":
      let fd = c.gen(node.callArgs[0])
      let data = c.gen(node.callArgs[1])
      let dummy = c.allocTemp()
      c.emit("40", "%rdi", fd, "00")
      c.emit("40", "%rsi", data, "00")
      c.emit("1B", "runtime_net_send", "0", dummy)
      return fd

    if node.callName == "net_close":
      let fd = c.gen(node.callArgs[0])
      let dummy = c.allocTemp()
      c.emit("40", "%rdi", fd, "00")
      c.emit("1B", "runtime_net_close", "0", dummy)
      return fd

    if node.callName == "net_recv":
      let fd = c.gen(node.callArgs[0])
      let size = c.gen(node.callArgs[1])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", fd, "00")
      c.emit("40", "%rsi", size, "00")
      c.emit("1B", "runtime_net_recv", "0", dest)
      return dest

    if node.callName == "read_file":
      let pathLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", pathLoc, "00")
      c.emit("1B", "read_file", "0", dest)
      return dest

    if node.callName == "__file_write_bin":
      let fileLoc = c.gen(node.callArgs[0])
      let writeLoc = c.gen(node.callArgs[1])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", fileLoc, "00")
      c.emit("40", "%rsi", writeLoc, "00")
      c.emit("1B", "sys_write_bytes", "0", dest)
      return dest

    if node.callName == "del_opcode":
      let mapLoc = c.gen(node.callArgs[0])
      let keyLoc = c.gen(node.callArgs[1])
      c.emit("04", mapLoc, keyLoc, "00")
      return ""

    if node.callName == "sys_exec":
      let cmdLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", cmdLoc, "00")
      c.emit("1B", "sys_exec", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return ""

    if node.callName == "sys_argv":
      let indexNode = node.callArgs[0]
      let indexLoc = c.gen(indexNode)
      let dest = c.allocTemp()
      c.emit("03", dest, "0", "00")
      c.emit("2C", indexLoc, dest, "00")
      return dest

    if node.callName == "sys_argc":
      let blank = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", blank, "00")
      c.emit("1B", "sys_argc", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "__sys_getenv":
      let keyLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", keyLoc, "00")
      c.emit("1B", "sys_getenv", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "__sys_time_now":
      let dest = c.allocTemp()
      c.emit("1B", "sys_time_now", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "substring":
      let strLoc = c.gen(node.callArgs[0])
      let startLoc = c.gen(node.callArgs[1])
      let lenLoc = c.gen(node.callArgs[2])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", strLoc, "00")
      c.emit("40", "%rsi", startLoc, "00")
      c.emit("40", "%rdx", lenLoc, "00")
      c.emit("1B", "string_substring", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "__file_size":
      let fdLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", fdLoc, "00")
      c.emit("1B", "sys_file_size", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest

    if node.callName == "__net_sendfile":
      let outFd = c.gen(node.callArgs[0])
      let inFd = c.gen(node.callArgs[1])
      let countLoc = c.gen(node.callArgs[2])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", outFd, "00")
      c.emit("40", "%rsi", inFd, "00")
      c.emit("40", "%rdx", countLoc, "00")
      c.emit("1B", "runtime_net_sendfile", "0", dest)
      return dest

    if node.callName.startsWith("#"):
        let c_symbol = node.callName[1..^1]
        let regs = @["%rdi", "%rsi", "%rdx", "%rcx", "%r8", "%r9"]
        var argLocs: seq[string] = @[]

        for i in 0 ..< min(node.callArgs.len, 6):
            argLocs.add(c.gen(node.callArgs[i]))

        for i in 0 ..< argLocs.len:
            c.emit("40", regs[i], argLocs[i], "00")

        let dest = c.allocTemp()
        if not dest.contains("(%rbp)"): c.emit("03", dest, "0", "00")
        c.emit("1I", c_symbol, "0", "00")
        c.emit("40", dest, "%rax", "00")
        return dest

    if node.callName == "prints":
      for arg in node.callArgs:
          let loc = c.gen(arg)
          c.emit("1F", loc, "00", "00")
      return ""

    let funcName = node.callName
    if not checks.functionRegistry.hasKey(funcName):
        ERR("Attemp to call undefined function '" & funcName & "'. If this is a variable, prefix using '$'.", node.line, "E010", "Variables require the '$' prefix to be read.")

    checks.validateCall(funcName, node.callArgs.len, node.line)

    var argCount = 0
    for i in countdown(node.callArgs.len - 1, 0):
        let arg = node.callArgs[i]
        let val = c.gen(arg)
        let tmp = c.allocTemp()
        if not tmp.contains("(%rbp)"): c.emit("03", tmp, "0", "00")
        c.emit("0G", tmp, val, "00")
        c.emit("1A", tmp, "00", "00")
        argCount.inc()

    var dest = c.allocTemp()
    if not dest.contains("(%rbp)"): c.emit("03", dest, "0", "00")
    c.emit("1B", "[F_" & funcName & "]", $argCount, dest)

    if not node.autoUnwrap:
      let taggedLine = (node.line shl 1) or 1
      c.emit("40", "%rdi", dest, "00")
      c.emit("40", "%rsi", "$" & $taggedLine, "00")
      c.emit("1B", "runtime_auto_unwrap", "0", "00")
      c.emit("40", dest, "%rax", "00")
    return dest

  of nkFloatLit:
    let lbl = "FLT_" & $c.allocLabel()
    c.emit("3B", lbl, node.strVal, "00")
    let res = c.allocTemp()
    c.emit("3A", lbl, "xmm0", "00")
    c.emit("1B", "newton_box_float", "0", "00")
    c.emit("40", res, "%rax", "00")
    return res

  of nkCallDynamic:
    let funcPtrLoc = c.gen(node.callTarget)
    var argCount = 0
    for i in countdown(node.callArgs.len - 1, 0):
        let arg = node.callArgs[i]
        let val = c.gen(arg)
        let tmp = c.allocTemp()
        if not tmp.contains("(%rbp)"): c.emit("03", tmp, "0", "00")
        c.emit("0G", tmp, val, "00")
        c.emit("1A", tmp, "00", "00")
        argCount.inc()

    var dest = c.allocTemp()
    if not dest.contains("(%rbp)"): c.emit("03", dest, "0", "00")
    c.emit("1G", funcPtrLoc, $argCount, dest)
    if node.autoUnwrap:
      let taggedLine = (node.line shl 1) or 1
      c.emit("40", "%rdi", dest, "00")
      c.emit("40", "%rsi", "$" & $taggedLine, "00")
      c.emit("1B", "runtime_auto_unwrap", "0", "00")
      c.emit("40", dest, "%rax", "00")
    return dest

  of nkBinaryOp:
    let leftLoc = c.gen(node.left)
    let rightLoc = c.gen(node.right)

    if node.op in ["+", "-", "*", "/", "%", ">>", "shl"]:
        let res = c.allocTemp()
        c.emit("40", "%rdi", leftLoc, "00")
        c.emit("40", "%rsi", rightLoc, "00")
        case node.op
        of "+": c.emit("1B", "runtime_add", "0", "00")
        of "-": c.emit("1B", "runtime_sub", "0", "00")
        of "*": c.emit("1B", "runtime_mul", "0", "00")
        of "/": c.emit("1B", "runtime_div", "0", "00")
        of "%": c.emit("1B", "runtime_mod", "0", "00")
        of ">>": c.emit("1B", "runtime_shr", "0", "00")
        of "shl": c.emit("1B", "runtime_shl", "0", "00")
        else: discard
        c.emit("40", res, "%rax", "00")
        return res

    if node.op in ["<", ">", "==", "!=", "<=", ">=", "and", "or", "not", "^"]:
        let res = c.allocTemp()
        c.emit("40", "%rdi", leftLoc, "00")
        c.emit("40", "%rsi", rightLoc, "00")
        case node.op
        of "<":   c.emit("1B", "runtime_lt", "0", "00")
        of ">":   c.emit("1B", "runtime_gt",  "0", "00")
        of "==":  c.emit("1B", "runtime_eq",  "0", "00")
        of "!=":  c.emit("1B", "runtime_neq", "0", "00")
        of "<=":  c.emit("1B", "runtime_le",  "0", "00")
        of ">=":  c.emit("1B", "runtime_ge",  "0", "00")
        of "and": c.emit("1B", "runtime_and", "0", "00")
        of "or":  c.emit("1B", "runtime_or",  "0", "00")
        of "not": c.emit("1B", "runtime_not", "0", "00")
        of "^":   c.emit("1B", "runtime_xor", "0", "00")
        else: discard
        c.emit("40", res, "%rax", "00")
        return res

  of nkInfix:
    if node.op == "<<":
        let dest = c.allocTemp()
        c.emit("03", dest, "0", "00")
        let leftLoc = c.gen(node.left)
        let rightLoc = c.gen(node.right)
        c.emit("2D", dest, leftLoc, rightLoc)
        return dest
    return ""

  of nkIf:
    let elseLabel = c.newLabel()
    let endLabel = c.newLabel()
    let condRaw = c.gen(node.condition)
    let condLoc = c.ensureLocation(condRaw)
    c.emit("0P", condLoc, elseLabel, "00")

    if node.thenBranch.kind == nkBlock:
        for stmt in node.thenBranch.blockStmts: discard c.gen(stmt)
    else: discard c.gen(node.thenBranch)

    c.emit("0B", "[$#]" % endLabel, "00", "00")
    c.emit("0J", "[$#]" % elseLabel, "00", "00")

    if node.elseBranch != nil:
        if node.elseBranch.kind == nkBlock:
            for stmt in node.elseBranch.blockStmts: discard c.gen(stmt)
        else: discard c.gen(node.elseBranch)

    c.emit("0J", "[$#]" % endLabel, "00", "00")
    return ""

  of nkLoop:
    if node.loopType == "for":
      let iterName = node.loopArgs[0].strVal
      let startNode = node.loopArgs[1]
      let endNode = node.loopArgs[2]
      let stepNode = node.loopArgs[3]

      let iterLoc = c.allocVar()
      c.locals[iterName] = iterLoc

      let startLoc = c.gen(startNode)
      c.emit("0A", c.ensureLocation(startLoc), iterLoc, "00")

      let loopStart = c.newLabel()
      let loopEnd = c.newLabel()

      c.emit("0J", loopStart, "00", "00")

      let endRaw = c.gen(endNode)
      let endLoc = c.ensureLocation(endRaw)
      let cmpRes = c.allocTemp()
      c.emit("40", "%rdi", iterLoc, "00")
      c.emit("40", "%rsi", endLoc, "00")
      c.emit("1B", "runtime_lt", "0", "00")
      c.emit("40", cmpRes, "%rax", "00")
      c.emit("0P", cmpRes, loopEnd, "00")

      c.loopStack.add(loopEnd)

      if node.loopBody.kind == nkBlock:
        for stmt in node.loopBody.blockStmts: discard c.gen(stmt)
      else: discard c.gen(node.loopBody)

      discard c.loopStack.pop()


      let stepRaw = c.gen(stepNode)
      let stepLoc = c.ensureLocation(stepRaw)
      c.emit("40", "%rdi", iterLoc, "00")
      c.emit("40", "%rsi", stepLoc, "00")
      c.emit("1B", "runtime_add", "0", "00")
      c.emit("40", iterLoc, "%rax", "00")

      c.emit("0B", loopStart, "00", "00")
      c.emit("0J", loopEnd, "00", "00")
      return ""
    else: return ""

  of nkWhile:
    let loopStart = c.newLabel()
    let loopEnd = c.newLabel()
    c.emit("0J", loopStart, "00", "00")
    let condRaw = c.gen(node.whileCondition)
    let condLoc = c.ensureLocation(condRaw)
    c.emit("0P", condLoc, loopEnd, "00")

    c.loopStack.add(loopEnd)

    if node.whileBody.kind == nkBlock:
        for stmt in node.whileBody.blockStmts: discard c.gen(stmt)
    else: discard c.gen(node.whileBody)

    discard c.loopStack.pop()

    c.emit("0B", loopStart, "00", "00")
    c.emit("0J", loopEnd, "00", "00")
    return ""

  of nkFunction:
    let skipLabel = c.newLabel()
    c.emit("0B", "[$#]" % skipLabel, "00", "00")

    if node.fnExpo:
        let fnLabel = "F_" & node.fnName
        c.emit("1H", "[$#]" % fnLabel, "00", "00")
        c.emit("0J", "[$#]" % fnLabel, "00", "00")
    else:
        let fnLabel = "F_" & node.fnName
        c.emit("0J", "[$#]" % fnLabel, "00", "00")

    let oldLocals = c.locals
    let oldStack = c.stackOffset
    c.inFunction = true
    c.stackOffset = 0
    registerFunction(node.fnName, node.fnArgs.len)
    c.currentFuncName = node.fnName
    c.currentFnArgs = node.fnArgs
    c.currentTcoLabel = c.newLabel()
    c.locals = initTable[string, string]()

    let fnPrologueIdx = c.output.len
    c.emit("41", "_NULL", "00", "00")

    for i, argName in node.fnArgs:
      let reg = c.allocVar()
      c.locals[argName] = reg
      c.emit("03", reg, "0", "00")
      c.emit("1D", reg, $i, "00")

    c.emitLabel(c.currentTcoLabel)

    discard c.gen(node.fnBody)

    if node.fnName == "main":
        c.emit("40", "%rdi", "0", "00")

    if c.output.len == 0 or not c.output[^1].startsWith("1C"):
        c.emit("1C", "00", "00", "00")

    # Collecting function stack footprint
    var fnStackNeeded = -c.stackOffset
    fnStackNeeded = (fnStackNeeded + 15) and not 15
    if fnStackNeeded == 0: fnStackNeeded = 16
    c.output[fnPrologueIdx] = "41 $# 00 00" % $fnStackNeeded

    c.locals = oldLocals
    c.stackOffset = oldStack
    c.inFunction = false
    c.emit("0J", "[$#]" % skipLabel, "00", "00")
    return ""

  of nkReturn:
    if node.returnVal != nil:
      if (node.returnVal.kind == nkCall or node.returnVal.kind == nkCommand) and node.returnVal.callName == c.currentFuncName:
        var evaledArgs: seq[string] = @[]

        for i in 0 ..< node.returnVal.callArgs.len:
            let arg = node.returnVal.callArgs[i]
            let val = c.gen(arg)
            let tmp = c.allocTemp()
            if not tmp.contains("(%rbp)"): c.emit("03", tmp, "0", "00")
            c.emit("0G", tmp, val, "00")
            evaledArgs.add(tmp)

        for i in 0 ..< node.returnVal.callArgs.len:
            if i < c.currentFnArgs.len:
                let argName = c.currentFnArgs[i]
                if c.locals.hasKey(argName):
                    let argReg = c.locals[argName]
                    c.emit("0G", argReg, evaledArgs[i], "00")

        c.emit("0B", "[$#]" % c.currentTcoLabel, "00", "00")
        return ""

      let retRaw = c.gen(node.returnVal)
      if retRaw != "[sra]":
          c.emit("0G", "[sra]", retRaw, "00")
      c.emit("1C", "00", "00", "00")
    else:
      c.emit("1C", "00", "00", "00")
    return ""

  of nkForeachFile:
    let targetLoc = c.gen(node.fileLoopTarget)
    let fpReg = c.allocTemp()
    c.emit("40", "%rdi", targetLoc, "00")
    c.emit("1B", "newton_fopen", "0", "00")
    c.emit("40", fpReg, "%rax", "00")

    let startLabel = c.newLabel()
    let endLabel = c.newLabel()
    c.emitLabel(startLabel)

    let lineReg = c.allocTemp()
    c.emit("40", "%rdi", fpReg, "00")
    c.emit("1B", "newton_getline", "0", "00")
    c.emit("40", lineReg, "%rax", "00")

    c.emit("0P", lineReg, endLabel, "00")

    let varReg = c.allocVar()
    c.locals[node.fileLoopVar] = varReg
    c.emit("03", varReg, "0", "00")
    c.emit("0G", varReg, lineReg, "00")

    discard c.gen(node.fileLoopBody)
    c.emit("0B", "[$#]" % startLabel, "00", "00")

    c.emitLabel(endLabel)
    c.emit("40", "%rdi", fpReg, "00")
    c.emit("1B", "newton_fclose", "0", "00")
    return ""

  # --- 2. THE ORIGINAL COLLECTION ITERATOR ---
  of nkForeachMap:
    let targetLoc = c.gen(node.mapLoopTarget)

    # Get the length of the Array/Map using our new universal sizeof
    let lenReg = c.allocTemp()
    c.emit("40", "%rdi", targetLoc, "00")
    c.emit("1B", "newton_sizeof", "0", "00")
    c.emit("40", lenReg, "%rax", "00")

    # Initialize index counter (Tagged 0 is '1')
    let idxReg = c.allocTemp()
    c.emit("03", idxReg, "1", "00")

    let startLabel = c.newLabel()
    let endLabel = c.newLabel()
    c.emitLabel(startLabel)

    # Check Bounds: if idx >= length, jump to end
    let cmpReg = c.allocTemp()
    c.emit("40", "%rdi", idxReg, "00")
    c.emit("40", "%rsi", lenReg, "00")
    c.emit("1B", "runtime_lt", "0", "00")  # Native Less-Than check
    c.emit("40", cmpReg, "%rax", "00")
    c.emit("0P", cmpReg, endLabel, "00")   # 0P jumps if False

    # Assign &<key> to the current Index
    let keyVar = c.allocVar()
    c.locals[node.mapLoopKey] = keyVar
    c.emit("03", keyVar, "0", "00")
    c.emit("40", "%rdi", targetLoc, "00")
    c.emit("40", "%rsi", idxReg, "00")
    c.emit("1B", "collection_get_key", "0", "00")
    c.emit("40", keyVar, "%rax", "00")

    # Assign &<val> to collection_get(target, index)
    let valVar = c.allocVar()
    c.locals[node.mapLoopVal] = valVar
    c.emit("03", valVar, "0", "00")
    c.emit("40", "%rdi", targetLoc, "00")
    c.emit("40", "%rsi", idxReg, "00")
    c.emit("1B", "collection_get", "0", "00")
    c.emit("40", valVar, "%rax", "00")

    # Execute Block
    discard c.gen(node.mapLoopBody)

    # Increment index natively
    c.emit("40", "%rdi", idxReg, "00")
    c.emit("1B", "newton_inc", "0", "00")
    c.emit("40", idxReg, "%rax", "00")

    c.emit("0B", "[$#]" % startLabel, "00", "00")
    c.emitLabel(endLabel)
    return ""

  of nkBlock:
    for stmt in node.blockStmts: discard c.gen(stmt)
    return ""

  of nkAssignment:
    let valLoc = c.gen(node.varValue)
    var addrStr = ""
    if c.locals.hasKey(node.varName): addrStr = c.locals[node.varName]
    elif c.globals.hasKey(node.varName): addrStr = c.globals[node.varName]
    else: raise newException(ValueError, "Error: Reassignment to undefined variable '" & node.varName & "'")
    c.emit("0G", addrStr, valLoc, "00")
    return ""

  of nkInput:
    let dest = c.allocTemp()
    c.emit("01", dest, "00", "00")
    return dest

  of nkMapLit:
    let mapLoc = c.allocTemp()
    c.emit("03", mapLoc, "0", "00")
    c.emit("20", mapLoc, "00", "00")

    if node.isList:
      for i, valNode in node.mapValues:
        let valLoc = c.gen(valNode)
        let taggedVal = (i shl 1) or 1
        let indexLoc = "$" & $taggedVal
        c.emit("21", mapLoc, indexLoc, valLoc)
    else:
      for i in 0 ..< node.mapKeys.len:
        let keyLoc = c.gen(node.mapKeys[i])
        let valLoc = c.gen(node.mapValues[i])
        c.emit("21", mapLoc, keyLoc, valLoc)
    return mapLoc

  of nkMapGet:
    let mapLoc = c.gen(node.targetMap)
    let keyLoc = c.gen(node.targetKey)
    let dest = c.allocTemp()
    c.emit("40", "%rdi", mapLoc, "00")
    c.emit("40", "%rsi", keyLoc, "00")
    c.emit("1B", "collection_get", "0", "00")
    c.emit("40", dest, "%rax", "00")
    return dest

  # --- [NEW] DESTRUCTURING ---
  of nkDestructDecl:
    let valLoc = c.gen(node.destructVal)
    let destMap = c.allocTemp()
    c.emit("0G", destMap, valLoc, "00")

    for i, name in node.destructNames:
        let reg = c.allocVar()
        c.locals[name] = reg
        c.emit("03", reg, "0", "00")

        let tmp = c.allocTemp()
        c.emit("40", "%rdi", destMap, "00")
        let taggedIdx = (i shl 1) or 1
        c.emit("40", "%rsi", "$" & $taggedIdx, "00")
        c.emit("1B", "collection_get", "0", "00")
        c.emit("40", tmp, "%rax", "00")
        c.emit("0G", reg, tmp, "00")
    return ""

  of nkMatch:
    let targetLoc = c.gen(node.matchTarget)
    let endLabel = c.newLabel()

    for branch in node.matchBranches:
        let nextLabel = c.newLabel()
        let condLoc = c.gen(branch.branchCond)
        let tmp = c.allocTemp()

        c.emit("40", "%rdi", targetLoc, "00")
        c.emit("40", "%rsi", condLoc, "00")
        c.emit("1B", "runtime_eq", "0", "00")
        c.emit("40", tmp, "%rax", "00")
        c.emit("0P", tmp, nextLabel, "00")

        discard c.gen(branch.branchBody)
        c.emit("0B", "[$#]" % endLabel, "00", "00")  # JMP endLabel

        c.emitLabel(nextLabel)

    c.emitLabel(endLabel)
    return ""

  of nkBracket:
    let arrLoc = c.allocTemp()
    let count = node.children.len
    let sizeBytes = (count * 8) + 64
    c.emit("40", "%rdi", "$" & $sizeBytes, "00")
    c.emit("1B", "new_array", "0", "00")
    c.emit("40", arrLoc, "%rax", "00")

    for i, child in node.children:
        let valLoc = c.gen(child)
        let taggedIdx = (i shl 1) or 1
        c.emit("40", "%rdi", arrLoc, "00")
        c.emit("40", "%rsi", "$" & $taggedIdx, "00")
        c.emit("40", "%rdx", valLoc, "00")
        c.emit("1B", "collection_set", "0", "00")
    return arrLoc

  else:
    echo "[Codegen] Unhandled: ", node.kind
    return ""

proc compile*(node: AstNode): seq[string] =
  let c = newCompiler()
  discard c.gen(node)
  return c.output
