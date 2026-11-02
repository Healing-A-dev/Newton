import ast, strutils, math

# Forward declarations
proc optimizePass*(node: AstNode): AstNode

proc makeIntNode(val: int, line: int = 0): AstNode =
  AstNode(kind: nkLiteral, strVal: $val, isString: false, line: line)

proc makeNumNode(val: float, line: int = 0): AstNode =
  let rounded = val.round()
  if val == rounded and val >= float(low(int)) and val <= float(high(int)):
    AstNode(kind: nkLiteral, strVal: $(val.toInt()), isString: false, line: line)
  else:
    AstNode(kind: nkFloatLit, strVal: $val, isString: false, line: line)

proc isZero(node: AstNode): bool =
  if node == nil: return false
  if node.kind == nkLiteral and not node.isString:
    return node.strVal == "0"
  if node.kind == nkFloatLit:
    try: return parseFloat(node.strVal) == 0.0
    except: return false
  return false

proc isOne(node: AstNode): bool =
  if node == nil: return false
  if node.kind == nkLiteral and not node.isString:
    return node.strVal == "1"
  if node.kind == nkFloatLit:
    try: return parseFloat(node.strVal) == 1.0
    except: return false
  return false

proc isEmptyString(node: AstNode): bool =
  node != nil and node.kind == nkLiteral and node.isString and node.strVal == ""

proc isPure(node: AstNode): bool =
  if node == nil: return true
  case node.kind:
  of nkLiteral, nkFloatLit, nkVarRef: return true
  of nkBinaryOp: return isPure(node.left) and isPure(node.right)
  of nkInfix: return isPure(node.left) and isPure(node.right)
  of nkBracket:
    for c in node.children:
      if not isPure(c): return false
    return true
  of nkMapLit:
    for k in node.mapKeys:
      if not isPure(k): return false
    for v in node.mapValues:
      if not isPure(v): return false
    return true
  else: return false

proc optimizeBlockStmts(stmts: seq[AstNode]): seq[AstNode] =
  result = @[]
  for s in stmts:
    let optS = optimizePass(s)
    if optS == nil: continue
    if optS.kind == nkBlock and optS.blockStmts.len == 0: continue
    result.add(optS)
    # Dead code elimination: unreachable code after return
    if optS.kind == nkReturn:
      break

proc optimizeSeq(nodes: seq[AstNode]): seq[AstNode] =
  result = @[]
  for n in nodes:
    let optN = optimizePass(n)
    if optN != nil:
      result.add(optN)

proc optimizePass*(node: AstNode): AstNode =
  if node == nil: return nil

  case node.kind:
  of nkProgram:
    node.stmts = optimizeBlockStmts(node.stmts)
    return node

  of nkBlock:
    node.blockStmts = optimizeBlockStmts(node.blockStmts)
    return node

  of nkFunction:
    node.fnBody = optimizePass(node.fnBody)
    return node

  of nkVarDecl, nkGlobalDecl, nkAssignment:
    node.varValue = optimizePass(node.varValue)
    return node

  of nkDestructDecl:
    node.destructVal = optimizePass(node.destructVal)
    return node

  of nkReturn:
    if node.returnVal != nil:
      node.returnVal = optimizePass(node.returnVal)
    return node

  of nkIf:
    node.condition = optimizePass(node.condition)
    node.thenBranch = optimizePass(node.thenBranch)
    if node.elseBranch != nil:
      node.elseBranch = optimizePass(node.elseBranch)

    # Constant condition folding / Dead branch elimination
    if node.condition != nil and node.condition.kind == nkLiteral:
      if not node.condition.isString:
        if isZero(node.condition):
          if node.elseBranch != nil: return node.elseBranch
          else: return AstNode(kind: nkBlock, blockStmts: @[])
        else:
          return node.thenBranch
      else:
        if node.condition.strVal.len > 0:
          return node.thenBranch
        else:
          if node.elseBranch != nil: return node.elseBranch
          else: return AstNode(kind: nkBlock, blockStmts: @[])

    return node

  of nkWhile:
    node.whileCondition = optimizePass(node.whileCondition)
    node.whileBody = optimizePass(node.whileBody)
    # Loop condition false at compile time
    if node.whileCondition != nil and isZero(node.whileCondition):
      return AstNode(kind: nkBlock, blockStmts: @[])
    return node

  of nkLoop:
    node.loopArgs = optimizeSeq(node.loopArgs)
    node.loopBody = optimizePass(node.loopBody)
    return node

  of nkForeachMap:
    node.mapLoopTarget = optimizePass(node.mapLoopTarget)
    node.mapLoopBody = optimizePass(node.mapLoopBody)
    return node

  of nkMatch:
    node.matchTarget = optimizePass(node.matchTarget)
    var optBranches: seq[AstNode] = @[]
    for b in node.matchBranches:
      b.branchCond = optimizePass(b.branchCond)
      b.branchBody = optimizePass(b.branchBody)
      optBranches.add(b)
    node.matchBranches = optBranches
    return node

  of nkCall, nkCommand, nkCallDynamic:
    if node.callTarget != nil:
      node.callTarget = optimizePass(node.callTarget)
    node.callArgs = optimizeSeq(node.callArgs)
    return node

  of nkBracket:
    node.children = optimizeSeq(node.children)
    return node

  of nkMapLit:
    node.mapKeys = optimizeSeq(node.mapKeys)
    node.mapValues = optimizeSeq(node.mapValues)
    return node

  of nkMapGet:
    node.targetMap = optimizePass(node.targetMap)
    node.targetKey = optimizePass(node.targetKey)
    return node

  of nkDel:
    node.delMap = optimizePass(node.delMap)
    node.delKey = optimizePass(node.delKey)
    return node

  of nkVarRef, nkLiteral, nkFloatLit, nkInput:
    return node

  of nkBinaryOp:
    node.left = optimizePass(node.left)
    node.right = optimizePass(node.right)

    # 1. Constant folding: numeric literals
    if node.left != nil and node.right != nil and
       node.left.kind in {nkLiteral, nkFloatLit} and node.right.kind in {nkLiteral, nkFloatLit} and
       not node.left.isString and not node.right.isString:
      try:
        let lval = parseFloat(node.left.strVal)
        let rval = parseFloat(node.right.strVal)
        case node.op
        of "+": return makeNumNode(lval + rval, node.line)
        of "-": return makeNumNode(lval - rval, node.line)
        of "*": return makeNumNode(lval * rval, node.line)
        of "/":
          if rval != 0.0: return makeNumNode(lval / rval, node.line)
        of "%":
          if rval.toInt() != 0: return makeNumNode(float(lval.toInt() mod rval.toInt()), node.line)
        of ">>": return makeNumNode(float(lval.toInt() shr rval.toInt()), node.line)
        of "shl": return makeNumNode(float(lval.toInt() shl rval.toInt()), node.line)
        of "^": return makeNumNode(float(lval.toInt() xor rval.toInt()), node.line)
        of "<": return makeIntNode(if lval < rval: 1 else: 0, node.line)
        of ">": return makeIntNode(if lval > rval: 1 else: 0, node.line)
        of "<=": return makeIntNode(if lval <= rval: 1 else: 0, node.line)
        of ">=": return makeIntNode(if lval >= rval: 1 else: 0, node.line)
        of "==": return makeIntNode(if lval == rval: 1 else: 0, node.line)
        of "!=": return makeIntNode(if lval != rval: 1 else: 0, node.line)
        of "and": return makeIntNode(if (lval != 0.0 and rval != 0.0): 1 else: 0, node.line)
        of "or": return makeIntNode(if (lval != 0.0 or rval != 0.0): 1 else: 0, node.line)
        else: discard
      except: discard

    # 2. Constant folding: string comparisons
    if node.left != nil and node.right != nil and
       node.left.kind == nkLiteral and node.right.kind == nkLiteral and
       node.left.isString and node.right.isString:
      case node.op
      of "==": return makeIntNode(if node.left.strVal == node.right.strVal: 1 else: 0, node.line)
      of "!=": return makeIntNode(if node.left.strVal != node.right.strVal: 1 else: 0, node.line)
      else: discard

    # 3. Algebraic simplifications
    case node.op
    of "+":
      if isZero(node.left): return node.right
      if isZero(node.right): return node.left
    of "-":
      if isZero(node.right): return node.left
    of "*":
      if isOne(node.left): return node.right
      if isOne(node.right): return node.left
      if isZero(node.left) and isPure(node.right): return makeIntNode(0, node.line)
      if isZero(node.right) and isPure(node.left): return makeIntNode(0, node.line)
    of "/":
      if isOne(node.right): return node.left
    of "and":
      if isZero(node.left) and isPure(node.right): return makeIntNode(0, node.line)
      if isZero(node.right) and isPure(node.left): return makeIntNode(0, node.line)
      if isOne(node.left): return node.right
      if isOne(node.right): return node.left
    of "or":
      if isOne(node.left) and isPure(node.right): return makeIntNode(1, node.line)
      if isOne(node.right) and isPure(node.left): return makeIntNode(1, node.line)
      if isZero(node.left): return node.right
      if isZero(node.right): return node.left
    else: discard

    return node

  of nkInfix:
    node.left = optimizePass(node.left)
    node.right = optimizePass(node.right)

    if node.op == "<<":
      # String literal concatenation
      if node.left != nil and node.right != nil and
         node.left.kind == nkLiteral and node.left.isString and
         node.right.kind == nkLiteral and node.right.isString:
        return AstNode(kind: nkLiteral, strVal: node.left.strVal & node.right.strVal, isString: true, line: node.line)

      if node.left != nil and node.right != nil and
         node.left.kind == nkLiteral and node.left.isString and
         node.right.kind == nkLiteral and not node.right.isString:
        return AstNode(kind: nkLiteral, strVal: node.left.strVal & node.right.strVal, isString: true, line: node.line)

      if node.left != nil and node.right != nil and
         node.left.kind == nkLiteral and not node.left.isString and
         node.right.kind == nkLiteral and node.right.isString:
        return AstNode(kind: nkLiteral, strVal: node.left.strVal & node.right.strVal, isString: true, line: node.line)

      # Identity: x << "" or "" << x
      if isEmptyString(node.left): return node.right
      if isEmptyString(node.right): return node.left

    return node

  else:
    return node

proc optimize*(node: AstNode): AstNode =
  if node == nil: return nil
  var current = node
  for pass in 0 ..< 4:
    current = optimizePass(current)
  return current
