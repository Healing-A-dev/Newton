# ---------------------------------------------------------
# PROCESS MANAGEMENT (Fork / Wait / PID)
# ---------------------------------------------------------

.section .text

# --- fork() -> pid ---
# Returns: 0 to the Child, ChildPID to the Parent
.global sys_fork
sys_fork:
    push %rbp
    mov %rsp, %rbp

    mov $57, %rax       # syscall: fork
    syscall

    # Check for error (negative)
    cmp $0, %rax
    jl .Lfork_err

    # Tag the PID (Integer)
    shl $1, %rax
    or $1, %rax
    leave
    ret

.Lfork_err:
    # On error, return -1 (Tagged)??
    # Let's just return 0 (False) or crash.
    # For now, return -1 encoded: -1 << 1 | 1 = -1 (actually works out to -1)
    mov $-1, %rax
    leave
    ret

# --- getpid() -> pid ---
.global sys_getpid
sys_getpid:
    mov $39, %rax       # syscall: getpid
    syscall

    shl $1, %rax        # Tag
    or $1, %rax
    ret

# --- wait() -> child_pid ---
# Pauses parent until a child dies (Zombie cleanup)
.global sys_wait
sys_wait:
    push %rbp
    mov %rsp, %rbp

    # syscall wait4(pid, status, options, rusage)
    # wait4(-1, NULL, 0, NULL) -> Wait for ANY child

    mov $61, %rax       # syscall: wait4
    mov $-1, %rdi       # pid = -1 (any)
    mov $0, %rsi        # status = NULL (we don't care why it died)
    mov $0, %rdx        # options = 0
    mov $0, %r10        # rusage = NULL
    syscall

    shl $1, %rax        # Tag result
    or $1, %rax
    leave
    ret

# --- sleep(seconds) ---
# Useful for testing concurrency
.global sys_sleep
sys_sleep:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp       # Alloc timespec struct {sec, nsec}

    sar $1, %rdi        # Untag seconds

    mov %rdi, (%rsp)    # tv_sec
    movq $0, 8(%rsp)    # tv_nsec

    mov $35, %rax       # syscall: nanosleep
    mov %rsp, %rdi      # req struct
    mov $0, %rsi        # rem struct (NULL)
    syscall

    leave
    ret
