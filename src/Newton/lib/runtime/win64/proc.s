# --- WINDOWS PROCESS MANAGEMENT FFI (win_proc.s) ---
.extern Sleep
.extern GetCurrentProcessId

.section .text

# --- getpid() -> pid ---
.global sys_getpid
sys_getpid:
    push %rbp; mov %rsp, %rbp
    
    # 32-byte Shadow Space + 16-byte alignment
    sub $32, %rsp
    and $-16, %rsp
    
    # Call kernel32.dll GetCurrentProcessId()
    call GetCurrentProcessId
    
    # Tag the returned PID as a Newton Integer
    shl $1, %rax
    or $1, %rax
    
    leave; ret


# --- sleep(seconds) ---
.global sys_sleep
sys_sleep:
    push %rbp; mov %rsp, %rbp
    
    # 32-byte Shadow Space + 16-byte alignment
    sub $32, %rsp
    and $-16, %rsp
    
    sar $1, %rdi       # Untag Newton Integer
    imul $1000, %rdi   # Convert seconds to milliseconds
    mov %rdi, %rcx     # Arg 1: dwMilliseconds
    
    # Call kernel32.dll Sleep()
    call Sleep
    
    leave; ret


# --- sleep_ms(milliseconds) ---
.global sys_sleep_ms
sys_sleep_ms:
    push %rbp; mov %rsp, %rbp
    
    # 32-byte Shadow Space + 16-byte alignment
    sub $32, %rsp
    and $-16, %rsp
    
    sar $1, %rdi       # Untag Newton Integer
    mov %rdi, %rcx     # Arg 1: dwMilliseconds
    
    # Call kernel32.dll Sleep()
    call Sleep
    
    leave; ret


# ==========================================
# THE "FORK" PROBLEM
# Windows does not support process cloning.
# These are safe stubs to prevent crashing!
# ==========================================

.global sys_fork
sys_fork:
    push %rbp; mov %rsp, %rbp
    mov $-1, %rax      # Return -1 to indicate fork failure
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
