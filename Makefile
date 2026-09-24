# Source Files
RUNTIME_SRCS_LINUX = src/Newton/lib/runtime/linux64/mm.s        \
               		 src/Newton/lib/runtime/linux64/io.s        \
               		 src/Newton/lib/runtime/linux64/types.s     \
               		 src/Newton/lib/runtime/linux64/math.s      \
               		 src/Newton/lib/runtime/linux64/sys.s       \
               		 src/Newton/lib/runtime/linux64/net.s       \
               		 src/Newton/lib/runtime/linux64/proc.s      \
               		 src/Newton/lib/runtime/linux64/unwrap.s    \
               		 src/Newton/lib/runtime/linux64/file.s

RUNTIME_SRCS_WINDOWS = src/Newton/lib/runtime/win64/io.s        \
					   src/Newton/lib/runtime/win64/mm.s        \
					   src/Newton/lib/runtime/win64/sys.s       \
					   src/Newton/lib/runtime/win64/types.s     \
					   src/Newton/lib/runtime/win64/math.s      \
					   src/Newton/lib/runtime/win64/unwrap.s    \
					   src/Newton/lib/runtime/win64/file.s      \
					   src/Newton/lib/runtime/win64/net.s       \
					   src/Newton/lib/runtime/win64/proc.s      \
					   src/Newton/lib/runtime/win64/wrappers.s

CORE_SRCS = src/Newton/core/ast.nim     \
			src/Newton/core/codegen.nim \
			src/Newton/core/errors.nim  \
			src/Newton/core/lexer.nim   \
			src/Newton/core/main.nim    \
			src/Newton/core/parser.nim

STD_SRC = src/Newton/lib/Std/File.nt       \
		  src/Newton/lib/Std/Collection.nt \
		  src/Newton/lib/Std/IO.nt         \
		  src/Newton/lib/Std/Json.nt       \
		  src/Newton/lib/Std/Math.nt       \
		  src/Newton/lib/Std/Process.nt    \
		  src/Newton/lib/Std/String.nt     \
		  src/Newton/lib/Std/System.nt     \
		  src/Newton/lib/Std/Terminal.nt   \
		  src/Newton/lib/Std/Web.nt        \
		  src/Newton/lib/Std/Result.nt     \
		  src/Newton/lib/Std/Test.nt       \
		  src/Newton/lib/Std/Path.nt       \
		  src/Newton/lib/Std/OS.nt         \
		  src/Newton/lib/Std/Crypt.nt


RUNTIME_OBJS_LINUX = $(RUNTIME_SRCS_LINUX:.s=.o)
RUNTIME_OBJS_WINDOWS = $(RUNTIME_SRCS_WINDOWS:.s=.w64.o)
CORE_OBJS = $(CORE_SRCS:.nim)

HOME_DIR = $(HOME)/.local/lib
BIN_DIR = $(HOME)/.local/bin
INSTALL_DIR = newton
COMPILER = nim
BACKEND =
HAS_GVM := $(shell command -v gvm 2> /dev/null)

# Windows Assembler & Compiler (mingw32)
ifeq ($(OS), Windows_NT)
	WAS = as
	WCC = gcc
	WAR = ar
	CLI_EXT = .exe
else
	WAS = x86_64-w64-mingw32-as
	WCC = x86_64-w64-mingw32-gcc
	WAR = x86_64-w64-mingw32-ar
	CLI_EXT =
endif

ifeq ($(filter install-GVM,$(MAKECMDGOALS)),)
ifeq ($(strip $(HAS_GVM)),)
$(error GravityVM (gvm) is not installed. Please run 'make install-GVM' to install.)
endif
endif


all: src/Newton/newton$(CLI_EXT) src/Newton/lib/libnewton.a src/Newtonian/nnpm

src/Newton/newton: $(CORE_OBJS) src/Newton/lib/libnewton.o src/Newton/lib/libnewton.a
	$(COMPILER) $(BACKEND) c -o:src/Newton/newton -d:release src/Newton/core/main.nim


src/Newtonian/nnpm:
	$(COMPILER) $(BACKEND) c -o:src/Newtonian/nnpm -d:release src/Newtonian/main.nim

src/Newton/lib/libnewton.o: $(RUNTIME_OBJS_LINUX)
	ld -r -o src/Newton/lib/libnewton.o $(RUNTIME_OBJS_LINUX)

src/Newton/lib/libnewton.a: $(RUNTIME_OBJS_WINDOWS)
	$(WAR) rcs $@ $(RUNTIME_OBJS_WINDOWS)

# Linux Assembly Rule
%.o: %.s
	as -o $@ $<

# Windows Assembly Rule
%.w64.o: %.s
	$(WAS) -o $@ $<

# Installation
install: src/Newton/newton

	@# Removing Old Newton File
	rm -f $(BIN_DIR)/newton
	rm -f $(BIN_DIR)/nnpm

	@# Removing Uneeded Object Files
	rm -f src/Newton/lib/runtime/linux64/*.o
	rm -f src/Newton/lib/runtime/win64/*.w64.o

	@# Creating Directories
	mkdir -p $(HOME_DIR)/$(INSTALL_DIR)/bin
	mkdir -p $(HOME_DIR)/$(INSTALL_DIR)/lib/std

	@# Moving Files
	cp src/Newton/newton $(HOME_DIR)/$(INSTALL_DIR)/bin/newton
	cp src/Newtonian/nnpm $(HOME_DIR)/$(INSTALL_DIR)/bin/nnpm
	cp src/Newton/lib/libnewton.o $(HOME_DIR)/$(INSTALL_DIR)/lib
	cp src/Newton/lib/libnewton.a $(HOME_DIR)/$(INSTALL_DIR)/lib
	cp src/Newton/lib/std/* $(HOME_DIR)/$(INSTALL_DIR)/lib/std


	@# Creating Symbolic Link
	ln -sf $(HOME_DIR)/$(INSTALL_DIR)/bin/newton $(BIN_DIR)/newton
	ln -sf $(HOME_DIR)/$(INSTALL_DIR)/bin/nnpm $(BIN_DIR)/nnpm

	@# Compiling newton script file (for .nts files)
	@# Needs to be compiled AFTER newton is already installed as it is written in itself
	newton src/Newton/bootstrap/newton-script/newton-script.nt -o src/Newton/newton@core__script.component --verbose --noStdlib
	cp src/Newton/newton@core__script.component $(HOME_DIR)/$(INSTALL_DIR)/bin/newton@core__script.component

	@# Cleanup
	rm -f src/Newton/newton
	rm -f src/Newtonian/nnpm
	rm -f src/Newton/newton@core__script.component

	@# Path Check
	@echo ""
	@echo "========================================"
	@echo "Newton successfully installed!"
	@echo "Checking if $(BIN_DIR) is in your PATH..."
	@if ! echo "$$PATH" | grep -q "$(BIN_DIR)"; then \
		echo "$(BIN_DIR) was not found in your PATH."; \
		echo "To use Newton globally, add it manually to your shell configuration:"; \
		echo "  Bash/Zsh (~/.bashrc or ~/.zshrc):"; \
		echo '    export PATH="$$PATH:$(BIN_DIR)"'; \
		echo "  Nushell (env.nu):"; \
		echo "    \$$env.PATH = (\$$env.PATH | split row (char esep) | append '$(BIN_DIR)')"; \
		echo "========================================"; \
	fi

install-GVM:
	git clone -b Nightly https://github.com/Healing-A-Dev/GravityVM.git build
	$(MAKE) -C build build HINTS="--hints:on"
	rm -rf build
	gvm clean-cache


clean:
	rm -f $(RUNTIME_OBJS_LINUX) $(RUNTIME_OBJS_WINDOWS) src/Newton/lib/libnewton.o src/Newton/lib/libnewton.dll src/Newton/lib/libnewton.a src/Newton/newton

.PHONY: all clean install install-GVM
