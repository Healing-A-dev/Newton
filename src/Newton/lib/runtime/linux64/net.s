.section .text

.global runtime_net_create
runtime_net_create: push %rbp; mov %rsp, %rbp; mov $41, %rax; mov $2, %rdi; mov $1, %rsi; mov $6, %rdx; syscall; shl $1, %rax; or $1, %rax; leave; ret

.global runtime_net_bind
runtime_net_bind: push %rbp; mov %rsp, %rbp; sub $16, %rsp; sar $1, %rdi; sar $1, %rsi; mov %rdi, %r8; mov %rsi, %rcx; movw $2, -16(%rbp); mov %cx, %ax; xchg %al, %ah; movw %ax, -14(%rbp); movl $0, -12(%rbp); movq $0, -8(%rbp); mov $49, %rax; mov %r8, %rdi; lea -16(%rbp), %rsi; mov $16, %rdx; syscall; shl $1, %rax; or $1, %rax; leave; ret

.global runtime_net_listen
runtime_net_listen: push %rbp; mov %rsp, %rbp; sar $1, %rdi; mov $50, %rax; mov $10, %rsi; syscall; shl $1, %rax; or $1, %rax; leave; ret

.global runtime_net_accept
runtime_net_accept: push %rbp; mov %rsp, %rbp; sar $1, %rdi; mov $43, %rax; mov $0, %rsi; mov $0, %rdx; syscall; shl $1, %rax; or $1, %rax; leave; ret

.global runtime_net_recv
runtime_net_recv:
    push %rbp; mov %rsp, %rbp; push %rbx
    sar $1, %rdi; sar $1, %rsi; mov %rdi, %rbx
    mov %rsi, %rdi; add $9, %rdi; call _malloc
    movq $1, 0(%rax); add $8, %rax; mov %rax, %rsi
    mov %rbx, %rdi; mov $0, %rax; mov $1024, %rdx; syscall
    cmp $0, %rax; jl .Lrecv_err
    movb $0, (%rsi, %rax, 1); mov %rsi, %rax
    pop %rbx; leave; ret
.Lrecv_err:
    movb $0, (%rsi); mov %rsi, %rax; pop %rbx; leave; ret

.global runtime_net_send
runtime_net_send: push %rbp; mov %rsp, %rbp; push %rbx; sar $1, %rdi; mov %rdi, %rbx; mov %rsi, %rdi; call string_len; mov %rax, %rdx; mov %rbx, %rdi; mov $1, %rax; syscall; shl $1, %rax; or $1, %rax; pop %rbx; leave; ret

.global runtime_net_close
runtime_net_close: push %rbp; mov %rsp, %rbp; sar $1, %rdi; mov $3, %rax; syscall; shl $1, %rax; or $1, %rax; leave; ret

# --- CONNECT TO SERVER ---
.global runtime_net_connect
runtime_net_connect:
    push %rbp; mov %rsp, %rbp; sub $32, %rsp
    sar $1, %rdi
    sar $1, %rsi
    sar $1, %rdx
    mov %rsi, %rax
    xchg %al, %ah
    mov %ax, -14(%rbp)
    movw $2, -16(%rbp)
    movl %edx, -12(%rbp)
    movq $0, -8(%rbp)
    mov $42, %rax
    lea -16(%rbp), %rsi
    mov $16, %rdx
    syscall
    shl $1, %rax
    or $1, %rax
    leave; ret

# --- ZERO-COPY FILE TRANSFER ---
.global runtime_net_sendfile
runtime_net_sendfile:
    push %rbp
    mov %rsp, %rbp
    sar $1, %rdi
    sar $1, %rsi
    sar $1, %rdx
    mov %rdx, %r10
    mov $0, %rdx
    mov $40, %rax
    syscall
    shl $1, %rax
    or $1, %rax
    leave; ret
