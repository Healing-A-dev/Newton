import strutils, tables, ast

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
  result.varTypes = initTable[string, string]() # Initialize Type Table

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
      of 'n': result.add('\L') # Add real newline (Line Feed)
      of 't': result.add('\t') # Add real tab
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
                i += 2 # Skip 'xHH' (total 4 chars consumed by loop inc)
            except ValueError:
                # Invalid hex, treat as literal 'x'
                result.add('x')
        else:
            result.add('x')
      else:
        # Unknown escape, keep literal
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
        c.emit("0H", "$00", "50", "00")
        c.emit("0H", "@00", "50", "00")
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

        # --- PASS 1: Compile Functions ---
        for stmt in node.stmts:
          if stmt.kind == nkFunction:
            discard c.gen(stmt)

        # --- Entry Point Logic ---
        c.emit("0J", "[$#]" % mainLabel, "00", "00")
        c.emitLabel(mainLabel)

        # [FIX 1] Terminate Stack Frame Chain
        # Push 0 so that RBP points to NULL. This stops stack walkers (like exit()) from crashing.
        c.emit("1A", "$0", "00", "00")

        # [FIX 2] Setup Frame
        c.emit("0A", "%rsp", "%rbp", "00")

        # [FIX 3] Alignment Padding
        # We need total pushes to be even (to maintain 16-byte alignment).
        # We pushed once for the Chain (Step 1).
        # We will push 128 times for locals.
        # Total = 129 (Odd). So we add ONE padding push here to make it 130 (Even).
        c.emit("1A", "$0", "00", "00") 

        # [FIX 4] Reserve Locals (128 slots)
        for i in 0..128:
            c.emit("1A", "$0", "00", "00")

        c.emit("03", "%sp", "0", "00")      # Dummy alloc

        c.inFunction = true
        c.stackOffset = 0

        # --- PASS 2: Compile Globals & Main Body ---
        for stmt in node.stmts:
           if stmt.kind != nkFunction:
            discard c.gen(stmt)

        # [FIX 5] No Teardown
        # Do not try to restore RSP. Just exit with the deep stack.
        c.emit("0L", "0", "00", "00") # EXIT
        c.emit("0I", "$00", "00", "00")
        c.emit("0I", "@00", "00", "00")
        c.emit("0I", "%00", "00", "00")
        return ""
        
  of nkVarDecl:
    # 1. DETECT TYPE (Critical for Strings)
    var vType = "int"
    if node.varValue.kind == nkLiteral and node.varValue.isString:
        vType = "string"
    elif node.varValue.kind == nkVarRef and c.varTypes.hasKey(node.varValue.refName):
        vType = c.varTypes[node.varValue.refName]

    c.varTypes[node.varName] = vType # Save Type Info

    # 2. Optimization: INC
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

    # Detect Global Type
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
        # Fallback for floats or weird formats
        return node.strVal

  of nkCommand, nkCall:
    if node.callName == "stdout":
      for arg in node.callArgs:
        let loc = c.gen(arg)
        var isString = false

        if arg.kind == nkLiteral and arg.isString: isString = true
        elif arg.kind == nkVarRef and c.varTypes.getOrDefault(arg.refName, "int") == "string": isString = true

        if isString:
             c.emit("1F", loc, "00", "00") # Opcode 1F: WRITES (String)
        else:
             c.emit("02", loc, "1", "00")  # Opcode 02: WRITE (Int/Generic)
      return ""

    if node.callName == "len":
      let mapArg = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("03", dest, "0", "00")
      c.emit("23", dest, mapArg, "00")
      return dest

    if node.callName == "string":
      let valLoc = c.gen(node.callArgs[0]) # Generate code for the argument (e.g., $i)
      let dest = c.allocTemp()             # Create a temporary variable for the result string
      c.emit("0O", dest, valLoc, "00")
      return dest
#
    if node.callName == "int":
      let valLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", valLoc, "00")      # Load Argument
      c.emit("1B", "runtime_to_int", "0", "00") # Call Runtime
      c.emit("40", dest, "%rax", "00")        # Store Result
      return dest

    if node.callName == "float":
      let valLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("40", "%rdi", valLoc, "00")
      c.emit("1B", "runtime_to_float", "0", "00")
      c.emit("40", dest, "%rax", "00")
      return dest
#
    if node.callName == "proc_fork":
      let dest = c.allocTemp()
      c.emit("1B", "sys_fork", "00", "00")
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

      # [FIX] Use Runtime Call directly
      c.emit("40", "%rdi", listLoc, "00")
      c.emit("40", "%rsi", idxLoc, "00")
      c.emit("40", "%rdx", valLoc, "00")
      c.emit("1B", "collection_set", "0", "00")
      return ""

    if node.callName == "typeof":
      let valLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("03", dest, "0", "00")
      c.emit("0T", dest, valLoc, "00") # Opcode 0T
      return dest

    if node.callName == "sys_err":
      let msgLoc = c.gen(node.callArgs[0])
      let lineNum = node.line
      let taggedLine = (lineNum shl 1) or 1
      let lineLoc = "$" & $taggedLine
      c.emit("40", "%rdi", msgLoc, "00")  # Arg 1: Message
      c.emit("40", "%rsi", lineLoc, "00") # Arg 2: Line Number
      c.emit("1B", "sys_log_err", "0", "00")
      return ""

    if node.callName == "sys_open":
      let dest = c.allocTemp()
      let path = c.gen(node.callArgs[0])
      let flags = c.gen(node.callArgs[1])
      c.emit("03", dest, "0", "00")
      c.emit("28", dest, path, flags) # FOPEN
      return dest

    if node.callName == "sys_free":
      let varLoc = c.gen(node.callArgs[0])
      c.emit("0I", varLoc, "00", "00") # Emit FREE opcode
      return

    if node.callName == "sys_write":
      let fd = c.gen(node.callArgs[0])
      let data = c.gen(node.callArgs[1])
      c.emit("29", fd, data, "00") # FWRITE
      return ""

    if node.callName == "sys_read":
      let dest = c.allocTemp()
      let fd = c.gen(node.callArgs[0])
      let len = c.gen(node.callArgs[1])
      c.emit("03", dest, "0", "00")
      c.emit("2A", dest, fd, len) # FREAD
      return dest

    if node.callName == "sys_close":
      let fd = c.gen(node.callArgs[0])
      c.emit("2B", fd, "00", "00") # FCLOSE
      return ""

    if node.callName == "net_create":
      let dest = c.allocTemp()
      c.emit("50", dest, "0", "0")
      return dest

    if node.callName == "net_bind":
      let fd = c.gen(node.callArgs[0])
      let port = c.gen(node.callArgs[1])
      c.emit("51", fd, port, "0")
      return fd

    if node.callName == "net_listen":
      let fd = c.gen(node.callArgs[0])
      c.emit("52", fd, "0", "0")
      return fd

    if node.callName == "net_accept":
      let serverFd = c.gen(node.callArgs[0])
      let clientFd = c.allocTemp()
      c.emit("53", clientFd, serverFd, "0")
      return clientFd

    if node.callName == "net_send":
      let fd = c.gen(node.callArgs[0])
      let data = c.gen(node.callArgs[1])
      c.emit("54", fd, data, "0")
      return fd

    if node.callName == "net_close":
      let fd = c.gen(node.callArgs[0])
      c.emit("55", fd, "0", "0")
      return fd

    if node.callName == "net_recv":
      let fd = c.gen(node.callArgs[0])
      let size = c.gen(node.callArgs[1])
      let dest = c.allocTemp()
      c.emit("56", dest, fd, size)
      return dest

    if node.callName == "read_file":
      let pathLoc = c.gen(node.callArgs[0])
      let dest = c.allocTemp()
      c.emit("2E", dest, pathLoc, "00")
      return dest

    if node.callName == "del_opcode":
      let mapLoc = c.gen(node.callArgs[0])
      let keyLoc = c.gen(node.callArgs[1])
      c.emit("04", mapLoc, keyLoc, "00")
      return ""

    if node.callName == "sys_exec":
      let cmdLoc = c.gen(node.callArgs[0])
      c.emit("40", "%rdi", cmdLoc, "00")
      c.emit("1B", "sys_exec", "0", "00")
      return ""

    if node.callName == "sys_argv":
      let indexNode = node.callArgs[0]
      let indexLoc = c.gen(indexNode)
      let dest = c.allocTemp()
      c.emit("03", dest, "0", "00") # Init dest to 0
      c.emit("2C", indexLoc, dest, "00")
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

    # 3. Handle Intrinsic 'prints' (Force String Output)
    if node.callName == "prints":
      for arg in node.callArgs:
          let loc = c.gen(arg)
          c.emit("1F", loc, "00", "00") # WRITES
      return ""

    # 4. Handle Regular Function Calls (F_Function)
    let funcName = node.callName
    var argCount = 0

    # Push Args Reverse (Right-to-Left)
    for i in countdown(node.callArgs.len - 1, 0):
        let arg = node.callArgs[i]
        let val = c.gen(arg)
        let tmp = c.allocTemp()
        if not tmp.contains("(%rbp)"): c.emit("03", tmp, "0", "00")
        c.emit("0G", tmp, val, "00")
        c.emit("1A", tmp, "00", "00") # PUSH
        argCount.inc()

    var dest = c.allocTemp()
    if not dest.contains("(%rbp)"): c.emit("03", dest, "0", "00")

    c.emit("1B", "[F_" & funcName & "]", $argCount, dest)
    return dest

  of nkFloatLit:
    let lbl = "FLT_" & $c.allocLabel()
    #c.dataSection.add(lbl & ": .double " & node.strVal & "\n")
    c.emit("3B", lbl, node.strVal, "00")
    let res = c.allocTemp()

    c.emit("3A", lbl, "xmm0", "00")
    c.emit("1B", "newton_box_float", "0", "00")
    c.emit("40", res, "%rax", "00")
    return res

  of nkCallDynamic:
    # 1. Resolve the Function Pointer (e.g., resolve $func -> -8(%rbp))
    let funcPtrLoc = c.gen(node.callTarget)
    var argCount = 0
    for i in countdown(node.callArgs.len - 1, 0):
        let arg = node.callArgs[i]
        let val = c.gen(arg)

        # Move to temp and Push
        let tmp = c.allocTemp()
        if not tmp.contains("(%rbp)"): c.emit("03", tmp, "0", "00")
        c.emit("0G", tmp, val, "00")
        c.emit("1A", tmp, "00", "00") # PUSH
        argCount.inc()

    var dest = c.allocTemp()
    if not dest.contains("(%rbp)"): c.emit("03", dest, "0", "00")
    c.emit("1G", funcPtrLoc, $argCount, dest)

    return dest

  of nkBinaryOp:
    # 1. Generate Operands
    let leftLoc = c.gen(node.left)
    let rightLoc = c.gen(node.right)

    # 2. Handle Arithmetic (+, -, *, /) via Runtime
    if node.op in ["+", "-", "*", "/"]:
        let res = c.allocTemp()
        c.emit("40", "%rdi", leftLoc, "00")
        c.emit("40", "%rsi", rightLoc, "00")

        # Call the appropriate Runtime Function
        case node.op
        of "+": c.emit("1B", "runtime_add", "0", "00") # 1B = CALL
        of "-": c.emit("1B", "runtime_sub", "0", "00")
        of "*": c.emit("1B", "runtime_mul", "0", "00")
        of "/": c.emit("1B", "runtime_div", "0", "00")
        else: discard

        # Move Result (RAX) to our temporary variable
        c.emit("40", res, "%rax", "00")
        return res

    if node.op in ["<", ">", "==", "!=", "<=", ">=", "and", "or", "not"]:
        let res = c.allocTemp()

        c.emit("40", "%rdi", leftLoc, "00")
        c.emit("40", "%rsi", rightLoc, "00")

        case node.op
        of "<":   c.emit("1B", "runtime_lt",  "0", "00")
        of ">":   c.emit("1B", "runtime_gt",  "0", "00")
        of "==":  c.emit("1B", "runtime_eq",  "0", "00")
        of "!=":  c.emit("1B", "runtime_neq", "0", "00")
        of "<=":  c.emit("1B", "runtime_le",  "0", "00")
        of ">=":  c.emit("1B", "runtime_ge",  "0", "00")
        of "and": c.emit("1B", "runtime_and", "0", "00")
        of "or":  c.emit("1B", "runtime_or",  "0", "00")
        of "not": c.emit("1B", "runtime_not", "0", "00")
        else: discard

        c.emit("40", res, "%rax", "00")
        return res

  of nkInfix:
    # Handle String Concatenation (<<)
    if node.op == "<<":
        # 1. Allocate a temporary variable to hold the new string pointer
        let dest = c.allocTemp()
        c.emit("03", dest, "0", "00") # Initialize Dest

        # 2. Resolve Left and Right strings
        let leftLoc = c.gen(node.left)
        let rightLoc = c.gen(node.right)

        # 3. Emit Opcode 2D: CAT [dest] [str1] [str2]
        c.emit("2D", dest, leftLoc, rightLoc)

        return dest
    return ""
#
  of nkIf:
    let elseLabel = c.newLabel()
    let endLabel = c.newLabel()

    # 1. Generate Condition
    let condRaw = c.gen(node.condition)
    let condLoc = c.ensureLocation(condRaw)

    # 2. [FIX IS HERE] Emit Jump False (JF)
    # Argument 1 (d0): The Condition Variable (condLoc)
    # Argument 2 (d1): The Target Label (elseLabel)
    # Argument 3 (d2): Unused ("00")

    c.emit("0P", condLoc, elseLabel, "00")  # <--- CORRECT ORDER

    # 3. Then Branch
    if node.thenBranch.kind == nkBlock:
        for stmt in node.thenBranch.blockStmts: discard c.gen(stmt)
    else: discard c.gen(node.thenBranch)

    # Jump to End
    c.emit("0B", "[$#]" % endLabel, "00", "00")

    # 4. Else Branch
    c.emit("0J", "[$#]" % elseLabel, "00", "00") # JF Jumps here

    if node.elseBranch != nil:
        if node.elseBranch.kind == nkBlock:
            for stmt in node.elseBranch.blockStmts: discard c.gen(stmt)
        else: discard c.gen(node.elseBranch)

    # End Label
    c.emit("0J", "[$#]" % endLabel, "00", "00")
    return ""

  of nkLoop:
    if node.loopType == "for":
      # 1. SETUP VARIABLES
      let iterName = node.loopArgs[0].strVal
      let startNode = node.loopArgs[1]
      let endNode = node.loopArgs[2]
      let stepNode = node.loopArgs[3]

      # Allocate loop variable and register it in locals
      let iterLoc = c.allocVar()
      c.locals[iterName] = iterLoc

      # 2. INITIALIZATION (iter = start)
      let startLoc = c.gen(startNode)
      # Opcode 0A (COPY)
      c.emit("0A", c.ensureLocation(startLoc), iterLoc, "00")

      # 3. LABELS
      let loopStart = c.newLabel()
      let loopEnd = c.newLabel()

      # 4. START LABEL (Opcode 0J)
      c.emit("0J", loopStart, "00", "00")

      # 5. CONDITION (iter < end) -> [FIX] Use runtime_lt
      let endRaw = c.gen(endNode)
      let endLoc = c.ensureLocation(endRaw)

      let cmpRes = c.allocTemp()
      c.emit("40", "%rdi", iterLoc, "00")
      c.emit("40", "%rsi", endLoc, "00")
      c.emit("1B", "runtime_lt", "0", "00")  # Call runtime_lt
      c.emit("40", cmpRes, "%rax", "00")    # Save Result

      # 6. EXIT CHECK (Opcode 0P = JF)
      c.emit("0P", cmpRes, loopEnd, "00")

      # 7. BODY
      if node.loopBody.kind == nkBlock:
        for stmt in node.loopBody.blockStmts: discard c.gen(stmt)
      else: discard c.gen(node.loopBody)

      # 8. INCREMENT (iter += step) -> [FIX] Use runtime_add
      # We removed the 'step 1' optimization because it breaks if user mixes types (e.g. 0.0 to 10.0 step 1)
      let stepRaw = c.gen(stepNode)
      let stepLoc = c.ensureLocation(stepRaw)

      c.emit("40", "%rdi", iterLoc, "00")   # Arg 1: Iterator
      c.emit("40", "%rsi", stepLoc, "00")   # Arg 2: Step
      c.emit("1B", "runtime_add", "0", "00") # Call runtime_add
      c.emit("40", iterLoc, "%rax", "00")   # Update Iterator

      # 9. JUMP BACK
      c.emit("0B", loopStart, "00", "00")

      # 10. END LABEL
      c.emit("0J", loopEnd, "00", "00")
      return ""
    else: return ""

  of nkWhile:
    let loopStart = c.newLabel()
    let loopEnd = c.newLabel()

    # 1. Place Start Label (Opcode 0J = LBL)
    # Arg 0: Raw Label String (No brackets!)
    c.emit("0J", loopStart, "00", "00")

    # 2. Generate Condition
    let condRaw = c.gen(node.whileCondition)
    let condLoc = c.ensureLocation(condRaw)

    # 3. Exit if False (Opcode 0P = JF)
    # Arg 0: Condition Variable (condLoc)
    # Arg 1: Target Label (loopEnd) - Raw String!
    c.emit("0P", condLoc, loopEnd, "00")

    # 4. Body
    if node.whileBody.kind == nkBlock:
        for stmt in node.whileBody.blockStmts: discard c.gen(stmt)
    else: discard c.gen(node.whileBody)

    # 5. Jump Back (Opcode 0B = JMP)
    # Arg 0: Target Label (loopStart) - Raw String!
    c.emit("0B", loopStart, "00", "00")

    # 6. Place End Label (Opcode 0J = LBL)
    c.emit("0J", loopEnd, "00", "00")

    return ""
#
  of nkFunction:
    let skipLabel = c.newLabel()
    c.emit("0B", "[$#]" % skipLabel, "00", "00")

    let fnLabel = "F_" & node.fnName
    c.emit("0J", "[$#]" % fnLabel, "00", "00")

    let oldLocals = c.locals
    let oldStack = c.stackOffset
    c.inFunction = true
    c.stackOffset = 0
    c.locals = initTable[string, string]()

    for i, argName in node.fnArgs:
      let reg = c.allocVar()
      c.locals[argName] = reg
      c.emit("03", reg, "0", "00")
      c.emit("1D", reg, $i, "00")

    discard c.gen(node.fnBody)

    if c.output.len == 0 or not c.output[^1].startsWith("1C"):
        c.emit("1C", "00", "00", "00")

    c.locals = oldLocals
    c.stackOffset = oldStack
    c.inFunction = false
    c.emit("0J", "[$#]" % skipLabel, "00", "00")
    return ""

  of nkReturn:
    if node.returnVal != nil:
      let retRaw = c.gen(node.returnVal)
      if retRaw != "[sra]":
          c.emit("0G", "[sra]", retRaw, "00")
      c.emit("1C", "00", "00", "00")
    else:
      c.emit("1C", "00", "00", "00")
    return ""

  of nkForeach:
    let mapLoc = c.gen(node.loopSource)

    # 1. Setup Cursor (Head of Map)
    let cursor = c.allocTemp()
    # Ensure 03/COPY works, or use 0A
    c.emit("03", cursor, "0", "00")    # Init cursor var
    c.emit("24", cursor, mapLoc, "00") # MHEAD: cursor = map.head

    let startLabel = c.newLabel()      # Use newLabel() if allocLabel is alias
    let endLabel = c.newLabel()

    # 2. Start Label
    c.emitLabel(startLabel)

    # 3. Condition: Is Cursor == NULL?
    let zeroLoc = c.ensureLocation("0")
    c.emit("0D", cursor, zeroLoc, "00") # CMP cursor, 0 -> Returns True(3) or False(1)

    # 4. [FIX] Jump If True (0K)
    # If Cursor IS Null (True), Jump to End.
    # We pass 'endLabel' raw (no [$...]).
    # The condition is already in %rax from 0D.
    c.emit("0K", endLabel, "00", "00")

    # 5. Setup Loop Variables (Key/Val)
    var keyLoc = ""
    if c.locals.hasKey(node.loopKey):
        keyLoc = c.locals[node.loopKey]
    else:
        keyLoc = c.allocVar()
        c.locals[node.loopKey] = keyLoc
        c.emit("03", keyLoc, "0", "00")

    var valLoc = ""
    if c.locals.hasKey(node.loopVal):
        valLoc = c.locals[node.loopVal]
    else:
        valLoc = c.allocVar()
        c.locals[node.loopVal] = valLoc
        c.emit("03", valLoc, "0", "00")

    # 6. Fetch Data
    c.emit("25", keyLoc, cursor, "00") # MKEY
    c.emit("26", valLoc, cursor, "00") # MVAL

    # 7. Body
    for stmt in node.foreachBody:
        discard c.gen(stmt)

    # 8. Advance Cursor & Loop
    c.emit("27", cursor, cursor, "00") # MNEXT: cursor = cursor.next

    # [FIX] Unconditional Jump Back
    # Pass 'startLabel' raw.
    c.emit("0B", startLabel, "00", "00")

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
    # 1. Allocate a temporary variable to hold the new map
    let mapLoc = c.allocTemp()
    c.emit("03", mapLoc, "0", "00") # Initialize temp

    # 2. Emit the NEWMAP instruction (Opcode 20)
    c.emit("20", mapLoc, "00", "00")

    # 3. Populate the Map
    if node.isList:
      # CASE A: It is a List ("A", "B") -> Auto-generate Integer Keys 0, 1...
      for i, valNode in node.mapValues:
        let valLoc = c.gen(valNode)
        let taggedVal = (i shl 1) or 1
        let indexLoc = "$" & $taggedVal

        c.emit("21", mapLoc, indexLoc, valLoc)

    else:
      # CASE B: It is a Dictionary (Key: Val)
      for i in 0 ..< node.mapKeys.len:
        let keyLoc = c.gen(node.mapKeys[i])
        let valLoc = c.gen(node.mapValues[i])

        # MSET map, key, value
        c.emit("21", mapLoc, keyLoc, valLoc)

    # 4. Return the location of the map so it can be assigned to a variable
    return mapLoc

  of nkMapGet:
    let mapLoc = c.gen(node.targetMap)
    let keyLoc = c.gen(node.targetKey)
    let dest = c.allocTemp()

    # [FIX] Ensure we use valid registers for the call
    c.emit("40", "%rdi", mapLoc, "00")
    c.emit("40", "%rsi", keyLoc, "00")
    c.emit("1B", "collection_get", "0", "00") # Call runtime
    c.emit("40", dest, "%rax", "00")         # Store result (POINTER or TAGGED INT)
    return dest
#
  of nkBracket:
    let arrLoc = c.allocTemp()

    # 1. Calculate Size in Bytes
    # Each item is 8 bytes. We add some buffer (e.g. +8 bytes) for safety/header.
    let count = node.children.len
    let sizeBytes = (count * 8) + 64  # Extra space to be safe

    # 2. Allocate Array
    c.emit("40", "%rdi", "$" & $sizeBytes, "00")
    c.emit("1B", "new_array", "0", "00")
    c.emit("40", arrLoc, "%rax", "00")

    # 3. Populate Elements
    for i, child in node.children:
        let valLoc = c.gen(child)

        # Calculate Tagged Index for i (0->1, 1->3, etc.)
        let taggedIdx = (i shl 1) or 1

        # Call collection_set(arr, idx, val)
        c.emit("40", "%rdi", arrLoc, "00")
        c.emit("40", "%rsi", "$" & $taggedIdx, "00") # Pass literal
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
