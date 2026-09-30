# --- WINDOWS WINSOCK2 NETWORKING FFI (win_net.s) ---
.extern WSAStartup
.extern socket
.extern bind
.extern listen
.extern accept
.extern closesocket
.extern recv
.extern send
.extern connect
.extern TransmitFile
.extern string_len
.extern _malloc

.section .bss

    wsa_initialized: .quad 0
    wsa_data:        .space 512

.section .text

# --- CREATE SOCKET ---
.global runtime_net_create
runtime_net_create:
    push %rbp; mov %rsp, %rbp
    sub $48, %rsp; and $-16, %rsp
    mov wsa_initialized(%rip), %rax
    test %rax, %rax
    jnz .Lwsa_ready
    mov $0x0202, %rcx
    lea wsa_data(%rip), %rdx
    call WSAStartup
    movq $1, wsa_initialized(%rip)

.Lwsa_ready:
    mov $2, %rcx
    mov $1, %rdx
    mov $6, %r8
    call socket

    shl $1, %rax; or $1, %rax
    leave; ret

# --- BIND ---
.global runtime_net_bind
runtime_net_bind:
    push %rbp; mov %rsp, %rbp
    sub $48, %rsp; and $-16, %rsp
    sar $1, %rdi
    sar $1, %rsi
    mov %rsi, %rax
    xchg %al, %ah
    mov %ax, 34(%rsp)
    movw $2, 32(%rsp)
    movl $0, 36(%rsp)
    movq $0, 40(%rsp)
    mov %rdi, %rcx
    lea 32(%rsp), %rdx
    mov $16, %r8
    call bind

    shl $1, %rax; or $1, %rax
    leave; ret

# --- LISTEN ---
.global runtime_net_listen
runtime_net_listen:
    push %rbp; mov %rsp, %rbp
    sub $32, %rsp; and $-16, %rsp
    sar $1, %rdi
    mov %rdi, %rcx
    mov $10, %rdx
    call listen

    shl $1, %rax; or $1, %rax
    leave; ret

# --- ACCEPT ---
.global runtime_net_accept
runtime_net_accept:
    push %rbp; mov %rsp, %rbp
    sub $32, %rsp; and $-16, %rsp
    sar $1, %rdi
    mov %rdi, %rcx
    mov $0, %rdx
    mov $0, %r8
    call accept

    shl $1, %rax; or $1, %rax
    leave; ret

# --- CLOSE ---
.global runtime_net_close
runtime_net_close:
    push %rbp; mov %rsp, %rbp
    sub $32, %rsp; and $-16, %rsp
    sar $1, %rdi
    mov %rdi, %rcx
    call closesocket

    shl $1, %rax; or $1, %rax
    leave; ret

# --- READ / RECV ---
.global runtime_net_read
runtime_net_read:
    push %rbp; mov %rsp, %rbp
    push %r12; push %r13; push %r14
    sub $48, %rsp; and $-16, %rsp
    sar $1, %rdi
    sar $1, %rsi
    mov %rdi, %r12
    mov %rsi, %r13
    mov %r13, %rdi
    add $9, %rdi
    call _malloc

    movq $1, 0(%rax)
    add $8, %rax
    mov %rax, %r14
    mov %r12, %rcx
    mov %r14, %rdx
    mov %r13, %r8
    mov $0, %r9
    call recv

    mov %rax, %rcx
    cmp $0, %rcx
    jl .Lread_err

    movb $0, (%r14, %rcx)
    mov %r14, %rax
    jmp .Lread_done

.Lread_err:
    mov $1, %rax

.Lread_done:
    lea -24(%rbp), %rsp
    pop %r14; pop %r13; pop %r12
    leave; ret

# --- WRITE / SEND ---
.global runtime_net_write
runtime_net_write:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12
    sub $48, %rsp; and $-16, %rsp
    sar $1, %rdi
    mov %rdi, %rcx
    mov %rsi, %rbx
    mov -8(%rbx), %rax
    cmp $5, %rax
    jne .Lw_ok
    mov 0(%rbx), %rbx

.Lw_ok:
    mov %rbx, %rdx
    push %rcx
    push %rdx
    mov %rbx, %rdi
    call string_len

    mov %rax, %r8
    pop %rdx
    pop %rcx
    mov $0, %r9
    call send

    shl $1, %rax; or $1, %rax
    lea -16(%rbp), %rsp
    pop %r12; pop %rbx
    leave; ret

# --- CONNECT ---
.global runtime_net_connect
runtime_net_connect:
    push %rbp; mov %rsp, %rbp
    sub $48, %rsp; and $-16, %rsp
    sar $1, %rdi
    sar $1, %rsi
    sar $1, %rdx
    mov %rsi, %rax
    xchg %al, %ah
    mov %ax, 34(%rsp)
    movw $2, 32(%rsp)
    movl %edx, 36(%rsp)
    movq $0, 40(%rsp)
    mov %rdi, %rcx
    lea 32(%rsp), %rdx
    mov $16, %r8
    call connect

    shl $1, %rax; or $1, %rax
    leave; ret

# --- ZERO-COPY SENDFILE ---
.global runtime_net_sendfile
runtime_net_sendfile:
    push %rbp; mov %rsp, %rbp
    sub $64, %rsp; and $-16, %rsp
    sar $1, %rdi
    sar $1, %rsi
    sar $1, %rdx
    mov %rdi, %rcx
    mov %rsi, %rdx
    mov %rdx, %r8
    mov $0, %r9
    movq $0, 32(%rsp)
    movq $0, 40(%rsp)
    movq $0, 48(%rsp)
    call TransmitFile

    shl $1, %rax; or $1, %rax
    leave; ret
