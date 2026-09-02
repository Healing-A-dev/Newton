# --- WINDOWS FILE I/O FFI (win64/file.s) ---
.extern CreateFileA
.extern ReadFile
.extern CloseHandle
.extern _malloc
.extern _write

.section .bss
.align 8
line_header:  .space 8
line_buffer:  .space 4096
chunk_buffer: .space 8192
chunk_size:   .quad 0
chunk_ptr:    .quad 0
bytes_read:   .quad 0

.section .text

# ---------------------------------------------------------
# FILE OPENING
# Usage in Newton: sys_open $path, $flag
# ---------------------------------------------------------
.global newton_fopen
newton_fopen:
    push %rbp; mov %rsp, %rbp

    and $-2, %rdi         # Untag filename pointer

    # 1. Allocate 64 bytes to align stack to 16-bytes and fit 7 arguments!
    # (32 bytes Shadow Space + 24 bytes for 5th, 6th, and 7th arguments)
    sub $64, %rsp

    # 2. Setup CreateFileA Arguments
    mov %rdi, %rcx        # Arg 1: lpFileName (Our string)
    mov $0x80000000, %rdx # Arg 2: dwDesiredAccess = GENERIC_READ
    mov $1, %r8           # Arg 3: dwShareMode = FILE_SHARE_READ
    mov $0, %r9           # Arg 4: lpSecurityAttributes = NULL
    movq $3, 32(%rsp)     # Arg 5: dwCreationDisposition = OPEN_EXISTING (3)
    movq $128, 40(%rsp)   # Arg 6: dwFlagsAndAttributes = FILE_ATTRIBUTE_NORMAL (128)
    movq $0, 48(%rsp)     # Arg 7: hTemplateFile = NULL

    call CreateFileA

    # Check for INVALID_HANDLE_VALUE (-1)
    cmp $-1, %rax
    je .Lfo_err

    # Reset our chunk readers
    movq $0, chunk_size(%rip)
    movq $0, chunk_ptr(%rip)

    # Tag the Windows HANDLE as a Newton Integer
    shl $1, %rax
    or $1, %rax
    leave; ret

.Lfo_err:
    mov $1, %rax          # Tagged 0 (Failure)
    leave; ret


# ---------------------------------------------------------
# FILE READING
# Usage in Newton: sys_read $fd
# ---------------------------------------------------------
.global newton_getline
newton_getline:
    push %rbp; mov %rsp, %rbp
    push %r12
    push %r13

    # Allocate 48 bytes (Shadow Space + Alignment)
    sub $48, %rsp

    cmp $1, %rdi
    je .Lgl_eof_pop

    sar $1, %rdi
    mov %rdi, %r12     # R12 = Windows HANDLE

    lea line_buffer(%rip), %r13
    xor %r10, %r10

.Lgl_loop:
    mov chunk_ptr(%rip), %rcx
    cmp chunk_size(%rip), %rcx
    jl .Lgl_read_byte

    # --- CALL WINDOWS ReadFile ---
    mov %r12, %rcx            # Arg 1: hFile (The HANDLE)
    lea chunk_buffer(%rip), %rdx # Arg 2: lpBuffer (Where to put the bytes)
    mov $8192, %r8            # Arg 3: nNumberOfBytesToRead
    lea bytes_read(%rip), %r9 # Arg 4: lpNumberOfBytesRead
    movq $0, 32(%rsp)         # Arg 5: lpOverlapped = NULL
    call ReadFile

    # If ReadFile fails (returns 0), we hit EOF
    cmp $0, %rax
    je .Lgl_end_of_file

    # If bytes_read == 0, we hit EOF
    mov bytes_read(%rip), %rax
    cmp $0, %rax
    je .Lgl_end_of_file

    mov %rax, chunk_size(%rip)
    movq $0, chunk_ptr(%rip)
    movq $0, %rcx

.Lgl_read_byte:
    lea chunk_buffer(%rip), %rsi
    movb (%rsi, %rcx), %al

    inc %rcx
    mov %rcx, chunk_ptr(%rip)

    cmpb $10, %al; je .Lgl_done_line     # '\n' -> Line complete!
    cmpb $13, %al; je .Lgl_loop          # '\r' -> Ignore and skip!

    movb %al, 0(%r13, %r10)
    inc %r10

    cmp $4095, %r10
    jge .Lgl_done_line

    jmp .Lgl_loop

.Lgl_end_of_file:
    test %r10, %r10
    jz .Lgl_eof_pop

.Lgl_done_line:
    mov %r10, %rdi
    add $9, %rdi

    # Preserve Caller-saved registers before calling _malloc
    push %r10
    call _malloc
    pop %r10

    movq $1, 0(%rax)
    add $8, %rax

    mov %r10, %rcx
    test %rcx, %rcx
    jz .Lgl_null_term

    push %rdi
    mov %rax, %rdi
    lea line_buffer(%rip), %rsi
    rep movsb
    mov %rdi, %rax
    pop %rdi
    sub %r10, %rax

.Lgl_null_term:
    movb $0, (%rax, %r10)
    jmp .Lgl_cleanup

.Lgl_eof_pop:
    mov $1, %rax     # Tagged 0

.Lgl_cleanup:
    lea -16(%rbp), %rsp
    pop %r13
    pop %r12
    leave; ret

.global sys_write_bytes
.extern WriteFile

sys_write_bytes:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12; push %r13; push %r14

    # Allocate 48 bytes of Windows Stack Space
    # (32 shadow + 8 for Arg 5 + 8 for lpNumberOfBytesWritten)
    sub $48, %rsp
    and $-16, %rsp       # Ensure strict 16-byte alignment

    # 1. Untag File Descriptor (Arg 1 is now %rcx)
    sar $1, %rcx
    mov %rcx, %r12       # R12 now holds the Windows HANDLE

    # 2. Check if Array is valid (Arg 2 is now %rdx)
    test %rdx, %rdx; jz .Lwb_done
    mov %rdx, %rax; and $1, %rax; jnz .Lwb_done
    mov -8(%rdx), %rax; cmp $3, %rax; jne .Lwb_done

    # 3. Read Array Length and Buffer Pointer
    mov 0(%rdx), %r13    # True Length
    test %r13, %r13; jz .Lwb_done
    lea 8(%rdx), %r14    # Elements Buffer

    # 4. Allocate temporary raw byte buffer
    mov %r13, %rcx       # Windows Arg 1: count
    call _malloc
    mov %rax, %rbx

    # 5. Extract bytes from Array
    xor %rcx, %rcx       # Using %rcx as our loop counter
.Lwb_loop:
    cmp %rcx, %r13
    je .Lwb_do_write
    mov (%r14, %rcx, 8), %rax
    sar $1, %rax         # Untag Newton Integer!
    movb %al, (%rbx, %rcx) # Store just the lowest 8 bits
    inc %rcx
    jmp .Lwb_loop

.Lwb_do_write:
    # 6. Call Windows WriteFile(hFile, lpBuffer, nBytesToWrite, lpBytesWritten, lpOverlapped)
    mov %r12, %rcx       # Arg 1: hFile (The HANDLE)
    mov %rbx, %rdx       # Arg 2: lpBuffer
    mov %r13, %r8        # Arg 3: nNumberOfBytesToWrite
    lea 40(%rsp), %r9    # Arg 4: lpNumberOfBytesWritten (Local stack pointer)
    movq $0, 32(%rsp)    # Arg 5: lpOverlapped = NULL
    call WriteFile

    # 7. Free the temporary byte buffer
    mov %rbx, %rcx       # Windows Arg 1: pointer
    call _free

.Lwb_done:
    mov $3, %rax         # Return Tagged 1 (Success)

    # Safely restore the stack bypassing the 48-byte allocation
    lea -32(%rbp), %rsp
    pop %r14; pop %r13; pop %r12; pop %rbx
    leave; ret
