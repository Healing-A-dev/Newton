# --- WINDOWS SYSTEM FFI (win_sys.s) ---
.extern ExitProcess
.extern GetEnvironmentVariableA
.extern CreateProcessA
.extern WaitForSingleObject
.extern CloseHandle
.extern _malloc

.section .bss
    .global __sys_stack_base
    __sys_stack_base: .quad 0

    .global __argc
    __argc:           .quad 0

    .global __sys_argv
    __sys_argv:       .quad 0

    .align 8
    env_buffer:       .space 8192
    cmd_buffer:       .space 8192
    startup_info:     .space 104
    proc_info:        .space 24

.section .rodata
    .Lcmd_prefix: .asciz "cmd.exe /c "
 	.Lempty_string: .string ""

.section .text

# --- PROCESS EXIT ---
.global sys_newton_exit
sys_newton_exit:
    push %rbp; mov %rsp, %rbp
    sub $32, %rsp
    and $-16, %rsp
    mov $0, %rcx
    call ExitProcess
    leave; ret

# --- ARGUMENTS ---
.global sys_argc
sys_argc:
    push %rbp; mov %rsp, %rbp
    mov __argc(%rip), %rax
    shl $1, %rax
    or $1, %rax
    leave; ret

# --- ENVIRONMENT VARIABLES ---
.global sys_getenv
sys_getenv:
    push %rbp; mov %rsp, %rbp
    push %r12
    sub $48, %rsp
    and $-16, %rsp
    test %rdi, %rdi
    jz .Lenv_fail
    mov %rdi, %rax
    and $1, %rax
    jnz .Lenv_fail
    mov -8(%rdi), %rcx
    cmp $5, %rcx
    jne .Lenv_ok
    mov 0(%rdi), %rdi

.Lenv_ok:
    mov %rdi, %rcx
    lea env_buffer(%rip), %rdx
    mov $8192, %r8
    call GetEnvironmentVariableA

    test %rax, %rax
    jz .Lenv_fail

    mov %rax, %r12
    mov %r12, %rdi
    add $9, %rdi
    call _malloc

    movq $1, 0(%rax)
    add $8, %rax
    mov %rax, %rdi
    lea env_buffer(%rip), %rsi
    mov %r12, %rcx
    rep movsb

    movb $0, (%rdi)
    sub %r12, %rdi
    mov %rdi, %rax
    jmp .Lenv_ret

.Lenv_fail:
    mov $1, %rax

.Lenv_ret:
    lea -8(%rbp), %rsp; pop %r12
    leave; ret

# --- PROCESS EXECUTION (CreateProcessA) ---
.global sys_exec
sys_exec:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12; push %r13; push %r14
    sub $96, %rsp
    and $-16, %rsp
    sar $1, %rdi
    mov %rdi, %r12
    lea cmd_buffer(%rip), %rdi
    lea .Lcmd_prefix(%rip), %rsi

.Lcopy_prefix:
    movb (%rsi), %al
    test %al, %al
    jz .Lcopy_user
    movb %al, (%rdi)
    inc %rdi; inc %rsi
    jmp .Lcopy_prefix

.Lcopy_user:
    movb (%r12), %al
    test %al, %al
    jz .Lcopy_done
    movb %al, (%rdi)
    inc %rdi; inc %r12
    jmp .Lcopy_user

.Lcopy_done:
    movb $0, (%rdi)
    lea startup_info(%rip), %rdi
    mov $104, %rcx
    xor %rax, %rax
    rep stosb

    lea startup_info(%rip), %rdi
    movl $104, (%rdi)
    mov $0, %rcx
    lea cmd_buffer(%rip), %rdx
    mov $0, %r8
    mov $0, %r9
    movq $0, 32(%rsp)
    movq $0, 40(%rsp)
    movq $0, 48(%rsp)
    movq $0, 56(%rsp)
    lea startup_info(%rip), %rax
    mov %rax, 64(%rsp)
    lea proc_info(%rip), %rax
    mov %rax, 72(%rsp)
    call CreateProcessA

    test %rax, %rax
    jz .Lexec_fail

    lea proc_info(%rip), %rbx
    mov 0(%rbx), %rcx
    mov $0xFFFFFFFF, %rdx
    call WaitForSingleObject

    lea proc_info(%rip), %rbx
    mov 0(%rbx), %rcx
    call CloseHandle

    lea proc_info(%rip), %rbx
    mov 8(%rbx), %rcx
    call CloseHandle

    mov $1, %rax
    jmp .Lexec_ret

.Lexec_fail:
    mov $0, %rax

.Lexec_ret:
    shl $1, %rax
    or $1, %rax
    lea -32(%rbp), %rsp
    pop %r14; pop %r13; pop %r12; pop %rbx
    leave; ret

.global sys_argv
sys_argv:
    push %rbp
    mov %rsp, %rbp
    sub $32, %rsp
    mov %rcx, %rax
    shr $1, %rax
    inc %rax
    mov __argc(%rip), %r8
    cmp %r8, %rax
    jge .Largv_out_of_bounds

    mov __sys_argv(%rip), %rdx
    mov (%rdx, %rax, 8), %rcx
    call string_new

    add $32, %rsp
    leave
    ret

.Largv_out_of_bounds:
    lea .Lempty_string(%rip), %rcx
    call string_new
    add $32, %rsp
    leave
    ret
