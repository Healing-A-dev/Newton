# 9. Standard Library Reference

Newton ships with a modular, highly performant standard library designed around a consistent, non-throwing `["ok", data]` / `["error", message]` tuple pattern.

To import any standard library module into your Newton file, use the `using` statement:

```crystal
using std::io
using std::string
using std::collection
using std::math
using std::file
using std::process
using std::os
using std::path
using std::json
using std::terminal
using std::web
```

> **Note:** The `Base` prelude module is automatically imported unless compiled with `--noStdlib`. It brings foundational macros (`@println`, `@assert`), global variables (`argc*`, `argv*`), and common wrappers (`readfile`, `fopen`) into global scope.

---

## 1. The Newton Prelude (`std::Base.nt`)

The Newton Prelude is the foundational standard library module automatically injected into every compiled program (`.nt`) and script (`.nts`).

### Automatic Imports
When the prelude is injected, the following core modules are automatically brought into scope without requiring explicit `using` statements:
- `std::io`
- `std::file`
- `std::string`
- `std::collection`
- `std::system`

To disable prelude injection (for bare-metal development or minimal standalone binaries), compile with the `--noStdlib` flag:
```bash
newton build main.nt --noStdlib
```

---

### Global Prelude Variables

| Variable | Type | Description |
|---|---|---|
| `argc*` | `int` | Total count of command-line arguments passed to the application. |
| `argv*` | `list` | List of command-line argument strings passed to the application. |
| `fmRead*` | `int` | File access mode constant for reading (`0`). |
| `fmWrite*` | `int` | File access mode constant for writing/truncating (`577`). |
| `fmAppend*` | `int` | File access mode constant for appending (`1089`). |
| `__iota__*` | `int` | Internal sequence state counter utilized by the `iota` generator. |

---

### Core Result & Assertion Macros

Newton standard library operations use a non-throwing tuple pattern: `["ok", payload]` or `["error", message]`.

| Macro | Syntax | Description |
|---|---|---|
| `@ok` | `@ok` | Expands to the string `"ok"`. Used in success tuples `[@ok, $result]`. |
| `@err` | `@err` | Expands to the string `"error"`. Used in failure tuples `[@err, $message]`. |
| `@capture` | `@capture expr` | Evaluates and captures the tuple result of an expression. |
| `@isError` | `@isError $result` | Evaluates whether `$result{0} == "error"`. Returns `1` or `0`. |
| `@getError` | `@getError $result` | Extracts the error message `$result{1}` from an error tuple. |
| `@assert` | `@assert cond, msg, [fn]` | Asserts that `cond` is non-zero. If false, aborts with `msg` or invokes optional callback function. |

```crystal
using std::file

fun main:
    set res: @capture file.readEntireFile "data.txt"
    if @isError $res:
        @println "Failed to read file: {}", @getError $res
    else:
        @println "Contents: {}", $res{1}
    end
end
```

---

### Variadic Printing & I/O Macros

| Macro | Syntax | Description |
|---|---|---|
| `@println` | `@println [format_str, args...]` | Variadic print with trailing newline. Replaces `{}` with argument values and recursively formats nested lists `[...]` and maps `(...)`. |
| `@print` | `@print [format_str, args...]` | Variadic print without trailing newline. Supports `{}` interpolation and polymorphic collection formatting. |
| `@readln` | `@readln [prompt]` | Reads a single line of input from `stdin`. If `prompt` is supplied, displays the prompt first. |
| `@quit` | `@quit <code>` | Immediately terminates the process with exit code `<code>`. |

---

### Global String Macros

| Macro | Syntax | Description |
|---|---|---|
| `@split` | `@split str, [delim]` | Splits `str` by `delim` (default `""` for characters). Enforces type checks and returns substring list. |
| `@splitToMap` | `@splitToMap str, [delim]` | Splits `str` into a reverse-indexed key-value map. |

---

### Global File Functions

The prelude exposes direct global wrappers around `std::file`:

| Function | Signature | Return Value | Description |
|---|---|---|---|
| `readfile` | `readfile path` | `["ok", string]` | Reads the entire content of a file into a string. |
| `fopen` | `fopen path, mode` | `["ok", fd]` | Opens file with mode (`"r"`, `"w"`, `"a"` or integer flag). |
| `fclose` | `fclose fd` | `["ok", 0]` | Closes open file descriptor. |
| `fwrite` | `fwrite fd, data` | `["ok", bytes]` | Writes string to file descriptor. |
| `fwriteBytes` | `fwriteBytes fd, data` | `["ok", bytes]` | Writes raw binary data to file descriptor. |
| `fgets` | `fgets fd, max_len` | `["ok", string]` | Reads up to `max_len` bytes from file descriptor. |
| `fsizeof` | `fsizeof fd` | `["ok", bytes]` | Returns file size in bytes from file descriptor. |
| `fileExists` | `fileExists path` | `["ok", 1\|0]` | Checks whether file exists on disk. |
| `deleteFile` | `deleteFile path` | `["ok", 0]` | Unlinks/deletes the specified file. |
| `newDirectory` | `newDirectory path` | `["ok", 0]` | Creates a directory at `path`. |

---

### Global Collection Functions

Direct global helpers for lists and maps:

| Function | Signature | Return Value | Description |
|---|---|---|---|
| `push` | `push coll, val` | `["ok", coll]` | Appends `val` to the end of list or map. |
| `pop` | `pop coll` | `["ok", val]` | Removes and returns the last element. |
| `delete` | `delete coll, key` | `["ok", 1]` | Deletes key from map or index from list. |
| `list` | `list val` | `["ok", list]` | Converts `val` (map, string, list) to a list. |
| `map` | `map val` | `map` | Converts `val` (list, string, map) to a map. |

---

### Global Utility Functions

| Function | Signature | Description |
|---|---|---|
| `die` | `die message, errno` | Writes error message to stderr and terminates process with `errno` (defaults to 1 if 0). |
| `true` | `true` | Returns boolean integer `1`. |
| `false` | `false` | Returns boolean integer `0`. |
| `pass` | `pass` | No-op empty placeholder function. |
| `iota` | `iota` | Returns an auto-incrementing integer starting from `0`. |
| `iota_reset` | `iota_reset` | Resets the `iota` counter back to `-1`. |

---

## 2. `std::io` — Input & Output

Module for terminal input/output and formatted display.

```crystal
using std::io
```

### Functions

| Function | Signature | Description |
|---|---|---|
| `io.println` | `io.println val` | Prints `val` followed by a newline. Handles nested maps `(...)` and lists `[...]` recursively. |
| `io.print` | `io.print val` | Prints `val` without a trailing newline. Recursively formats collections. |
| `io.readln` | `io.readln` | Reads a single line of input from `stdin`. Returns `["ok", line]`. |
| `io.prompt` | `io.prompt msg` | Displays `msg` without a newline, then reads a line from `stdin`. Returns `["ok", line]`. |
| `io.err` | `io.err msg, errno` | Writes ANSI-red colored error message to `stderr` and terminates process with code `errno`. |

---

## 3. `std::string` — String Manipulation

Comprehensive utilities for inspecting, modifying, splitting, and padding strings.

```crystal
using std::string
```

### Functions

| Function | Signature | Return Value | Description |
|---|---|---|---|
| `string.split` | `string.split str, delim` | `["ok", list]` | Splits `str` into a list of substrings separated by `delim`. If `delim` is `""`, splits into individual characters. |
| `string.splitToMap` | `string.splitToMap str, delim` | `["ok", map]` | Splits `str` into a key-value map with reverse-indexed items. |
| `string.reverse` | `string.reverse str` | `["ok", string]` | Reverses character sequence of `str`. |
| `string.sub` | `string.sub str, start, len` | `["ok", string]` | Returns a substring starting at index `start` with length `len`. |
| `string.has` | `string.has str, pattern` | `["ok", int]` | Returns `1` if `pattern` occurs within `str`, otherwise `0`. |
| `string.replace` | `string.replace str, pat, rep` | `["ok", string]` | Replaces all non-overlapping occurrences of `pat` with `rep`. |
| `string.startsWith` | `string.startsWith str, prefix` | `["ok", int]` | Returns `1` if `str` begins with `prefix`, else `0`. |
| `string.endsWith` | `string.endsWith str, suffix` | `["ok", int]` | Returns `1` if `str` ends with `suffix`, else `0`. |
| `string.ascii` | `string.ascii str` | `["ok", int]` | Returns ASCII code integer of the first character. |
| `string.char` | `string.char ascii_code` | `["ok", string]` | Converts ASCII integer code to a 1-character string. |
| `string.find` | `string.find str, val` | `["ok", string]` / `["ok", 0]` | Searches `str` for `val`. Returns `val` if found, `0` otherwise. |
| `string.chop` | `string.chop str` | `["ok", string]` | Returns `str` with its last character removed. |
| `string.lower` | `string.lower str` | `string` | Converts ASCII letters in `str` to lowercase. |
| `string.upper` | `string.upper str` | `string` | Converts ASCII letters in `str` to uppercase. |
| `string.repeat` | `string.repeat str, count` | `string` | Repeats `str` sequentially `count` times. |
| `string.stripWhitespace` | `string.stripWhitespace str` | `["ok", string]` | Trims leading and trailing spaces, tabs, and newlines. |
| `string.trim` | `string.trim str` | `["ok", string]` | Alias for `stripWhitespace`. |
| `string.lstrip` | `string.lstrip str` | `["ok", string]` | Trims leading whitespace characters. |
| `string.rstrip` | `string.rstrip str` | `["ok", string]` | Trims trailing whitespace characters. |
| `string.count` | `string.count str, pat` | `["ok", int]` | Counts non-overlapping occurrences of `pat` in `str`. |
| `string.padLeft` | `string.padLeft str, len, ch` | `["ok", string]` | Prepends `ch` until length reaches `len`. |
| `string.padRight` | `string.padRight str, len, ch` | `["ok", string]` | Appends `ch` until length reaches `len`. |

---

## 4. `std::collection` — Lists & Maps

High-level manipulation of arrays, lists `[...]`, and key-value maps `(...)`.

```crystal
using std::collection
```

### Functions

| Function | Signature | Return Value | Description |
|---|---|---|---|
| `collection.push` | `collection.push coll, val` | `["ok", coll]` | Appends `val` to the end of list or map. |
| `collection.pop` | `collection.pop coll` | `["ok", val]` | Removes and returns the last element. |
| `collection.remove` | `collection.remove coll, key` | `["ok", 1]` | Removes the specified key or index from `coll`. |
| `collection.join` | `collection.join coll, sep` | `["ok", string]` | Concatenates elements of `coll` into a string separated by `sep`. |
| `collection.contains` | `collection.contains coll, item` | `["ok", int]` | Returns `1` if `coll` contains `item`, otherwise `0`. |
| `collection.indexOf` | `collection.indexOf list, item` | `["ok", int]` | Returns 0-based index of `item`, or `-1` if not found. |
| `collection.slice` | `collection.slice list, start, n` | `["ok", list]` | Returns a new sub-list starting at index `start` of length `n`. |
| `collection.keys` | `collection.keys map` | `["ok", list]` | Returns a list of all keys in `map`. |
| `collection.values` | `collection.values map` | `["ok", list]` | Returns a list of all values in `map`. |
| `collection.hasKey` | `collection.hasKey map, key` | `["ok", int]` | Checks if `key` exists in `map`. |
| `collection.invert` | `collection.invert map` | `map` | Swaps keys and values in `map`. |
| `collection.zip` | `collection.zip list1, list2` | `["ok", map]` | Zips two lists into a key-value map (`list1{i}: list2{i}`). |
| `collection.toMap` | `collection.toMap val` | `map` | Converts list or string into a key-indexed map. |
| `collection.toList` | `collection.toList val` | `["ok", list]` | Converts map or string into a list. |
| `collection.fill` | `collection.fill coll, val, count` | `["ok", coll]` | Fills indices `0` through `count - 1` with `val`. |
| `collection.min` | `collection.min coll` | `["ok", num]` | Finds the minimum element in numeric collection. |
| `collection.max` | `collection.max coll` | `["ok", num]` | Finds the maximum element in numeric collection. |
| `collection.reverse` | `collection.reverse list` | `["ok", list]` | Returns a reversed copy of `list`. |
| `collection.clone` | `collection.clone coll` | `["ok", coll]` | Performs a shallow clone of list or map. |
| `collection.clear` | `collection.clear coll` | `["ok", coll]` | Removes all elements from `coll`. |
| `collection.flatten` | `collection.flatten list` | `["ok", list]` | Flattens a 2D nested list into a 1D list. |
| `collection.shiftLeft` | `collection.shiftLeft list` | `void` | Shifts elements left by 1 (first item rotates to the end). |
| `collection.shiftRight`| `collection.shiftRight list` | `void` | Shifts elements right by 1 (last item rotates to index 0). |
| `collection.duplicates`| `collection.duplicates coll` | `map` | Returns map with duplicate analysis (`hasDuplicates`, `duplicates`, `indexOfDuplicates`). |

---

## 5. `std::math` — Mathematical Operations

Constants, arithmetic functions, trigonometry, and bitwise utilities.

```crystal
using std::math
```

### Constants
- `math.PI*`: Archimedes' constant (`3.1415926353`).
- `math.TAU*`: Circle constant \(\tau = 2\pi\) (`6.2831853`).
- `math.E*`: Euler's number (`2.7182818284`).

### Functions

| Function | Signature | Description |
|---|---|---|
| `math.abs` | `math.abs n` | Returns absolute value of `n`. |
| `math.min` | `math.min a, b` | Returns smaller of `a` and `b`. |
| `math.max` | `math.max a, b` | Returns larger of `a` and `b`. |
| `math.pow` | `math.pow base, exp` | Computes \(\text{base}^{\text{exp}}\) for integer exponents. |
| `math.mod` | `math.mod a, b` | Computes integer modulo `a % b`. |
| `math.floor` | `math.floor n` | Truncates float to nearest lower integer. |
| `math.ceil` | `math.ceil n` | Rounds float to nearest upper integer. |
| `math.round` | `math.round n` | Rounds float to nearest integer. |
| `math.sqrt` | `math.sqrt n` | Calculates square root using Newton-Raphson approximation. |
| `math.random` | `math.random max` | Returns pseudorandom integer between `0` and `max - 1`. |
| `math.sin` | `math.sin x` | Taylor series approximation of \(\sin(x)\). |
| `math.cos` | `math.cos x` | Taylor series approximation of \(\cos(x)\). |
| `math.clamp` | `math.clamp val, low, high` | Clamps `val` to range `[low, high]`. |
| `math.xor` | `math.xor a, b` | Bitwise XOR of two integers. |
| `math.sign` | `math.sign n` | Returns `-1` for negative, `1` for positive, and `0` for zero. |
| `math.isEven` | `math.isEven n` | Returns `1` if `n` is even, else `0`. |
| `math.isOdd` | `math.isOdd n` | Returns `1` if `n` is odd, else `0`. |
| `math.gcd` | `math.gcd a, b` | Greatest Common Divisor via Euclidean algorithm. |
| `math.lcm` | `math.lcm a, b` | Least Common Multiple. |
| `math.lerp` | `math.lerp a, b, t` | Linear interpolation: \(a + (b - a) \times t\). |
| `math.degToRad` | `math.degToRad deg` | Converts degrees to radians. |
| `math.radToDeg` | `math.radToDeg rad` | Converts radians to degrees. |
| `math.factorial` | `math.factorial n` | Computes factorial \(n!\). |

---

## 6. `std::file` — Filesystem I/O

Low-level and high-level file operations.

```crystal
using std::file
```

### Functions

| Function | Signature | Return Value | Description |
|---|---|---|---|
| `file.open` | `file.open path, flags` | `["ok", fd]` | Opens file at `path` with integer `flags`. Returns file descriptor. |
| `file.readEntireFile`| `file.readEntireFile path` | `["ok", text]` | Opens, reads entire file into memory as string, and closes. |
| `file.read` | `file.read fd, len` | `["ok", text]` | Reads up to `len` bytes from open descriptor `fd`. |
| `file.write` | `file.write fd, text` | `["ok", written]` | Writes string `text` to descriptor `fd`. |
| `file.writeBytes` | `file.writeBytes fd, data` | `["ok", written]` | Writes binary data to descriptor `fd`. |
| `file.close` | `file.close fd` | `["ok", 0]` | Closes open descriptor `fd`. |
| `file.exists` | `file.exists path` | `["ok", 1]` / `["ok", 0]` | Checks if path exists on the filesystem. |
| `file.delete` | `file.delete path` | `["ok", 0]` | Deletes (unlinks) file at `path`. |
| `file.newDirectory` | `file.newDirectory path` | `["ok", 0]` | Creates directory at `path` (`sys_mkdir`). |
| `file.sizeof` | `file.sizeof fd` | `["ok", bytes]` | Retrieves file size in bytes from descriptor. |

---

## 7. `std::process` — OS Processes

Process creation, signaling, execution control, and sleeping.

```crystal
using std::process
```

### Functions

| Function | Signature | Return Value | Description |
|---|---|---|---|
| `process.fork` | `process.fork 0` | `["ok", pid]` | Forks execution. In parent returns child PID; in child returns `0`. |
| `process.id` | `process.id 0` | `["ok", pid]` | Returns PID of calling process. |
| `process.wait` | `process.wait mode` | `["ok", status]` | Waits for child process to terminate. Pass `"nohang"` for non-blocking. |
| `process.sleep` | `process.sleep sec` | `void` | Pauses execution for `sec` seconds. |
| `process.nanosleep` | `process.nanosleep ms` | `void` | Pauses execution for milliseconds. |
| `process.exit` | `process.exit code` | `void` | Immediately terminates process with exit `code`. |

---

## 8. `std::os` — Operating System Environment

Environment inspection, timing, and command execution.

```crystal
using std::os
```

### Functions

| Function | Signature | Return Value | Description |
|---|---|---|---|
| `os.getenv` | `os.getenv var_name` | `string` | Reads value of environment variable `var_name`. |
| `os.time` | `os.time` | `int` | Returns current UNIX epoch timestamp in seconds. |
| `os.timeSince` | `os.timeSince start_time` | `int` | Computes elapsed seconds since `start_time`. |
| `os.host` | `os.host` | `string` | Returns host operating system name (e.g. `"linux"`). |
| `os.execute` | `os.execute cmd` | `["ok", 1]` | Polymorphic shell command execution. Accepts string, list, or map of arguments. |

---

## 9. `std::path` — Path Manipulation

Platform-aware file path manipulation.

```crystal
using std::path
```

### Functions

| Function | Signature | Return Value | Description |
|---|---|---|---|
| `path.join` | `path.join p1, p2` | `["ok", string]` | Joins two path segments safely, cleaning duplicate slashes. |
| `path.basename` | `path.basename p` | `["ok", string]` | Extracts filename component from path. |
| `path.dirname` | `path.dirname p` | `["ok", string]` | Extracts parent directory component from path. |
| `path.extension` | `path.extension p` | `["ok", string]` | Extracts file extension including dot (e.g. `".nt"`). |

---

## 10. `std::json` — JSON Serialization & Parsing

Parsing JSON strings and serializing Newton data structures.

```crystal
using std::json
```

### Functions

| Function | Signature | Return Value | Description |
|---|---|---|---|
| `json.parse` | `json.parse json_str` | `["ok", map]` | Parses JSON object string into a Newton map. |
| `json.stringify`| `json.stringify map_obj` | `["ok", string]` | Serializes flat key-value map into JSON string. |
| `json.jsonify` | `json.jsonify data` | `string` | Recursively converts strings, numbers, lists, and maps into valid JSON text. |

---

## 11. `std::terminal` — ANSI Terminal Styling

ANSI escape sequences and colored status output helpers.

```crystal
using std::terminal
```

### Constants
- Formatting: `terminal.RESET*`, `terminal.BOLD*`
- Foreground colors: `terminal.BLACK*`, `terminal.RED*`, `terminal.GREEN*`, `terminal.YELLOW*`, `terminal.BLUE*`, `terminal.MAGENTA*`, `terminal.CYAN*`, `terminal.WHITE*`
- Background colors: `terminal.BG_RED*`, `terminal.BG_GREEN*`, `terminal.BG_YELLOW*`, `terminal.BG_BLUE*`

### Functions

| Function | Signature | Description |
|---|---|---|
| `terminal.text` | `terminal.text color_code, msg` | Formats `msg` with `color_code` and appends `RESET`. |
| `terminal.error` | `terminal.error msg` | Formats `[ERROR] msg` in bright red. |
| `terminal.success` | `terminal.success msg` | Formats `[SUCCESS] msg` in bright green. |
| `terminal.warning` | `terminal.warning msg` | Formats `[WARNING] msg` in bright yellow. |
| `terminal.debug` | `terminal.debug msg` | Formats `[DEBUG] msg` in bright cyan. |

---

## 12. `std::crypt` — Cryptographic Utilities

```crystal
using std::crypt
```

### Functions

| Function | Signature | Return Value | Description |
|---|---|---|---|
| `crypt.hash` | `crypt.hash str` | `["ok", int]` | Computes djb2 polynomial hash of string. |

---

## 13. `std::test` — Unit Testing

```crystal
using std::test
```

### Functions

| Function | Signature | Return Value | Description |
|---|---|---|---|
| `test.testCase` | `test.testCase name, actual, expected` | `["ok", int]` | Asserts equality between `actual` and `expected`. Prints colored `[PASS]` or `[FAIL]` diagnostic. |

---

## 14. `std::web` — Web & Networking

Full-featured TCP and HTTP networking suite. See [Chapter 8: Web & Networking](08_Web_and_Networking.md) for complete tutorials and architecture details.

```crystal
using std::web
```

### High-Level TCP
| Function | Signature | Description |
|---|---|---|
| `web.tcpServer` | `web.tcpServer port` | Creates, binds, and listens on `0.0.0.0:<port>`. |
| `web.tcpConnect`| `web.tcpConnect ip, port` | Connects TCP socket to IPv4 address and port. |
| `web.tcpAccept` | `web.tcpAccept server_fd` | Accepts incoming client connection. |
| `web.tcpSend` | `web.tcpSend client_fd, data` | Sends data string over socket. |
| `web.tcpRecv` | `web.tcpRecv client_fd, max_len` | Receives up to `max_len` bytes. |
| `web.tcpClose` | `web.tcpClose fd` | Closes socket descriptor. |

### High-Level HTTP Server
| Function | Signature | Description |
|---|---|---|
| `web.httpServer` | `web.httpServer port` | Alias for `tcpServer(port)`. |
| `web.serveRequest`| `web.serveRequest client_fd` | Reads request and parses into structured map (`method`, `path`, `headers`, `body`, `query`). |
| `web.respond` | `web.respond fd, code, body, type` | Formats full HTTP response, sends over socket, and closes connection. |
| `web.respondHtml` | `web.respondHtml fd, html` | Responds with 200 OK and `text/html; charset=utf-8`. |
| `web.respondJson` | `web.respondJson fd, json` | Responds with 200 OK and `application/json`. |
| `web.respondNotFound`| `web.respondNotFound fd` | Responds with 404 Not Found. |

### High-Level HTTP Client
| Function | Signature | Description |
|---|---|---|
| `web.httpGet` | `web.httpGet host, port, path` | Performs HTTP/1.1 GET request. Returns structured response map (`status`, `headers`, `body`). |
| `web.httpPost` | `web.httpPost host, port, path, body, type` | Performs HTTP/1.1 POST request with payload and content-type header. |
| `web.parseResponse`| `web.parseResponse raw_http` | Parses raw HTTP response string into structured map. |

### Low-Level Socket Syscalls
| Function | Signature | Description |
|---|---|---|
| `web.new` | `web.new` | Invokes `sys_socket` (AF_INET, SOCK_STREAM). |
| `web.bind` | `web.bind sock, port` | Invokes `sys_bind`. |
| `web.listen` | `web.listen sock` | Invokes `sys_listen`. |
| `web.accept` | `web.accept sock` | Invokes `sys_accept`. |
| `web.send` | `web.send sock, msg` | Invokes `sys_send`. |
| `web.receive` | `web.receive sock, max_len` | Invokes `sys_recv`. |
| `web.connect` | `web.connect sock, port, ip_int` | Invokes `sys_connect`. |
| `web.sendFile` | `web.sendFile sock, path, size` | Invokes `sys_sendfile`. |
| `web.close` | `web.close sock` | Invokes `sys_close_socket`. |

