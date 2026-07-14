import strutils, tables, os, osproc

type
  NpfManifest = object
    name: string
    version: string
    entrypoint: string
    packages: Table[string, string]

# --- 1. PARSE THE .NPF FILE ---
proc parseNpf(): NpfManifest =
  var manifest = NpfManifest(packages: initTable[string, string]())
  if not fileExists(".Newtonproj.toml"):
    echo "\e[91m[NNPM Error]\e[0m No '.Newtonproj.toml' file found in current directory!"
    quit(1)

  var currentSection = ""
  for rawLine in lines(".Newtonproj.toml"):
    let line = rawLine.strip()
    if line == "" or line.startsWith("#"): continue
    if line.startsWith("[") and line.endsWith("]"):
      currentSection = line[1 .. ^2]
      continue

    let parts = line.split("=", 1)
    if parts.len == 2:
      let key = parts[0].strip()
      let val = parts[1].strip().replace("\"", "")
      if currentSection == "Project":
        case key
        of "name": manifest.name = val
        of "version": manifest.version = val
        of "entrypoint": manifest.entrypoint = val
        else: discard
      elif currentSection == "Packages":
        manifest.packages[key] = val

  return manifest

# --- 2. ADD A NEW PACKAGE ---
proc addPackage(name: string, url: string, isLocal: bool) =
  if not fileExists(".Newtonproj.toml"):
    echo "\e[91m[NNPM Error]\e[0m No '.Newtonproj.toml' found."
    quit(1)

  var fileLines = readFile(".Newtonproj.toml").splitLines()
  var inPkgsSection = false
  var pkgsSectionIndex = -1
  var pkgExists = false

  for i, line in fileLines:
    let stripped = line.strip()
    if stripped == "[Packages]":
      inPkgsSection = true
      pkgsSectionIndex = i
      continue
    elif stripped.startsWith("[") and stripped.endsWith("]"):
      inPkgsSection = false

    if inPkgsSection and (stripped.startsWith(name & " ") or stripped.startsWith(name & "=")):
      pkgExists = true; break

  if pkgExists:
    echo "\e[93m[NNPM Warning]\e[0m Package '" & name & "' is already in .Newtonproj.toml!"
    return

  var finalUrl = url
  if isLocal and not finalUrl.startsWith("local:"):
    finalUrl = "local:" & finalUrl

  let newPkgLine = name & " = \"" & finalUrl & "\""

  if pkgsSectionIndex != -1: fileLines.insert(newPkgLine, pkgsSectionIndex + 1)
  else: fileLines.add(["", "[Packages]", newPkgLine])

  writeFile(".Newtonproj.toml", fileLines.join("\n"))
  echo "\e[92m[NNPM Success]\e[0m Added '" & name & "' to .Newtonproj.toml!"

# --- 3. THE AMALGAMATOR ---
proc amalgamatePackage(pkgDir: string, outFile: string) =
  echo "    \e[96m-> Amalgamating files into " & outFile & ".nt...\e[0m"
  var combinedCode = "| Auto-generated Amalgamation by NNPM\n"

  # Scan the package directory for all .nt files
  for kind, path in walkDir(pkgDir):
    if kind == pcFile and path.endsWith(".nt"):
      combinedCode &= "\n| --- Source: " & extractFilename(path) & " ---\n"
      combinedCode &= readFile(path) & "\n"

  # Create a hidden 'Packages' folder in the user's project to store the final files
  let projectCacheDir = getCurrentDir() / "packages"
  if not dirExists(projectCacheDir): createDir(projectCacheDir)

  writeFile(projectCacheDir / outFile & ".nt", combinedCode)

# --- 4. THE FETCHER ---
proc fetchPackages(manifest: NpfManifest) =
  let globalCacheDir = getEnv("HOME") / ".nnpm" / "packages"
  if not dirExists(globalCacheDir): createDir(globalCacheDir)

  for name, rawUrl in manifest.packages.pairs():

    if rawUrl.startsWith("local:"):
      let localPath = rawUrl[6..^1].replace("~", getEnv("HOME")) # Strip 'local:' and expand '~'
      echo "  \e[94m[Local Link]\e[0m " & name & " -> " & localPath

      if not dirExists(localPath):
        echo "\e[91m[NNPM Error]\e[0m Local path does not exist: " & localPath
        continue

      # Look for package.nnpm directly in the live folder
      let pkgManifestPath = localPath / "package.nnpm"
      var outName = name
      if fileExists(pkgManifestPath):
        for line in lines(pkgManifestPath):
          if "Out ->" in line:
            let parts = line.split("Out ->")
            if parts.len == 2: outName = parts[1].strip().replace("\"", ""); break

      # Amalgamate straight from their live code!
      amalgamatePackage(localPath, outName)
      continue

    let url = rawUrl
    let pkgDir = globalCacheDir / name

    if dirExists(pkgDir):
      echo "  \e[92m[Cached]\e[0m " & name
    else:
      echo "  \e[93m[Fetching]\e[0m " & name & " from " & url & "..."
      # Use HTTPS for git clone to ensure it works without SSH keys setup
      var cloneUrl = url
      if not cloneUrl.startsWith("http"): cloneUrl = "https://" & cloneUrl

      let (output, exitCode) = execCmdEx("git clone " & cloneUrl & " " & pkgDir)
      if exitCode != 0:
        echo "\e[91m[NNPM Error]\e[0m Failed to fetch " & name & "!\n" & output
        continue

    # Now look for the package.nnpm file to find the output name!
    let pkgManifestPath = pkgDir / "package.nnpm"
    if fileExists(pkgManifestPath):
      var outName = name # Default to the package name
      for line in lines(pkgManifestPath):
        if "Out ->" in line:
          let parts = line.split("Out ->")
          if parts.len == 2:
            outName = parts[1].strip().replace("\"", "")
            break

      amalgamatePackage(pkgDir, outName)
    else:
      echo "    \e[93m[Warning]\e[0m No package.nnpm found in " & name & ". Treating as raw repository."
      amalgamatePackage(pkgDir, name)

# --- 5. CLI ENGINE ---
proc main() =
  let args = commandLineParams()
  if args.len == 0:
    echo "🪐 \e[96mNNPM - Newtonian Package Manager\e[0m"
    echo "Usage:"
    echo "  nnpm add <name> <url> [--local]   (Adds to .Newtonproj.toml)"
    echo "  nnpm install                      (Downloads & Amalgamates packages)"
    quit(0)

  let command = args[0]
  if command == "add" and args.len >= 3:
    var isLocal = false
    if args.len == 4 and args[3] == "--local": isLocal = true

    addPackage(args[1], args[2], isLocal)

  elif command == "install":
    let manifest = parseNpf()
    if manifest.packages.len == 0:
      echo "No packages found in .Newtonproj.toml. You're good to go!"
    else:
      echo "Installing " & $manifest.packages.len & " packages for \e[92m" & manifest.name & "\e[0m..."
      fetchPackages(manifest)
      echo "\e[92m[Complete]\e[0m All packages installed in packages/!"
  else:
    echo "Invalid command."

when isMainModule:
  main()
