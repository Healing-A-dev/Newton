.section .bss
    .global input_buffer
    input_buffer: .zero 256

.section .text

# --- SMART PRINT ---
.global print_string
print_string:
    push %rbp; mov %rsp, %rbp; push %rbx
    test $1, %rdi; jnz .Lprint_int
    test %rdi, %rdi; jz .Lprint_done
    mov -8(%rdi), %rax
    cmp $1, %rax; je .Lprint_str
    cmp $4, %rax; je .Lprint_float
    jmp .Lprint_done
.Lprint_int: call int_to_string; mov %rax, %rdi; jmp .Lprint_str
.Lprint_float: call float_to_string; mov %rax, %rdi; jmp .Lprint_str
.Lprint_str:
    mov %rdi, %rbx; xor %rdx, %rdx
.Lplen: cmpb $0, (%rbx, %rdx); je .Lpwrite; inc %rdx; jmp .Lplen
.Lpwrite: mov $1, %rax; mov $1, %rdi; mov %rbx, %rsi; syscall
.Lprint_done: pop %rbx; leave; ret

# --- [NEW] READ FROM FD (For Sockets) ---
.global read_from_fd
read_from_fd:
    push %rbp; mov %rsp, %rbp; sub $16, %rsp
    mov %rdi, -8(%rbp)
    mov $4096, %rdi; call _malloc
    movq $1, (%rax); add $8, %rax; mov %rax, -16(%rbp)
    mov $0, %rax; mov -8(%rbp), %rdi; mov -16(%rbp), %rsi; mov $4095, %rdx; syscall
    cmp $0, %rax; jl .Lread_fail
    mov -16(%rbp), %rbx; add %rax, %rbx; movb $0, (%rbx)
    mov -16(%rbp), %rax; leave; ret

# --- READ FILE (For Paths) ---
.global read_file
read_file:
    push %rbp; mov %rsp, %rbp; sub $16, %rsp
    mov $2, %rax; mov $0, %rsi; mov $0, %rdx; syscall
    cmp $0, %rax; jl .Lread_fail
    mov %rax, -8(%rbp)
    mov $4096, %rdi; call _malloc
    movq $1, (%rax); add $8, %rax; mov %rax, -16(%rbp)
    mov $0, %rax; mov -8(%rbp), %rdi; mov -16(%rbp), %rsi; mov $4095, %rdx; syscall
    push %rax
    mov $3, %rax; mov -8(%rbp), %rdi; syscall
    pop %rax
    cmp $0, %rax; jl .Lread_fail
    mov -16(%rbp), %rbx; add %rax, %rbx; movb $0, (%rbx)
    mov -16(%rbp), %rax; leave; ret

.Lread_fail:
    mov $9, %rdi; call _malloc; movq $1, (%rax); add $8, %rax; movb $0, (%rax); leave; ret

# --- STUBS & UTILS ---
.global file_open
file_open: mov $2, %rax; mov $420, %rdx; syscall; ret

.global file_close
file_close: mov $3, %rax; syscall; ret

.global read_string
read_string:
    push %rbp; mov %rsp, %rbp; mov $0, %rax; mov $0, %rdi; lea input_buffer(%rip), %rsi; mov $255, %rdx; syscall
    cmp $0, %rax; jle .rsd; lea input_buffer(%rip), %rsi; movb $0, -1(%rsi, %rax)
.rsd: lea input_buffer(%rip), %rax; leave; ret

.global file_write
file_write:
    push %rbp; mov %rsp, %rbp; push %rbx
    mov %rdi, %rbx; mov %rsi, %r12; mov %r12, %rdi; call .Lslen
    mov %rax, %rdx; mov $1, %rax; mov %rbx, %rdi; mov %r12, %rsi; syscall
    pop %rbx; leave; ret
.Lslen: xor %rax, %rax; .Lsl: cmpb $0, (%rdi, %rax); je .sld; inc %rax; jmp .Lsl; .sld: ret

.global file_read
file_read: jmp read_from_fd

.global exit_program
exit_program:
    sar $1, %rdi        # Untag the integer (e.g. 1->0, 3->1)
    mov $60, %rax       # syscall: sys_exit
    syscall
    ret

# STDERR
.global sys_log_err
sys_log_err:
    push %rbp
    mov %rsp, %rbp
    push %rbx
    push %r12

    mov %rdi, %rbx      # Save Message Ptr
    mov %rsi, %r12      # Save Line Number

    # 1. Print "Error (Line "
    mov $1, %rax        # sys_write
    mov $2, %rdi        # fd 2 (STDERR)
    lea .Lstr_err_pre(%rip), %rsi
    mov $13, %rdx       # Length
    syscall

    # 2. Print Line Number
    mov %r12, %rdi      # Tagged Int
    call int_to_string  # Returns Data Ptr

    # [FIX] Do NOT add $8. %rax is already the Data Pointer.
    mov %rax, %rcx

    push %rcx
    mov %rcx, %rdi
    call string_len_asm
    mov %rax, %rdx
    pop %rsi            # Buffer

    mov $1, %rax
    mov $2, %rdi
    syscall

    # 3. Print "): "
    mov $1, %rax
    mov $2, %rdi
    lea .Lstr_err_mid(%rip), %rsi
    mov $3, %rdx
    syscall

    # 4. Print Message
    # [FIX] Do NOT add $8. %rbx is already the Data Pointer.
    mov %rbx, %rdi

    push %rdi
    call string_len_asm
    mov %rax, %rdx
    pop %rsi

    mov $1, %rax
    mov $2, %rdi
    syscall

    # 5. Print Newline
    mov $1, %rax
    mov $2, %rdi
    lea .Lstr_nl(%rip), %rsi
    mov $1, %rdx
    syscall

    pop %r12
    pop %rbx
    leave
    ret

# Helper: Raw String Length (stops at null)
string_len_asm:
    xor %rax, %rax
.Lsl_loop:
    cmpb $0, (%rdi, %rax)
    je .Lsl_done
    inc %rax
    jmp .Lsl_loop
.Lsl_done:
    ret

.section .rodata
.Lstr_err_pre: .string "Error (Line "
.Lstr_err_mid: .string "): "
.Lstr_nl:      .string "\n"
