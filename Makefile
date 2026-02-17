RUNTIME_SRCS = lib/runtime/mm.s \
               lib/runtime/io.s \
               lib/runtime/types.s \
               lib/runtime/math.s \
               lib/runtime/sys.s \
               lib/runtime/net.s \
               lib/runtime/proc.s

CORE_SRCS = core/ast.nim \
			core/codegen.nim \
			core/errors.nim \
			core/lexer.nim \
			core/main.nim \
			core/parser.nim

RUNTIME_OBJS = $(RUNTIME_SRCS:.s=.o)
CORE_OBJS = $(CORE_SRCS:.nim)




newton: $(CORE_OBJS) lib/libnewton.o
	nim c -o:newton -d:release core/main.nim
	@printf "\033c"
	@printf "\033[94mComplete\033[0m\n"
	
lib/libnewton.o: $(RUNTIME_OBJS)
	ld -r -o lib/libnewton.o $(RUNTIME_OBJS)

%.o: %.s
	as -o $@ $<


install: newton
	sudo cp newton /usr/local/bin

clean:
	rm -f lib/runtime/*.s

.phony:
	newton
