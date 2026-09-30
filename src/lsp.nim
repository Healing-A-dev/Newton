import json, strutils, streams, os, tables
import Newton/core/[parser, ast, errors, lexer]

var documents = initTable[string, string]()

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

proc publishDiagnostics(uri: string, sourceCode: string) =
  var diagnostics = newJArray()
  errors.isLspMode = true

  try:
    let tokens = lexer.lex(sourceCode)
    let subParser = parser.newParser(tokens)
    let astTree = subParser.parseProgram()

  except NewtonDiagnostic as e:
    let zeroIndexedLine = max(0, e.line - 1)
    let diag = %*{
      "range": {
        "start": {"line": zeroIndexedLine, "character": 0},
        "end": {"line": zeroIndexedLine, "character": 999} 
      },
      "severity": 1, 
      "code": e.code,
      "message": e.msg,
      "source": "newton"
    }
    diagnostics.add(diag)
  except Exception as e:
    discard

  sendNotification("textDocument/publishDiagnostics", %*{
    "uri": uri,
    "diagnostics": diagnostics
  })

proc getWordAtPosition(sourceCode: string, lineIdx, charIdx: int): string =
  let lines = sourceCode.splitLines()
  if lineIdx < 0 or lineIdx >= lines.len: return ""
  let lineStr = lines[lineIdx]
  if charIdx < 0 or charIdx >= lineStr.len: return ""
  
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
  
  if documents.hasKey(uri):
    let sourceCode = documents[uri]
    let word = getWordAtPosition(sourceCode, line, character)
    case word
    of "fun":
      hoverText = """**Keyword: `fun`**\n\nDefines a new function in Newton. Functions must be closed with `end`.\n\n
http://googleusercontent.com/immersive_entry_chip/0
http://googleusercontent.com/immersive_entry_chip/1
"""

proc handleInitialize(id: JsonNode) =
  let result = %*{
    "capabilities": {
      "textDocumentSync": 1, 
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
  publishDiagnostics(uri, text) 

proc handleDidChange(params: JsonNode) =
  let uri = params["textDocument"]["uri"].getStr()
  let newText = params["contentChanges"][0]["text"].getStr()
  documents[uri] = newText
  publishDiagnostics(uri, newText) 

proc handleDidClose(params: JsonNode) =
  let uri = params["textDocument"]["uri"].getStr()
  documents.del(uri)
  sendNotification("textDocument/publishDiagnostics", %*{
    "uri": uri,
    "diagnostics": []
  })

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
