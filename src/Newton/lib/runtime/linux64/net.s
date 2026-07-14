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
    
    sar $1, %rdi     # Untag FD
    sar $1, %rsi     # Untag Port
    sar $1, %rdx     # Untag IP
    
    # 1. Byte-swap the port (htons)
    mov %rsi, %rax
    xchg %al, %ah
    mov %ax, -14(%rbp)     # sin_port
    
    # 2. Build sockaddr_in struct
    movw $2, -16(%rbp)     # sin_family = AF_INET (2)
    movl %edx, -12(%rbp)   # sin_addr = IP Address
    movq $0, -8(%rbp)      # Padding
    
    # 3. Syscall 42: connect
    mov $42, %rax
    lea -16(%rbp), %rsi    # Pointer to struct
    mov $16, %rdx          # Struct length
    syscall
    
    # Tag the return status so Newton can securely check 'if status < 0'
    shl $1, %rax
    or $1, %rax
    leave; ret

# --- ZERO-COPY FILE TRANSFER ---
.global runtime_net_sendfile
runtime_net_sendfile:
    push %rbp
    mov %rsp, %rbp
    
    sar $1, %rdi      # Untag client_fd (out_fd)
    sar $1, %rsi      # Untag file_fd (in_fd)
    sar $1, %rdx      # Untag size
    
    # Linux sys_sendfile expects:
    # rdi = out_fd, rsi = in_fd, rdx = offset ptr, r10 = count
    mov %rdx, %r10    # Move size to %r10
    mov $0, %rdx      # Set offset pointer to NULL (reads from current pos)
    
    mov $40, %rax     # syscall 40: sendfile
    syscall
    
    # Tag the return status (number of bytes written, or negative error)
    shl $1, %rax
    or $1, %rax
    
    leave; ret
