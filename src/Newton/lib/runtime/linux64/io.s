.section .bss
    .global input_buffer
    input_buffer: .zero 256

.section .rodata
    .Lerr_1: .asciz "\r\n\033[1;31m--- [ RUNTIME FAULT ] ---\033[0m\r\n\033[1mFile   :\033[0m "
    .Lerr_line: .asciz " (Line "
    .Lerr_close: .asciz ")\r\n\033[1mIssue  :\033[0m Runtime Panic\r\n\r\n  "
    .Lerr_pipe: .asciz " | "
    .Lerr_hint: .asciz "\r\n\033[1;30mHint   :\033[0m "
    .Lerr_footer: .asciz "\r\n\033[1;31m--------------------------------\033[0m\r\n\r\n"

.section .text

# --- SMART PRINT ---
.global print_string
print_string:
    push %rbp; mov %rsp, %rbp; push %rbx
    test %rdi, %rdi; jnz .Lps_valid
    mov $1, %rdi

.Lps_valid:
    test $1, %rdi; jnz .Lprint_int
    mov -8(%rdi), %rax
    cmp $1, %rax; je .Lprint_str
    cmp $4, %rax; je .Lprint_float
    cmp $5, %rax; je .Lprint_view
    jmp .Lprint_done

.Lprint_int: call int_to_string; mov %rax, %rdi; jmp .Lprint_str
.Lprint_float: call float_to_string; mov %rax, %rdi; jmp .Lprint_str
.Lprint_view:
    mov $1, %rax
    mov 8(%rdi), %rdx
    mov 0(%rdi), %rsi
    mov $1, %rdi
    syscall
    jmp .Lprint_done

.Lprint_str:
    mov %rdi, %rbx
    xor %rdx, %rdx
.Lplen: cmpb $0, (%rbx, %rdx); je .Lpwrite; inc %rdx; jmp .Lplen
.Lpwrite: mov $1, %rax; mov $1, %rdi; mov %rbx, %rsi; syscall
.Lprint_done: pop %rbx; leave; ret

# --- READ STRING (STDIN) ---
.global read_string
read_string:
    push %rbp; mov %rsp, %rbp; push %rbx; push %r12
    mov $137, %rdi
    call _malloc
    mov %rax, %rbx

    movq $1, 0(%rbx)
    add $8, %rbx
    xor %r12, %r12

.Lrs_loop:
    mov $0, %rax
    mov $0, %rdi
    lea (%rbx, %r12), %rsi
    mov $1, %rdx
    syscall
    cmp $1, %rax
    jne .Lrs_done

    movb (%rbx, %r12), %al
    cmp $10, %al
    je .Lrs_done

    inc %r12
    cmp $127, %r12
    jl .Lrs_loop

.Lrs_done:
    movb $0, (%rbx, %r12)
    mov %rbx, %rax
    pop %r12; pop %rbx; leave; ret

# --- DYNAMIC READ FILE ---
.global read_file
read_file:
    push %rbp; mov %rsp, %rbp; push %rbx; push %r12; push %r13
    mov %rdi, %rbx
    mov $2, %rax; mov %rbx, %rdi; mov $0, %rsi; mov $0, %rdx; syscall
    cmp $0, %rax; jl .Lread_fail
    mov %rax, %rbx
    mov $8, %rax; mov %rbx, %rdi; mov $0, %rsi; mov $2, %rdx; syscall
    mov %rax, %r12
    mov $8, %rax; mov %rbx, %rdi; mov $0, %rsi; mov $0, %rdx; syscall
    mov %r12, %rdi; add $9, %rdi; call _malloc
    mov %rax, %r13
    movq $1, 0(%r13)
    add $8, %r13
    mov $0, %rax; mov %rbx, %rdi; mov %r13, %rsi; mov %r12, %rdx; syscall
    movb $0, (%r13, %r12)
    mov $3, %rax; mov %rbx, %rdi; syscall
    mov %r13, %rax
    pop %r13; pop %r12; pop %rbx; leave; ret
.Lread_fail:
    mov $9, %rdi; call _malloc; movq $1, 0(%rax); add $8, %rax; movb $0, (%rax); leave; ret

# --- WRAPPERS ---
.global file_write
file_write:
    push %rbp; mov %rsp, %rbp; push %rbx
    mov %rdi, %rbx; mov %rsi, %r12; mov %r12, %rdi; call .Lslen
    mov %rax, %rdx; mov $1, %rax; mov %rbx, %rdi; mov %r12, %rsi; syscall
    pop %rbx; leave; ret
.Lslen: xor %rax, %rax; .Lsl: cmpb $0, (%rdi, %rax); je .sld; inc %rax; jmp .Lsl; .sld: ret

.global file_read
file_read: jmp read_from_fd

.global read_from_fd
read_from_fd:
    push %rbp; mov %rsp, %rbp; sub $16, %rsp
    mov %rdi, -8(%rbp)
    mov $4096, %rdi; call _malloc
    movq $1, 0(%rax); add $8, %rax; mov %rax, -16(%rbp)
    mov $0, %rax; mov -8(%rbp), %rdi; mov -16(%rbp), %rsi; mov $4095, %rdx; syscall
    cmp $0, %rax; jl .Lread_fail
    mov -16(%rbp), %rbx; add %rax, %rbx; movb $0, (%rbx)
    mov -16(%rbp), %rax; leave; ret

.global file_open
file_open: mov $2, %rax; mov $420, %rdx; syscall; ret
.global file_close
file_close: mov $3, %rax; syscall; ret
.global exit_program
exit_program: sar $1, %rdi; mov $60, %rax; syscall; ret

print_raw_os:
    push %rbp; mov %rsp, %rbp
    mov %rdi, %rsi
    xor %rdx, %rdx
.Lpro_len:
    cmpb $0, (%rsi, %rdx)
    je .Lpro_do
    inc %rdx
    jmp .Lpro_len
.Lpro_do:
    mov $1, %rax
    mov $1, %rdi
    syscall
    leave; ret

.global sys_log_err
sys_log_err:
    push %rbp; mov %rsp, %rbp
    push %r12; push %r13; push %r14; push %r15

    mov %rdi, %r12
    mov %rsi, %r13
    mov %rdx, %r14
    mov %rcx, %r15

    lea .Lerr_1(%rip), %rdi; call print_raw_os
    mov %r12, %rdi; call print_string

    lea .Lerr_line(%rip), %rdi; call print_raw_os
    mov %r13, %rdi; call print_string
    lea .Lerr_close(%rip), %rdi; call print_raw_os

    mov %r13, %rdi; call print_string
    lea .Lerr_pipe(%rip), %rdi; call print_raw_os
    mov %r14, %rdi; call print_string

    lea .Lerr_hint(%rip), %rdi; call print_raw_os
    mov %r15, %rdi; call print_string
    lea .Lerr_footer(%rip), %rdi; call print_raw_os

    pop %r15; pop %r14; pop %r13; pop %r12
    leave; ret

.global sys_access
sys_access:
    push %rbp; mov %rsp, %rbp
    mov $21, %rax
    mov $0, %rsi
    syscall
    shl $1, %rax; or $1, %rax
    leave; ret

# Create a directory (mkdir)
.global sys_mkdir
sys_mkdir:
    push %rbp; mov %rsp, %rbp
    mov $83, %rax
    mov $511, %rsi
    syscall
    shl $1, %rax; or $1, %rax
    leave; ret

# Delete a file (unlink)
.global sys_unlink
sys_unlink:
    push %rbp; mov %rsp, %rbp
    mov $87, %rax
    syscall
    shl $1, %rax; or $1, %rax
    leave; ret

.global sys_file_size
sys_file_size:
    push %rbp; mov %rsp, %rbp
    sar $1, %rdi

    mov %rdi, %r8
    mov $8, %rax
    mov $0, %rsi
    mov $2, %rdx
    syscall

    mov %rax, %r9
    mov %r8, %rdi
    mov $8, %rax
    mov $0, %rsi
    mov $0, %rdx
    syscall

    mov %r9, %rax
    shl $1, %rax
    or $1, %rax
    leave; ret
