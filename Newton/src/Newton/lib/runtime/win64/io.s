# --- WINDOWS IO FFI (win_io.s) ---
.extern GetStdHandle
.extern WriteFile
.extern GetFileAttributesA
.extern CreateDirectoryA
.extern DeleteFileA
.extern GetFileSizeEx
.extern int_to_string

.section .bss
    .global input_buffer
    input_buffer: .zero 256

.section .rodata
    .Lerr_1: .asciz "\r\033[1;31merror[R001]\033[0m: Runtime Panic\r\n  --> \033[1;34m"
    .Lerr_colon: .asciz ":"
    .Lerr_2: .asciz "\033[0m\r\n   \033[1;34m|\033[0m\r\n"
    .Lerr_pipe: .asciz "\033[1;34m | \033[0m"
    .Lerr_3: .asciz "\r\n   \033[1;34m|\033[0m\r\n   = help: "
    .Lerr_4: .asciz "\r\n\r\n"

    .Lstr_bracket_l: .asciz "["
    .Lstr_bracket_r: .asciz "]"
    .Lstr_paren_l:   .asciz "("
    .Lstr_paren_r:   .asciz ")"
    .Lstr_comma:     .asciz ", "

.section .text

# ==================================================
# 1. PURE NEWTON LOGIC (OS Agnostic Formatting)
# ==================================================
.global print_string
print_string:
    push %rbp; mov %rsp, %rbp; push %rbx
    test %rdi, %rdi; jnz .Lps_valid
    mov $1, %rdi
.Lps_valid:
    test $1, %rdi; jnz .Lprint_int
    mov -8(%rdi), %rax
    cmp $1, %rax; je .Lprint_str
    cmp $4, %rax; je .Lprint_str
    cmp $3, %rax; je .Lprint_array
    cmp $2, %rax; je .Lprint_map
    jmp .Lps_done
.Lprint_int:
    call int_to_string
    mov %rax, %rdi
.Lprint_str:
    call print_raw_os
    jmp .Lps_done
.Lprint_array:
    call print_array_inline
    jmp .Lps_done
.Lprint_map:
    call print_map_inline
.Lps_done:
    pop %rbx; leave; ret

print_array_inline:
    push %rbp; mov %rsp, %rbp
    push %r12; push %r13; push %r14
    mov %rdi, %r12
    lea .Lstr_bracket_l(%rip), %rdi; call print_raw_os
    mov 0(%r12), %r13
    lea 8(%r12), %r14
.Lpai_loop:
    test %r13, %r13; jz .Lpai_done
    mov (%r14), %rdi; call print_string
    cmp $1, %r13; je .Lpai_skip_comma
    lea .Lstr_comma(%rip), %rdi; call print_raw_os
.Lpai_skip_comma:
    add $8, %r14
    dec %r13
    jmp .Lpai_loop
.Lpai_done:
    lea .Lstr_bracket_r(%rip), %rdi; call print_raw_os
    pop %r14; pop %r13; pop %r12
    leave; ret

print_map_inline:
    push %rbp; mov %rsp, %rbp
    push %r12; push %r13
    mov 0(%rdi), %r12
    lea .Lstr_paren_l(%rip), %rdi; call print_raw_os
.Lpmi_loop:
    test %r12, %r12; jz .Lpmi_done
    mov 0(%r12), %rdi; call print_string
    lea .Lerr_colon(%rip), %rdi; call print_raw_os
    mov 8(%r12), %rdi; call print_string
    mov 16(%r12), %r12
    test %r12, %r12; jz .Lpmi_loop
    lea .Lstr_comma(%rip), %rdi; call print_raw_os
    jmp .Lpmi_loop
.Lpmi_done:
    lea .Lstr_paren_r(%rip), %rdi; call print_raw_os
    pop %r13; pop %r12
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
    lea .Lerr_colon(%rip), %rdi; call print_raw_os
    mov %r13, %rdi; call print_string
    lea .Lerr_2(%rip), %rdi; call print_raw_os
    mov %r13, %rdi; call print_string
    lea .Lerr_pipe(%rip), %rdi; call print_raw_os
    mov %r14, %rdi; call print_string
    lea .Lerr_3(%rip), %rdi; call print_raw_os
    mov %r15, %rdi; call print_string
    lea .Lerr_4(%rip), %rdi; call print_raw_os
    pop %r15; pop %r14; pop %r13; pop %r12
    leave; ret


# ==================================================
# 2. WINDOWS KERNEL32 API BRIDGES
# ==================================================

.Lstring_len_native:
    xor %rax, %rax
.Lsln_loop:
    cmpb $0, (%rdi, %rax)
    je .Lsln_done
    inc %rax
    jmp .Lsln_loop
.Lsln_done:
    ret

.global print_raw_os
print_raw_os:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12

    # 64 bytes for Shadow Space, Local Variables, and Alignment
    sub $64, %rsp
    and $-16, %rsp

    mov %rdi, %rbx       # Save string pointer
    xor %r12, %r12       # Length counter = 0
.Lpro_len:
    cmpb $0, (%rbx, %r12)
    je .Lpro_do
    inc %r12
    jmp .Lpro_len
.Lpro_do:
    # 1. GetStdHandle(-11 = STD_OUTPUT_HANDLE)
    mov $-11, %rcx
    call GetStdHandle

    # 2. WriteFile(hFile, lpBuffer, nBytesToWrite, lpBytesWritten, lpOverlapped)
    mov %rax, %rcx
    mov %rbx, %rdx
    mov %r12, %r8
    lea 48(%rsp), %r9
    movq $0, 32(%rsp)
    call WriteFile

    # 3. Safely Restore Stack and Registers
    lea -16(%rbp), %rsp
    pop %r12
    pop %rbx
    leave; ret

.global sys_access
sys_access:
    push %rbp; mov %rsp, %rbp
    sub $32, %rsp
    and $-16, %rsp

    mov %rdi, %rcx
    call GetFileAttributesA

    cmp $-1, %rax        # Check for INVALID_FILE_ATTRIBUTES
    je .Lacc_fail
    mov $0, %rax
    jmp .Lacc_done
.Lacc_fail:
    mov $-1, %rax
.Lacc_done:
    shl $1, %rax; or $1, %rax  # Tag return code
    leave; ret


.global sys_mkdir
sys_mkdir:
    push %rbp; mov %rsp, %rbp
    sub $32, %rsp
    and $-16, %rsp

    mov %rdi, %rcx
    mov $0, %rdx         # NULL Security Attributes
    call CreateDirectoryA

    test %rax, %rax
    jz .Lmkdir_fail
    mov $0, %rax
    jmp .Lmkdir_done
.Lmkdir_fail:
    mov $-1, %rax
.Lmkdir_done:
    shl $1, %rax; or $1, %rax
    leave; ret


.global sys_unlink
sys_unlink:
    push %rbp; mov %rsp, %rbp
    sub $32, %rsp
    and $-16, %rsp

    mov %rdi, %rcx
    call DeleteFileA

    test %rax, %rax
    jz .Lunlink_fail
    mov $0, %rax
    jmp .Lunlink_done
.Lunlink_fail:
    mov $-1, %rax
.Lunlink_done:
    shl $1, %rax; or $1, %rax
    leave; ret


.global sys_file_size
sys_file_size:
    push %rbp; mov %rsp, %rbp
    sub $48, %rsp
    and $-16, %rsp

    sar $1, %rdi          # Untag the Windows HANDLE

    # GetFileSizeEx(hFile, &lpFileSize)
    mov %rdi, %rcx
    lea 32(%rsp), %rdx
    call GetFileSizeEx

    test %rax, %rax
    jz .Lfsize_fail

    mov 32(%rsp), %rax    # Load the resulting size
    jmp .Lfsize_done
.Lfsize_fail:
    mov $-1, %rax
.Lfsize_done:
    shl $1, %rax; or $1, %rax
    leave; ret
