import strutils, os

type
  NewtonDiagnostic* = object of CatchableError
    line*: int
    code*: string
    hint*: string

var isLspMode*: bool = false
var currentCompilingFile*: string = "main.nt"
var ERRCOUNT*: int = 0

proc ERR*(Msg: string, Line: int, Code: string = "", Hint: string = ""): void =
  # Exit early if too many errors are found
  if ERRCOUNT >= 10:
    echo "Compilation Failed With <\e[1;31m" & $ERRCOUNT & "+\e[0m> Errors"
    quit(1)

  var finalCode = Code
  var finalHint = Hint

  if finalCode == "":
    if Msg.contains("Unexpected character"):
      finalCode = "E001"
      if finalHint == "": finalHint = "The Lexer found a character that isn't a valid Newton symbol. Did you make a typo?"
    elif Msg.contains("Expected") or Msg.contains("Unknown statement"):
      finalCode = "E002"
      if finalHint == "": finalHint = "The Parser encountered an unexpected token. Check for missing commas, colons, or mismatched brackets."
    elif Msg.contains("Could not find module"):
      finalCode = "E003"
      if finalHint == "": finalHint = "Module resolution failed. Check if the file exists in the correct directory, or verify your 'using' path."
    else:
      finalCode = "E099"
      if finalHint == "": finalHint = "An internal compilation constraint was violated."

  if isLspMode:
      var e = newException(NewtonDiagnostic, Msg)
      e.line = Line
      e.code = finalCode
      e.hint = finalHint
      raise e

  if ERRCOUNT == 0:
    echo "\e[1;31m--- [ COMPILER FAULT ] ---\e[0m"
    echo "\e[1mCode   :\e[0m ", finalCode
    echo "\e[1mFile   :\e[0m ", currentCompilingFile, " (Line ", Line, ")"
    echo "\e[1mReason :\e[0m ", Msg
    echo ""

    var lineContent = ""
    if fileExists(currentCompilingFile):
      let lines = readFile(currentCompilingFile).splitLines()
      if Line > 0 and Line <= lines.len:
        lineContent = lines[Line - 1]

    if lineContent != "":
      let lineStr = $Line
      let pad = repeat(' ', lineStr.len)

      echo "  ", lineStr, " | ", lineContent

      let trimmed = lineContent.strip(leading=true, trailing=false)
      let spaceCount = lineContent.len - trimmed.len

      let squiggly = repeat(' ', spaceCount) & "\e[1;31m" & repeat('^', max(1, trimmed.len)) & "\e[0m"
      echo "  ", pad, " | ", squiggly
    else:
      echo "  <source code unavailable>"

    echo ""
    if finalHint != "":
      echo "\e[1;30mHint   :\e[0m ", finalHint

  ERRCOUNT.inc
