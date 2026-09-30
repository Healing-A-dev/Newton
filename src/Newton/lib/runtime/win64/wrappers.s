# --- WINDOWS STANDARD LIBRARY ADAPTER (win_wrappers.s) ---
.extern CreateFileA
.extern WriteFile
.extern ReadFile
.extern CloseHandle
.extern GetStdHandle
.extern _malloc

.section .text

# --- ALIASES ---
.global exit_program
exit_program:
    jmp sys_newton_exit

.global newton_init_runtime
newton_init_runtime:
    push %rbp; mov %rsp, %rbp
    mov __sys_stack_base(%rip), %rax
    test %rax, %rax
    jnz .Lnir_done
    mov %rsp, %rax
    add $65536, %rax
    mov %rax, __sys_stack_base(%rip)
.Lnir_done:
    leave; ret

# --- FILE OPERATIONS ---
.global file_open
file_open:
    push %rbp; mov %rsp, %rbp
    sub $64, %rsp; and $-16, %rsp
    sar $1, %rdi
    sar $1, %rsi

    mov $0x80000000, %rdx
    mov $3, %r10

    cmp $577, %rsi
    jne .Lcheck_append
    mov $0x40000000, %rdx
    mov $2, %r10
    jmp .Ldo_open

.Lcheck_append:
    cmp $1089, %rsi
    jne .Ldo_open
    mov $0x0004, %rdx
    mov $4, %r10

.Ldo_open:
    mov %rdi, %rcx
    mov $1, %r8
    mov $0, %r9
    mov %r10, 32(%rsp)
    movq $128, 40(%rsp)
    movq $0, 48(%rsp)
    call CreateFileA

    cmp $-1, %rax
    je .Lfo_fail
    shl $1, %rax; or $1, %rax
    leave; ret
.Lfo_fail:
    mov $-1, %rax
    shl $1, %rax; or $1, %rax
    leave; ret

.global file_write
file_write:
    push %rbp; mov %rsp, %rbp; push %rbx; push %r12
    sub $48, %rsp; and $-16, %rsp
    sar $1, %rdi
    mov %rdi, %rcx
    mov %rsi, %rbx
    mov -8(%rbx), %rax
    cmp $5, %rax
    jne .Lfw_ok
    mov 0(%rbx), %rbx

.Lfw_ok:
    mov %rbx, %rdx
    push %rcx; push %rdx
    mov %rsi, %rdi; call string_len; mov %rax, %r8
    pop %rdx; pop %rcx
    lea 40(%rsp), %r9
    movq $0, 32(%rsp)
    call WriteFile

    mov 40(%rsp), %rax
    shl $1, %rax; or $1, %rax
    lea -16(%rbp), %rsp; pop %r12; pop %rbx
    leave; ret

.global file_read
file_read:
    push %rbp; mov %rsp, %rbp; push %r12; push %r13
    sub $48, %rsp; and $-16, %rsp
    sar $1, %rdi
    sar $1, %rsi
    mov %rdi, %r12
    mov %rsi, %r13
    mov %r13, %rdi
    add $9, %rdi
    call _malloc

    movq $1, 0(%rax)
    add $8, %rax
    mov %rax, %rbx
    mov %r12, %rcx
    mov %rbx, %rdx
    mov %r13, %r8
    lea 40(%rsp), %r9
    movq $0, 32(%rsp)
    call ReadFile

    mov 40(%rsp), %rcx
    movb $0, (%rbx, %rcx)
    mov %rbx, %rax
    lea -16(%rbp), %rsp; pop %r13; pop %r12
    leave; ret

.global file_close
file_close:
    push %rbp; mov %rsp, %rbp
    sub $32, %rsp; and $-16, %rsp
    sar $1, %rdi
    mov %rdi, %rcx
    call CloseHandle

    mov $3, %rax
    leave; ret

.global read_file
read_file:
    push %rbp; mov %rsp, %rbp; push %r14
    sub $48, %rsp; and $-16, %rsp
    mov %rdi, %r14
    call sys_file_size

    mov %rax, %r12
    mov %r14, %rdi
    mov $1, %rsi
    call file_open

    mov %rax, %r13
    mov %r13, %rdi
    mov %r12, %rsi
    call file_read

    mov %rax, %rbx
    mov %r13, %rdi
    call file_close

    mov %rbx, %rax
    lea -8(%rbp), %rsp; pop %r14
    leave; ret

.global read_string
read_string:
    push %rbp; mov %rsp, %rbp
    sub $64, %rsp; and $-16, %rsp
    mov $-10, %rcx
    call GetStdHandle

    mov %rax, %r12
    mov $1033, %rdi
    call _malloc

    movq $1, 0(%rax)
    add $8, %rax
    mov %rax, %rbx
    mov %r12, %rcx
    mov %rbx, %rdx
    mov $1024, %r8
    lea 40(%rsp), %r9
    movq $0, 32(%rsp)
    call ReadFile

    mov 40(%rsp), %rcx
    cmp $0, %rcx
    jle .Lrs_done
    cmpb $10, -1(%rbx, %rcx)
    jne .Lrs_done
    dec %rcx
    cmpb $13, -1(%rbx, %rcx)
    jne .Lrs_done
    dec %rcx

.Lrs_done:
    movb $0, (%rbx, %rcx)
    mov %rbx, %rax
    leave; ret
