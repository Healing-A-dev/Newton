.section .rodata

.align 8
.quad 1
.Lstr_unwrap_file: .asciz "<Runtime Unwrap>"

.align 8
.quad 1
.Lstr_unwrap_code: .asciz "Unwrapped a fatal error result"

.section .data
.Lerr_tag: .asciz "error"
.Lok_tag:  .asciz "ok"

.section .text

.global runtime_auto_unwrap
runtime_auto_unwrap:
    push %rbp
    mov %rsp, %rbp
    sub $32, %rsp
    mov %rdi, -8(%rbp)
    mov %rsi, -16(%rbp)
    mov %rdi, %rax
    test $1, %al
    jnz .Lreturn_original

    mov -8(%rbp), %rdi
    mov $1, %rsi
    call collection_get

    mov %rax, -24(%rbp)
    test $1, %al
    jnz .Lreturn_original

    mov -24(%rbp), %rdi
    mov -8(%rdi), %rax
    cmp $1, %rax
    jne .Lreturn_original

    mov -24(%rbp), %rdi
    lea .Lerr_tag(%rip), %rsi
    call newton_strcmp

    cmp $0, %rax
    je .Lcrash_with_error

    mov -24(%rbp), %rdi
    lea .Lok_tag(%rip), %rsi
    call newton_strcmp

    cmp $0, %rax
    je .Lunwrap_ok
    jmp .Lreturn_original

.Lreturn_original:
    mov -8(%rbp), %rax
    leave
    ret

.Lunwrap_ok:
    mov -8(%rbp), %rdi
    mov $3, %rsi
    call collection_get
    leave
    ret

.Lcrash_with_error:
    mov -8(%rbp), %rdi
    mov $3, %rsi
    call collection_get

    mov %rax, -32(%rbp)
    lea .Lstr_unwrap_file(%rip), %rdi
    mov -16(%rbp), %rsi
    lea .Lstr_unwrap_code(%rip), %rdx
    mov -32(%rbp), %rcx
    call sys_log_err

    mov $3, %rdi
    call exit_program
