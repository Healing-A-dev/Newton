# --- WINDOWS FILE I/O FFI (win64/file.s) ---
.extern CreateFileA
.extern ReadFile
.extern CloseHandle
.extern _malloc
.extern _write

.section .bss
.align 8
line_header:  .space 8
line_buffer:  .space 4096
chunk_buffer: .space 8192
chunk_size:   .quad 0
chunk_ptr:    .quad 0
bytes_read:   .quad 0

.section .text

.global newton_fopen
newton_fopen:
    push %rbp; mov %rsp, %rbp
    and $-2, %rdi
    sub $64, %rsp
    mov %rdi, %rcx
    mov $0x80000000, %rdx
    mov $1, %r8
    mov $0, %r9
    movq $3, 32(%rsp)
    movq $128, 40(%rsp)
    movq $0, 48(%rsp)
    call CreateFileA

    cmp $-1, %rax
    je .Lfo_err

    movq $0, chunk_size(%rip)
    movq $0, chunk_ptr(%rip)
    shl $1, %rax
    or $1, %rax
    leave; ret

.Lfo_err:
    mov $1, %rax
    leave; ret

.global newton_getline
newton_getline:
    push %rbp; mov %rsp, %rbp
    push %r12
    push %r13
    sub $48, %rsp
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
    mov %r12, %rcx
    lea chunk_buffer(%rip), %rdx
    mov $8192, %r8
    lea bytes_read(%rip), %r9
    movq $0, 32(%rsp)
    call ReadFile

    cmp $0, %rax
    je .Lgl_end_of_file

    mov bytes_read(%rip), %rax
    cmp $0, %rax
    je .Lgl_end_of_file

    mov %rax, chunk_size(%rip)
    movq $0, chunk_ptr(%rip)
    movq $0, %rcx

.Lgl_read_byte:
    lea chunk_buffer(%rip), %rsi
    movb (%rsi, %rcx), %al
    inc %rcx
    mov %rcx, chunk_ptr(%rip)
    cmpb $10, %al; je .Lgl_done_line
    cmpb $13, %al; je .Lgl_loop
    movb %al, 0(%r13, %r10)
    inc %r10
    cmp $4095, %r10
    jge .Lgl_done_line
    jmp .Lgl_loop

.Lgl_end_of_file:
    test %r10, %r10
    jz .Lgl_eof_pop

.Lgl_done_line:
    mov %r10, %rdi
    add $9, %rdi
    push %r10
    call _malloc

    pop %r10
    movq $1, 0(%rax)
    add $8, %rax
    mov %r10, %rcx
    test %rcx, %rcx
    jz .Lgl_null_term

    push %rdi
    mov %rax, %rdi
    lea line_buffer(%rip), %rsi
    rep movsb
    mov %rdi, %rax
    pop %rdi
    sub %r10, %rax

.Lgl_null_term:
    movb $0, (%rax, %r10)
    jmp .Lgl_cleanup

.Lgl_eof_pop:
    mov $1, %rax

.Lgl_cleanup:
    lea -16(%rbp), %rsp
    pop %r13
    pop %r12
    leave; ret

.global sys_write_bytes
.extern WriteFile

sys_write_bytes:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12; push %r13; push %r14
    sub $48, %rsp
    and $-16, %rsp
    sar $1, %rcx
    mov %rcx, %r12
    test %rdx, %rdx; jz .Lwb_done
    mov %rdx, %rax; and $1, %rax; jnz .Lwb_done
    mov -8(%rdx), %rax; cmp $3, %rax; jne .Lwb_done
    mov 0(%rdx), %r13
    test %r13, %r13; jz .Lwb_done
    lea 8(%rdx), %r14
    mov %r13, %rcx

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
    mov %r12, %rcx
    mov %rbx, %rdx
    mov %r13, %r8
    lea 40(%rsp), %r9
    movq $0, 32(%rsp)
    call WriteFile

    mov %rbx, %rcx
    call _free

.Lwb_done:
    mov $3, %rax
    lea -32(%rbp), %rsp
    pop %r14; pop %r13; pop %r12; pop %rbx
    leave; ret
