import json, strutils, os, tables
import parser, ast, errors, lexer

var documents* = initTable[string, string]()

# -------------------------------------------------------------
# JSON-RPC Protocol Helpers
# -------------------------------------------------------------

proc sendResponse*(id: JsonNode, result: JsonNode) =
  let response = %*{"jsonrpc": "2.0", "id": id, "result": result}
  let jsonStr = $response
  stdout.write("Content-Length: " & $jsonStr.len & "\r\n\r\n" & jsonStr)
  stdout.flushFile()

proc sendError*(id: JsonNode, code: int, message: string) =
  let response = %*{
    "jsonrpc": "2.0",
    "id": id,
    "error": {
      "code": code,
      "message": message
    }
  }
  let jsonStr = $response
  stdout.write("Content-Length: " & $jsonStr.len & "\r\n\r\n" & jsonStr)
  stdout.flushFile()

proc sendNotification*(methodName: string, params: JsonNode) =
  let response = %*{"jsonrpc": "2.0", "method": methodName, "params": params}
  let jsonStr = $response
  stdout.write("Content-Length: " & $jsonStr.len & "\r\n\r\n" & jsonStr)
  stdout.flushFile()

proc readMessage*(): JsonNode =
  var contentLength = 0
  while true:
    var line: string
    try:
      line = stdin.readLine()
    except EOFError:
      return newJNull()

    let trimmed = line.strip()
    if trimmed == "":
      break

    if trimmed.toLowerAscii().startsWith("content-length:"):
      let parts = trimmed.split(':')
      if parts.len > 1:
        try:
          contentLength = parseInt(parts[1].strip())
        except ValueError:
          discard

  if contentLength <= 0:
    return newJNull()

  var bodyStr = newString(contentLength)
  var totalRead = 0
  while totalRead < contentLength:
    let bytesRead = stdin.readBuffer(addr bodyStr[totalRead], contentLength - totalRead)
    if bytesRead <= 0:
      break
    totalRead += bytesRead

  if totalRead < contentLength:
    return newJNull()

  try:
    return parseJson(bodyStr)
  except JsonParsingError as e:
    stderr.writeLine("[NewtonLSP] JSON parse error: " & e.msg)
    return newJNull()

# -------------------------------------------------------------
# Diagnostics
# -------------------------------------------------------------

proc publishDiagnostics*(uri: string, sourceCode: string) =
  var diagnostics = newJArray()
  errors.isLspMode = true
  errors.resetErrorState()
  parser.resetParserState()

  try:
    let tokens = lexer.lex(sourceCode)
    let subParser = parser.newParser(tokens)
    let astTree = subParser.parseProgram()
    discard astTree
  except NewtonDiagnostic as e:
    let lines = sourceCode.splitLines()
    let zeroIndexedLine = max(0, e.line - 1)
    var endChar = 80
    if zeroIndexedLine < lines.len:
      endChar = max(1, lines[zeroIndexedLine].len)

    var msg = e.msg
    if e.hint != "":
      msg.add("\nHint: " & e.hint)

    let diag = %*{
      "range": {
        "start": {"line": zeroIndexedLine, "character": 0},
        "end": {"line": zeroIndexedLine, "character": endChar}
      },
      "severity": 1,
      "code": e.code,
      "message": msg,
      "source": "newton"
    }
    diagnostics.add(diag)
  except Exception as e:
    discard e

  sendNotification("textDocument/publishDiagnostics", %*{
    "uri": uri,
    "diagnostics": diagnostics
  })

# -------------------------------------------------------------
# Symbol Extraction & Navigation
# -------------------------------------------------------------

type
  NewtonDocSymbol* = object
    name*: string
    kind*: int # 12: Function, 11: Macro, 13: Variable
    signature*: string
    line*: int       # 0-indexed
    startChar*: int
    endChar*: int
    endLine*: int

proc extractSymbols*(sourceCode: string): seq[NewtonDocSymbol] =
  result = @[]
  let lines = sourceCode.splitLines()
  for i, line in lines:
    let trimmed = line.strip()
    if trimmed.startsWith(";") or trimmed.len == 0:
      continue

    # fun name: @args ...
    if trimmed.startsWith("fun ") or trimmed.startsWith("exposed fun "):
      let isExposed = trimmed.startsWith("exposed fun ")
      let prefix = if isExposed: "exposed fun " else: "fun "
      let rest = trimmed[prefix.len .. ^1].strip()
      let colonIdx = rest.find(':')
      var fnName = if colonIdx != -1: rest[0 ..< colonIdx].strip() else: rest.splitWhitespace()[0]
      let col = line.find(fnName)

      # Find matching end
      var endL = i
      var depth = 1
      for j in (i + 1) ..< lines.len:
        let subTrimmed = lines[j].strip()
        if subTrimmed.startsWith("fun ") or subTrimmed.startsWith("if ") or subTrimmed.startsWith("while ") or
           subTrimmed.startsWith("for ") or subTrimmed.startsWith("foreach ") or subTrimmed.startsWith("match ") or
           subTrimmed.startsWith("defmacro "):
          depth.inc
        elif subTrimmed == "end" or subTrimmed.startsWith("end "):
          depth.dec
          if depth == 0:
            endL = j
            break

      result.add(NewtonDocSymbol(
        name: fnName,
        kind: 12,
        signature: trimmed,
        line: i,
        startChar: max(0, col),
        endChar: max(0, col + fnName.len),
        endLine: endL
      ))

    # defmacro name:
    elif trimmed.startsWith("defmacro "):
      let rest = trimmed["defmacro ".len .. ^1].strip()
      let colonIdx = rest.find(':')
      var macroName = if colonIdx != -1: rest[0 ..< colonIdx].strip() else: rest.splitWhitespace()[0]
      let col = line.find(macroName)

      var endL = i
      var depth = 1
      for j in (i + 1) ..< lines.len:
        let subTrimmed = lines[j].strip()
        if subTrimmed.startsWith("fun ") or subTrimmed.startsWith("if ") or subTrimmed.startsWith("while ") or
           subTrimmed.startsWith("for ") or subTrimmed.startsWith("foreach ") or subTrimmed.startsWith("match ") or
           subTrimmed.startsWith("defmacro "):
          depth.inc
        elif subTrimmed == "end" or subTrimmed.startsWith("end "):
          depth.dec
          if depth == 0:
            endL = j
            break

      result.add(NewtonDocSymbol(
        name: "@" & macroName,
        kind: 11,
        signature: trimmed,
        line: i,
        startChar: max(0, col),
        endChar: max(0, col + macroName.len),
        endLine: endL
      ))

    # Global variable: set name*: val
    elif trimmed.startsWith("set ") and trimmed.contains('*'):
      let rest = trimmed["set ".len .. ^1].strip()
      let colonIdx = rest.find(':')
      if colonIdx != -1:
        let varName = rest[0 ..< colonIdx].strip()
        if varName.endsWith('*'):
          let col = line.find(varName)
          result.add(NewtonDocSymbol(
            name: varName,
            kind: 13,
            signature: trimmed,
            line: i,
            startChar: max(0, col),
            endChar: max(0, col + varName.len),
            endLine: i
          ))

# -------------------------------------------------------------
# Token Inspection at Cursor
# -------------------------------------------------------------

proc getWordAtPosition*(sourceCode: string, lineIdx, charIdx: int): tuple[fullWord: string, baseWord: string, modulePrefix: string] =
  let lines = sourceCode.splitLines()
  if lineIdx < 0 or lineIdx >= lines.len: return ("", "", "")
  let lineStr = lines[lineIdx]
  if lineStr.len == 0 or charIdx < 0: return ("", "", "")

  let clampedIdx = min(charIdx, lineStr.len - 1)

  proc isIdentChar(c: char): bool =
    c.isAlphaNumeric or c in {'_', '$', '@', '#', '*'}

  var startIdx = clampedIdx
  while startIdx > 0 and isIdentChar(lineStr[startIdx - 1]):
    startIdx.dec

  var endIdx = clampedIdx
  while endIdx < lineStr.len and isIdentChar(lineStr[endIdx]):
    endIdx.inc

  let rawWord = if startIdx < endIdx: lineStr[startIdx ..< endIdx] else: ""

  # Check for preceding module prefix (e.g. web.httpServer or io.println)
  var modPrefix = ""
  if startIdx > 1 and lineStr[startIdx - 1] == '.':
    var modStart = startIdx - 2
    while modStart > 0 and lineStr[modStart - 1].isAlphaNumeric:
      modStart.dec
    modPrefix = lineStr[modStart ..< startIdx - 1]

  var full = rawWord
  if modPrefix.len > 0:
    full = modPrefix & "." & rawWord

  return (full, rawWord, modPrefix)

# -------------------------------------------------------------
# Documentation Database for Hover & Autocompletion
# -------------------------------------------------------------

proc getHoverDocumentation*(symbol: string, rawWord: string, modPrefix: string): string =
  # 1. Keywords
  case rawWord
  of "fun":
    return """### Keyword: `fun`
Defines a function in Newton.
```nim
fun calculate: @args x, y
    return $x + $y
end
```
Functions in Newton must conclude with the `end` keyword."""

  of "exposed":
    return """### Keyword: `exposed`
Exports a function with standard CDECL ABI calling conventions (`F_<name>`) so external C libraries and foreign code can call it.
```nim
exposed fun multiply: @args a, b
    return $a * $b
end
```"""

  of "end":
    return """### Keyword: `end`
Closes open code blocks including `fun`, `if`, `while`, `for`, `foreach`, `match`, and `defmacro`."""

  of "set":
    return """### Keyword: `set`
Declares and initializes a local variable.
```nim
set count: 0
count: $count + 1 ; Reassignment omits 'set'
```"""

  of "if", "elif", "elseif", "else":
    return """### Control Flow: Conditional Branching
Newton conditionals evaluate conditions against truthy expressions (non-zero).
```nim
if $code == 200:
    @println "OK"
elif $code == 404:
    @println "Not Found"
else:
    @println "Other"
end
```"""

  of "while":
    return """### Control Flow: `while`
Loops while the given expression evaluates to non-zero.
```nim
while $i < 10:
    i: $i + 1
end
```"""

  of "for":
    return """### Control Flow: `for`
Numeric range loop iterating from `start` to `end` (exclusive) by `step`.
```nim
for &i, 0, 10, 1:
    @println "Index: {}", $i
end
```"""

  of "foreach":
    return """### Control Flow: `foreach`
Iterates over collections (maps, lists, arrays) or characters of a string.
Supports 1-variable and 2-variable iteration:
```nim
foreach $k, $v in (lang: "Newton", fast: 1):
    @println "{}: {}", $k, $v
end

foreach $item in ["alpha", "beta", "gamma"]:
    @println "Item: {}", $item
end
```"""

  of "match":
    return """### Pattern Matching: `match`
Branching construct matching values to target patterns.
```nim
match $status:
    200 -> @println "OK"
    404 -> @println "Not Found"
end
```"""

  of "return":
    return """### Keyword: `return`
Exits the current function and returns the evaluated payload to the caller."""

  of "break":
    return """### Keyword: `break`
Terminates execution of the innermost `while`, `for`, or `foreach` loop."""

  of "using":
    return """### Module Import: `using`
Imports an external or standard library module into scope.
```nim
using std::io
using std::web
```"""

  of "defmacro":
    return """### Compile-Time Macro: `defmacro`
Defines an AST macro expanded at compile time. Macro arguments are automatically packed into `$M_ARGV`. Macros must be invoked with `@<name>`.
```nim
defmacro log:
    @println "[LOG] {}", $M_ARGV{0}
end
```"""

  of "sizeof":
    return """### Operator: `sizeof <expr>`
Returns the element count of a list or map, or the character length of a string."""

  of "typeof":
    return """### Operator: `typeof <expr>`
Returns a string identifying the runtime type (`"int"`, `"float"`, `"string"`, `"list"`, `"map"`)."""

  of "substring":
    return """### Operator: `substring <str>, <start>, <length>`
Extracts a substring of `<length>` characters starting at 0-indexed position `<start>`."""

  of "call":
    return """### First-Class Calls: `call <fn_ptr>(<args>...)`
Executes a dynamic function reference with passed arguments."""

  # 2. Base Prelude Macros
  of "@println", "println":
    if modPrefix == "" or modPrefix == "Base":
      return """### Prelude Macro: `@println [format_string, args...]`
Variadic output macro with newline. Supports `{}` placeholder interpolation and polymorphic recursive printing for lists `[...]` and maps `(...)`.
```nim
@println "User {}: {}", $id, $name
```"""

  of "@print", "print":
    if modPrefix == "" or modPrefix == "Base":
      return """### Prelude Macro: `@print [format_string, args...]`
Variadic output macro without a trailing newline. Supports `{}` placeholder interpolation and polymorphic collection formatting."""

  of "@assert", "assert":
    return """### Prelude Macro: `@assert <condition>, <message>`
Asserts that `<condition>` evaluates to non-zero. If false, aborts execution with `<message>`.
```nim
@assert ($age >= 18), "Must be an adult!"
```"""

  of "@isError":
    return """### Prelude Macro: `@isError <tuple>`
Returns `1` if `$tuple{0} == "error"`, else `0`."""

  of "@getError":
    return """### Prelude Macro: `@getError <tuple>`
Extracts the error message `$tuple{1}` from an error tuple."""

  of "@capture":
    return """### Prelude Macro: `@capture <expr>`
Captures the result tuple of an expression without immediate failure."""

  of "@ok":
    return """### Prelude Macro: `@ok`
Expands to `"ok"`. Used for success result tuples `[@ok, $payload]`."""

  of "@err":
    return """### Prelude Macro: `@err`
Expands to `"error"`. Used for error result tuples `[@err, $message]`."""

  of "@readln":
    return """### Prelude Macro: `@readln [prompt]`
Reads a line from standard input. If a prompt argument is supplied, displays the prompt first."""

  of "@quit":
    return """### Prelude Macro: `@quit <code>`
Immediately terminates the running process with integer exit code `<code>`."""

  of "@split":
    return """### Prelude Macro: `@split <str>, [delim]`
Splits a string into a list of substrings with assertion type verification."""

  of "@splitToMap":
    return """### Prelude Macro: `@splitToMap <str>, [delim]`
Splits a string into a reverse-indexed key-value map."""

  # 3. Base Prelude Variables & Functions
  of "argc*", "$argc*":
    return """### Global Variable: `argc*` (int)
Total count of command-line arguments passed to the Newton program."""

  of "argv*", "$argv*":
    return """### Global Variable: `argv*` (list)
List of command-line argument strings passed to the Newton program."""

  of "fmRead*", "fmWrite*", "fmAppend*":
    return """### File Mode Flags (`Base.nt`)
- `fmRead*`: Read mode (`0`)
- `fmWrite*`: Write mode (`577`)
- `fmAppend*`: Append mode (`1089`)"""

  of "readfile":
    return """### Prelude Function: `readfile <path>`
Reads the entire contents of a file at `<path>` into memory as a string. Returns `["ok", content]`."""

  of "fopen":
    return """### Prelude Function: `fopen <path>, <mode>`
Opens a file with mode (`"r"`, `"w"`, `"a"` or integer flag). Returns `["ok", fd]`."""

  of "fclose":
    return """### Prelude Function: `fclose <fd>`
Closes the open file descriptor `<fd>`."""

  of "fwrite":
    return """### Prelude Function: `fwrite <fd>, <data>`
Writes string data to the specified file descriptor."""

  of "fileExists":
    return """### Prelude Function: `fileExists <path>`
Returns `["ok", 1]` if the file exists on disk, else `["ok", 0]`."""

  of "deleteFile":
    return """### Prelude Function: `deleteFile <path>`
Deletes (unlinks) the file at `<path>`."""

  of "die":
    return """### Prelude Function: `die <message>, <errno>`
Prints an error message to standard error and terminates process with `<errno>`."""

  # 4. Standard Modules
  of "io":
    return """### Module: `std::io`
Terminal input/output utilities and formatted collection printing.
- `io.println val`
- `io.print val`
- `io.readln`
- `io.prompt msg`
- `io.err msg, errno`"""

  of "string":
    return """### Module: `std::string`
String inspection, transformation, splitting, trimming, and searching.
- `string.split str, delim`
- `string.reverse str`
- `string.has str, pattern`
- `string.replace str, pat, rep`
- `string.lower str` / `string.upper str`
- `string.trim str`"""

  of "collection":
    return """### Module: `std::collection`
List and map operations: pushing, popping, slicing, joining, keys, and values.
- `collection.push coll, val`
- `collection.pop coll`
- `collection.join coll, sep`
- `collection.keys map`
- `collection.values map`
- `collection.slice list, start, count`"""

  of "math":
    return """### Module: `std::math`
Constants (`PI*`, `TAU*`, `E*`) and mathematical functions (`abs`, `min`, `max`, `pow`, `sqrt`, `round`, `clamp`, `sin`, `cos`, `gcd`)."""

  of "file":
    return """### Module: `std::file`
Filesystem I/O: `open`, `read`, `readEntireFile`, `write`, `close`, `exists`, `delete`, `sizeof`."""

  of "process":
    return """### Module: `std::process`
Process management: `fork`, `id`, `wait`, `sleep`, `nanosleep`, `exit`."""

  of "os":
    return """### Module: `std::os`
Operating system environment: `getenv`, `time`, `timeSince`, `host`, `execute`."""

  of "web":
    return """### Module: `std::web`
High-level networking suite: HTTP servers, HTTP clients (`httpGet`, `httpPost`), TCP sockets, and request parsing."""

  else: discard

  # 5. Qualified Module Calls (e.g. web.httpServer, io.println)
  case symbol
  # std::io
  of "io.println":
    return """### `io.println val`
Prints `val` with a trailing newline. Polymorphically and recursively formats maps `(...)` and lists `[...]`."""
  of "io.print":
    return """### `io.print val`
Prints `val` without a trailing newline. Polymorphically and recursively formats maps and lists."""
  of "io.readln":
    return """### `io.readln` -> `["ok", line]`
Reads a line of text from standard input."""
  of "io.prompt":
    return """### `io.prompt msg` -> `["ok", line]`
Prints prompt string `msg` without a newline, then reads a line from standard input."""

  # std::web
  of "web.httpServer":
    return """### `web.httpServer port` -> `server_fd`
Creates, binds, and listens on `0.0.0.0:<port>`. Ready for `web.accept` and `web.serveRequest`."""
  of "web.serveRequest":
    return """### `web.serveRequest client_fd` -> `map`
Reads up to 4096 bytes and parses incoming HTTP request into a map: `(method, path, headers, body, query)`."""
  of "web.respond":
    return """### `web.respond client_fd, status_code, body, content_type`
Formats an HTTP/1.1 response, sends it over the socket, and automatically closes the client connection."""
  of "web.respondHtml":
    return """### `web.respondHtml client_fd, html_body`
Responds with HTTP 200 OK and `Content-Type: text/html; charset=utf-8`, then closes socket."""
  of "web.respondJson":
    return """### `web.respondJson client_fd, json_body`
Responds with HTTP 200 OK and `Content-Type: application/json`, then closes socket."""
  of "web.respondNotFound":
    return """### `web.respondNotFound client_fd`
Responds with HTTP 404 Not Found, then closes socket."""
  of "web.httpGet":
    return """### `web.httpGet host, port, path` -> `map`
Sends an HTTP/1.1 GET request. Returns structured map: `(status, headers, body)`."""
  of "web.httpPost":
    return """### `web.httpPost host, port, path, body, content_type` -> `map`
Sends an HTTP/1.1 POST request with payload and content-type header. Returns response map."""
  of "web.tcpServer":
    return """### `web.tcpServer port` -> `sock_fd`
Creates and listens on a raw TCP socket at the specified port."""
  of "web.tcpConnect":
    return """### `web.tcpConnect ip_str, port` -> `["ok", sock_fd]`
Connects to a remote TCP server at IPv4 address and port."""

  # std::string
  of "string.split":
    return """### `string.split str, delim` -> `["ok", list]`
Splits `str` into substrings separated by `delim`. If `delim` is empty, splits into individual characters."""
  of "string.splitToMap":
    return """### `string.splitToMap str, delim` -> `["ok", map]`
Splits string into a key-value map with reverse-indexed items."""
  of "string.reverse":
    return """### `string.reverse str` -> `["ok", string]`
Reverses character order of `str`."""
  of "string.has":
    return """### `string.has str, pattern` -> `["ok", 1|0]`
Returns `1` if `pattern` is present within `str`, otherwise `0`."""
  of "string.replace":
    return """### `string.replace str, pattern, replacement` -> `["ok", string]`
Replaces all non-overlapping occurrences of `pattern` with `replacement`."""
  of "string.trim", "string.stripWhitespace":
    return """### `string.trim str` -> `["ok", string]`
Strips leading and trailing spaces, tabs, and newlines from `str`."""
  of "string.lower":
    return """### `string.lower str` -> `string`
Converts ASCII characters to lowercase."""
  of "string.upper":
    return """### `string.upper str` -> `string`
Converts ASCII characters to uppercase."""

  # std::collection
  of "collection.push":
    return """### `collection.push coll, val` -> `["ok", coll]`
Appends `val` to the end of a list or map."""
  of "collection.pop":
    return """### `collection.pop coll` -> `["ok", val]`
Removes and returns the last element of a list or map."""
  of "collection.join":
    return """### `collection.join coll, sep` -> `["ok", string]`
Concatenates collection items into a string separated by `sep`."""
  of "collection.keys":
    return """### `collection.keys map` -> `["ok", list]`
Returns a list containing all keys in `map`."""
  of "collection.values":
    return """### `collection.values map` -> `["ok", list]`
Returns a list containing all values in `map`."""
  of "collection.slice":
    return """### `collection.slice list, start, count` -> `["ok", list]`
Extracts `count` items from `list` starting at index `start`."""

  # std::math
  of "math.abs":
    return """### `math.abs n` -> `num`
Returns absolute value of `n`."""
  of "math.min":
    return """### `math.min a, b` -> `num`
Returns smaller of `a` and `b`."""
  of "math.max":
    return """### `math.max a, b` -> `num`
Returns larger of `a` and `b`."""
  of "math.pow":
    return """### `math.pow base, exp` -> `num`
Computes exponentiation `base ^ exp`."""
  of "math.sqrt":
    return """### `math.sqrt n` -> `float`
Computes square root of `n` via Newton-Raphson approximation."""
  of "math.clamp":
    return """### `math.clamp val, low, high` -> `num`
Clamps `val` to range `[low, high]`."""

  else: return ""

# -------------------------------------------------------------
# LSP Request Handlers
# -------------------------------------------------------------

proc handleInitialize*(id: JsonNode) =
  let result = %*{
    "capabilities": {
      "textDocumentSync": 1, # Full synchronization
      "hoverProvider": true,
      "definitionProvider": true,
      "documentSymbolProvider": true,
      "completionProvider": {
        "resolveProvider": false,
        "triggerCharacters": [".", "$", "@", ":"]
      }
    },
    "serverInfo": {
      "name": "Newton Language Server",
      "version": "0.6.1"
    }
  }
  sendResponse(id, result)

proc handleHover*(id: JsonNode, params: JsonNode) =
  let uri = params["textDocument"]["uri"].getStr()
  let line = params["position"]["line"].getInt()
  let character = params["position"]["character"].getInt()

  if not documents.hasKey(uri):
    sendResponse(id, newJNull())
    return

  let sourceCode = documents[uri]
  let (fullWord, rawWord, modPrefix) = getWordAtPosition(sourceCode, line, character)

  var hoverText = getHoverDocumentation(fullWord, rawWord, modPrefix)

  # Check if hovering over a user function or macro defined in this file
  if hoverText == "":
    let symbols = extractSymbols(sourceCode)
    for sym in symbols:
      if sym.name == rawWord or sym.name == fullWord or sym.name == "@" & rawWord:
        let kindStr = if sym.kind == 11: "Macro" elif sym.kind == 13: "Global Variable" else: "Function"
        hoverText = "### " & kindStr & ": `" & sym.name & "`\n```nim\n" & sym.signature & "\n```\nDefined on line " & $(sym.line + 1)
        break

  if hoverText != "":
    let result = %*{
      "contents": {
        "kind": "markdown",
        "value": hoverText
      }
    }
    sendResponse(id, result)
  else:
    sendResponse(id, newJNull())

proc handleCompletion*(id: JsonNode, params: JsonNode) =
  let uri = params["textDocument"]["uri"].getStr()
  let line = params["position"]["line"].getInt()
  let character = params["position"]["character"].getInt()

  var items = newJArray()

  if documents.hasKey(uri):
    let sourceCode = documents[uri]
    let lines = sourceCode.splitLines()
    var linePrefix = ""
    if line >= 0 and line < lines.len and character >= 0:
      let clamped = min(character, lines[line].len)
      linePrefix = lines[line][0 ..< clamped]

    # Extract token context before cursor
    let trimmedPrefix = linePrefix.strip(leading = false)
    var modToken = ""
    let dotIdx = trimmedPrefix.rfind('.')
    if dotIdx != -1:
      var modStart = dotIdx - 1
      while modStart >= 0 and trimmedPrefix[modStart].isAlphaNumeric:
        modStart.dec
      let candidate = trimmedPrefix[modStart + 1 ..< dotIdx]
      if candidate in ["io", "web", "string", "collection", "math", "file", "process", "os", "path", "json", "terminal", "crypt", "test"]:
        modToken = candidate

    let atIdx = trimmedPrefix.rfind('@')
    let isMacroPrefix = (atIdx != -1 and not trimmedPrefix[atIdx .. ^1].contains(' '))

    # 1. Module Member Completions (e.g. io., web.http, string.sp)
    if modToken == "io":
      for fn in ["println", "print", "readln", "prompt", "err"]:
        items.add(%*{"label": fn, "kind": 3, "detail": "std::io", "insertText": fn & " "})

    elif modToken == "web":
      for fn in ["httpServer", "serveRequest", "respond", "respondHtml", "respondJson", "respondNotFound", "httpGet", "httpPost", "tcpServer", "tcpConnect", "tcpAccept", "tcpSend", "tcpRecv", "tcpClose"]:
        items.add(%*{"label": fn, "kind": 3, "detail": "std::web", "insertText": fn & " "})

    elif modToken == "string":
      for fn in ["split", "splitToMap", "reverse", "sub", "has", "replace", "startsWith", "endsWith", "ascii", "char", "find", "chop", "lower", "upper", "repeat", "trim", "lstrip", "rstrip", "count", "padLeft", "padRight"]:
        items.add(%*{"label": fn, "kind": 3, "detail": "std::string", "insertText": fn & " "})

    elif modToken == "collection":
      for fn in ["push", "pop", "remove", "join", "fill", "min", "max", "zip", "duplicates", "toMap", "toList", "shiftLeft", "shiftRight", "contains", "indexOf", "slice", "keys", "values", "reverse", "clone", "clear", "flatten"]:
        items.add(%*{"label": fn, "kind": 3, "detail": "std::collection", "insertText": fn & " "})

    elif modToken == "math":
      for fn in ["PI", "TAU", "E", "abs", "min", "max", "pow", "mod", "floor", "ceil", "round", "sqrt", "random", "sin", "cos", "clamp", "xor", "sign", "isEven", "isOdd", "gcd", "lcm", "lerp", "degToRad", "radToDeg", "factorial"]:
        items.add(%*{"label": fn, "kind": 3, "detail": "std::math", "insertText": fn})

    elif modToken == "file":
      for fn in ["open", "write", "writeBytes", "read", "readEntireFile", "close", "exists", "delete", "newDirectory", "sizeof"]:
        items.add(%*{"label": fn, "kind": 3, "detail": "std::file", "insertText": fn & " "})

    elif modToken == "process":
      for fn in ["fork", "id", "wait", "sleep", "nanosleep", "exit"]:
        items.add(%*{"label": fn, "kind": 3, "detail": "std::process", "insertText": fn & " "})

    elif modToken == "os":
      for fn in ["getenv", "time", "timeSince", "host", "execute"]:
        items.add(%*{"label": fn, "kind": 3, "detail": "std::os", "insertText": fn & " "})

    elif modToken == "path":
      for fn in ["join", "basename", "dirname", "extension"]:
        items.add(%*{"label": fn, "kind": 3, "detail": "std::path", "insertText": fn & " "})

    elif modToken == "json":
      for fn in ["parse", "stringify", "jsonify"]:
        items.add(%*{"label": fn, "kind": 3, "detail": "std::json", "insertText": fn & " "})

    elif modToken == "terminal":
      for fn in ["text", "error", "success", "warning", "debug", "RESET", "BOLD", "RED", "GREEN", "YELLOW", "BLUE"]:
        items.add(%*{"label": fn, "kind": 3, "detail": "std::terminal", "insertText": fn})

    # 2. Macro Completions (after '@')
    elif isMacroPrefix:
      for m in ["println", "print", "assert", "isError", "getError", "capture", "ok", "err", "readln", "quit", "split", "splitToMap"]:
        items.add(%*{"label": "@" & m, "kind": 15, "detail": "Macro", "insertText": m & " "})

    # 3. Standard Library Import Completions (after 'using std::')
    elif trimmedPrefix.contains("using std::") or trimmedPrefix.contains("using "):
      for mName in ["io", "string", "collection", "math", "file", "process", "os", "path", "json", "terminal", "web", "crypt", "test"]:
        items.add(%*{"label": mName, "kind": 9, "detail": "Standard Library Module", "insertText": mName})

    # 4. General Keyword, Prelude & Document Function Completions
    else:
      for kw in ["fun", "end", "set", "if", "elif", "elseif", "else", "while", "for", "foreach", "match", "return", "break", "using", "defmacro", "exposed", "sizeof", "typeof", "substring"]:
        items.add(%*{"label": kw, "kind": 14, "detail": "Keyword", "insertText": kw & " "})

      for fn in ["readfile", "fopen", "fclose", "fwrite", "fileExists", "deleteFile", "newDirectory", "die", "push", "pop", "list", "map", "delete", "iota"]:
        items.add(%*{"label": fn, "kind": 3, "detail": "Prelude Function", "insertText": fn & " "})

      for m in ["@println", "@print", "@assert", "@isError", "@getError", "@capture", "@readln", "@quit"]:
        items.add(%*{"label": m, "kind": 15, "detail": "Prelude Macro", "insertText": m & " "})

      # Add user-defined functions from this file
      let userSymbols = extractSymbols(sourceCode)
      for sym in userSymbols:
        items.add(%*{
          "label": sym.name,
          "kind": sym.kind,
          "detail": sym.signature,
          "insertText": sym.name & " "
        })

  let result = %*{
    "isIncomplete": false,
    "items": items
  }
  sendResponse(id, result)

proc handleDocumentSymbols*(id: JsonNode, params: JsonNode) =
  let uri = params["textDocument"]["uri"].getStr()
  var symbols = newJArray()

  if documents.hasKey(uri):
    let sourceCode = documents[uri]
    let docSymbols = extractSymbols(sourceCode)
    for sym in docSymbols:
      symbols.add(%*{
        "name": sym.name,
        "kind": sym.kind,
        "range": {
          "start": {"line": sym.line, "character": 0},
          "end": {"line": sym.endLine, "character": 999}
        },
        "selectionRange": {
          "start": {"line": sym.line, "character": sym.startChar},
          "end": {"line": sym.line, "character": sym.endChar}
        }
      })

  sendResponse(id, symbols)

proc handleDefinition*(id: JsonNode, params: JsonNode) =
  let uri = params["textDocument"]["uri"].getStr()
  let line = params["position"]["line"].getInt()
  let character = params["position"]["character"].getInt()

  if not documents.hasKey(uri):
    sendResponse(id, newJNull())
    return

  let sourceCode = documents[uri]
  let (fullWord, rawWord, _) = getWordAtPosition(sourceCode, line, character)

  let symbols = extractSymbols(sourceCode)
  for sym in symbols:
    if sym.name == rawWord or sym.name == fullWord or sym.name == "@" & rawWord:
      let loc = %*{
        "uri": uri,
        "range": {
          "start": {"line": sym.line, "character": sym.startChar},
          "end": {"line": sym.line, "character": sym.endChar}
        }
      }
      sendResponse(id, loc)
      return

  sendResponse(id, newJNull())

proc handleDidOpen*(params: JsonNode) =
  let uri = params["textDocument"]["uri"].getStr()
  let text = params["textDocument"]["text"].getStr()
  documents[uri] = text
  publishDiagnostics(uri, text)

proc handleDidChange*(params: JsonNode) =
  let uri = params["textDocument"]["uri"].getStr()
  let newText = params["contentChanges"][0]["text"].getStr()
  documents[uri] = newText
  publishDiagnostics(uri, newText)

proc handleDidClose*(params: JsonNode) =
  let uri = params["textDocument"]["uri"].getStr()
  documents.del(uri)
  sendNotification("textDocument/publishDiagnostics", %*{
    "uri": uri,
    "diagnostics": []
  })

# -------------------------------------------------------------
# Main Event Loop
# -------------------------------------------------------------

proc startServer*() =
  stderr.writeLine("[NewtonLSP] Newton Language Server initialized and listening...")
  while true:
    try:
      let msg = readMessage()
      if msg.kind == JNull: continue

      let methodName = msg.getOrDefault("method").getStr()
      let params = msg.getOrDefault("params")
      let id = msg.getOrDefault("id")

      case methodName
      of "initialize":
        handleInitialize(id)
      of "initialized":
        stderr.writeLine("[NewtonLSP] Handshake complete.")
      of "textDocument/didOpen":
        handleDidOpen(params)
      of "textDocument/didChange":
        handleDidChange(params)
      of "textDocument/didSave":
        if params.hasKey("textDocument") and params["textDocument"].hasKey("uri"):
          let uri = params["textDocument"]["uri"].getStr()
          if documents.hasKey(uri):
            publishDiagnostics(uri, documents[uri])
      of "textDocument/didClose":
        handleDidClose(params)
      of "textDocument/hover":
        handleHover(id, params)
      of "textDocument/completion":
        handleCompletion(id, params)
      of "textDocument/documentSymbol":
        handleDocumentSymbols(id, params)
      of "textDocument/definition":
        handleDefinition(id, params)
      of "shutdown":
        sendResponse(id, newJNull())
      of "exit":
        quit(0)
      else:
        # Ignore unhandled notifications, return null for unhandled requests
        if id.kind != JNull:
          sendResponse(id, newJNull())

    except EOFError:
      break
    except Exception as e:
      stderr.writeLine("[NewtonLSP] Error in main loop: " & e.msg)
