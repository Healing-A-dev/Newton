# Standard Modules
import std / [tables, os]
import lexer
import parser
#import pattern
#import OrbitVM/core/memory

type 
    ORB_VAR = object
        Type*: string
        Value*: string
        Content*: seq[string]

# Variables Table
var VARIABLES*: Table[string, Table[string, ORB_VAR]] = initTable[string, Table[string, ORB_VAR]]()
type TOKEN = tuple[Token: string, Value: string, isToken: bool, isStatement: bool]


let FILENAME:string = commandLineParams()[0]

proc main(): void =
    let Tokens: Table[int, seq[TOKEN]] = Lex(FILENAME)
    Parse(Tokens)
    #echo Tokens
    for s in (0..<Tokens.len):
        echo s
        for _,value in Tokens[s].pairs():
            echo "    " & $value
    
main()


#const test: string = "    .puts \"Hello, World!\""
#let p_match: string = test.p_replace("    ", test.len)
#echo p_match
