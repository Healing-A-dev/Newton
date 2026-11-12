.section .data
    .global gc_threshold
    gc_threshold:    .quad 67108864       # Initial threshold: 64 MB
    .global min_heap_addr
    min_heap_addr:   .quad 0
    .global max_heap_addr
    max_heap_addr:   .quad 0

.section .bss
    .global current_brk
    current_brk:     .quad 0
    .global current_slab_end
    current_slab_end:.quad 0

    .global free_bins
    free_bins:       .space 256          # 32 segregated size-class bin heads (32 * 8 bytes)
    .global free_list_head
    free_list_head:  .quad 0
    .global gc_head
    gc_head:         .quad 0
    .global slabs_head
    slabs_head:      .quad 0

    .global bytes_allocated
    bytes_allocated: .quad 0

    # --- MARK-SWEEP GC STATE ---
    .global grey_stack
    grey_stack:      .space 2097152      # 2 MB grey stack (262,144 pointers)
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
    mov %rsp, %rax
    add $65536, %rax
    mov %rax, __sys_stack_base(%rip)

.Lmalloc_update_bytes:
    mov bytes_allocated(%rip), %rax
    add %rdi, %rax
    mov %rax, bytes_allocated(%rip)

    # Trigger GC cycle if threshold exceeded
    cmp gc_threshold(%rip), %rax
    jl .Lmalloc_align

    push %rdi
    call gc_collect
    pop %rdi

.Lmalloc_align:
    add $15, %rdi
    and $-16, %rdi
    test %rdi, %rdi
    jnz 1f
    mov $16, %rdi
1:
    mov %rdi, %r12
    mov %r12, %r13
    add $16, %r13                       # 16-byte metadata header [next | size]

    # Segregated size-class bin lookup:
    # Bins 0..30: exact sizes 32, 48, 64, ..., 512 (bin_idx = (r13 - 32) >> 4)
    # Bin 31: large blocks (> 512 bytes)
    lea -32(%r13), %rax
    shr $4, %rax
    cmp $30, %rax
    jbe .Lbin_exact
    mov $31, %rax

.Lbin_exact:
    lea free_bins(%rip), %rdx
    lea (%rdx, %rax, 8), %rbx           # %rbx = &free_bins[bin_idx]
    cmp $31, %rax
    je .Lsearch_large

    # O(1) pop from exact bin
    mov (%rbx), %rax
    test %rax, %rax
    jz .Lalloc_new
    mov (%rax), %rdx
    mov %rdx, (%rbx)
    mov %rax, %rbx
    mov %r13, 8(%rbx)                   # Store clean chunk size
    jmp .Linit_header

.Lsearch_large:
    mov $16, %r11                       # bound search to at most 16 hops
.Lsearch_loop:
    test %r11, %r11
    jz .Lalloc_new
    dec %r11
    mov (%rbx), %rax
    test %rax, %rax
    jz .Lalloc_new

    mov 8(%rax), %rcx
    btr $62, %rcx                       # strip any freed flag
    btr $63, %rcx                       # strip any mark bit
    cmp %r13, %rcx
    jge .Lrecycle

    lea 0(%rax), %rbx
    jmp .Lsearch_loop

.Lrecycle:
    mov 0(%rax), %rdx
    mov %rdx, (%rbx)
    mov %rax, %rbx
    mov %rcx, 8(%rbx)                   # Store clean size (flags stripped)
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
    mov $2097152, %rsi                  # 2 MB default slab
    lea 16(%r13), %rcx
    cmp %rsi, %rcx
    jle .Ldo_mmap
    mov %rcx, %rsi

.Ldo_mmap:
    push %rsi
    mov $9, %rax                        # sys_mmap
    mov $0, %rdi                        # addr = NULL
    mov $3, %rdx                        # PROT_READ | PROT_WRITE
    mov $34, %r10                       # MAP_PRIVATE | MAP_ANONYMOUS
    mov $-1, %r8                        # fd = -1
    mov $0, %r9                         # offset = 0
    syscall
    pop %rsi

    # Update global heap address bounds
    mov min_heap_addr(%rip), %rdx
    test %rdx, %rdx
    jz .Lfirst_slab_min
    cmp %rax, %rdx
    jbe .Lcheck_max_bound
.Lfirst_slab_min:
    mov %rax, min_heap_addr(%rip)
.Lcheck_max_bound:
    mov %rax, %rcx
    add %rsi, %rcx                      # rcx = slab_end
    mov max_heap_addr(%rip), %rdx
    cmp %rcx, %rdx
    jae .Llink_slab
    mov %rcx, max_heap_addr(%rip)

.Llink_slab:
    mov slabs_head(%rip), %rdx
    mov %rdx, 0(%rax)
    mov %rax, slabs_head(%rip)
    mov %rcx, 8(%rax)                   # 8(slab) = slab_end

    lea 16(%rax), %rbx                  # rbx = first object header in slab
    lea (%rbx, %r13), %rdi
    mov %rdi, current_brk(%rip)
    mov %rcx, current_slab_end(%rip)
    mov %r13, 8(%rbx)

.Linit_header:
    mov gc_head(%rip), %rax
    # Guard: ensure gc_head is valid before storing
    test %rax, %rax
    jz 1f
    cmp min_heap_addr(%rip), %rax
    jb .Linit_reset_head
    cmp max_heap_addr(%rip), %rax
    jae .Linit_reset_head
    test $15, %rax
    jnz .Linit_reset_head
    jmp 1f
.Linit_reset_head:
    xor %rax, %rax
1:
    mov %rax, 0(%rbx)
    mov %rbx, gc_head(%rip)
    lea 16(%rbx), %rax                  # User pointer = rbx + 16

    # Zero-initialize full payload (up to actual chunk size)
    push %rax
    push %rcx
    push %rdi
    mov %rax, %rdi
    mov 8(%rbx), %rcx
    btr $62, %rcx
    btr $63, %rcx
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
    mov %rdi, %rax
    and $15, %rax
    cmp $8, %rax
    je .Lfree_user
    sub $16, %rdi                       # Malloc pointer (chunk + 16)
    jmp .Lfree_chunk
.Lfree_user:
    sub $24, %rdi                       # User pointer (chunk + 24)
.Lfree_chunk:
    btsq $62, 8(%rdi)                   # Mark bit 62: manually freed
    btrq $63, 8(%rdi)                   # Ensure unmark; gc_sweep reclaims to free_list_head
.Lfree_done:
    ret

# --- FAST HEAP POINTER VALIDATION ---
.global is_heap_ptr
is_heap_ptr:
    test %rdi, %rdi
    jz .Lihp_false
    test $1, %rdi
    jnz .Lihp_false

    # Newton user pointers are always chunk + 24, where chunk is 16-byte aligned.
    # Therefore, (user_ptr & 15) must be 8.
    mov %rdi, %rax
    and $15, %rax
    cmp $8, %rax
    jne .Lihp_false

    # O(1) global bounds check
    cmp min_heap_addr(%rip), %rdi
    jb .Lihp_false
    cmp max_heap_addr(%rip), %rdi
    jae .Lihp_false

    # Verify pointer falls inside one of the allocated slabs
    mov slabs_head(%rip), %rcx
.Lihp_loop:
    test %rcx, %rcx
    jz .Lihp_false
    lea 24(%rcx), %rax
    cmp %rax, %rdi
    jb .Lihp_next
    cmp 8(%rcx), %rdi
    jae .Lihp_next

    # Check type tag at user_ptr - 8 (must be 1..7)
    mov -8(%rdi), %rdx
    cmp $1, %rdx
    jl .Lihp_next
    cmp $7, %rdx
    jg .Lihp_next

    # Check chunk size at user_ptr - 16 (size >= 32, size <= 1GB, aligned by 16)
    mov -16(%rdi), %rdx
    btr $62, %rdx
    btr $63, %rdx
    cmp $32, %rdx
    jl .Lihp_next
    cmp $1073741824, %rdx
    jg .Lihp_next
    test $15, %rdx
    jnz .Lihp_next

    # Valid user object!
    mov $1, %rax
    ret

.Lihp_next:
    mov 0(%rcx), %rcx
    jmp .Lihp_loop

.Lihp_false:
    xor %rax, %rax
    ret

# --- MARK STAGE ---
.global make_grey_conservative
make_grey_conservative:
    jmp make_grey

.global make_grey
make_grey:
    push %rbp
    mov %rsp, %rbp
    cmpq $0, gc_phase(%rip)
    jz .Lmg_done
    test %rdi, %rdi
    jz .Lmg_done
    test $1, %rdi
    jnz .Lmg_done

    push %rdi
    call is_heap_ptr
    pop %rdi
    test %rax, %rax
    jz .Lmg_done

    # Valid heap pointer!
    # User pointer is at rbx + 24.
    # rdi - 8  is the type tag (rbx + 16).
    # rdi - 16 is the chunk size field (rbx + 8).
    # rdi - 24 is the chunk gc_next field (rbx + 0).
    mov -16(%rdi), %rcx
    bt $63, %rcx
    jc .Lmg_done                        # Already marked

    btsq $63, -16(%rdi)                 # Mark bit 63 in chunk size field (does not touch tag!)

    # Push user pointer to grey stack
    mov grey_count(%rip), %rcx
    cmp $262140, %rcx
    jge .Lmg_done                       # Safety stack overflow boundary

    lea grey_stack(%rip), %r8
    mov %rdi, (%r8, %rcx, 8)
    inc %rcx
    mov %rcx, grey_count(%rip)

.Lmg_done:
    leave
    ret

.global gc_step
gc_step:
    push %rbp
    mov %rsp, %rbp
    push %rbx
    push %r12

    mov grey_count(%rip), %rcx
    test %rcx, %rcx
    jz .Lstep_empty

    dec %rcx
    mov %rcx, grey_count(%rip)
    lea grey_stack(%rip), %r8
    mov (%r8, %rcx, 8), %rdi            # rdi = object user pointer

    mov -8(%rdi), %rdx                  # Type tag at user_ptr - 8
    cmp $3, %rdx
    je .Lstep_array
    cmp $7, %rdx
    je .Lstep_done                      # Tag 7 data buffer is scanned via parent array
    cmp $2, %rdx
    je .Lstep_map
    cmp $6, %rdx
    je .Lstep_map_node
    cmp $5, %rdx
    je .Lstep_string_view
    jmp .Lstep_done

.Lstep_array:
    # Array traversal:
    # 0(%rdi) is length
    # 16(%rdi) is data_ptr
    mov 16(%rdi), %rsi                  # rsi = data_ptr
    test %rsi, %rsi
    jz .Lstep_done

    # First mark data_ptr itself so sweep preserves it
    push %rdi
    push %rsi
    mov %rsi, %rdi
    call make_grey
    pop %rsi
    pop %rdi

    # Now mark elements inside data_ptr
    mov 0(%rdi), %rcx                   # rcx = length
    test %rcx, %rcx
    jz .Lstep_done

.Lsa_loop:
    test %rcx, %rcx
    jz .Lstep_done
    mov (%rsi), %rdi
    test $1, %rdi
    jnz .Lsa_skip
    push %rcx
    push %rsi
    call make_grey
    pop %rsi
    pop %rcx
.Lsa_skip:
    add $8, %rsi
    dec %rcx
    jmp .Lsa_loop

.Lstep_map:
    mov 0(%rdi), %rsi                   # Head of map nodes
.Lsm_loop:
    test %rsi, %rsi
    jz .Lstep_done
    push %rsi
    mov %rsi, %rdi
    call make_grey
    pop %rsi
    mov 16(%rsi), %rsi                  # Next node pointer
    jmp .Lsm_loop

.Lstep_map_node:
    # Map node: 0(%rdi) = key, 8(%rdi) = val, 16(%rdi) = next
    mov 0(%rdi), %rsi
    test $1, %rsi
    jnz .Lsmn_val
    push %rdi
    mov %rsi, %rdi
    call make_grey
    pop %rdi
.Lsmn_val:
    mov 8(%rdi), %rsi
    test $1, %rsi
    jnz .Lsmn_next
    push %rdi
    mov %rsi, %rdi
    call make_grey
    pop %rdi
.Lsmn_next:
    mov 16(%rdi), %rsi
    test %rsi, %rsi
    jz .Lstep_done
    push %rdi
    mov %rsi, %rdi
    call make_grey
    pop %rdi
    jmp .Lstep_done

.Lstep_string_view:
    # String view: 0(%rdi) points to source string buffer
    mov 0(%rdi), %rdi
    call make_grey
    jmp .Lstep_done

.Lstep_empty:
    movq $0, gc_phase(%rip)
.Lstep_done:
    pop %r12
    pop %rbx
    leave
    ret

.global seed_roots
seed_roots:
    push %rbp
    mov %rsp, %rbp
    push %rsi
    push %rbx

    mov __sys_stack_base(%rip), %rcx
    mov %rsp, %rsi

.Lseed_loop:
    cmp %rsi, %rcx
    jbe .Lseed_done
    mov (%rsi), %rdi
    test $1, %rdi
    jnz .Lseed_next
    test %rdi, %rdi
    jz .Lseed_next

    push %rsi
    push %rcx
    call make_grey
    pop %rcx
    pop %rsi

.Lseed_next:
    add $8, %rsi
    jmp .Lseed_loop

.Lseed_done:
    # --- Scan Global Variables Table (.data section before gc_threshold) ---
    lea gc_threshold(%rip), %rcx        # rcx = end of user globals (.data section)
    mov %rcx, %rsi
    sub $32768, %rsi                    # Scan up to 32 KB of globals table

.Lseed_globals_loop:
    cmp %rsi, %rcx
    jbe .Lseed_all_done
    mov (%rsi), %rdi
    test $1, %rdi
    jnz .Lseed_globals_next
    test %rdi, %rdi
    jz .Lseed_globals_next

    push %rsi
    push %rcx
    call make_grey
    pop %rcx
    pop %rsi

.Lseed_globals_next:
    add $8, %rsi
    jmp .Lseed_globals_loop

.Lseed_all_done:
    pop %rbx
    pop %rsi
    leave
    ret

# --- SWEEP STAGE ---
.global gc_sweep
gc_sweep:
    push %rbp
    mov %rsp, %rbp
    push %rbx
    push %r12
    xor %r12, %r12                      # r12 = live_bytes
    lea gc_head(%rip), %rbx

.Lsweep_loop:
    mov (%rbx), %rax
    test %rax, %rax
    jz .Lsweep_done

    # Validate that rax is a valid heap chunk
    cmp min_heap_addr(%rip), %rax
    jb .Lsweep_corrupt
    cmp max_heap_addr(%rip), %rax
    jae .Lsweep_corrupt
    test $15, %rax
    jnz .Lsweep_corrupt

    mov 8(%rax), %rcx                   # size + flags
    bt $63, %rcx
    jc .Lsweep_unmark                   # Object is marked (alive!)

    # Object is dead (or was marked dead by _free via bit 62).
    # Unlink from gc_head
    mov 0(%rax), %rdx
    test %rdx, %rdx
    jz .Lsweep_unlink_ok
    cmp min_heap_addr(%rip), %rdx
    jb .Lsweep_corrupt_next
    cmp max_heap_addr(%rip), %rdx
    jae .Lsweep_corrupt_next
    test $15, %rdx
    jnz .Lsweep_corrupt_next

.Lsweep_unlink_ok:
    mov %rdx, (%rbx)

    # Clean flags and add to segregated free_bins
    btr $62, %rcx
    btr $63, %rcx
    mov %rcx, 8(%rax)

    lea -32(%rcx), %r8
    shr $4, %r8
    cmp $30, %r8
    jbe .Lsweep_push_bin
    mov $31, %r8

.Lsweep_push_bin:
    lea free_bins(%rip), %r9
    lea (%r9, %r8, 8), %r9
    mov (%r9), %r10
    mov %r10, 0(%rax)
    mov %rax, (%r9)
    jmp .Lsweep_loop

.Lsweep_corrupt_next:
    movq $0, (%rbx)                     # Safely truncate corrupt next link
    btr $62, %rcx
    btr $63, %rcx
    mov %rcx, 8(%rax)
    lea -32(%rcx), %r8
    shr $4, %r8
    cmp $30, %r8
    jbe .Lsweep_corrupt_push
    mov $31, %r8
.Lsweep_corrupt_push:
    lea free_bins(%rip), %r9
    lea (%r9, %r8, 8), %r9
    mov (%r9), %r10
    mov %r10, 0(%rax)
    mov %rax, (%r9)
    jmp .Lsweep_done

.Lsweep_corrupt:
    movq $0, (%rbx)                     # Safely truncate corrupted gc_head
    jmp .Lsweep_done

.Lsweep_unmark:
    btr $63, %rcx                       # Clear mark bit
    mov %rcx, 8(%rax)                   # Store clean size
    add %rcx, %r12                      # live_bytes += size
    lea 0(%rax), %rbx                   # Advance rbx to &current->next
    jmp .Lsweep_loop

.Lsweep_done:
    # Adaptive threshold: max(64MB, live_bytes * 2)
    shl $1, %r12
    cmp $67108864, %r12
    jge .Lset_thresh
    mov $67108864, %r12
.Lset_thresh:
    mov %r12, gc_threshold(%rip)
    movq $0, bytes_allocated(%rip)
    pop %r12
    pop %rbx
    leave
    ret

# --- FORCE FULL COLLECTION ---
.global gc_collect
gc_collect:
    push %rbp
    mov %rsp, %rbp
    push %rax
    push %rbx
    push %rcx
    push %rdx
    push %rsi
    push %rdi
    push %r8
    push %r9
    push %r10
    push %r11
    push %r12
    push %r13
    push %r14
    push %r15

    movq $1, gc_phase(%rip)
    movq $0, grey_count(%rip)
    call seed_roots

.Lforce_mark_loop:
    mov grey_count(%rip), %rcx
    test %rcx, %rcx
    jz .Lforce_sweep
    call gc_step
    jmp .Lforce_mark_loop

.Lforce_sweep:
    call gc_sweep
    movq $0, gc_phase(%rip)
    movq $0, grey_count(%rip)
    pop %r15
    pop %r14
    pop %r13
    pop %r12
    pop %r11
    pop %r10
    pop %r9
    pop %r8
    pop %rdi
    pop %rsi
    pop %rdx
    pop %rcx
    pop %rbx
    pop %rax
    leave
    ret
