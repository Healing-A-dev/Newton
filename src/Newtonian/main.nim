import strutils, tables, os, osproc

type
  NpfManifest = object
    name: string
    version: string
    entrypoint: string
    packages: Table[string, string]

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


proc installPackage(pkgDir: string, outName: string) =
  echo "    \e[96m-> Installing source tree for " & outName & "...\e[0m"

  let projectCacheDir = getCurrentDir() / "packages"
  if not dirExists(projectCacheDir): createDir(projectCacheDir)
  let targetDir = projectCacheDir / outName

  if dirExists(targetDir): removeDir(targetDir)

  copyDir(pkgDir, targetDir)

  if dirExists(targetDir / ".git"): removeDir(targetDir / ".git")

  echo "    \e[92m-> " & outName & " installed successfully!\e[0m"


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

      let pkgManifestPath = localPath / "package.nnpm"
      var outName = name
      var entryFile = name & ".nt"

      if fileExists(pkgManifestPath):
        for line in lines(pkgManifestPath):
          if "Out ->" in line:
            let parts = line.split("Out ->")
            if parts.len == 2: outName = parts[1].strip().replace("\"", "")
          elif "Entry ->" in line: # <--- [NEW] Parse the Entry point
            let parts = line.split("Entry ->")
            if parts.len == 2: entryFile = parts[1].strip().replace("\"", "")

      installPackage(localPath, outName)
      continue

    let url = rawUrl
    let pkgDir = globalCacheDir / name

    if dirExists(pkgDir):
      echo "  \e[92m[Cached]\e[0m " & name
    else:
      echo "  \e[93m[Fetching]\e[0m " & name & " from " & url & "..."
      var cloneUrl = url
      if not cloneUrl.startsWith("http"): cloneUrl = "https://" & cloneUrl

      let (output, exitCode) = execCmdEx("git clone " & cloneUrl & " " & pkgDir)
      if exitCode != 0:
        echo "\e[91m[NNPM Error]\e[0m Failed to fetch " & name & "!\n" & output
        continue

    let pkgManifestPath = pkgDir / "package.nnpm"
    if fileExists(pkgManifestPath):
      var outName = name # Default to the package name
      var entryFile = name & ".nt"
      for line in lines(pkgManifestPath):
        if "Out ->" in line:
          let parts = line.split("Out ->")
          if parts.len == 2: outName = parts[1].strip().replace("\"", "")
        elif "Entry ->" in line:
          let parts = line.split("Entry ->")
          if parts.len == 2: entryFile = parts[1].strip().replace("\"", "")

      installPackage(pkgDir, outName)
    else:
      echo "    \e[93m[Warning]\e[0m No package.nnpm found in " & name & ". Treating as raw repository."
      installPackage(pkgDir, name)


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
