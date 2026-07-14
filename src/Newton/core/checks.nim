import tables, errors

# The Global Function Registry
var functionRegistry* = initTable[string, tuple[minArgs: int, maxArgs: int]]()

# Pre-load the Newton Standard Library (C-FFI wrappers)
proc initChecks*() =
  # --- STD::BASE ----
  functionRegistry["push"]                = (minArgs: 2, maxArgs: 2)
  functionRegistry["die"]                 = (minArgs: 1, maxArgs: 2)
  functionRegistry["map"]                 = (minArgs: 1, maxArgs: 1)
  functionRegistry["pop"]                 = (minArgs: 1, maxArgs: 1)
  functionRegistry["list"]                = (minArgs: 1, maxArgs: 1)
  functionRegistry["true"]                = (minArgs: 0, maxArgs: 0)
  functionRegistry["false"]               = (minArgs: 0, maxArgs: 0)
  # --- STD::COLLECTION ---
  functionRegistry["Collection.pop"]      = (minArgs: 2, maxArgs: 2)
  functionRegistry["Collection.push"]     = (minArgs: 2, maxArgs: 2)
  functionRegistry["Collection.join"]     = (minArgs: 1, maxArgs: 2)
  functionRegistry["Collection.remove"]   = (minArgs: 2, maxArgs: 2)
  functionRegistry["Collection.hasKey"]   = (minArgs: 2, maxArgs: 2)
  functionRegistry["Collection.toMap"]    = (minArgs: 1, maxArgs: 1)
  functionRegistry["Collection.toList"]   = (minArgs: 1, maxArgs: 1)
  # --- STD::IO ---
  functionRegistry["IO.err"]              = (minArgs: 1, maxArgs: 2)
  functionRegistry["IO.print"]            = (minArgs: 1, maxArgs: 1)
  functionRegistry["IO.prompt"]           = (minArgs: 1, maxArgs: 1)
  functionRegistry["IO.println"]          = (minArgs: 1, maxArgs: 1)
  functionRegistry["IO.readln"]           = (minArgs: 0, maxArgs: 0)
  # --- STD::FILE ---
  functionRegistry["File.open"]           = (minArgs: 2, maxArgs: 2)
  functionRegistry["File.write"]          = (minArgs: 2, maxArgs: 2)
  functionRegistry["File.read"]           = (minArgs: 2, maxArgs: 2)
  functionRegistry["File.readEntireFile"] = (minArgs: 1, maxArgs: 1)
  functionRegistry["File.close"]          = (minArgs: 1, maxArgs: 1)
  functionRegistry["File.exists"]         = (minArgs: 1, maxArgs: 1)
  functionRegistry["File.delete"]         = (minArgs: 1, maxArgs: 1)
  functionRegistry["File.newDirectory"]   = (minArgs: 1, maxArgs: 1)
  functionRegistry["File.sizeof"]         = (minArgs: 1, maxArgs: 1)
  # --- STD::JSON ---
  functionRegistry["Json.parse"]          = (minArgs: 1, maxArgs: 1)
  functionRegistry["Json.jsonify"]        = (minArgs: 1, maxArgs: 1)
  functionRegistry["Json.stringify"]      = (minArgs: 1, maxArgs: 1)
  # --- STD::MATH ---
  functionRegistry["Math.pow"]            = (minArgs: 2, maxArgs: 2)
  functionRegistry["Math.abs"]            = (minArgs: 1, maxArgs: 1)
  functionRegistry["Math.min"]            = (minArgs: 1, maxArgs: 1)
  functionRegistry["Math.max"]            = (minArgs: 1, maxArgs: 1)
  functionRegistry["Math.sin"]            = (minArgs: 1, maxArgs: 1)
  functionRegistry["Math.cos"]            = (minArgs: 1, maxArgs: 1)
  functionRegistry["Math.sqrt"]           = (minArgs: 1, maxArgs: 1)
  functionRegistry["Math.round"]          = (minArgs: 1, maxArgs: 1)
  functionRegistry["Math.random"]         = (minArgs: 1, maxArgs: 1)
  # --- STD::PROCESS ---
  functionRegistry["Process.wait"]        = (minArgs: 0, maxArgs: 1)
  functionRegistry["Process.exit"]        = (minArgs: 0, maxArgs: 1)
  functionRegistry["Process.sleep"]       = (minArgs: 1, maxArgs: 1)
  functionRegistry["Process.nanosleep"]   = (minArgs: 1, maxArgs: 1)
  functionRegistry["Process.id"]          = (minArgs: 0, maxArgs: 0)
  functionRegistry["Process.fork"]        = (minArgs: 0, maxArgs: 0)
  # --- STD::STRING ---
  functionRegistry["String.sub"]          = (minArgs: 3, maxArgs: 3)
  functionRegistry["String.replace"]      = (minArgs: 3, maxArgs: 3)
  functionRegistry["String.has"]          = (minArgs: 2, maxArgs: 2)
  functionRegistry["String.endsWith"]     = (minArgs: 2, maxArgs: 2)
  functionRegistry["String.startsWith"]   = (minArgs: 2, maxArgs: 2)
  functionRegistry["String.find"]         = (minArgs: 2, maxArgs: 2)
  functionRegistry["String.split"]        = (minArgs: 1, maxArgs: 2)
  functionRegistry["String.reverse"]      = (minArgs: 1, maxArgs: 1)
  functionRegistry["String.ascii"]        = (minArgs: 1, maxArgs: 1)
  functionRegistry["String.char"]         = (minArgs: 1, maxArgs: 1)
  # --- STD::SYSTEM ---
  functionRegistry["System.argv"]         = (minArgs: 1, maxArgs: 1)
  functionRegistry["System.exec"]         = (minArgs: 1, maxArgs: 1)
  functionRegistry["System.exit"]         = (minArgs: 1, maxArgs: 1)
  functionRegistry["System.argc"]         = (minArgs: 0, maxArgs: 0)
  # --- STD::TERMINAL ---
  functionRegistry["Terminal.text"]       = (minArgs: 2, maxArgs: 2)
  functionRegistry["Terminal.debug"]      = (minArgs: 1, maxArgs: 1)
  functionRegistry["Terminal.error"]      = (minArgs: 1, maxArgs: 1)
  functionRegistry["Terminal.success"]    = (minArgs: 1, maxArgs: 1)
  functionRegistry["Terminal.warning"]    = (minArgs: 1, maxArgs: 1)
  # --- STD::WEB ---
  functionRegistry["Web.connect"]         = (minArgs: 3, maxArgs: 3)
  functionRegistry["Web.sendFile"]        = (minArgs: 3, maxArgs: 3)
  functionRegistry["Web.bind"]            = (minArgs: 2, maxArgs: 2)
  functionRegistry["Web.send"]            = (minArgs: 2, maxArgs: 2)
  functionRegistry["Web.recieve"]         = (minArgs: 2, maxArgs: 2)
  functionRegistry["Web.close"]           = (minArgs: 1, maxArgs: 1)
  functionRegistry["Web.listen"]          = (minArgs: 1, maxArgs: 1)
  functionRegistry["Web.accept"]          = (minArgs: 1, maxArgs: 1)
  functionRegistry["Web.new"]             = (minArgs: 0, maxArgs: 0)
  # --- STD::OS ---
  functionRegistry["OS.GetENV"]           = (minArgs: 1, maxArgs: 1)
  functionRegistry["OS.Host"]             = (minArgs: 0, maxArgs: 0)
  functionRegistry["OS.Time"]             = (minArgs: 0, maxArgs: 0)
  functionRegistry["OS.TimeSince"]        = (minArgs: 1, maxArgs: 1)
  # --- INTRINSICS ---
  functionRegistry["substring"]           = (minArgs: 3, maxArgs: 3)
  functionRegistry["net_connect"]         = (minArgs: 3, maxArgs: 3)
  functionRegistry["__net_sendfile"]      = (minArgs: 3, maxArgs: 3)
  functionRegistry["sys_open"]            = (minArgs: 2, maxArgs: 2)
  functionRegistry["sys_read"]            = (minArgs: 2, maxArgs: 2)
  functionRegistry["sys_write"]           = (minArgs: 2, maxArgs: 2)
  functionRegistry["net_bind"]            = (minArgs: 2, maxArgs: 2)
  functionRegistry["net_send"]            = (minArgs: 2, maxArgs: 2)
  functionRegistry["net_recv"]            = (minArgs: 2, maxArgs: 2)
  functionRegistry["__math_xor"]          = (minArgs: 2, maxArgs: 2)
  functionRegistry["__sys_collection_delete"] = (minArgs: 2, maxArgs: 2)
  functionRegistry["int"]                 = (minArgs: 1, maxArgs: 1)
  functionRegistry["float"]               = (minArgs: 1, maxArgs: 1)
  functionRegistry["sizeof"]              = (minArgs: 1, maxArgs: 1)
  functionRegistry["string"]              = (minArgs: 1, maxArgs: 1)
  functionRegistry["sys_err"]             = (minArgs: 1, maxArgs: 1)
  functionRegistry["sys_argv"]            = (minArgs: 1, maxArgs: 1)
  functionRegistry["sys_exec"]            = (minArgs: 1, maxArgs: 1)
  functionRegistry["sys_close"]           = (minArgs: 1, maxArgs: 1)
  functionRegistry["sys_mkdir"]           = (minArgs: 1, maxArgs: 1)
  functionRegistry["read_file"]           = (minArgs: 1, maxArgs: 1)
  functionRegistry["net_close"]           = (minArgs: 1, maxArgs: 1)
  functionRegistry["proc_wait"]           = (minArgs: 1, maxArgs: 1)
  functionRegistry["proc_exit"]           = (minArgs: 1, maxArgs: 1)
  functionRegistry["proc_sleep"]          = (minArgs: 1, maxArgs: 1)
  functionRegistry["sys_access"]          = (minArgs: 1, maxArgs: 1)
  functionRegistry["net_listen"]          = (minArgs: 1, maxArgs: 1)
  functionRegistry["net_accept"]          = (minArgs: 1, maxArgs: 1)
  functionRegistry["__file_size"]         = (minArgs: 1, maxArgs: 1)
  functionRegistry["__sys_getenv"]        = (minArgs: 1, maxArgs: 1)
  functionRegistry["__string_ord"]        = (minArgs: 1, maxArgs: 1)
  functionRegistry["__string_char"]       = (minArgs: 1, maxArgs: 1)
  functionRegistry["__proc_sleep_ms"]     = (minArgs: 1, maxArgs: 1)
  functionRegistry["proc_wait_nohang"]    = (minArgs: 1, maxArgs: 1)
  functionRegistry["__alloc_array"]       = (minArgs: 1, maxArgs: 1)
  functionRegistry["input"]               = (minArgs: 0, maxArgs: 0)
  functionRegistry["sys_argc"]            = (minArgs: 0, maxArgs: 0)
  functionRegistry["proc_pid"]            = (minArgs: 0, maxArgs: 0)
  functionRegistry["proc_fork"]           = (minArgs: 0, maxArgs: 0)
  functionRegistry["net_create"]          = (minArgs: 0, maxArgs: 0)
  functionRegistry["__sys_time_now"]      = (minArgs: 0, maxArgs: 0)
  functionRegistry["prints"]              = (minArgs: -1, maxArgs: -1)

# Register a user-defined function during AST traversal
proc registerFunction*(name: string, argCount: int) =
  functionRegistry[name] = (minArgs: argCount, maxArgs: argCount)

# Validate that a function call has the correct number of arguments
proc validateCall*(name: string, argCount: int, line: int) =
  if functionRegistry.hasKey(name):
    let bounds = functionRegistry[name]

    if argCount < bounds.minArgs or (bounds.maxArgs != -1 and argCount > bounds.maxArgs):
      var expectedStr = ""
      if bounds.minArgs == bounds.maxArgs:
          expectedStr = $bounds.minArgs
      elif bounds.maxArgs == -1:
          expectedStr = $bounds.minArgs & " or more"
      else:
          expectedStr = $bounds.minArgs & " to " & $bounds.maxArgs

      ERR("Function '" & name & "' expected " & expectedStr & " arguments, but got " & $argCount & ".", line, "E010", "Check the function definition and ensure you are passing the correct amount of parameters.")
