.global socket_create
socket_create:
    push %rbp; mov %rsp, %rbp
    mov $41, %rax; mov $2, %rdi; mov $1, %rsi; mov $6, %rdx; syscall
    shl $1, %rax; or $1, %rax; leave; ret

.global socket_bind
socket_bind:
    push %rbp; mov %rsp, %rbp; sub $16, %rsp
    sar $1, %rdi; sar $1, %rsi; mov %rdi, %r8; mov %rsi, %rcx
    movw $2, -16(%rbp); mov %cx, %ax; xchg %al, %ah; movw %ax, -14(%rbp); movl $0, -12(%rbp); movq $0, -8(%rbp)
    mov $49, %rax; mov %r8, %rdi; lea -16(%rbp), %rsi; mov $16, %rdx; syscall
    shl $1, %rax; or $1, %rax; leave; ret

.global socket_listen
socket_listen:
    push %rbp; mov %rsp, %rbp; sar $1, %rdi; mov $50, %rax; mov $10, %rsi; syscall
    shl $1, %rax; or $1, %rax; leave; ret

.global socket_accept
socket_accept:
    push %rbp; mov %rsp, %rbp; sar $1, %rdi; mov $43, %rax; mov $0, %rsi; mov $0, %rdx; syscall
    shl $1, %rax; or $1, %rax; leave; ret

# --- [FIX] Points to read_from_fd ---
.global socket_read
socket_read:
    sar $1, %rdi; jmp read_from_fd

.global socket_write
socket_write:
    sar $1, %rdi; jmp file_write

.global socket_close
socket_close:
    sar $1, %rdi; jmp file_close
