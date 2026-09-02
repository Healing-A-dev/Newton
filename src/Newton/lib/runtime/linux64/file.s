# --- LINUX FILE I/O FFI (linux64/file.s) ---
.section .bss
.align 8
line_header:  .space 8
line_buffer:  .space 4096
chunk_buffer: .space 8192
chunk_size:   .quad 0
chunk_ptr:    .quad 0

.section .text

# ---------------------------------------------------------
# FILE OPENING
# Usage in Newton: sys_open $path, $flag
# ---------------------------------------------------------
.global newton_fopen
newton_fopen:
    push %rbp; mov %rsp, %rbp

    and $-2, %rdi
    mov $2, %rax
    mov $0, %rsi
    mov $0, %rdx
    syscall

    cmp $0, %rax
    jl .Lfo_err

    movq $0, chunk_size(%rip)
    movq $0, chunk_ptr(%rip)

    shl $1, %rax
    or $1, %rax
    leave; ret

.Lfo_err:
    mov $1, %rax
    leave; ret

# ---------------------------------------------------------
# FILE READING
# Usage in Newton: sys_read $fd
# ---------------------------------------------------------
.global newton_getline
newton_getline:
    push %rbp; mov %rsp, %rbp
    push %r12
    push %r13

    cmp $1, %rdi
    je .Lgl_eof_pop

    sar $1, %rdi
    mov %rdi, %r12

    lea line_buffer(%rip), %r13
    xor %r10, %r10

.Lgl_loop:
    mov chunk_ptr(%rip), %rcx
    cmp chunk_size(%rip), %rcx
    jl .Lgl_read_byte

    mov $0, %rax       # Linux Syscall ID for 'sys_read'
    mov %r12, %rdi     # File Descriptor
    lea chunk_buffer(%rip), %rsi # Where to put the bytes
    mov $8192, %rdx    # How many bytes to read
    syscall

    cmp $0, %rax
    jle .Lgl_end_of_file

    mov %rax, chunk_size(%rip)
    movq $0, chunk_ptr(%rip)
    movq $0, %rcx

.Lgl_read_byte:
    lea chunk_buffer(%rip), %rsi
    movb (%rsi, %rcx), %al

    inc %rcx
    mov %rcx, chunk_ptr(%rip)

    cmpb $10, %al; je .Lgl_done_line     # '\n' -> Line complete!
    cmpb $13, %al; je .Lgl_loop          # '\r' -> Ignore and skip!

    movb %al, 0(%r13, %r10)
    inc %r10

    cmp $4095, %r10
    jge .Lgl_done_line

    jmp .Lgl_loop

.Lgl_end_of_file:
    test %r10, %r10
    jg .Lgl_done_line
    jmp .Lgl_eof_pop

.Lgl_done_line:
    movb $0, 0(%r13, %r10)
    movq $1, line_header(%rip)
    lea line_buffer(%rip), %rax

    pop %r13
    pop %r12
    leave; ret

.Lgl_eof_pop:
    mov $1, %rax                # Return Tagged False (1)
    pop %r13
    pop %r12
    leave; ret

# ---------------------------------------------------------
# FILE CLOSING
# Usage in Newton: sys_close $fd
# ---------------------------------------------------------
.global newton_fclose
newton_fclose:
    push %rbp; mov %rsp, %rbp
    cmp $1, %rdi
    je .Lfc_end

    sar $1, %rdi       # Untag File Descriptor
    mov $3, %rax       # Linux Syscall ID for 'sys_close'
    syscall
.Lfc_end:
    leave; ret


# ---------------------------------------------------------
# BINARY FILE WRITER
# Usage in Newton: sys_write_bytes $fd, $byte_array
# ---------------------------------------------------------
.global sys_write_bytes
sys_write_bytes:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12; push %r13; push %r14

    sar $1, %rdi
    mov %rdi, %r12

    test %rsi, %rsi; jz .Lwb_done
    mov %rsi, %rax; and $1, %rax; jnz .Lwb_done
    mov -8(%rsi), %rax; cmp $3, %rax; jne .Lwb_done

    mov 0(%rsi), %r13    # True Length
    test %r13, %r13; jz .Lwb_done
    lea 8(%rsi), %r14    # Elements Buffer

    mov %r13, %rdi
    call _malloc
    mov %rax, %rbx

    xor %rcx, %rcx
.Lwb_loop:
    cmp %rcx, %r13
    je .Lwb_do_write
    mov (%r14, %rcx, 8), %rax
    sar $1, %rax
    movb %al, (%rbx, %rcx)
    inc %rcx
    jmp .Lwb_loop

.Lwb_do_write:
    mov $1, %rax         # Linux syscall 1: sys_write
    mov %r12, %rdi       # FD
    mov %rbx, %rsi       # Buffer
    mov %r13, %rdx       # Length
    syscall

    mov %rbx, %rdi
    call _free

.Lwb_done:
    mov $3, %rax         # Return Tagged 1 (Success)
    pop %r14; pop %r13; pop %r12; pop %rbx
    leave; ret
