import strutils, tables, errors

type
  TokenType* = enum
    tokEof, tokEol,
    tokIdentifier, tokNumberLit, tokStringLit,
    tokPlus, tokMinus, tokStar, tokSlash,
    tokLt, tokGt, tokEqEq, tokNeq,
    tokLParen, tokRParen, tokColon, tokComma, tokDollar, tokAmpersand,
    tokSet, tokIf, tokElseIf, tokElse, tokEnd, tokFn, tokFor, tokWhile, tokReturn,
    tokAtArgs, tokUsing, tokDot, tokDoubleColon, tokInput, tokLBrace, tokRBrace,
    tokForeach, tokConcat, tokCall, tokLBracket, tokRBracket, tokFloatLit,
    tokLe, tokGe, tokAnd, tokOr, tokNot, tokNamespace, tokDefmacro, tokMacroRef,
    tokMod, tokBitXor, tokShr, tokShl, tokMatch, tokArrow, tokIn, tokExposed

  Token* = object
    kind*: TokenType
    lexeme*: string
    line*: int

const keywords = {
  "set":      tokSet,
  "if":       tokIf,
  "elseif":   tokElseIf,
  "else":     tokElse,
  "end":      tokEnd,
  "fun":      tokFn,
  "for":      tokFor,
  "foreach":  tokForeach,
  "while":    tokWhile,
  "return":   tokReturn,
  "using":    tokUsing,
  "input":    tokInput,
  "call":     tokCall,
  "and":      tokAnd,
  "or":       tokOr,
  "match":    tokMatch,
  "not":      tokNot,
  "shl":      tokShl,
  "in":       tokIn, # Lol tokIN, token, get it?
  "defmacro": tokDefmacro,
  "exposed":  tokExposed
}.toTable()

proc newToken(kind: TokenType, lexeme: string, line: int): Token =
  return Token(kind: kind, lexeme: lexeme, line: line)

proc lex*(input: string): seq[Token] =
  var tokens: seq[Token] = @[]
  var start = 0
  var current = 0
  var line = 1

  while current < input.len:
    start = current
    let c = input[current]
    current.inc

    case c
    of ' ', '\r', '\t': discard
    of '\n':
      tokens.add(newToken(tokEol, "\n", line))
      line.inc
    of ';':
      while current < input.len and input[current] != '\n': current.inc
    of '(': tokens.add(newToken(tokLParen, "(", line))
    of ')': tokens.add(newToken(tokRParen, ")", line))
    of '{': tokens.add(newToken(tokLBrace, "{", line))
    of '}': tokens.add(newToken(tokRBrace, "}", line))
    of '[': tokens.add(newToken(tokLBracket, "[", line))
    of ']': tokens.add(newToken(tokRBracket, "]", line))
    of ':':
      if current < input.len and input[current] == ':':
          current.inc
          tokens.add(newToken(tokDoubleColon, "::", line))
      else:
          tokens.add(newToken(tokColon, ":", line))
    of '.': tokens.add(newToken(tokDot, ".", line))
    of ',': tokens.add(newToken(tokComma, ",", line))
    of '$': tokens.add(newToken(tokDollar, "$", line))
    of '&': tokens.add(newToken(tokAmpersand, "&", line))
    of '+': tokens.add(newToken(tokPlus, "+", line))
    of '*': tokens.add(newToken(tokStar, "*", line))
    of '/': tokens.add(newToken(tokSlash, "/", line))
    of '%': tokens.add(newToken(tokMod, "%", line))
    of '^': tokens.add(newToken(tokBitXor, "^", line))

    # Comparisons
    of '-':
      if current < input.len and input[current] == '>':
          current.inc
          tokens.add(newToken(tokArrow, "->", line))
      else:
          tokens.add(newToken(tokMinus, "-", line))
    of '<':
      # <=
      if current < input.len and input[current] == '=':
        current.inc
        tokens.add(newToken(tokLe, "<=", line))
      # << (Concat)
      elif current < input.len and input[current] == '<':
        current.inc
        tokens.add(newToken(tokConcat, "<<", line))
      else:
        tokens.add(newToken(tokLt, "<", line))
    of '>':
      # >=
      if current < input.len and input[current] == '=':
        current.inc
        tokens.add(newToken(tokGe, ">=", line))
      elif current < input.len and $input[current] ==  ">":
        current.inc
        tokens.add(newToken(tokShr, ">>", line))
      else:
        tokens.add(newToken(tokGt, ">", line))
    of '=':
        if current < input.len and input[current] == '=':
            current.inc
            tokens.add(newToken(tokEqEq, "==", line))
        else: ERR("Unexpected '='. Did you mean '=='?", line)
    of '!':
        if current < input.len and input[current] == '=':
            current.inc
            tokens.add(newToken(tokNeq, "!=", line))
        else: ERR("Unexpected '!'. Did you mean '!='?", line)

    # --- MACRO HANDLING (@) ---
    of '@':
        var text = "@"
        while current < input.len and input[current].isAlphaNumeric:
            text.add(input[current])
            current.inc

        if text == "@args":
            tokens.add(newToken(tokAtArgs, text, line))
        elif text == "@namespace":
            tokens.add(newToken(tokNamespace, text, line))
        else:
            tokens.add(newToken(tokMacroRef, text[1..^1], line))
            # raise newException(ValueError, "Unknown macro '" & text & "' at line " & $line)

    of '"':
        var strVal = ""

        while current < input.len and input[current] != '"':
            if input[current] == '\\' and current + 1 < input.len:
                strVal.add(input[current])
                current.inc               
                strVal.add(input[current])
            else:
                strVal.add(input[current])

            current.inc # Move to the next character in the string

        if current < input.len and input[current] == '"':
            current.inc # Skip the closing quote

        tokens.add(newToken(tokStringLit, strVal, line))

    else:
      if c.isDigit:
        # 1. Scan the integer part
        while current < input.len and input[current].isDigit:
          current.inc
        if current < input.len and input[current] == '.':
            var isFloat = false

            if current + 1 < input.len and input[current + 1].isDigit:
                isFloat = true

            if isFloat:
                current.inc
                while current < input.len and input[current].isDigit:
                    current.inc
                tokens.add(newToken(tokFloatLit, input[start..<current], line))
            else:
                tokens.add(newToken(tokNumberLit, input[start..<current], line))
        else:
            tokens.add(newToken(tokNumberLit, input[start..<current], line))

      elif c.isAlphaAscii or c == '_' or c == '#':
        while current < input.len and (input[current].isAlphaNumeric or input[current] == '_'):
          current.inc
        let text = input[start..<current]
        if keywords.hasKey(text): tokens.add(newToken(keywords[text], text, line))
        else: tokens.add(newToken(tokIdentifier, text, line))
      else:
        ERR("Unexpected character: '" & $c & "'", line)

  tokens.add(newToken(tokEof, "", line))
  return tokens
