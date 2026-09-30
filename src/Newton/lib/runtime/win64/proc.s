# --- WINDOWS PROCESS MANAGEMENT FFI (win_proc.s) ---
.extern Sleep
.extern GetCurrentProcessId

.section .text

# --- getpid() -> pid ---
.global sys_getpid
sys_getpid:
    push %rbp; mov %rsp, %rbp
    sub $32, %rsp
    and $-16, %rsp
    call GetCurrentProcessId

    shl $1, %rax
    or $1, %rax
    leave; ret


# --- sleep(seconds) ---
.global sys_sleep
sys_sleep:
    push %rbp; mov %rsp, %rbp
    sub $32, %rsp
    and $-16, %rsp
    sar $1, %rdi
    imul $1000, %rdi
    mov %rdi, %rcx
    call Sleep
    leave; ret


# --- sleep_ms(milliseconds) ---
.global sys_sleep_ms
sys_sleep_ms:
    push %rbp; mov %rsp, %rbp
    sub $32, %rsp
    and $-16, %rsp
    sar $1, %rdi
    mov %rdi, %rcx
    call Sleep
    leave; ret

.global sys_fork
sys_fork:
    push %rbp; mov %rsp, %rbp
    mov $-1, %rax
    shl $1, %rax
    or $1, %rax
    leave; ret

.global sys_wait
sys_wait:
    push %rbp; mov %rsp, %rbp
    mov $-1, %rax
    shl $1, %rax
    or $1, %rax
    leave; ret

.global sys_wait_nohang
sys_wait_nohang:
    push %rbp; mov %rsp, %rbp
    mov $-1, %rax
    shl $1, %rax
    or $1, %rax
    leave; ret
