import lexer, ast, strutils, os, errors, tables

var globalImportedModules = initTable[string, bool]()

type
  Parser* = ref object
    tokens: seq[Token]
    pos: int

# --- Forward Declarations ---
proc parseExpression(p: Parser): AstNode
proc parseLogicOr(p: Parser): AstNode
proc parseLogicAnd(p: Parser): AstNode
proc parseComparison(p: Parser): AstNode
proc parseTerm(p: Parser): AstNode
proc parseFactor(p: Parser): AstNode
proc parsePrimary(p: Parser): AstNode
proc parseStatement(p: Parser): AstNode
proc parseBlock(p: Parser): AstNode
proc parseProgram*(p: Parser): AstNode

# --- Helper Methods ---
proc newParser*(tokens: seq[Token]): Parser =
  new(result)
  result.tokens = tokens
  result.pos = 0

proc peek(p: Parser, offset: int = 0): Token =
  if p.pos + offset >= p.tokens.len: return Token(kind: tokEof)
  return p.tokens[p.pos + offset]

proc advance(p: Parser): Token =
  if p.pos < p.tokens.len:
    result = p.tokens[p.pos]
    p.pos.inc
  else:
    result = Token(kind: tokEof)

proc match(p: Parser, k: TokenType): bool =
  if p.peek().kind == k:
    discard p.advance()
    return true
  return false

proc consume(p: Parser, k: TokenType, err: string): Token =
  if p.peek().kind == k: return p.advance()
  ERR(err, p.peek().line)

proc resolveModulePath(pathParts: seq[string]): string =
  let relativePath = pathParts.join($DirSep) & ".nt"
  let libPath = "lib" & $DirSep & relativePath

  if fileExists(relativePath): return relativePath
  if fileExists(libPath): return libPath

  let envPath = getEnv("NEWTON_PATH")
  if envPath != "" and fileExists(envPath / relativePath):
    return envPath / relativePath

  let exeDir = getAppDir()
  if fileExists(exeDir / relativePath): return exeDir / relativePath
  if fileExists(exeDir / "lib" / relativePath): return exeDir / "lib" / relativePath

  let userLocalPath = getHomeDir() / ".local" / "lib" / "newton"
  if fileExists(userLocalPath / relativePath): return userLocalPath / relativePath
  if fileExists(userLocalPath / "lib" / relativePath): return userLocalPath / "lib" / relativePath

  let globalPath = "/usr/local/lib/newton"
  if fileExists(globalPath / relativePath): return globalPath / relativePath
  if fileExists(globalPath / "lib" / relativePath): return globalPath / "lib" / relativePath

  return ""

# --- Expression Parsing ---
proc parsePrimary(p: Parser): AstNode =
  let t = p.peek()
  case t.kind

  of tokNumberLit:
    discard p.advance()
    return AstNode(kind: nkLiteral, strVal: t.lexeme, isString: false)

  of tokFloatLit:
    discard p.advance()
    return AstNode(kind: nkFloatLit, strVal: t.lexeme)

  of tokStringLit:
    discard p.advance()
    return AstNode(kind: nkLiteral, strVal: t.lexeme, isString: true)

  of tokLBracket:
    discard p.advance()
    var elements: seq[AstNode] = @[]
    while p.peek().kind == tokEol: discard p.advance()

    if p.peek().kind != tokRBracket:
        elements.add(p.parseExpression())
        while true:
            while p.peek().kind == tokEol: discard p.advance()
            if not p.match(tokComma): break
            while p.peek().kind == tokEol: discard p.advance()

            if p.peek().kind == tokRBracket: break

            elements.add(p.parseExpression())

    while p.peek().kind == tokEol: discard p.advance()
    discard p.consume(tokRBracket, "Expected ']'")
    return AstNode(kind: nkBracket, children: elements)

  of tokMinus:
    discard p.advance()
    let val = p.parsePrimary()
    return AstNode(kind: nkBinaryOp, op: "-", left: AstNode(kind: nkLiteral, strVal: "0"), right: val)

  of tokNot:
    discard p.advance()
    let val = p.parsePrimary()
    return AstNode(kind: nkBinaryOp, op: "not", left: AstNode(kind: nkLiteral, strVal: "0"), right: val)

  of tokDollar:
    discard p.advance()
    var name = p.consume(tokIdentifier, "Expected variable name after '$'").lexeme
    if p.match(tokDot):
        let prop = p.consume(tokIdentifier, "Expected property").lexeme
        name = name & "_" & prop
    var baseNode = AstNode(kind: nkVarRef, refName: name, line: p.peek().line)

    while p.match(tokLBrace):
        var keyNode: AstNode
        if p.peek().kind == tokIdentifier:
            let keyId = p.advance().lexeme
            keyNode = AstNode(kind: nkLiteral, strVal: keyId, isString: true)
        else:
            keyNode = p.parseExpression()
        discard p.consume(tokRBrace, "Expected '}'")
        baseNode = AstNode(kind: nkMapGet, targetMap: baseNode, targetKey: keyNode)

    return baseNode

  of tokMacroRef:
    let lineNum = t.line
    let name = "MACRO_" & p.advance().lexeme
    var args: seq[AstNode] = @[]

    if p.match(tokLParen):
        if p.peek().kind != tokRParen:
            args.add(p.parseExpression())
            while p.match(tokComma): args.add(p.parseExpression())
        discard p.consume(tokRParen, "Expected ')'")
    else:
        if p.peek().kind in {tokNumberLit, tokFloatLit, tokStringLit, tokDollar, tokAmpersand, tokIdentifier, tokInput, tokLBracket, tokLParen, tokMacroRef}:
            args.add(p.parseExpression())
            while p.match(tokComma): args.add(p.parseExpression())

    let arrNode = AstNode(kind: nkBracket, children: args)
    var macroNode = AstNode(kind: nkCommand, callName: name, callArgs: @[arrNode], line: lineNum)

    if name == "MACRO_isERR" or name == "MACRO_isOK" or name == "MACRO_capture" or name == "MACRO_getERR":
        macroNode.autoUnwrap = true
        for arg in args:
            arg.autoUnwrap = true

    return macroNode

  of tokAmpersand:
    discard p.advance()
    let id = p.consume(tokIdentifier, "Expected identifier")
    return AstNode(kind: nkVarRef, refName: id.lexeme)
  of tokInput:
    discard p.advance()
    return AstNode(kind: nkInput)
  of tokCall:
    discard p.advance()
    let target = p.parseExpression()
    discard p.consume(tokLParen, "Expected '('")
    var args: seq[AstNode] = @[]
    if p.peek().kind != tokRParen:
        args.add(p.parseExpression())
        while p.match(tokComma): args.add(p.parseExpression())
    discard p.consume(tokRParen, "Expected ')'")
    return AstNode(kind: nkCallDynamic, callTarget: target, callArgs: args)

  of tokLParen:
    discard p.advance()
    while p.peek().kind == tokEol: discard p.advance()

    if p.peek().kind == tokRParen:
      discard p.advance()
      return AstNode(kind: nkMapLit, mapKeys: @[], mapValues: @[], isList: true)

    var firstExpr: AstNode
    if p.peek().kind == tokIdentifier and p.peek(1).kind == tokColon:
        let idToken = p.advance()
        firstExpr = AstNode(kind: nkLiteral, strVal: idToken.lexeme, isString: true)
    else:
        firstExpr = p.parseExpression()

    while p.peek().kind == tokEol: discard p.advance()

    # ----------------------------------------------------
    # 2. MAP CASE: (key: value)
    # ----------------------------------------------------
    if p.match(tokColon):
      while p.peek().kind == tokEol: discard p.advance()
      let firstVal = p.parseExpression()
      var keys = @[firstExpr]
      var vals = @[firstVal]

      while true:
        while p.peek().kind == tokEol: discard p.advance()
        if not p.match(tokComma): break
        while p.peek().kind == tokEol: discard p.advance()

        if p.peek().kind == tokRParen: break

        var k: AstNode
        if p.peek().kind == tokIdentifier and p.peek(1).kind == tokColon:
            let idToken = p.advance()
            k = AstNode(kind: nkLiteral, strVal: idToken.lexeme, isString: true)
        else:
            k = p.parseExpression()

        while p.peek().kind == tokEol: discard p.advance()
        discard p.consume(tokColon, "Expected ':' in map definition")
        while p.peek().kind == tokEol: discard p.advance()

        let v = p.parseExpression()
        keys.add(k)
        vals.add(v)

      while p.peek().kind == tokEol: discard p.advance()
      discard p.consume(tokRParen, "Expected ')' at end of map")
      return AstNode(kind: nkMapLit, mapKeys: keys, mapValues: vals, isList: false)

    # ----------------------------------------------------
    # 3. TUPLE/LIST CASE: (val1, val2)
    # ----------------------------------------------------
    elif p.peek().kind == tokComma:
      var vals = @[firstExpr]
      while true:
        while p.peek().kind == tokEol: discard p.advance()
        if not p.match(tokComma): break
        while p.peek().kind == tokEol: discard p.advance()

        if p.peek().kind == tokRParen: break

        vals.add(p.parseExpression())

      while p.peek().kind == tokEol: discard p.advance()
      discard p.consume(tokRParen, "Expected ')' at end of list")
      return AstNode(kind: nkMapLit, mapKeys: @[], mapValues: vals, isList: true)

    # ----------------------------------------------------
    # 4. SINGLE EXPRESSION CASE: (1 + 1)
    # ----------------------------------------------------
    else:
      while p.peek().kind == tokEol: discard p.advance()
      discard p.consume(tokRParen, "Expected ')' after expression")
      return firstExpr

  of tokIdentifier:
    let lineNum = t.line
    var name = p.advance().lexeme

    if p.match(tokDot):
        let sub = p.consume(tokIdentifier, "Expected property after '.'").lexeme
        name = name & "_" & sub

    var args: seq[AstNode] = @[]

    while p.peek().kind in {tokStringLit, tokNumberLit, tokFloatLit, tokDollar, tokAmpersand, tokIdentifier, tokInput, tokLBracket, tokLParen, tokMacroRef}:
        args.add(p.parseExpression())
        discard p.match(tokComma)

    return AstNode(kind: nkCommand, callName: name, callArgs: args, line: p.peek().line)

  else:
    ERR("Unexpected token in expression: " & $t.kind, t.line)

proc parseFactor(p: Parser): AstNode =
  var left = p.parsePrimary()
  while p.peek().kind in {tokStar, tokSlash, tokMod}:
    let op = p.advance().lexeme
    let right = p.parsePrimary()
    left = AstNode(kind: nkBinaryOp, left: left, right: right, op: op)
  return left

proc parseTerm(p: Parser): AstNode =
  var left = p.parseFactor()
  while p.peek().kind in {tokPlus, tokMinus, tokConcat, tokBitXor, tokShr, tokShl}:
    let opToken = p.advance()
    let right = p.parseFactor()
    if opToken.kind == tokConcat:
       left = AstNode(kind: nkInfix, op: "<<", left: left, right: right)
    else:
       left = AstNode(kind: nkBinaryOp, left: left, right: right, op: opToken.lexeme)
  return left

proc parseComparison(p: Parser): AstNode =
  var left = p.parseTerm()
  while p.peek().kind in {tokLt, tokGt, tokEqEq, tokNeq, tokGe, tokLe}:
    let op = p.advance().lexeme
    let right = p.parseTerm()
    left = AstNode(kind: nkBinaryOp, left: left, right: right, op: op)
  return left

proc parseLogicAnd(p: Parser): AstNode =
  var left = p.parseComparison()
  while p.match(tokAnd):
    let right = p.parseComparison()
    left = AstNode(kind: nkBinaryOp, left: left, right: right, op: "and")
  return left

proc parseLogicOr(p: Parser): AstNode =
  var left = p.parseLogicAnd()
  while p.match(tokOr):
    let right = p.parseLogicAnd()
    left = AstNode(kind: nkBinaryOp, left: left, right: right, op: "or")
  return left

proc parseExpression(p: Parser): AstNode =
  return parseLogicOr(p)

# --- Statement Parsing ---
proc parseBlock(p: Parser): AstNode =
  var stmts: seq[AstNode] = @[]
  while p.peek().kind == tokEol: discard p.advance()
  while not (p.peek().kind in {tokEnd, tokElse, tokElseIf, tokEof}):
    stmts.add(p.parseStatement())
    while p.peek().kind == tokEol: discard p.advance()
  return AstNode(kind: nkBlock, blockStmts: stmts)

proc prefixAst(nodes: seq[AstNode], prefix: string) =
  for node in nodes:
    if node.fromImport: continue
    if node.kind == nkFunction:
        if not node.fnName.startsWith("MACRO_"):
            node.fnName = prefix & "_" & node.fnName

    if node.kind == nkGlobalDecl: node.varName = prefix & "_" & node.varName

proc parseImport(p: Parser): seq[AstNode] =
    var pathParts: seq[string] = @[]
    pathParts.add(p.consume(tokIdentifier, "Expected module name").lexeme)

    while p.match(tokDoubleColon):
        pathParts.add(p.consume(tokIdentifier, "Expected submodule name").lexeme)

    let moduleName = pathParts[^1]
    let filename = resolveModulePath(pathParts)

    if filename == "":
        ERR("Could not find module '" & pathParts.join("::") & "'", p.peek().line)

    if globalImportedModules.hasKey(filename):
        return @[]
    globalImportedModules[filename] = true

    let oldFile = currentCompilingFile
    currentCompilingFile = filename

    let content = readFile(filename)
    let tokens = lexer.lex(content)
    let subParser = newParser(tokens)
    let moduleAst = subParser.parseProgram()

    prefixAst(moduleAst.stmts, moduleName)
    let isCompiledPackage = filename.contains("packages" & $DirSep)
    for n in moduleAst.stmts:
        n.fromImport = true
        n.isPrecompiled = isCompiledPackage

    currentCompilingFile = oldFile
    return moduleAst.stmts

proc parseStatement(p: Parser): AstNode =
  let t = p.peek()
  case t.kind
  of tokUsing:
    discard p.advance()
    let importedStmts = p.parseImport()
    return AstNode(kind: nkBlock, blockStmts: importedStmts)

  of tokSet:
    discard p.advance()

    # DESTRUCTURING: set [a, b]: [1, 2]
    if p.peek().kind == tokLBracket:
      discard p.advance()
      var names: seq[string] = @[]
      names.add(p.consume(tokIdentifier, "Expected variable name in destructuring").lexeme)
      while p.match(tokComma):
        names.add(p.consume(tokIdentifier, "Expected variable name").lexeme)
      discard p.consume(tokRBracket, "Expected ']' after destructuring variables")
      discard p.consume(tokColon, "Expected ':' after destructuring block")
      let val = p.parseExpression()
      return AstNode(kind: nkDestructDecl, destructNames: names, destructVal: val, line: t.line)

    # STANDARD ASSIGNMENT: set a: 1  OR  set a*: 1
    else:
      let name = p.consume(tokIdentifier, "Expected variable name").lexeme
      var isGlobal = false
      if p.match(tokStar):
          isGlobal = true

      discard p.consume(tokColon, "Expected ':' after variable name")
      let val = p.parseExpression()

      if isGlobal:
          return AstNode(kind: nkGlobalDecl, varName: name, varValue: val, line: t.line)
      else:
          return AstNode(kind: nkVarDecl, varName: name, varValue: val, line: t.line)

  of tokMatch:
    discard p.advance()
    let target = p.parseExpression()
    discard p.consume(tokColon, "Expected ':' after match target")
    var branches: seq[AstNode] = @[]

    while p.peek().kind != tokEnd and p.peek().kind != tokEof:
      while p.peek().kind == tokEol: discard p.advance()
      if p.peek().kind == tokEnd: break

      let cond = p.parseExpression()
      discard p.consume(tokArrow, "Expected '->' after match condition")
      let bodyStmt = p.parseStatement()
      branches.add(AstNode(kind: nkMatchBranch, branchCond: cond, branchBody: bodyStmt, line: p.peek().line))
      while p.peek().kind == tokEol: discard p.advance()

    discard p.consume(tokEnd, "Expected 'end' after match block")
    return AstNode(kind: nkMatch, matchTarget: target, matchBranches: branches, line: t.line)

  of tokIf:
    discard p.advance()
    let cond = p.parseExpression()
    discard p.consume(tokColon, "Expected ':'")
    let thenBranch = p.parseBlock()
    var elseBranch: AstNode = nil
    var currentIf = AstNode(kind: nkIf, condition: cond, thenBranch: thenBranch, elseBranch: nil)
    var rootIf = currentIf

    while p.peek().kind == tokElseIf:
        discard p.advance() # Eat 'elseif'
        let subCond = p.parseExpression()
        discard p.consume(tokColon, "Expected ':' after elseif")
        let subBlock = p.parseBlock()
        let newIf = AstNode(kind: nkIf, condition: subCond, thenBranch: subBlock, elseBranch: nil)
        currentIf.elseBranch = newIf
        currentIf = newIf

    if p.peek().kind == tokElse:
        discard p.advance()
        discard p.consume(tokColon, "Expected ':'")
        let finalBlock = p.parseBlock()
        currentIf.elseBranch = finalBlock

    discard p.consume(tokEnd, "Expected 'end'")
    return rootIf

  of tokDefmacro:
    discard p.advance()
    let name = p.consume(tokIdentifier, "Expected macro name").lexeme
    discard p.consume(tokColon, "Expected ':'")
    while p.peek().kind == tokEol: discard p.advance()

    let body = p.parseBlock()
    discard p.consume(tokEnd, "Expected 'end'")
    return AstNode(kind: nkFunction, fnName: "MACRO_" & name, fnBody: body, fnArgs: @["M_ARGV"])

  of tokNamespace:
    discard p.advance()
    discard p.consume(tokIdentifier, "Expected namespace name")
    return AstNode(kind: nkBlock, blockStmts: @[])

  of tokFor:
    discard p.advance()
    discard p.consume(tokAmpersand, "Expected '&'")
    let iterName = p.consume(tokIdentifier, "Expected iter").lexeme
    discard p.consume(tokComma, ",")
    let startExpr = p.parseExpression()
    discard p.consume(tokComma, ",")
    let endExpr = p.parseExpression()
    discard p.consume(tokComma, ",")
    let stepExpr = p.parseExpression()
    discard p.consume(tokColon, ":")
    let body = p.parseBlock()
    discard p.consume(tokEnd, "end")
    return AstNode(kind: nkLoop, loopType: "for", loopArgs: @[AstNode(kind: nkLiteral, strVal: iterName), startExpr, endExpr, stepExpr], loopBody: body)

  of tokWhile:
    discard p.advance()
    let cond = p.parseExpression()
    discard p.consume(tokColon, ":")
    let body = p.parseBlock()
    discard p.consume(tokEnd, "end")
    return AstNode(kind: nkWhile, whileCondition: cond, whileBody: body)

  of tokExposed:
    discard p.advance()
    discard p.consume(tokFn, "Expected 'fun' keyword after 'exposed'")
    let name = p.consume(tokIdentifier, "Function name").lexeme
    discard p.consume(tokColon, ":")
    while p.peek().kind == tokEol: discard p.advance()
    var args: seq[string] = @[]
    if p.peek().kind == tokAtArgs:
        discard p.advance()
        while true:
            args.add(p.consume(tokIdentifier, "Arg name").lexeme)
            if not p.match(tokComma): break
        if p.peek().kind == tokEol: discard p.advance()
    let body = p.parseBlock()
    discard p.consume(tokEnd, "end")
    return AstNode(kind: nkFunction, fnName: name, fnBody: body, fnArgs: args, fnExpo: true)

  of tokFn:
    discard p.advance()
    let name = p.consume(tokIdentifier, "Function name").lexeme
    discard p.consume(tokColon, ":")
    while p.peek().kind == tokEol: discard p.advance()
    var args: seq[string] = @[]
    if p.peek().kind == tokAtArgs:
        discard p.advance()
        while true:
            args.add(p.consume(tokIdentifier, "Arg name").lexeme)
            if not p.match(tokComma): break
        if p.peek().kind == tokEol: discard p.advance()
    let body = p.parseBlock()
    discard p.consume(tokEnd, "end")
    return AstNode(kind: nkFunction, fnName: name, fnBody: body, fnArgs: args, fnExpo: false)

  of tokReturn:
    discard p.advance()
    if p.peek().kind != tokEol and p.peek().kind != tokEof:
      return AstNode(kind: nkReturn, returnVal: p.parseExpression())
    return AstNode(kind: nkReturn, returnVal: nil)

  of tokIdentifier:
    let lineNum = t.line
    var name = p.advance().lexeme
    if p.match(tokDot):
        name = name & "_" & p.consume(tokIdentifier, "prop").lexeme
    if p.match(tokColon):
        return AstNode(kind: nkAssignment, varName: name, varValue: p.parseExpression())
    elif p.match(tokLBrace):
        let keyExpr = p.parseExpression()
        discard p.consume(tokRBrace, "}")
        if p.match(tokColon):
            let valExpr = p.parseExpression()
            let listRef = AstNode(kind: nkVarRef, refName: name)
            return AstNode(kind: nkCommand, callName: "set_index", callArgs: @[listRef, keyExpr, valExpr])
        return AstNode(kind: nkMapGet, targetMap: AstNode(kind: nkVarRef, refName: name), targetKey: keyExpr)
    elif p.match(tokLParen):
        var args: seq[AstNode] = @[]
        if p.peek().kind != tokRParen:
            args.add(p.parseExpression())
            while p.match(tokComma): args.add(p.parseExpression())
        discard p.consume(tokRParen, ")")
        return AstNode(kind: nkCommand, callName: name, callArgs: args)
    else:
        var args: seq[AstNode] = @[]
        if p.peek().kind in {tokNumberLit, tokFloatLit, tokStringLit, tokDollar, tokAmpersand, tokIdentifier, tokInput, tokLBracket, tokLParen}:
            args.add(p.parseExpression())
            while p.match(tokComma): args.add(p.parseExpression())
        return AstNode(kind: nkCommand, callName: name, callArgs: args, line: lineNum)

  of tokForeach:
    discard p.advance() # Consume 'foreach'
    discard p.consume(tokAmpersand, "Expected '&' before loop variable")
    let firstVarName = p.consume(tokIdentifier, "Expected variable name").lexeme

    if p.peek().kind == tokComma:
      discard p.advance() # Consume ','
      discard p.consume(tokAmpersand, "Expected '&' before value variable")
      let valName = p.consume(tokIdentifier, "Expected value variable name").lexeme
      discard p.consume(tokComma, "Expected ',' after value variable")
      let target = p.parseExpression()
      discard p.consume(tokColon, "Expected ':' after foreach declaration")

      var bodyStmts: seq[AstNode] = @[]
      while p.peek().kind != tokEnd and p.peek().kind != tokEof:
        while p.peek().kind == tokEol: discard p.advance()
        if p.peek().kind == tokEnd: break
        bodyStmts.add(p.parseStatement())
        while p.peek().kind == tokEol: discard p.advance()
      discard p.consume(tokEnd, "Expected 'end'")

      let bodyBlock = AstNode(kind: nkBlock, blockStmts: bodyStmts)
      return AstNode(kind: nkForeachMap, mapLoopKey: firstVarName, mapLoopVal: valName, mapLoopTarget: target, mapLoopBody: bodyBlock, line: t.line)

    elif p.peek().kind == tokIn:
      discard p.advance() # Consume 'in'
      let target = p.parseExpression()
      discard p.consume(tokColon, "Expected ':' after foreach declaration")

      var bodyStmts: seq[AstNode] = @[]
      while p.peek().kind != tokEnd and p.peek().kind != tokEof:
        while p.peek().kind == tokEol: discard p.advance()
        if p.peek().kind == tokEnd: break
        bodyStmts.add(p.parseStatement())
        while p.peek().kind == tokEol: discard p.advance()
      discard p.consume(tokEnd, "Expected 'end'")

      let bodyBlock = AstNode(kind: nkBlock, blockStmts: bodyStmts)
      return AstNode(kind: nkForeachFile, fileLoopVar: firstVarName, fileLoopTarget: target, fileLoopBody: bodyBlock, line: t.line)

    else:
      discard p.consume(tokIn, "Expected 'in' or ',' after foreach loop variable")

  of tokStringLit, tokNumberLit, tokFloatLit, tokLParen, tokLBracket, tokMinus, tokNot, tokDollar, tokAmpersand, tokInput, tokCall, tokMacroRef:
    return p.parseExpression()
  else:
    ERR("Unknown statement: " & $t.kind, t.line)

proc injectPrelude*(stmts: var seq[AstNode]) =
  let pathParts = @["std", "Base"]
  let filename = resolveModulePath(pathParts)
  if filename == "": return
  if globalImportedModules.hasKey(filename): return

  globalImportedModules[filename] = true
  let oldFile = currentCompilingFile
  currentCompilingFile = filename
  let content = readFile(filename)
  let tokens = lexer.lex(content)
  let subParser = newParser(tokens)
  let moduleAst = subParser.parseProgram()
  currentCompilingFile = oldFile

  stmts = moduleAst.stmts & stmts

proc parseProgram*(p: Parser): AstNode =
  var stmts: seq[AstNode] = @[]
  while p.peek().kind != tokEof:
    if p.peek().kind == tokEol:
      discard p.advance()
      continue
    let stmt = p.parseStatement()
    if stmt.kind == nkBlock:
        for s in stmt.blockStmts: stmts.add(s)
    else:
        stmts.add(stmt)
  return AstNode(kind: nkProgram, stmts: stmts)
