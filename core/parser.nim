import lexer, ast, strutils, os

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
  raise newException(ValueError, err & " at line " & $p.peek().line)

# --- Expression Parsing ---

# 1. Primary
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
        while p.match(tokComma):
            while p.peek().kind == tokEol: discard p.advance()
            elements.add(p.parseExpression())
    while p.peek().kind == tokEol: discard p.advance()
    discard p.consume(tokRBracket, "Expected ']'")
    return AstNode(kind: nkBracket, children: elements)
  of tokMinus:
    discard p.advance()
    let val = p.parsePrimary()
    return AstNode(kind: nkBinaryOp, op: "-", left: AstNode(kind: nkLiteral, strVal: "0"), right: val)

  # [NEW] Logical NOT
  of tokNot:
    discard p.advance()
    let val = p.parsePrimary()
    # "not x" -> binary op with dummy left, handled in codegen
    return AstNode(kind: nkBinaryOp, op: "not", left: AstNode(kind: nkLiteral, strVal: "0"), right: val)

  of tokDollar:
    discard p.advance()
    var name = p.consume(tokIdentifier, "Expected variable name").lexeme
    if p.match(tokDot):
        let prop = p.consume(tokIdentifier, "Expected property").lexeme
        name = name & "_" & prop
    var baseNode = AstNode(kind: nkVarRef, refName: name)
    if p.match(tokLBrace):
        var keyNode: AstNode
        if p.peek().kind == tokIdentifier:
            let keyId = p.advance().lexeme
            keyNode = AstNode(kind: nkLiteral, strVal: keyId, isString: true)
        else:
            keyNode = p.parseExpression()
        discard p.consume(tokRBrace, "Expected '}'")
        baseNode = AstNode(kind: nkMapGet, targetMap: baseNode, targetKey: keyNode)
    return baseNode
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
    if p.peek().kind == tokColon:
      discard p.advance()
      while p.peek().kind == tokEol: discard p.advance()
      let firstVal = p.parseExpression()
      var keys = @[firstExpr]
      var vals = @[firstVal]
      while p.match(tokComma):
        while p.peek().kind == tokEol: discard p.advance()
        var k: AstNode
        if p.peek().kind == tokIdentifier and p.peek(1).kind == tokColon:
            let id = p.advance()
            k = AstNode(kind: nkLiteral, strVal: id.lexeme, isString: true)
        else:
            k = p.parseExpression()
        discard p.consume(tokColon, "Expected ':'")
        while p.peek().kind == tokEol: discard p.advance()
        let v = p.parseExpression()
        keys.add(k)
        vals.add(v)
        while p.peek().kind == tokEol: discard p.advance()
      discard p.consume(tokRParen, "Expected ')'")
      return AstNode(kind: nkMapLit, mapKeys: keys, mapValues: vals, isList: false)
    elif p.peek().kind == tokComma:
      var vals = @[firstExpr]
      while p.match(tokComma):
        while p.peek().kind == tokEol: discard p.advance()
        vals.add(p.parseExpression())
        while p.peek().kind == tokEol: discard p.advance()
      discard p.consume(tokRParen, "Expected ')'")
      return AstNode(kind: nkMapLit, mapKeys: @[], mapValues: vals, isList: true)
    else:
      while p.peek().kind == tokEol: discard p.advance()
      discard p.consume(tokRParen, "Expected ')'")
      return firstExpr
  of tokIdentifier:
    let lineNum = t.line
    var name = p.advance().lexeme
    if p.match(tokDot):
        let sub = p.consume(tokIdentifier, "Expected property").lexeme
        name = name & "_" & sub
    if p.match(tokLParen):
        var args: seq[AstNode] = @[]
        if p.peek().kind != tokRParen:
            args.add(p.parseExpression())
            while p.match(tokComma): args.add(p.parseExpression())
        discard p.consume(tokRParen, "Expected ')'")
        return AstNode(kind: nkCall, callName: name, callArgs: args)
    elif p.peek().kind in {tokNumberLit, tokStringLit, tokDollar, tokAmpersand, tokInput, tokLBracket, tokLParen, tokIdentifier}:
        var args: seq[AstNode] = @[]
        args.add(p.parseExpression())
        while p.match(tokComma): args.add(p.parseExpression())
        return AstNode(kind: nkCommand, callName: name, callArgs: args, line: lineNum)
    else:
        # [FIX] Enforce $ rule
        raise newException(ValueError, "Variable references must start with '$'. Found identifier: '" & name & "'")
  else:
    raise newException(ValueError, "Unexpected token in expression: " & $t.kind)

# 2. Factor
proc parseFactor(p: Parser): AstNode =
  var left = p.parsePrimary()
  while p.peek().kind in {tokStar, tokSlash}:
    let op = p.advance().lexeme
    let right = p.parsePrimary()
    left = AstNode(kind: nkBinaryOp, left: left, right: right, op: op)
  return left

# 3. Term
proc parseTerm(p: Parser): AstNode =
  var left = p.parseFactor()
  while p.peek().kind in {tokPlus, tokMinus, tokConcat}:
    let opToken = p.advance()
    let right = p.parseFactor()
    if opToken.kind == tokConcat:
       left = AstNode(kind: nkInfix, op: "<<", left: left, right: right)
    else:
       left = AstNode(kind: nkBinaryOp, left: left, right: right, op: opToken.lexeme)
  return left

# 4. Comparison
proc parseComparison(p: Parser): AstNode =
  var left = p.parseTerm()
  while p.peek().kind in {tokLt, tokGt, tokEqEq, tokNeq, tokGe, tokLe}:
    let op = p.advance().lexeme
    let right = p.parseTerm()
    left = AstNode(kind: nkBinaryOp, left: left, right: right, op: op)
  return left

# 5. Logic AND
proc parseLogicAnd(p: Parser): AstNode =
  var left = p.parseComparison()
  while p.match(tokAnd):
    let right = p.parseComparison()
    left = AstNode(kind: nkBinaryOp, left: left, right: right, op: "and")
  return left

# 6. Logic OR
proc parseLogicOr(p: Parser): AstNode =
  var left = p.parseLogicAnd()
  while p.match(tokOr):
    let right = p.parseLogicAnd()
    left = AstNode(kind: nkBinaryOp, left: left, right: right, op: "or")
  return left

# 7. Entry Point
proc parseExpression(p: Parser): AstNode =
  return parseLogicOr(p)

# --- Statement Parsing ---

proc parseBlock(p: Parser): AstNode =
  var stmts: seq[AstNode] = @[]
  while p.peek().kind == tokEol: discard p.advance()
  # [FIX] Added tokElseIf to stop block parsing
  while not (p.peek().kind in {tokEnd, tokElse, tokElseIf, tokEof}):
    stmts.add(p.parseStatement())
    while p.peek().kind == tokEol: discard p.advance()
  return AstNode(kind: nkBlock, blockStmts: stmts)

proc prefixAst(nodes: seq[AstNode], prefix: string) =
  for node in nodes:
    if node.kind == nkFunction: node.fnName = prefix & "_" & node.fnName
    if node.kind == nkGlobalDecl: node.varName = prefix & "_" & node.varName

proc parseImport(p: Parser): seq[AstNode] =
    var pathParts: seq[string] = @[]
    pathParts.add(p.consume(tokIdentifier, "Expected module name").lexeme)
    while p.match(tokDoubleColon):
        pathParts.add(p.consume(tokIdentifier, "Expected submodule name").lexeme)
    var filename = ""
    let relativePath = pathParts.join($DirSep) & ".nt"
    let libPath = "lib" & $DirSep & relativePath
    let moduleName = pathParts[^1]
    if fileExists(relativePath): filename = relativePath
    elif fileExists(libPath): filename = libPath
    else: raise newException(IOError, "Could not find module: " & filename)
    let content = readFile(filename)
    let tokens = lexer.lex(content)
    let subParser = newParser(tokens)
    let moduleAst = subParser.parseProgram()
    prefixAst(moduleAst.stmts, moduleName)
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
    let name = p.consume(tokIdentifier, "Expected variable name").lexeme
    let isGlobal = p.match(tokStar)
    discard p.consume(tokColon, "Expected ':'")
    let val = p.parseExpression()
    if isGlobal: return AstNode(kind: nkGlobalDecl, varName: name, varValue: val)
    else: return AstNode(kind: nkVarDecl, varName: name, varValue: val)

  # [FIX] Enhanced IF / ELSEIF / ELSE
  of tokIf:
    discard p.advance()
    let cond = p.parseExpression()
    discard p.consume(tokColon, "Expected ':'")
    let thenBranch = p.parseBlock()
    var elseBranch: AstNode = nil

    # Handle ElseIf Chain (Recursively nested)
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
  of tokFn:
    discard p.advance()
    let name = p.consume(tokIdentifier, "Fn name").lexeme
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
    return AstNode(kind: nkFunction, fnName: name, fnBody: body, fnArgs: args)
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
        if p.peek().kind in {tokNumberLit, tokStringLit, tokDollar, tokAmpersand, tokIdentifier, tokInput, tokLBracket, tokLParen}:
            args.add(p.parseExpression())
            while p.match(tokComma): args.add(p.parseExpression())
        return AstNode(kind: nkCommand, callName: name, callArgs: args, line: lineNum)
  of tokForeach:
    discard p.advance()
    discard p.consume(tokAmpersand, "&")
    let keyName = p.consume(tokIdentifier, "key").lexeme
    discard p.consume(tokComma, ",")
    discard p.consume(tokAmpersand, "&")
    let valName = p.consume(tokIdentifier, "val").lexeme
    discard p.consume(tokComma, ",")
    let src = p.parseExpression()
    discard p.consume(tokColon, ":")
    let body = p.parseBlock()
    discard p.consume(tokEnd, "end")
    return AstNode(kind: nkForeach, loopKey: keyName, loopVal: valName, loopSource: src, foreachBody: body.blockStmts)
  of tokDel:
    discard p.advance()
    let t = p.parseExpression()
    if t.kind != nkMapGet: raise newException(ValueError, "del map{key}")
    return AstNode(kind: nkCommand, callName: "del_opcode", callArgs: @[t.targetMap, t.targetKey])
  of tokStringLit, tokNumberLit, tokFloatLit, tokLParen, tokLBracket, tokMinus, tokNot, tokDollar, tokAmpersand, tokInput, tokCall:
    return p.parseExpression()
  else:
    raise newException(ValueError, "Unknown statement: " & $t.kind)

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
