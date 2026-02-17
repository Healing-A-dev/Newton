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
    mov %rax, 60
    syscall


.global sys_exec
sys_exec:
    push %rbp
    mov %rsp, %rbp
    push %rbx
    push %r12
    mov %rdi, %r12      # Command String
    push $0             # NULL terminator
    push %r12           # Command

    lea .Lstr_dash_c(%rip), %rax
    push %rax           # "-c"

    lea .Lstr_bin_sh(%rip), %rax
    push %rax           # "/bin/sh"

    lea .Lstr_bin_sh(%rip), %rdi
    mov %rsp, %rsi

    # RDX = ENVP (NULL)
    mov $0, %rdx
    mov $59, %rax       # sys_execve
    syscall

    # If we get here, exec failed
    pop %rax
    pop %rax
    pop %rax
    pop %rax
    pop %r12
    pop %rbx
    leave
    ret

.section .rodata
.Lstr_bin_sh: .string "/bin/sh"
.Lstr_dash_c: .string "-c"
