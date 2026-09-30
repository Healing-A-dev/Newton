.section .data
    .global gc_threshold
    gc_threshold:    .quad 2097152

.section .bss
    .global current_brk
    current_brk:     .quad 0
    .global current_slab_end
    current_slab_end:.quad 0

    .global free_list_head
    free_list_head:  .quad 0
    .global gc_head
    gc_head:         .quad 0
    .global slabs_head
    slabs_head:      .quad 0

    .global bytes_allocated
    bytes_allocated: .quad 0

    # --- INCREMENTAL GC STATE ---
    .global grey_stack
    grey_stack:      .space 8192
    .global grey_count
    grey_count:      .quad 0
    .global gc_phase
    gc_phase:        .quad 0

.section .text

# --- MEMORY ALLOCATOR ---
.global _malloc
_malloc:
    push %rbp
    mov %rsp, %rbp
    push %rbx
    push %r12
    push %r13

    # --- INITIALIZE STACK BASE IF 0 ---
    mov __sys_stack_base(%rip), %rax
    test %rax, %rax
    jnz .Lmalloc_update_bytes
    # Safe fallback: If the entrypoint didn't set __sys_stack_base,
    mov %rsp, %rax
    add $65536, %rax
    mov %rax, __sys_stack_base(%rip)

.Lmalloc_update_bytes:
    mov bytes_allocated(%rip), %rax
    add %rdi, %rax
    mov %rax, bytes_allocated(%rip)

    mov gc_phase(%rip), %rax
    cmp $1, %rax
    je .Lmalloc_step

    mov bytes_allocated(%rip), %rax
    cmp gc_threshold(%rip), %rax
    jl .Lmalloc_align

    movq $1, gc_phase(%rip)
    movq $0, bytes_allocated(%rip)
    push %rdi
    call seed_roots
    pop %rdi
    jmp .Lmalloc_step

.Lmalloc_step:
    push %rdi
    call gc_step
    pop %rdi

.Lmalloc_align:
    add $15, %rdi
    and $-16, %rdi
    mov %rdi, %r12
    mov %r12, %r13
    add $16, %r13

    lea free_list_head(%rip), %rbx
.Lsearch_loop:
    mov (%rbx), %rax
    test %rax, %rax
    jz .Lalloc_new

    mov 8(%rax), %rcx
    cmp %r13, %rcx
    jge .Lrecycle

    lea 0(%rax), %rbx
    jmp .Lsearch_loop

.Lrecycle:
    mov 0(%rax), %rdx
    mov %rdx, (%rbx)
    mov %rax, %rbx
    jmp .Linit_header

.Lalloc_new:
    mov current_brk(%rip), %rbx
    test %rbx, %rbx
    jz .Lnew_slab

    lea (%rbx, %r13), %rdi
    cmp current_slab_end(%rip), %rdi
    jae .Lnew_slab

    mov %rdi, current_brk(%rip)
    mov %r13, 8(%rbx)
    jmp .Linit_header

.Lnew_slab:
    mov $2097152, %rsi
    lea 16(%r13), %rcx
    cmp %rsi, %rcx
    jle .Ldo_mmap
    mov %rcx, %rsi

.Ldo_mmap:
    push %rsi
    mov $9, %rax
    mov $0, %rdi
    mov $3, %rdx
    mov $34, %r10
    mov $-1, %r8
    mov $0, %r9
    syscall

    pop %rsi
    mov slabs_head(%rip), %rdx
    mov %rdx, 0(%rax)
    mov %rax, slabs_head(%rip)
    mov %rax, %rcx
    add %rsi, %rcx
    mov %rcx, 8(%rax)
    lea 16(%rax), %rbx
    lea (%rbx, %r13), %rdi
    mov %rdi, current_brk(%rip)
    mov %rcx, current_slab_end(%rip)
    mov %r13, 8(%rbx)

.Linit_header:
    mov gc_head(%rip), %rax
    mov %rax, 0(%rbx)
    mov %rbx, gc_head(%rip)
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
    sub $24, %rdi
    mov free_list_head(%rip), %rax
    mov %rax, 0(%rdi)
    mov %rdi, free_list_head(%rip)

.Lfree_done:
    ret

# --- PROTECT .RODATA ---
.global is_heap_ptr
is_heap_ptr:
    mov slabs_head(%rip), %rcx

.Lihp_loop:
    test %rcx, %rcx
    jz .Lihp_false
    cmp %rcx, %rdi
    jb .Lihp_next
    mov 8(%rcx), %r8
    cmp %r8, %rdi
    jae .Lihp_next
    mov $1, %rax
    ret

.Lihp_next:
    mov 0(%rcx), %rcx
    jmp .Lihp_loop

.Lihp_false:
    xor %rax, %rax
    ret

# Safely verifies a stack address is a real heap object
.global make_grey_conservative
make_grey_conservative:
    push %rbp; mov %rsp, %rbp
    test %rdi, %rdi; jz .Lmgc_done
    mov gc_head(%rip), %rcx

.Lmgc_loop:
    test %rcx, %rcx
    jz .Lmgc_done

    lea 24(%rcx), %r8
    cmp %r8, %rdi
    je .Lmgc_found

    mov 0(%rcx), %rcx
    jmp .Lmgc_loop

.Lmgc_found:
    call make_grey

.Lmgc_done:
    leave; ret

.global make_grey
make_grey:
    push %rbp; mov %rsp, %rbp
    test %rdi, %rdi; jz .Lmg_done
    push %rdi; push %rcx; push %r8
    call is_heap_ptr

    test %rax, %rax
    pop %r8; pop %rcx; pop %rdi
    jz .Lmg_done

    mov %rdi, %rax
    sub $24, %rax
    mov 8(%rax), %rcx
    bt $63, %rcx
    jc .Lmg_done

    bts $63, %rcx
    mov %rcx, 8(%rax)
    mov grey_count(%rip), %rcx
    cmp $1000, %rcx
    jge .Lmg_done

    lea grey_stack(%rip), %r8
    mov %rdi, (%r8, %rcx, 8)
    inc %rcx
    mov %rcx, grey_count(%rip)

.Lmg_done:
    leave; ret

.global gc_step
gc_step:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12
    mov $10, %r12

.Lstep_loop:
    mov grey_count(%rip), %rcx
    test %rcx, %rcx
    jz .Lstep_empty

    dec %rcx
    mov %rcx, grey_count(%rip)
    lea grey_stack(%rip), %r8
    mov (%r8, %rcx, 8), %rdi
    mov -8(%rdi), %rdx
    cmp $3, %rdx
    je .Lstep_array

    cmp $2, %rdx
    je .Lstep_map
    jmp .Lstep_next

    cmp $6, %rdx
    je .Lstep_map_node
    jmp .Lstep_next

.Lstep_next:
    dec %r12
    jnz .Lstep_loop
    jmp .Lstep_done

.Lstep_empty:
    movq $0, gc_phase(%rip)
    call gc_sweep

.Lstep_done:
    pop %r12; pop %rbx
    leave; ret

.Lstep_array:
    mov 0(%rdi), %rcx
    lea 8(%rdi), %rsi

.Lsa_loop:
    test %rcx, %rcx; jz .Lstep_next
    mov (%rsi), %rdi
    test $1, %rdi; jnz .Lsa_skip
    push %rcx; push %rsi; push %r12
    call make_grey
    pop %r12; pop %rsi; pop %rcx

.Lsa_skip:
    add $8, %rsi
    dec %rcx
    jmp .Lsa_loop

.Lstep_map:
    mov (%rdi), %rsi

.Lsm_loop:
    test %rsi, %rsi; jz .Lstep_next
    push %rsi; push %r12
    mov %rsi, %rdi
    call make_grey

    pop %r12; pop %rsi
    mov 0(%rsi), %rdi
    test $1, %rdi; jnz .Lsm_skip_key
    push %rsi; push %r12
    call make_grey

    pop %r12; pop %rsi

.Lsm_skip_key:
    mov 8(%rsi), %rdi
    test $1, %rdi; jnz .Lsm_skip_val
    push %rsi; push %r12
    call make_grey
    pop %r12; pop %rsi

.Lsm_skip_val:
    mov 16(%rsi), %rsi
    jmp .Lsm_loop

.Lstep_map_node:
    mov %rdi, %rsi
    mov 0(%rsi), %rdi
    test $1, %rdi
    jnz .Lstep_mn_val
    push %rsi; push %r12
    call make_grey
    pop %r12; pop %rsi

.Lstep_mn_val:
    mov 8(%rsi), %rdi
    test $1, %rdi
    jnz .Lstep_mn_next
    push %rsi; push %r12
    call make_grey
    pop %r12; pop %rsi

.Lstep_mn_next:
    mov 16(%rsi), %rdi
    test %rdi, %rdi
    jz .Lstep_next
    push %rsi; push %r12
    call make_grey
    pop %r12; pop %rsi
    jmp .Lstep_next


.global seed_roots
seed_roots:
    push %rbp; mov %rsp, %rbp
    mov __sys_stack_base(%rip), %rcx
    mov %rsp, %rsi

.Lseed_loop:
    cmp %rsi, %rcx
    jbe .Lseed_done
    mov (%rsi), %rdi
    test $1, %rdi
    jnz .Lseed_next
    push %rsi; push %rcx
    call make_grey_conservative
    pop %rcx; pop %rsi

.Lseed_next:
    add $8, %rsi
    jmp .Lseed_loop

.Lseed_done:
    leave; ret


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

    mov 0(%rax), %rdx
    mov %rdx, (%rbx)
    mov free_list_head(%rip), %r9
    mov %r9, 0(%rax)
    mov %rax, free_list_head(%rip)
    jmp .Lsweep_loop

.Lsweep_unmark:
    btr $63, %rcx
    mov %rcx, 8(%rax)
    lea 0(%rax), %rbx
    jmp .Lsweep_loop

.Lsweep_done:
    leave
    ret

.global gc_collect
gc_collect:
    push %rbp; mov %rsp, %rbp
    movq $1, gc_phase(%rip)
    call seed_roots

.Lforce_mark_loop:
    mov grey_count(%rip), %rcx
    test %rcx, %rcx
    jz .Lforce_sweep
    call gc_step
    jmp .Lforce_mark_loop

.Lforce_sweep:
    leave; ret
