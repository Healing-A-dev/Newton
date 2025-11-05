# Imports #
import tables
import errors

var STACK*:seq[string] = @[]

#[

Parsing options:

 - Option 1:
    Parse -> AST -> Xohe Intructions

 - Option 2:
    Parse -> Xohe Intructions

Or[bit] VM instruction example:
    x := 10                ->   10 64 10 00
    y := 5                 ->   10 65 05 00
    .puts x                ->   02 @64 00 00
    .puts x + y            ->   64 @64 @65 [ax]
                           ->   02 [ax] 00 00

    (ALL INTRUCTIONS ARE BASE16)
    (ANY STRINGS, VALUES OVER 2 DIGITS IN LENGTH, AND SPECIAL REGISTERS MUST BE ENCLOSED BY BRACKETS)
    (POINTER TO VARIABLE LOCATION VALUES ARE DENOTED BY @<location>)

    10  | STORE
    64  | Location to store variable
    10  | Data to store (number 10)
    00  | NOP

    10  | STORE
    65  | Location to store variable
    05  | Data to store (number 5)
    00  | NOP

    02  | WRITE
    @64 | Location of x
    00  | NOP
    00  | NOP

    64   | ADD
    @64  | Location of first variable (x)
    @65  | Location of second variable (y)
    [ax] | Special register to store answer

    02   | WIRTE
    [ax] | Data to write (Special register [ax])
    00   | NOP
    00   | NOP
]#

# Creating TOKEN type #
type TOKEN = tuple[Token: string, Value: string, isToken: bool, isStatement: bool]

proc Parse*(tokens: Table[int, seq[TOKEN]]): void =
    # Instance Variables
    var buffer_stack: bool = false
    var buffer_statement: string = ""
    
    for line in 0..<tokens.len:
        var pos: int = 0
        for _ in 0..<tokens[line].len:
            # Token Variable(s)
            var token: TOKEN = tokens[line][pos]

            # Stack Handling
            if token.isStatement == true:
                buffer_stack = true
                buffer_statement = token.TOKEN
                if buffer_statement == "%UNFOLD_STMT_PROC":
                    buffer_statement = tokens[line][pos-3].Value

            if buffer_stack == true and token.Token == "COLON":
                #echo "ADDED ", buffer_statement, " to stack"
                case buffer_statement
                of "ELSE_STMT", "ELSEIF_STMT":
                    if STACK[STACK.len-1] == "IF_STMT" or STACK[STACK.len-1] == "ELSEIF_STMT":
                        STACK[STACK.len-1] = buffer_statement
                    else:
                        processStack(STACK)
                        throwError("MISSING END FOR " & STACK[STACK.len-1] & "!")
                else:
                    STACK.add(buffer_statement)
                buffer_stack = false

            if token.Token == "END" and STACK.len > 0:
                #echo "REMOVED ", STACK[STACK.len-1], " from stack"
                STACK.del(STACK.len-1)
            elif token.Token == "END" and STACK.len == 0:
                processStack(STACK)
                throwError("UNEXPECTED_TOKEN", line, @[token.Token])

            pos.inc()

        # Missing (:) to initiate statement
        if buffer_stack == true:
            processStack(STACK)
            throwError("STATEMENT_INIT", line, @[tokens[line][pos-1].Value, buffer_statement])

    # Missing (end) to close statement
    if STACK.len > 0:
        processStack(STACK)
        throwError("MISSING END FOR " & STACK[STACK.len - 1] & "!")
