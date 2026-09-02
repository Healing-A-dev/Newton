# Filename: src/lsp.nim
import json, strutils, streams, os, tables
import Newton/core/[parser, ast, errors, lexer]

# ---------------------------------------------------------
# 1. State Management (The Virtual File System)
# ---------------------------------------------------------
# Maps the file's URI (e.g., "file:///home/user/main.nt") to its source code
var documents = initTable[string, string]()

# ---------------------------------------------------------
# 2. JSON-RPC Communication Layer
# ---------------------------------------------------------
proc sendResponse(id: JsonNode, result: JsonNode) =
  let response = %*{"jsonrpc": "2.0", "id": id, "result": result}
  let jsonStr = $response
  stdout.write("Content-Length: " & $jsonStr.len & "\r\n\r\n" & jsonStr)
  stdout.flushFile()

proc sendNotification(methodName: string, params: JsonNode) =
  let response = %*{"jsonrpc": "2.0", "method": methodName, "params": params}
  let jsonStr = $response
  stdout.write("Content-Length: " & $jsonStr.len & "\r\n\r\n" & jsonStr)
  stdout.flushFile()

proc readMessage(): JsonNode =
  var contentLength = 0
  while true:
    var line = stdin.readLine()
    if line == "": break
    if line.startsWith("Content-Length:"):
      contentLength = parseInt(line.split(":")[1].strip())

  if contentLength == 0: return newJNull()
  var bodyStr = newString(contentLength)
  discard stdin.readChars(bodyStr, 0, contentLength)
  return parseJson(bodyStr)

# ---------------------------------------------------------
# 3. Diagnostics Engine (Red Squiggles)
# ---------------------------------------------------------
proc publishDiagnostics(uri: string, sourceCode: string) =
  var diagnostics = newJArray()

  # Tell the compiler we are in LSP mode so it doesn't 'echo' or 'quit'
  errors.isLspMode = true

  try:
    # 1. Lex the raw string provided by the editor
    let tokens = lexer.lex(sourceCode)

    # 2. Parse the tokens into an AST
    let subParser = parser.newParser(tokens)
    let astTree = subParser.parseProgram()

    # If we get here, the code is perfectly valid! No squiggles needed.

  except NewtonDiagnostic as e:
    # We caught a syntax error! Let's build a red squiggle for the editor.
    # LSP lines are 0-indexed, but Newton lines are 1-indexed, so we subtract 1.
    let zeroIndexedLine = max(0, e.line - 1)

    let diag = %*{
      "range": {
        "start": {"line": zeroIndexedLine, "character": 0},
        "end": {"line": zeroIndexedLine, "character": 999} # Highlight the whole line
      },
      "severity": 1, # 1 = Error
      "code": e.code,
      "message": e.msg,
      "source": "newton"
    }
    diagnostics.add(diag)

  except Exception as e:
    # Catch any standard Nim panics just in case
    discard

  # Send the diagnostics (either empty or containing the error) back to the editor
  sendNotification("textDocument/publishDiagnostics", %*{
    "uri": uri,
    "diagnostics": diagnostics
  })

# ---------------------------------------------------------
# 4. Method Handlers
# ---------------------------------------------------------
proc getWordAtPosition(sourceCode: string, lineIdx, charIdx: int): string =
  ## A quick utility to extract the word the user is hovering over
  let lines = sourceCode.splitLines()
  if lineIdx < 0 or lineIdx >= lines.len: return ""

  let lineStr = lines[lineIdx]
  if charIdx < 0 or charIdx >= lineStr.len: return ""

  # Scan backwards and forwards to find the word boundaries
  var startIdx = charIdx
  while startIdx > 0 and (lineStr[startIdx - 1].isAlphaNumeric or lineStr[startIdx - 1] == '_'):
    startIdx.dec

  var endIdx = charIdx
  while endIdx < lineStr.len and (lineStr[endIdx].isAlphaNumeric or lineStr[endIdx] == '_'):
    endIdx.inc

  return lineStr[startIdx ..< endIdx]

proc handleHover(id: JsonNode, params: JsonNode) =
  let uri = params["textDocument"]["uri"].getStr()
  let line = params["position"]["line"].getInt()
  let character = params["position"]["character"].getInt()

  var hoverText = ""

  # 1. Grab the virtual file
  if documents.hasKey(uri):
    let sourceCode = documents[uri]
    let word = getWordAtPosition(sourceCode, line, character)

    # 2. Match the word and provide Markdown documentation!
    case word
    of "fun":
      hoverText = """**Keyword: `fun`**\n\nDefines a new function in Newton. Functions must be closed with `end`.\n\n
http://googleusercontent.com/immersive_entry_chip/0
http://googleusercontent.com/immersive_entry_chip/1
"""


proc handleInitialize(id: JsonNode) =
  let result = %*{
    "capabilities": {
      "textDocumentSync": 1, # Full sync mode
      "hoverProvider": true,
      "completionProvider": {
        "resolveProvider": false,
        "triggerCharacters": ["."]
      }
    },
    "serverInfo": {"name": "NewtonLSP", "version": "1.0.0"}
  }
  sendResponse(id, result)

proc handleDidOpen(params: JsonNode) =
  let uri = params["textDocument"]["uri"].getStr()
  let text = params["textDocument"]["text"].getStr()
  documents[uri] = text
  publishDiagnostics(uri, text) # Check for errors immediately on open

proc handleDidChange(params: JsonNode) =
  let uri = params["textDocument"]["uri"].getStr()
  # Because we use Full Sync (1), the editor sends the whole file in the first change event
  let newText = params["contentChanges"][0]["text"].getStr()
  documents[uri] = newText
  publishDiagnostics(uri, newText) # Re-check for errors every time they type!

proc handleDidClose(params: JsonNode) =
  let uri = params["textDocument"]["uri"].getStr()
  documents.del(uri)

  # Clear diagnostics when the file is closed so squiggles don't get stuck
  sendNotification("textDocument/publishDiagnostics", %*{
    "uri": uri,
    "diagnostics": []
  })

# ---------------------------------------------------------
# 5. Main Event Loop
# ---------------------------------------------------------
proc startServer*() =
  stderr.writeLine("[NewtonLSP] Server initialized and listening...")

  while true:
    try:
      let msg = readMessage()
      if msg.kind == JNull: continue

      let methodName = msg.getOrDefault("method").getStr()
      let params = msg.getOrDefault("params")
      let id = msg.getOrDefault("id")

      case methodName
      of "initialize": handleInitialize(id)
      of "initialized": stderr.writeLine("[NewtonLSP] Handshake complete.")
      of "textDocument/didOpen": handleDidOpen(params)
      of "textDocument/didChange": handleDidChange(params)
      of "textDocument/didClose": handleDidClose(params)
      of "shutdown": sendResponse(id, newJNull())
      of "exit": quit(0)
      else: discard

    except EOFError: break
    except Exception as e:
      stderr.writeLine("[NewtonLSP] Fatal Error: " & e.msg)

when isMainModule:
  startServer()
