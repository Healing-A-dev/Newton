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
    # We must lazily initialize WinSock2 once per program execution!
    wsa_initialized: .quad 0
    wsa_data:        .space 512

.section .text

# --- CREATE SOCKET ---
.global runtime_net_create
runtime_net_create:
    push %rbp; mov %rsp, %rbp
    sub $48, %rsp; and $-16, %rsp

    # 1. Check if WSAStartup has already been called
    mov wsa_initialized(%rip), %rax
    test %rax, %rax
    jnz .Lwsa_ready

    # 2. Call WSAStartup(MAKEWORD(2,2), &wsa_data)
    mov $0x0202, %rcx
    lea wsa_data(%rip), %rdx
    call WSAStartup
    movq $1, wsa_initialized(%rip)

.Lwsa_ready:
    # 3. Call socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
    mov $2, %rcx
    mov $1, %rdx
    mov $6, %r8
    call socket

    # Tag the returned SOCKET handle as a Newton Integer
    shl $1, %rax; or $1, %rax
    leave; ret

# --- BIND ---
.global runtime_net_bind
runtime_net_bind:
    push %rbp; mov %rsp, %rbp
    sub $48, %rsp; and $-16, %rsp

    sar $1, %rdi      # Untag SOCKET
    sar $1, %rsi      # Untag Port

    # 1. Byte-swap the port (htons)
    mov %rsi, %rax
    xchg %al, %ah
    mov %ax, 34(%rsp)      # sin_port

    # 2. Build sockaddr_in struct
    movw $2, 32(%rsp)      # sin_family = AF_INET (2)
    movl $0, 36(%rsp)      # sin_addr = INADDR_ANY (0)
    movq $0, 40(%rsp)      # Padding

    # 3. bind(s, name, namelen)
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
    mov %rdi, %rcx      # SOCKET
    mov $10, %rdx       # Backlog
    call listen

    shl $1, %rax; or $1, %rax
    leave; ret

# --- ACCEPT ---
.global runtime_net_accept
runtime_net_accept:
    push %rbp; mov %rsp, %rbp
    sub $32, %rsp; and $-16, %rsp

    sar $1, %rdi
    mov %rdi, %rcx      # SOCKET
    mov $0, %rdx        # NULL sockaddr
    mov $0, %r8         # NULL addrlen
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
    call closesocket    # [CRITICAL] Windows requires closesocket, not close!

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
    mov %rdi, %r12      # SOCKET
    mov %rsi, %r13      # Length

    # Allocate GC-Safe String Buffer
    mov %r13, %rdi
    add $9, %rdi
    call _malloc
    movq $1, 0(%rax)    # Tag as Type 1 String
    add $8, %rax
    mov %rax, %r14

    # recv(s, buf, len, flags)
    mov %r12, %rcx
    mov %r14, %rdx
    mov %r13, %r8
    mov $0, %r9
    call recv

    # Check for error / EOF
    mov %rax, %rcx
    cmp $0, %rcx
    jl .Lread_err

    # Null Terminate Securely
    movb $0, (%r14, %rcx)
    mov %r14, %rax
    jmp .Lread_done

.Lread_err:
    mov $1, %rax        # Return Tagged 0

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
    mov %rdi, %rcx      # SOCKET
    mov %rsi, %rbx      # Newton String Object

    # 1. Resolve String View (if it's a slice)
    mov -8(%rbx), %rax
    cmp $5, %rax
    jne .Lw_ok
    mov 0(%rbx), %rbx
.Lw_ok:
    mov %rbx, %rdx      # Buffer Pointer

    # 2. Get true string length natively
    push %rcx
    push %rdx
    mov %rbx, %rdi
    call string_len
    mov %rax, %r8       # Length
    pop %rdx
    pop %rcx

    # 3. send(s, buf, len, flags)
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

    # Byte-swap the port
    mov %rsi, %rax
    xchg %al, %ah
    mov %ax, 34(%rsp)

    # Build sockaddr_in
    movw $2, 32(%rsp)
    movl %edx, 36(%rsp)
    movq $0, 40(%rsp)

    # connect(s, name, namelen)
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

    # TransmitFile(hSocket, hFile, nNumberOfBytesToWrite, nNumberOfBytesPerSend, lpOverlapped, lpTransmitBuffers, dwReserved)
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
