OUTFILE = "orb"

compile:
	@clear
	nim c --hints:off -o:$(OUTFILE) src/main.nim
