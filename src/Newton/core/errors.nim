import strutils, os

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

  # Print the error header
  if ERRCOUNT == 0:
    echo "\e[1;31merror[", finalCode, "]\e[0m\e[1m: ", Msg, "\e[0m"
    echo "\e[1;34m  --> \e[0m", currentCompilingFile, ":", Line
    echo "\e[1;34m   |\e[0m"
  
    var lineContent = ""
    if fileExists(currentCompilingFile):
      let lines = readFile(currentCompilingFile).splitLines()
      if Line > 0 and Line <= lines.len:
        lineContent = lines[Line - 1]
  
    let lineStr = $Line
    let pad = repeat(' ', lineStr.len)
  
    if lineContent != "":
      echo " \e[1;34m", lineStr, " | \e[0m", lineContent
  
      let trimmed = lineContent.strip(leading=true, trailing=false)
      let spaceCount = lineContent.len - trimmed.len
      let squiggly = repeat(' ', spaceCount) & "\e[1;31m" & repeat('^', max(1, trimmed.len)) & "\e[0m"
  
      echo " \e[1;34m", pad, " | \e[0m", squiggly
    else:
      echo "\e[1;34m", lineStr, " | \e[0m <source code unavailable>"
  
    echo "\e[1;34m   |\e[0m"
    if finalHint != "":
      echo "\e[1;36m   = help\e[0m: ", finalHint
    echo "\n"
  ERRCOUNT.inc
