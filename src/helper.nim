import errors
import tables
import strutils

type TOKEN = tuple[
    Token: string,
    Value: string,
    isToken: bool,
    isStatement: bool
]

proc expect*(values: seq[string], tokens: Table[int, seq[TOKEN]], line: int = 0, position: int = 0, err: string = "NAME_EXPECTED"): TOKEN {.discardable.} = 
    var position: int = position
    if position < 0:
        position = 0 
    var token: TOKEN = tokens[line][position]
    var prev_token: string = "null"

    if position + 1 >= tokens[line].len and err == "NAME_EXPECTED":
        throwError(err, line, @[token.Value, ""]) 

    for name in values:
        if position + 1 < tokens[line].len and tokens[line][position + 1].Token.contains(name):
            return tokens[line][position+1]

    if position + 1 < tokens[line].len:
        prev_token = "'" & tokens[line][position + 1].Value & "'"

    throwError(err, line, @[token.Value, prev_token])


# VERY BASIC Pattern Matching
proc patternMatch*(str: string, pattern: string): string =
    # Instance Variables
    var builtin: Table[string, string] = {
        "s": " ",
        "d": "",
    }.toTable()
    
    # Defining pattern
    # for 

    return ""
