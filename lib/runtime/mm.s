.section .data
    # GC Configuration
    .global gc_threshold
    gc_threshold:    .quad 65536

.section .bss
    .global current_brk
    current_brk:     .quad 0

    .global free_list_head
    free_list_head:  .quad 0

    .global gc_head
    gc_head:         .quad 0

    .global heap_start
    heap_start:      .quad 0

    .global heap_end
    heap_end:        .quad 0

    .global bytes_allocated
    bytes_allocated: .quad 0

.section .text

# --- MEMORY ALLOCATOR ---
.global _malloc
_malloc:
    push %rbp
    mov %rsp, %rbp
    push %rbx
    push %r12
    push %r13

    # 1. GC Trigger Check
    mov bytes_allocated(%rip), %rax
    add %rdi, %rax
    mov %rax, bytes_allocated(%rip)

    cmp gc_threshold(%rip), %rax
    jl .Lmalloc_align

    # Trigger GC
    push %rdi
    call gc_collect
    pop %rdi
    movq $0, bytes_allocated(%rip)

.Lmalloc_align:
    # 2. Align Size
    add $15, %rdi
    and $-16, %rdi
    mov %rdi, %r12
    mov %r12, %r13
    add $16, %r13

    # 3. Search Free List
    lea free_list_head(%rip), %rbx

.Lsearch_loop:
    mov (%rbx), %rax
    test %rax, %rax
    jz .Lalloc_new

    mov (%rax), %rcx
    cmp %r13, %rcx
    jge .Lrecycle

    lea 8(%rax), %rbx
    jmp .Lsearch_loop

.Lrecycle:
    mov 8(%rax), %rdx
    mov %rdx, (%rbx)
    sub $8, %rax
    mov %rax, %rbx
    jmp .Linit_header

.Lalloc_new:
    cmpq $0, heap_start(%rip)
    jne .Lbump
    mov $12, %rax
    xor %rdi, %rdi
    syscall
    mov %rax, heap_start(%rip)

.Lbump:
    mov $12, %rax
    xor %rdi, %rdi
    syscall
    mov %rax, %rbx

    lea (%rbx, %r13), %rdi
    mov $12, %rax
    syscall

    mov %rax, heap_end(%rip)
    mov %r13, 8(%rbx)

.Linit_header:
    mov gc_head(%rip), %rax
    mov %rax, 0(%rbx)
    mov %rbx, gc_head(%rip)

    # Zeroing Logic
    lea 16(%rbx), %rax
    push %rax
    push %rcx
    push %rdi
    mov %rax, %rdi
    mov %r13, %rcx
    sub $16, %rcx
    xor %rax, %rax
    rep stosb
    pop %rdi
    pop %rcx
    pop %rax

    pop %r13
    pop %r12
    pop %rbx
    leave
    ret

.global _free
_free:
    test %rdi, %rdi
    jz .Lfree_done
    sub $8, %rdi
    mov free_list_head(%rip), %rax
    mov %rax, 8(%rdi)
    mov %rdi, free_list_head(%rip)
.Lfree_done:
    ret

# --- GARBAGE COLLECTOR ---
.global gc_sweep
gc_sweep:
    push %rbp
    mov %rsp, %rbp
    lea gc_head(%rip), %rbx

.Lsweep_loop:
    mov (%rbx), %rax
    test %rax, %rax
    jz .Lsweep_done

    mov 8(%rax), %rcx
    bt $63, %rcx
    jc .Lsweep_unmark

    # Reclaim
    mov 0(%rax), %rdx
    mov %rdx, (%rbx)

    lea 8(%rax), %r8
    mov free_list_head(%rip), %r9
    mov %r9, 8(%r8)
    mov %r8, free_list_head(%rip)
    jmp .Lsweep_loop

.Lsweep_unmark:
    btr $63, %rcx
    mov %rcx, 8(%rax)
    lea 0(%rax), %rbx
    jmp .Lsweep_loop

.Lsweep_done:
    leave
    ret

.global gc_mark
gc_mark:
    push %rbp
    mov %rsp, %rbp

    # 1. Bounds Check
    cmp heap_start(%rip), %rdi
    jb .Lmark_done
    cmp heap_end(%rip), %rdi
    jae .Lmark_done

    # [CRITICAL FIX] Alignment Check
    # Objects are at Block + 24 (ends in 8).
    # Raw pointers are at Block + 16 (ends in 0).
    # We MUST ignore raw pointers to prevent heap corruption.
    test $8, %rdi
    jz .Lmark_done

    # 2. Find Block Start
    mov %rdi, %rax
    sub $24, %rax

    # 3. Check Mark Bit
    mov 8(%rax), %rcx
    bt $63, %rcx
    jc .Lmark_done

    # 4. Set Mark Bit
    bts $63, %rcx
    mov %rcx, 8(%rax)

    # 5. Scan Children
    mov -8(%rdi), %rdx

    cmp $3, %rdx         # Type 3 = Array
    je .Lmark_array

    jmp .Lmark_done

.Lmark_array:
    mov (%rdi), %rcx     # Length
    lea 16(%rdi), %rsi   # Data

.Lmark_array_loop:
    test %rcx, %rcx
    jz .Lmark_done

    mov (%rsi), %rdi
    test $1, %rdi        # Check tag
    jnz .Lmark_skip_element

    push %rsi
    push %rcx
    call gc_mark
    pop %rcx
    pop %rsi

.Lmark_skip_element:
    add $8, %rsi
    dec %rcx
    jmp .Lmark_array_loop

.Lmark_done:
    leave
    ret

.global gc_collect
gc_collect:
    push %rbp
    mov %rsp, %rbp
    mov %rsp, %rsi
    mov __sys_stack_base(%rip), %rcx

.Lroot_loop:
    cmp %rsi, %rcx
    jbe .Lroot_done
    mov (%rsi), %rdi
    cmp heap_start(%rip), %rdi
    jb .Lnext_root
    cmp heap_end(%rip), %rdi
    jae .Lnext_root

    # Check for tagged ints
    test $1, %rdi
    jnz .Lnext_root

    push %rsi
    push %rcx
    call gc_mark
    pop %rcx
    pop %rsi
.Lnext_root:
    add $8, %rsi
    jmp .Lroot_loop

.Lroot_done:
    call gc_sweep
    leave
    ret
