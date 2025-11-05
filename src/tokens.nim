import tables

const Tokens* = {
    # Keywords
    "proc":      "STMT_PROC",
    "end":       "END",
    "if":        "IF_STMT",
    "elseif":    "ELSEIF_STMT",
    "else":      "ELSE_STMT",
    "for":       "FOR_STMT",
    "using":     "USING",
    "while":     "WHILE_STMT",
    "export":    "GLOBAL",
    "true":      "TRUE",
    "false":     "FALSE",
    "null":      "NULL",
    "fold":      "FOLD",
    "and":       "AND",
    "or":        "OR",
    "ret":       "RETURN",

    # Symbols
    " ":         "SPACE",
    ".":         "PERIOD",
    ":":         "COLON",
    ",":         "COMMA",
    "#":         "SINGLE_COMMENT",
    "+":         "ADD",
    "-":         "SUB",
    "/":         "DIV",
    "*":         "MUL",
    "^":         "EXP",
    "=":         "EQU",
    ">":         "G_THAN",
    "<":         "L_THAN",
    "!":         "BANG",
    "'":         "S_QUOTE",
    "\"":        "D_QUOTE",
    "(":         "O_PAREN",
    ")":         "C_PAREN",
    "[":         "O_BRACKET",
    "]":         "C_BRACKET",
    "{":         "O_BRACE",
    "}":         "C_BRACE",
    "&":         "UNFOLD",
    "$":         "VAR_CALL",
    "\n":        "NEWLINE",
    "@":         "LIB_CALL",

    # Combined Symbols
    "==":        "CMP",
    ">=":        "G_EQU",
    "<=":        "L_EQU",
    "!=":        "N_EQU",
    "/=":        "M_COMMENT_START",
    "=/":        "M_COMMENT_END",
    "->":        "CALLS",
    "::":        "SUB_VAR_CALL",
    ":=":        "VAR_DEFINE"
}.toTable()

type TOKEN = tuple[
    Token: string,
    Value: string,
    isToken: bool,
    isStatement: bool
]

proc fetchCombinedToken*(token1: string, token2: string): TOKEN = 
    let combined_token = token1 & token2
    if Tokens.hasKey(combined_token) and combined_token.len == 2:
        let value = Tokens.getOrDefault(combined_token)
        return (Token: value, Value: combined_token, isToken: true, isStatement: false)
