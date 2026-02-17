import strutils, os, tables

let ERRORS: Table[string, string] = initTable[string, string]()


proc ERR(Msg: string, Line: int): void =
  






let HELP: Table[string, Table[string, string]] = initTable[string, Table[string, string]]()
