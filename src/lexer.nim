# Modules
import std/[strutils, tables, os]
import tokens
import errors
import helper
import pattern

# Creating TOKEN type #
type TOKEN = tuple[
  Token: string,
  Value: string,
  isToken: bool,
  isStatement: bool
]

# Instance Variables #
var LexerTokens: Table[int, seq[TOKEN]] = initTable[int, seq[TOKEN]]()
var DISCARDED: TOKEN = (Token: "DISCARDED", Value: "", isToken: false, isStatement: false)


# Token Checker #
proc isValidToken(token: string): TOKEN =
  if len(token) == 1:
    if Tokens.hasKey(token):
      return (Token: Tokens.getOrDefault(token), Value: token, isToken: true, isStatement: false)

  elif len(token) > 1:
    let rep_token: string = token.p_replace(" ", token.len)
    if Tokens.hasKey(rep_token):
      let token_value: string = Tokens.getOrDefault(rep_token)
      if token_value.contains("STMT"):
        return (Token: token_value, Value: rep_token, isToken: true, isStatement: true)

      return (Token: token_value, Value: rep_token, isToken: true, isStatement: false)

  return (Token: "", Value: "", isToken: false, isStatement: false)


# Tokenizer #
proc Tokenize(lines: seq[string]): void =
  var token_buffer: seq[string] = @[]
  for line, content in lines.pairs():
    LexerTokens[line] = @[]
    for character in content:
      if not isValidToken("" & character).isToken:
        token_buffer.add("" & character)
      else:
        if len(token_buffer) > 0:
          let token: string = token_buffer.join("")
          let token_data: tuple = isValidToken(token)
          if token_data.isToken:
            LexerTokens[line].add(token_data)
          else:
            LexerTokens[line].add((Token: "TBD", Value: token, isToken: false, isStatement: false))

        token_buffer.setLen(0)
        LexerTokens[line].add(isValidToken("" & character))
    if len(token_buffer) > 0:
      let token: string = token_buffer.join("")
      let token_data: tuple = isValidToken("" & token)
      if token_data.isToken:
        LexerTokens[line].add(token_data)
      else:
        LexerTokens[line].add((Token: "TBD", Value: token, isToken: false, isStatement: false))
      token_buffer.setLen(0)


proc Adjust(): void =
  for line in 0..<LexerTokens.len:
    var fix: seq[TOKEN] = @[]
    var pos: int = 0
    while pos < LexerTokens[line].len:
      var token: TOKEN = LexerTokens[line][pos]

      # Combined tokens
      if pos < LexerTokens[line].len-1:
        let combined: Token = fetchCombinedToken(token.Value, LexerTokens[line][pos+1].Value)
        if combined.Token != "":
          fix.add(combined)
          pos += 2
          continue

      # String literals
      if token.Token.contains("QUOTE"):
        var buffer: seq[string] = @[]
        var skipper: int = 1
        while pos+skipper < LexerTokens[line].len and LexerTokens[line][pos+skipper].Token != token.Token:
          buffer.add(LexerTokens[line][pos+skipper].Value)
          LexerTokens[line][pos+skipper] = DISCARDED
          skipper.inc()

        if pos+skipper >= LexerTokens[line].len:
          throwError("SYNTAX_ERROR", line, @[buffer.join(""), "unfinished string near: " & buffer.join(""), "`" & token.Value & "`" , "string", " `" & token.Value & "`"])
        else:
          fix.add((Token: "STR", Value: buffer.join(""), isToken: true, isStatement: false))
          LexerTokens[line][pos+skipper] = DISCARDED
          pos += skipper+1
          continue

      # Numbers
      if token.Token == "TBD":
        try:
          discard parseInt(token.Value)
          fix.add((Token: "NUM", Value: token.Value, isToken: true, isStatement: false))
          LexerTokens[line][pos] = DISCARDED
          pos.inc()
          continue
        except ValueError as err:
          discard

      # Keep useful tokens
      if token.Token != "SPACE" and token.Token != "DISCARDED":
        fix.add(token)

      pos.inc()

    LexerTokens[line] = fix


proc Lex*(filename: string): Table[int, seq[TOKEN]]=
  # Instance Variables
  var ReturnTokens: Table[int, seq[TOKEN]] = initTable[int, seq[TOKEN]]()
  var multiline_comment: bool = false

  # Checking if file exist
  if fileExists(filename):
    let lines = readFile(filename).splitLines()
    Tokenize(lines)
  else:
    throwError("FILE_DNE", 0, @[filename])

  # Adjusting tokens
  Adjust()

  # Finalizing lexing
  for line in 0..<LexerTokens.len:
    var pos = 0
    for i,token in LexerTokens[line]:

      case token.Token
      # Global keyword
      of "GLOBAL":
        let old_token: string = expect(@["TBD"], LexerTokens, line, pos).Value
        LexerTokens[line][pos+1].Token = "@G_" & old_token
        LexerTokens[line][pos] = DISCARDED

      # Defining Variables
      of "VAR_DEFINE":
        if pos - 1 < 0 or pos == 0:
          throwError("NAME_EXPECTED", line, @[token.Value])

        let old_token: string = LexerTokens[line][pos-1].Token
        if old_token != "TBD" and not old_token.contains("VAR") and not old_token.contains("@G_"):
          echo old_token, ": ", LexerTokens[line][pos-1].Value
          throwError("NAME_EXPECTED", line, @[token.Value])

        expect(@["VAR_CALL", "STR", "O_BRACE", "NUM", "PERIOD"], LexerTokens, line, pos, "VALUE_EXPECTED")
        LexerTokens[line][pos-1].Token = "$" & (old_token <?> "@G_").Pattern & "VAR"

      # Reassigning Variables
      of "EQU":
        if pos - 1 < 0 or pos == 0:
          throwError("NAME_EXPECTED", line, @[token.Value])

        let old_token: TOKEN = LexerTokens[line][pos-1]
        if old_token.Token != "VAR_CALL":
          throwError("NAME_EXPECTED", line, @[token.Value])

        expect(@["VAR_CALL", "STR", "O_BRACE", "NUM", "PERIOD"], LexerTokens, line, pos, "VALUE_EXPECTED")

      # Period (function calls, floats)
      of "PERIOD":
        if pos - 1 < 0 or pos == 0:
          expect(@["TBD"], LexerTokens, line, pos)
          LexerTokens[line][pos] = DISCARDED
          LexerTokens[line][pos+1].Token = "CALL_PROC"
        else:
          let prev_token: TOKEN = expect(@["VAR_DEFINE", "NUM", "COMMA", "O_BRACE", "CONCAT", "EQU", "O_BRACKET"], LexerTokens, line, pos-2, "VALUE_EXPECTED")
          let next_token: TOKEN = expect(@["TBD", "NUM"], LexerTokens, line, pos, "VALUE_EXPECTED")
          # Floats (eg. 3.14)
          if prev_token.Token == "NUM" and next_token.Token != "NUM":
            throwError("SYNTAX_ERROR", line, @[token.Value, "invalid integer: " & next_token.Value, "<integer> `" & token.Value & "`", "integer", ""])
          else:
            LexerTokens[line][pos-1].Value = prev_token.Value & token.Value & next_token.Value
            LexerTokens[line][pos] = DISCARDED
            LexerTokens[line][pos+1] = DISCARDED

          # Function calls (eg. .main)
          if prev_token.Token != "NUM" and next_token.Token == "TBD":
            LexerTokens[line][pos] = DISCARDED
            LexerTokens[line][pos+1].Token = "CALL_PROC"

      # Calls (->)
      of "CALLS":
        if pos - 1 < 0 or pos == 0:
          throwError("NAME_EXPECTED", line, @[token.Value])
        else:
          let prev_token: TOKEN = LexerTokens[line][pos-1]
          let next_token: TOKEN = LexerTokens[line][pos+1]
          if prev_token.Token != "TBD" and not prev_token.Token.contains("@G_"):
            throwError("NAME_EXPECTED", line, @[token.Value, prev_token.Value])
          else:
            LexerTokens[line][pos-1].Token = "$" & (prev_token.Token <?> "@G_").Pattern & "VAR"

          if next_token.Token != "UNFOLD":
            throwError("SYNTAX_ERROR", line, @[token.Value, "& expected after '" & token.Value & "': got " & next_token.Value, "`" & token.Value & "` &", "folded_function_name", ""])

      # Unfold (&)
      of "UNFOLD":
        let next_token: TOKEN = expect(@["TBD", "PROC"], LexerTokens, line, pos)
        if LexerTokens[line][pos+1].Token.contains("STMT"):
          LexerTokens[line][pos+1].Token = "%UNFOLD_" & (next_token.Token <?> "STMT").Pattern
        else:
          LexerTokens[line][pos+1].Token = "%UNFOLD_STMT"

      # Variable Calling
      of "VAR_CALL":
        expect(@["TBD"], LexerTokens, line, pos)
        LexerTokens[line][pos+1].Token = token.Token
        LexerTokens[line][pos] = DISCARDED

      # Single-line Comments
      of "SINGLE_COMMENT":
        var skipper: int = 0
        while pos + skipper < LexerTokens[line].len:
          LexerTokens[line][pos+skipper] = DISCARDED
          skipper.inc()

      # Multi-line Comments
      of "M_COMMENT_START":
        var line_skipper: int = line
        var pos_skipper: int = pos + 1
        var found_end: bool = false
      
        while line_skipper < LexerTokens.len:
          while pos_skipper < LexerTokens[line_skipper].len:
            let t: TOKEN = LexerTokens[line_skipper][pos_skipper]
            if t.Token == "M_COMMENT_END":
              LexerTokens[line_skipper][pos_skipper] = DISCARDED
              found_end = true
              break
            else:
              LexerTokens[line_skipper][pos_skipper] = DISCARDED
            pos_skipper.inc()
      
          if found_end:
            break
          # Go to next line and reset position
          line_skipper.inc()
          pos_skipper = 0
      
        if not found_end:
          throwError("SYNTAX_ERROR", line, @["Unterminated multiline comment"])
      
        # Discard start token
        LexerTokens[line][pos] = DISCARDED
        pos = LexerTokens[line].len
        continue
      
      # Library Call
      of "LIB_CALL":
        var lib_name: TOKEN = expect(@["TBD"], LexerTokens, line, pos)
        throwWarning("TODO\n|> Implement array file importing\n|> @{std, err, web, etc}\n|> {\"file1\", \"file2\", \"file3\", etc}\n")

      # Return Keyword
      of "RETURN":
        var skipper: int = 1
        while pos + skipper < LexerTokens[line].len:
          LexerTokens[line][pos + skipper].Token = "RETURN_VALUE"
          skipper.inc()
      
      pos.inc()

  # Cleaning Lexer Table
  for line in 0..<LexerTokens.len:
    var pos: int = 0
    ReturnTokens[line] = @[]
    for token in LexerTokens[line]:
      if token.Token != "DISCARDED" and token.Token != "TBD":
        ReturnTokens[line].add(LexerTokens[line][pos])
      elif token.Token == "TBD":
        if pos > 0:
          #echo line
          throwError("UNEXPECTED_TOKEN", line, @[token.Value, LexerTokens[line][pos-1].Value])
        else:
          #echo line
          throwError("UNEXPECTED_TOKEN", line, @[token.Value])
      pos.inc()

  return ReturnTokens
