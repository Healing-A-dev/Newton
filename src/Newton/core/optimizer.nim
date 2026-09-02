import ast, strutils, math

# Forward declaration for recursion
proc optimize*(node: AstNode): AstNode

# Helper to optimize a list of nodes
proc optimizeSeq*(nodes: seq[AstNode]): seq[AstNode] =
  result = @[]
  for n in nodes:
    result.add(optimize(n))

proc optimize*(node: AstNode): AstNode =
  if node == nil: return nil

  case node.kind:
  of nkProgram:
    node.stmts = optimizeSeq(node.stmts)
    return node

  of nkBlock:
    node.blockStmts = optimizeSeq(node.blockStmts)
    return node

  of nkVarDecl, nkGlobalDecl, nkAssignment:
    node.varValue = optimize(node.varValue)
    return node

  of nkReturn:
    node.returnVal = optimize(node.returnVal)
    return node

  of nkIf:
    node.condition = optimize(node.condition)
    node.thenBranch = optimize(node.thenBranch)
    if node.elseBranch != nil:
      node.elseBranch = optimize(node.elseBranch)
    return node

  of nkCall, nkCommand, nkCallDynamic:
    node.callArgs = optimizeSeq(node.callArgs)
    return node

  of nkFunction:
    node.fnBody = optimize(node.fnBody)
    return node

  of nkBracket:
    node.children = optimizeSeq(node.children)
    return node

  of nkVarRef:
    return node

  of nkBinaryOp:
    node.left = optimize(node.left)
    node.right = optimize(node.right)

    if node.left.kind == nkLiteral and node.right.kind == nkLiteral and
       not node.left.isString and not node.right.isString:

       try:
         let lval = parseFloat(node.left.strVal)
         let rval = parseFloat(node.right.strVal)
         var res: float

         case node.op:
           of "+": res = lval + rval
           of "-": res = lval - rval
           of "*": res = lval * rval
           of "/":
             if rval == 0.0: return node # Prevent division by zero at compile time
             res = lval / rval
           else: return node

         let isInt = (res == res.round())
         let resStr = if isInt: $(res.toInt()) else: $res

         return AstNode(
           kind: nkLiteral,
           strVal: resStr,
           isString: false,
           line: node.line
         )
       except:
         return node

    return node

  else:
    return node
