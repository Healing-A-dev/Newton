# ---------------------------------------------------------
# PROCESS MANAGEMENT (Fork / Wait / PID)
# ---------------------------------------------------------

.section .text

# --- fork() -> pid ---
.global sys_fork
sys_fork:
    push %rbp
    mov %rsp, %rbp
    mov $57, %rax
    syscall

    cmp $0, %rax
    jl .Lfork_err
    shl $1, %rax
    or $1, %rax
    leave
    ret

.Lfork_err:
    mov $-1, %rax
    leave
    ret

# --- getpid() -> pid ---
.global sys_getpid
sys_getpid:
    mov $39, %rax
    syscall

    shl $1, %rax
    or $1, %rax
    ret

# --- wait() -> child_pid ---
.global sys_wait
sys_wait:
    push %rbp
    mov %rsp, %rbp
    mov $61, %rax
    mov $-1, %rdi
    mov $0, %rsi
    mov $0, %rdx
    mov $0, %r10
    syscall

    shl $1, %rax
    or $1, %rax
    leave
    ret

# --- wait_nohang() -> Cleans up zombies in the background ---
.global sys_wait_nohang
sys_wait_nohang:
    push %rbp; mov %rsp, %rbp
    mov $61, %rax
    mov $-1, %rdi
    mov $0, %rsi
    mov $1, %rdx
    mov $0, %r10
    syscall

    shl $1, %rax; or $1, %rax
    leave; ret

# --- sleep(seconds) ---
.global sys_sleep
sys_sleep:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp
    sar $1, %rdi
    mov %rdi, (%rsp)
    movq $0, 8(%rsp)
    mov $35, %rax
    mov %rsp, %rdi
    mov $0, %rsi
    syscall

    leave
    ret

# --- sleep_ms(milliseconds) via %rdi ---
.global sys_sleep_ms
sys_sleep_ms:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp
    sar $1, %rdi
    mov %rdi, %rax
    xor %rdx, %rdx
    mov $1000, %rcx
    div %rcx
    mov %rax, 0(%rsp)
    mov %rdx, %rax
    mov $1000000, %rcx
    mul %rcx
    mov %rax, 8(%rsp)
    mov $35, %rax
    mov %rsp, %rdi
    mov $0, %rsi
    syscall

    mov $1, %rax
    leave
    ret
