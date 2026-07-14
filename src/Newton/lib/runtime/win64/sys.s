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

.section .text

# --- PROCESS EXIT ---
.global sys_newton_exit
sys_newton_exit:
    push %rbp; mov %rsp, %rbp

    # 32-byte Shadow Space + 16-byte alignment
    sub $32, %rsp
    and $-16, %rsp

    # Call ExitProcess(0)
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
# Windows provides a native API for this, so we bypass memory scanning!
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

    # GetEnvironmentVariableA(Key, Buffer, Size)
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

    # CreateProcess requires 10 arguments! We need massive shadow space.
    sub $96, %rsp
    and $-16, %rsp

    sar $1, %rdi
    mov %rdi, %r12

    # 1. Build string: "cmd.exe /c " + "user command"
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

    # 2. Zero-out and initialize the 104-byte STARTUPINFO struct
    lea startup_info(%rip), %rdi
    mov $104, %rcx
    xor %rax, %rax
    rep stosb
    lea startup_info(%rip), %rdi
    movl $104, (%rdi)

    # 3. Fire CreateProcessA
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

    # 4. Wait for command to finish
    lea proc_info(%rip), %rbx
    mov 0(%rbx), %rcx
    mov $0xFFFFFFFF, %rdx    # INFINITE timeout
    call WaitForSingleObject

    # 5. Clean up Memory Handles
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
