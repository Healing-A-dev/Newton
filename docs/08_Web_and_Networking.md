# 8. Web & Networking (`std::web`)

Newton's standard library provides a complete, modern TCP and HTTP networking module in `std::web`. It offers both high-level APIs for instant client/server creation and low-level syscall wrappers for bare-metal socket manipulation.

To import the module:

```crystal
using std::web
```

---

## 1. High-Level HTTP Server

Creating an HTTP server in Newton takes just a few lines of code.

```crystal
using std::web

fun main:
    ; Create and bind HTTP server on port 8080
    set server: web.httpServer 8080
    @println "Listening on http://127.0.0.1:8080..."

    while 1 == 1:
        set client: web.accept $server
        set req: web.serveRequest $client

        if $req{"method"} != "":
            @println "[HTTP] {} {}", $req{"method"}, $req{"path"}

            if $req{"path"} == "/":
                web.respondHtml $client, "<h1>Welcome to Newton Web!</h1>"
            elif $req{"path"} == "/api/status":
                web.respondJson $client, "{\"status\": \"ok\", \"runtime\": \"GravityVM\"}"
            else:
                web.respondNotFound $client
            end
        else:
            web.close $client
        end
    end
end
```

### Server Helper Functions

| Function | Signature | Description |
|---|---|---|
| `web.httpServer` | `web.httpServer port` | Creates, binds, and listens on `0.0.0.0:<port>`. Returns server socket fd. |
| `web.serveRequest` | `web.serveRequest client_fd` | Reads up to 4096 bytes and parses request into a structured map. |
| `web.respond` | `web.respond client_fd, code, body, type` | Formats an HTTP response, sends it, and closes the client connection. |
| `web.respondHtml` | `web.respondHtml client_fd, body` | Responds with 200 OK and `text/html; charset=utf-8`. |
| `web.respondJson` | `web.respondJson client_fd, json_str` | Responds with 200 OK and `application/json`. |
| `web.respondNotFound`| `web.respondNotFound client_fd` | Responds with 404 Not Found. |

---

## 2. High-Level HTTP Client

Newton provides built-in HTTP client methods to query web services with automatic TCP connection management and response parsing.

### HTTP GET Request

```crystal
using std::web

fun main:
    set resp: web.httpGet "http://127.0.0.1:8080/api/status"

    @println "Status: {} {}", $resp{"status"}, $resp{"status_text"}
    @println "Content-Type: {}", $resp{"headers"}{"content-type"}
    @println "Body:\n{}", $resp{"body"}
end
```

### HTTP POST Request

```crystal
using std::web

fun main:
    set payload: "{\"action\": \"ping\", \"timestamp\": 12345}"
    set resp: web.httpPost "http://127.0.0.1:8080/api/echo", $payload, "application/json"

    @println "Server response: {}", $resp{"body"}
end
```

---

## 3. HTTP Protocol Engine

`std::web` includes built-in parsing and response construction helpers.

### Parsing Requests (`web.parseRequest`)

Parses raw HTTP/1.1 request text into a native Newton map:

```crystal
set raw_req: "GET /search?q=newton&limit=5 HTTP/1.1\r\nHost: localhost\r\n\r\n"
set req: web.parseRequest $raw_req

; Accessible fields:
; $req{"method"}   -> "GET"
; $req{"path"}     -> "/search"
; $req{"query"}    -> "q=newton&limit=5"
; $req{"version"}  -> "HTTP/1.1"
; $req{"headers"}  -> (host: "localhost")
; $req{"body"}     -> ""
```

### Query Parameter Parsing (`web.parseQueryParams`)

```crystal
set params: web.parseQueryParams "q=newton&limit=5"
@println "Query: {}", $params{"q"}      ; "newton"
@println "Limit: {}", $params{"limit"}  ; "5"
```

### URL Parsing (`web.parseUrl`)

```crystal
set parsed: web.parseUrl "http://127.0.0.1:8080/api/users"
; $parsed{"host"} -> "127.0.0.1"
; $parsed{"port"} -> 8080
; $parsed{"path"} -> "/api/users"
```

### Response Generators

Construct RFC-compliant HTTP response strings with automated `Content-Length`, `Content-Type`, and `Connection: close`:

```crystal
; Generic response
set resp: web.response 200, "Hello World", "text/plain"

; Shortcut responses
set h1: web.html "<h1>Hello</h1>"               ; 200 text/html
set j1: web.json "{\"ok\": true}"              ; 200 application/json
set t1: web.text "Plain text"                  ; 200 text/plain
set e1: web.notFound "<h1>Not Found</h1>"      ; 404 text/html
set r1: web.redirect "http://example.com"      ; 302 Found
```

---

## 4. TCP Networking API

For raw TCP services (chat servers, binary protocols, custom proxies):

### TCP Server

```crystal
using std::web

fun main:
    set server: web.tcpServer 9000
    @println "TCP server listening on port 9000..."

    while 1 == 1:
        set client: web.tcpAccept $server
        web.tcpSend $client, "Welcome to Newton TCP Server!\n"

        set msg: web.tcpRecv $client, 1024
        @println "Received from client: {}", $msg

        web.tcpClose $client
    end
end
```

### TCP Client

```crystal
using std::web

fun main:
    ; Connects using host string (e.g. "127.0.0.1", "localhost") and port
    set client: web.tcpConnect "127.0.0.1", 9000

    web.tcpSend $client, "Hello TCP Server!\n"
    set reply: web.tcpRecv $client, 1024
    @println "Reply: {}", $reply

    web.tcpClose $client
end
```

### IP Conversions

| Function | Signature | Description |
|---|---|---|
| `web.ipToInt` | `web.ipToInt ip_str` | Converts `"127.0.0.1"`, `"localhost"`, etc., to a 32-bit network-byte-order integer. |
| `web.intToIp` | `web.intToIp ip_int` | Converts a 32-bit integer back to dotted-quad `"127.0.0.1"`. |

---

## 5. Low-Level Socket Syscalls (Backwards Compatible)

`std::web` preserves Newton's original low-level socket syscall wrappers:

| Function | Signature | Underlying Syscall |
|---|---|---|
| `web.new` | `web.new` | `socket(AF_INET, SOCK_STREAM, 0)` |
| `web.bind` | `web.bind sock, port` | `bind(sock, ...)` |
| `web.listen` | `web.listen sock` | `listen(sock, 10)` |
| `web.accept` | `web.accept sock` | `accept(sock, NULL, NULL)` |
| `web.send` | `web.send client, msg` | `send(client, msg, ...)` |
| `web.receive` | `web.receive client, size` | `recv(client, buf, size, ...)` |
| `web.close` | `web.close client` | `close(client)` |
| `web.connect` | `web.connect sock, port, ip_int` | `connect(sock, ...)` |
| `web.sendFile` | `web.sendFile client, file, size` | `sendfile(client, file, ...)` |

---

## Complete Working Showcase

See [`src/Newton/examples/web_showcase.nt`](../src/Newton/examples/web_showcase.nt) for a complete example running a background HTTP server and performing automated client requests.

---

Next: [9. Standard Library Reference](09_Standard_Library.md)

