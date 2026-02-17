import tables

type
  AstNodeKind* = enum
    nkProgram, nkFunction, nkBlock,
    nkVarDecl, nkAssignment, nkGlobalDecl,
    nkVarRef, nkLiteral, nkBinaryOp,
    nkIf, nkLoop, nkWhile,
    nkCall, nkCommand, nkReturn,
    nkInput, nkMapLit, nkMapGet,
    nkForeach, nkDel, nkInfix,
    nkCallDynamic, nkBracket, nkFloatLit

  AstNode* = ref object
    line*: int
    case kind*: AstNodeKind
    of nkProgram: stmts*: seq[AstNode]
    of nkBlock: blockStmts*: seq[AstNode]

    # --- FIX: Group nkAssignment here ---
    # It shares the same fields (varName, varValue) as declarations
    of nkVarDecl, nkGlobalDecl, nkAssignment:
      varName*: string
      varValue*: AstNode

    of nkVarRef: refName*: string
    of nkLiteral, nkFloatLit:
      strVal*: string
      isString*: bool
    of nkBinaryOp, nkInfix:
      op*: string
      left*, right*: AstNode
    of nkCommand, nkCall, nkCallDynamic:
      callName*: string
      callTarget*: AstNode
      callArgs*: seq[AstNode]
    of nkFunction:
      fnName*: string
      fnArgs*: seq[string]
      fnBody*: AstNode
    of nkReturn:
      returnVal*: AstNode
    of nkIf:
      condition*: AstNode
      thenBranch*: AstNode
      elseBranch*: AstNode
    of nkLoop:
      loopType*: string
      loopArgs*: seq[AstNode]
      loopBody*: AstNode
    of nkWhile:
      whileCondition*: AstNode
      whileBody*: AstNode
    of nkInput:
      discard
    of nkMapLit:
      mapKeys*: seq[AstNode]   # Stores keys (or empty for lists)
      mapValues*: seq[AstNode] # Stores values
      isList*: bool            # True if defined as ("a", "b"), False if (a:1)
    of nkMapGet:
      targetMap*: AstNode      # The variable holding the map (e.g., $names)
      targetKey*: AstNode
    of nkForeach:
      loopKey*: string
      loopVal*: string
      loopSource*: AstNode
      foreachBody*: seq[AstNode]
    of nkDel:
      delMap*: AstNode
      delKey*: AstNode
    of nkBracket:
      children*: seq[AstNode]
