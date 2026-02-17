import strutils, tables

type
  TokenType* = enum
    tokEof, tokEol,
    tokIdentifier, tokNumberLit, tokStringLit,
    tokPlus, tokMinus, tokStar, tokSlash,
    tokLt, tokGt, tokEqEq, tokNeq,
    tokLParen, tokRParen, tokColon, tokComma, tokDollar, tokAmpersand,
    tokSet, tokIf, tokElseIf, tokElse, tokEnd, tokFn, tokFor, tokWhile, tokReturn,
    tokAtArgs, tokUsing, tokDot, tokDoubleColon, tokInput, tokLBrace, tokRBrace,
    tokForeach, tokDel, tokConcat, tokCall, tokLBracket, tokRBracket, tokFloatLit,
    tokLe, tokGe, tokAnd, tokOr, tokNot

  Token* = object
    kind*: TokenType
    lexeme*: string
    line*: int

const keywords = {
  "set":     tokSet,
  "if":      tokIf,
  "elseif":  tokElseIf,
  "else":    tokElse,
  "end":     tokEnd,
  "fn":      tokFn,
  "for":     tokFor,
  "foreach": tokForeach,
  "while":   tokWhile,
  "return":  tokReturn,
  "using":   tokUsing,   # <--- ADDED: Support for 'using' keyword
  "input":   tokInput,
  "del":     tokDel,
  "call":    tokCall,
  "and":     tokAnd,
  "or":      tokOr,
  "not":     tokNot
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

    # --- UPDATED: Colon and Double Colon Logic ---
    of ':':
      if current < input.len and input[current] == ':':
          current.inc
          tokens.add(newToken(tokDoubleColon, "::", line))
      else:
          tokens.add(newToken(tokColon, ":", line))

    # --- UPDATED: Dot Logic ---
    of '.': tokens.add(newToken(tokDot, ".", line))

    of ',': tokens.add(newToken(tokComma, ",", line))
    of '$': tokens.add(newToken(tokDollar, "$", line))
    of '&': tokens.add(newToken(tokAmpersand, "&", line))
    of '+': tokens.add(newToken(tokPlus, "+", line))
    of '-': tokens.add(newToken(tokMinus, "-", line))
    of '*': tokens.add(newToken(tokStar, "*", line))
    of '/': tokens.add(newToken(tokSlash, "/", line))

    # Comparisons
    of '<':
      # Check for <=
      if current < input.len and input[current] == '=':
        current.inc
        tokens.add(newToken(tokLe, "<=", line))
      # Check for << (Concat)
      elif current < input.len and input[current] == '<':
        current.inc
        tokens.add(newToken(tokConcat, "<<", line))
      else:
        tokens.add(newToken(tokLt, "<", line))
    of '>':
      # Check for >=
      if current < input.len and input[current] == '=':
        current.inc
        tokens.add(newToken(tokGe, ">=", line))
      else:
        tokens.add(newToken(tokGt, ">", line))
    of '=':
        if current < input.len and input[current] == '=':
            current.inc
            tokens.add(newToken(tokEqEq, "==", line))
        else: raise newException(ValueError, "Unexpected '=' at line " & $line)
    of '!':
        if current < input.len and input[current] == '=':
            current.inc
            tokens.add(newToken(tokNeq, "!=", line))
        else: raise newException(ValueError, "Unexpected '!' at line " & $line)

    # --- MACRO HANDLING (@) ---
    of '@':
        var text = "@"
        while current < input.len and input[current].isAlphaNumeric:
            text.add(input[current])
            current.inc

        if text == "@args":
            tokens.add(newToken(tokAtArgs, text, line))
        else:
            # You can add more macros here later
            raise newException(ValueError, "Unknown macro '" & text & "' at line " & $line)

    of '"':
      var strVal = ""
      while current < input.len and input[current] != '"':
        strVal.add(input[current])
        current.inc
      if current < input.len: current.inc
      tokens.add(newToken(tokStringLit, strVal, line))

    else:
      if c.isDigit:
        # 1. Scan the integer part
        while current < input.len and input[current].isDigit:
          current.inc
        # 2. Check for Decimal Point
        # We look ahead: If we see a '.', AND the character after it is a digit, it's a Float.
        # (This prevents confusion with method calls like `1.toString`)
        if current < input.len and input[current] == '.':
            # Peek next char to ensure it's a number (e.g. "3.14") not just "1."
            var isFloat = false
            if current + 1 < input.len and input[current + 1].isDigit:
                isFloat = true
            if isFloat:
                current.inc # Consume '.'
                # Scan the fractional part
                while current < input.len and input[current].isDigit:
                    current.inc
                tokens.add(newToken(tokFloatLit, input[start..<current], line))
            else:
                # It was just an integer followed by a dot (e.g. end of sentence or method)
                tokens.add(newToken(tokNumberLit, input[start..<current], line))
        else:
            # It's a standard Integer
            tokens.add(newToken(tokNumberLit, input[start..<current], line))
      elif c.isAlphaAscii or c == '_':
        while current < input.len and (input[current].isAlphaNumeric or input[current] == '_'):
          current.inc
        let text = input[start..<current]
        if keywords.hasKey(text): tokens.add(newToken(keywords[text], text, line))
        else: tokens.add(newToken(tokIdentifier, text, line))
      else:
        raise newException(ValueError, "Unexpected character: " & $c & " at line " & $line)

  tokens.add(newToken(tokEof, "", line))
  return tokens
