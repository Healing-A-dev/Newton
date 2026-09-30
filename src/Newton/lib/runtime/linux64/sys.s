.section .bss
    .global __sys_stack_base
    __sys_stack_base: .quad 0

    .global __argc
    __argc:           .quad 0

    .global __sys_argv
    __sys_argv:       .quad 0

.section .text
.global sys_newton_exit
sys_newton_exit:
    push %rbp
    mov $60, %rax
    mov $0, %rdi
    syscall

.global sys_argc
sys_argc:
    push %rbp
    mov %rsp, %rbp
    mov __argc(%rip), %rax
    shl $1, %rax
    or $1, %rax
    leave
    ret

.global sys_exec
sys_exec:
    push %rbp
    mov %rsp, %rbp
    push %rbx
    push %r12
    mov %rdi, %r12
    push $0
    push %r12

    lea .Lstr_dash_c(%rip), %rax
    push %rax

    lea .Lstr_bin_sh(%rip), %rax
    push %rax

    lea .Lstr_bin_sh(%rip), %rdi
    mov %rsp, %rsi
    mov __argc(%rip), %rax
    inc %rax
    inc %rax
    mov __sys_argv(%rip), %rcx
    lea (%rcx, %rax, 8), %rdx
    mov $59, %rax
    syscall

    pop %rax
    pop %rax
    pop %rax
    pop %rax
    pop %r12
    pop %rbx
    leave
    ret

.global sys_getenv
sys_getenv:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12; push %r13; push %r14
    test %rdi, %rdi
    jz .Lenv_not_found
    mov %rdi, %rax
    and $1, %rax
    jnz .Lenv_not_found
    mov %rdi, %rbx
    mov %rbx, %rdi
    call string_len

    mov %rax, %r12
    test %r12, %r12
    jz .Lenv_not_found

    mov %rbx, %r13
    mov -8(%rbx), %rcx
    cmp $5, %rcx
    jne .Lenv_key_ok

    mov 0(%rbx), %r13

.Lenv_key_ok:
    mov __sys_argv(%rip), %r14
    test %r14, %r14
    jz .Lenv_not_found

    mov __argc(%rip), %rax
    inc %rax
    lea (%r14, %rax, 8), %r14

.Lenv_loop:
    mov (%r14), %rsi
    test %rsi, %rsi
    jz .Lenv_not_found

    mov %r12, %rcx
    mov %r13, %rdi
    cld
    repe cmpsb
    jne .Lenv_next

    cmpb $'=', (%rsi)
    jne .Lenv_next

    inc %rsi
    mov %rsi, %rdi
    call string_new
    jmp .Lenv_done

.Lenv_next:
    add $8, %r14
    jmp .Lenv_loop

.Lenv_not_found:
    mov $1, %rax

.Lenv_done:
    pop %r14; pop %r13; pop %r12; pop %rbx
    leave; ret

.global sys_time_now
sys_time_now:
    push %rbp; mov %rsp, %rbp
    sub $16, %rsp
    mov $228, %rax
    mov $0, %rdi
    mov %rsp, %rsi
    syscall
    mov 0(%rsp), %rax
    mov $1000, %rcx
    mul %rcx
    mov %rax, %r8
    mov 8(%rsp), %rax
    mov $1000000, %rcx
    xor %rdx, %rdx
    div %rcx
    add %r8, %rax
    shl $1, %rax
    or $1, %rax

    leave; ret

 .global sys_argv
 sys_argv:
     push %rbp
     mov %rsp, %rbp
     mov %rdi, %rax
     shr $1, %rax
     inc %rax
     mov __argc(%rip), %r8
     cmp %r8, %rax
     jge .Largv_out_of_bounds

     mov __sys_argv(%rip), %rcx
     mov (%rcx, %rax, 8), %rdi
     call string_new

     leave
     ret

 .Largv_out_of_bounds:
     lea .Lempty_string(%rip), %rdi
     call string_new
     leave
     ret

 .section .rodata
 .Lempty_string: .string ""

.section .rodata
.Lstr_bin_sh: .string "/bin/sh"
.Lstr_dash_c: .string "-c"
