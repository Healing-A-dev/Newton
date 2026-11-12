.section .rodata
    .Lstr_int:    .string "int"
    .Lstr_string: .string "string"
    .Lstr_map:    .string "map"
    .Lstr_list:   .string "list"
    .Lstr_float:  .string "float"
    .Lstr_unknown:.string "unknown"

.section .text

.global string_len
string_len:
    test %rdi, %rdi; jz .null_len
    mov %rdi, %rax
    and $1, %rax
    jnz .null_len

    mov -8(%rdi), %rcx
    cmp $5, %rcx
    je .Llen_view
    xor %rax, %rax

.len_loop: cmpb $0, (%rdi, %rax); je .len_done; inc %rax; jmp .len_loop
.Llen_view: mov 8(%rdi), %rax; ret
.len_done: ret
.null_len: xor %rax, %rax; ret

.global string_substring
string_substring:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12; push %r13; push %r14; push %r15
    sar $1, %rsi
    sar $1, %rdx
    mov %rdi, %rbx
    mov %rsi, %r12
    mov %rdx, %r13
    mov %rbx, %rdi
    call string_len

    mov %rax, %r14
    cmp %r14, %r12
    jge .Lsub_empty

    mov %r12, %rax
    add %r13, %rax
    cmp %r14, %rax
    jle .Lsub_do

    mov %r14, %r13
    sub %r12, %r13

.Lsub_do:
    mov %r13, %rdi
    add $9, %rdi
    call _malloc

    movq $1, 0(%rax)
    add $8, %rax
    mov %rax, %r15
    mov -8(%rbx), %rcx
    cmp $5, %rcx
    jne .Lsub_copy
    mov 0(%rbx), %rbx

.Lsub_copy:
    mov %r15, %rdi
    lea (%rbx, %r12), %rsi
    mov %r13, %rcx
    test %rcx, %rcx
    jz .Lsub_term
    cld; rep movsb

.Lsub_term:
    movb $0, (%rdi)
    mov %r15, %rax
    pop %r15; pop %r14; pop %r13; pop %r12; pop %rbx
    leave; ret

.Lsub_empty:
    mov $9, %rdi
    call _malloc

    movq $1, 0(%rax)
    add $8, %rax
    movb $0, (%rax)
    pop %r15; pop %r14; pop %r13; pop %r12; pop %rbx
    leave; ret

.global string_concat
string_concat:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12; push %r13; push %r14; push %r15
    mov %rdi, %rbx
    mov %rsi, %r12
    mov %rbx, %rdi

    call string_len
    mov %rax, %r13
    mov %r12, %rdi

    call string_len
    mov %rax, %r14
    lea 9(%r13, %r14), %rdi

    call _malloc
    movq $1, 0(%rax)
    add $8, %rax
    mov %rax, %r15
    test %rbx, %rbx
    jz .Lsc_str1_ok

    mov %rbx, %rax
    and $1, %rax
    jnz .Lsc_str1_ok

    mov -8(%rbx), %rcx
    cmp $5, %rcx
    jne .Lsc_str1_ok
    mov 0(%rbx), %rbx

.Lsc_str1_ok:
    test %r12, %r12
    jz .Lsc_str2_ok
    mov %r12, %rax
    and $1, %rax
    jnz .Lsc_str2_ok

    mov -8(%r12), %rcx
    cmp $5, %rcx
    jne .Lsc_str2_ok
    mov 0(%r12), %r12

.Lsc_str2_ok:
    mov %r15, %rdi
    mov %rbx, %rsi
    mov %r13, %rcx
    rep movsb

    mov %r15, %rdi
    add %r13, %rdi
    mov %r12, %rsi
    mov %r14, %rcx
    rep movsb

    mov %r15, %rdi
    add %r13, %rdi
    add %r14, %rdi
    movb $0, (%rdi)
    mov %r15, %rax
    pop %r15; pop %r14; pop %r13; pop %r12; pop %rbx
    leave; ret

.global string_ord
string_ord:
    test %rdi, %rdi
    jz .Lord_zero
    mov %rdi, %rax
    and $1, %rax
    jnz .Lord_zero
    mov -8(%rdi), %rcx
    cmp $5, %rcx
    jne .Lord_read
    mov 0(%rdi), %rdi

.Lord_read:
    xor %rax, %rax
    movb (%rdi), %al
    shl $1, %rax
    or $1, %rax
    ret

.Lord_zero:
    mov $1, %rax
    ret

.global string_char
string_char:
    push %rbp; mov %rsp, %rbp; push %rbx
    mov %rdi, %rbx
    sar $1, %rbx
    mov $10, %rdi
    call _malloc

    movq $1, 0(%rax)
    add $8, %rax
    movb %bl, 0(%rax)
    movb $0, 1(%rax)
    pop %rbx; leave; ret

.global collection_len
collection_len:
    test %rdi, %rdi; jz .Lclz
    mov %rdi, %rcx; and $1, %rcx; jnz .Lclz
    mov -8(%rdi), %rax
    cmp $1, %rax; je .Ldsl
    cmp $2, %rax; je map_len
    cmp $3, %rax; je array_len

.Lclz: mov $1, %rax; ret
.Ldsl: call string_len; shl $1, %rax; or $1, %rax; ret

.global collection_delete
collection_delete:
    test %rdi, %rdi; jz .Lcol_del_fail
    mov -8(%rdi), %rax
    cmp $2, %rax; je map_delete
    cmp $3, %rax; je array_delete

.Lcol_del_fail:
    mov $1, %rax
    ret

.global collection_get
collection_get:
    test %rdi, %rdi; jz .Lcg_zero
    test %rsi, %rsi; jnz .Lcg_do
    mov $1, %rsi

.Lcg_do:
    mov %rdi, %rcx; and $1, %rcx; jnz .Lcg_zero
    mov -8(%rdi), %rax
    cmp $1, %rax; je .Lcg_str
    cmp $2, %rax; je map_get
    cmp $3, %rax; je array_get

.Lcg_zero:
    mov $1, %rax; ret

.Lcg_str:
    sar $1, %rsi; xor %rax, %rax; movb (%rdi, %rsi, 1), %al; shl $1, %rax; or $1, %rax; ret

.global collection_set
collection_set:
    test %rdi, %rdi; jz .csetr; mov -8(%rdi), %rax
    cmp $2, %rax; je map_set; cmp $3, %rax; je array_set

.csetr: ret

.global collection_get_key
collection_get_key:
    test %rdi, %rdi; jz .Lcgk_null
    mov -8(%rdi), %rax
    cmp $2, %rax
    je .Lcgk_map
    mov %rsi, %rax
    ret

.Lcgk_map:
    mov (%rdi), %rcx
    mov %rsi, %r9
    sar $1, %r9

.Lcgk_map_loop:
    test %rcx, %rcx; jz .Lcgk_null
    test %r9, %r9; jz .Lcgk_map_found
    dec %r9
    mov 16(%rcx), %rcx
    jmp .Lcgk_map_loop

.Lcgk_map_found:
    mov 0(%rcx), %rax
    ret

.Lcgk_null:
    mov $1, %rax
    ret

.global new_array
new_array:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12; push %r13
    sub $8, %rsp

    # Calculate initial capacity (in elements)
    cmp $64, %rdi
    jg .Lnew_arr_calc_cap
    mov $8, %r12                        # Default capacity: 8 elements
    jmp .Lnew_arr_alloc_buf

.Lnew_arr_calc_cap:
    sub $64, %rdi
    shr $3, %rdi                        # count = (rdi - 64) / 8
    add $4, %rdi                        # count + 4 headroom
    cmp $8, %rdi
    jge .Lnew_arr_cap_ok
    mov $8, %rdi
.Lnew_arr_cap_ok:
    mov %rdi, %r12                      # r12 = capacity (elements)

.Lnew_arr_alloc_buf:
    # Allocate data buffer chunk: tag 7, payload = (capacity * 8) + 8 bytes
    mov %r12, %rdi
    shl $3, %rdi                        # bytes = capacity * 8
    add $8, %rdi                        # +8 bytes for TAG_ARRAY_DATA
    call _malloc                        # returns rax = chunk + 16
    movq $7, 0(%rax)                    # Tag 7 = TAG_ARRAY_DATA
    lea 8(%rax), %r13                   # r13 = data_ptr (chunk + 24)

    # Zero out data buffer with tagged 0 ($1)
    mov %r13, %rdi
    mov %r12, %rcx
    mov $1, %rax
    cld
    rep stosq

    # Allocate descriptor chunk: tag 3, payload = 32 bytes (tag + len, cap, data_ptr)
    push %r13                           # Protect data_ptr across _malloc
    mov $32, %rdi
    call _malloc                        # returns rax = chunk + 16
    pop %r13
    movq $3, 0(%rax)                    # Tag 3 = TAG_ARRAY
    movq $0, 8(%rax)                    # length = 0
    mov %r12, 16(%rax)                  # capacity = r12
    mov %r13, 24(%rax)                  # data_ptr = r13
    lea 8(%rax), %rax                   # rax = user_ptr (chunk + 24)

    add $8, %rsp
    pop %r13; pop %r12; pop %rbx
    leave; ret

.global array_set
array_set:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12; push %r13; push %r14

    mov %rsi, %rax
    and $1, %rax
    jz .Larr_set_done
    sar $1, %rsi                        # rsi = untagged index
    cmp $0, %rsi
    jl .Larr_set_done

    mov %rdi, %rbx                      # rbx = arr
    mov %rsi, %r12                      # r12 = index
    mov %rdx, %r13                      # r13 = val

    # Check capacity at 8(%rbx)
    mov 8(%rbx), %rax
    cmp %r12, %rax
    jg .Larr_set_has_cap

    # Need to grow!
    # new_capacity = max(capacity * 2, index + 16)
    shl $1, %rax                        # capacity * 2
    lea 16(%r12), %rcx                  # index + 16
    cmp %rcx, %rax
    cmovl %rcx, %rax
    mov %rax, %r14                      # r14 = new_capacity

    # Allocate new data buffer chunk: tag 7, size = (new_capacity * 8) + 8
    mov %r14, %rdi
    shl $3, %rdi                        # new_capacity * 8 bytes
    add $8, %rdi                        # +8 bytes for TAG_ARRAY_DATA
    call _malloc                        # returns rax = chunk + 16
    movq $7, 0(%rax)
    lea 8(%rax), %rax                   # rax = new data_ptr (chunk + 24)

    # Zero-fill new buffer with $1 (tagged 0)
    push %rax
    mov %rax, %rdi
    mov %r14, %rcx
    mov $1, %rax
    cld
    rep stosq
    pop %rax

    # Copy old elements to new buffer
    mov 16(%rbx), %rsi                  # old data_ptr
    mov 0(%rbx), %rcx                   # old length
    test %rsi, %rsi
    jz .Larr_set_update_cap
    test %rcx, %rcx
    jz .Larr_set_update_cap

    push %rax
    mov %rax, %rdi                      # dst = new data_ptr
    cld
    rep movsq
    pop %rax

.Larr_set_update_cap:
    mov %r14, 8(%rbx)                   # update capacity
    mov %rax, 16(%rbx)                  # update data_ptr

.Larr_set_has_cap:
    # Update length if index >= length
    mov 0(%rbx), %rcx
    cmp %r12, %rcx
    jg .Larr_set_do_store
    lea 1(%r12), %rcx
    mov %rcx, 0(%rbx)

.Larr_set_do_store:
    mov 16(%rbx), %rax                  # data_ptr
    mov %r13, (%rax, %r12, 8)

.Larr_set_done:
    pop %r14; pop %r13; pop %r12; pop %rbx
    leave; ret

.global array_get
array_get:
    mov %rsi, %rax
    and $1, %rax
    jz .Larr_get_null
    sar $1, %rsi
    cmp $0, %rsi
    jl .Larr_get_null
    cmp 0(%rdi), %rsi                   # cmp index, length
    jge .Larr_get_null
    mov 16(%rdi), %rax                  # rax = data_ptr
    mov (%rax, %rsi, 8), %rax           # load element
    ret

.Larr_get_null:
    mov $1, %rax
    ret

.global array_len
array_len:
    mov 0(%rdi), %rax
    shl $1, %rax
    or $1, %rax
    ret

.global array_delete
array_delete:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12
    sar $1, %rsi
    cmp $0, %rsi; jl .Larr_del_out_of_bounds
    mov 0(%rdi), %rcx                   # rcx = length
    cmp %rsi, %rcx; jle .Larr_del_out_of_bounds

    mov 16(%rdi), %rbx                  # rbx = data_ptr
    mov %rcx, %r8; sub %rsi, %r8; dec %r8
    test %r8, %r8; jz .Larr_del_finish

    lea (%rbx, %rsi, 8), %rdx           # dst = data_ptr + index*8
    lea 8(%rbx, %rsi, 8), %r9           # src = data_ptr + (index+1)*8

.Larr_del_shift_loop:
    mov (%r9), %rax; mov %rax, (%rdx)
    add $8, %rdx; add $8, %r9; dec %r8
    jnz .Larr_del_shift_loop

.Larr_del_finish:
    dec %rcx
    mov %rcx, 0(%rdi)                   # update length
    movq $1, (%rbx, %rcx, 8)            # zero out trailing slot
    mov $3, %rax
    pop %r12; pop %rbx
    leave; ret

.Larr_del_out_of_bounds:
    mov $1, %rax
    pop %r12; pop %rbx
    leave; ret

.global array_concat
array_concat:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12; push %r13; push %r14
    mov %rdi, %rbx                      # arr1
    mov %rsi, %r12                      # arr2
    mov 0(%rbx), %r8                    # len1
    mov 0(%r12), %r9                    # len2
    lea (%r8, %r9), %r14                # total_len = len1 + len2

    # Allocate new_array with initial capacity for total_len
    lea 64(,%r14,8), %rdi
    call new_array
    mov %rax, %r13                      # r13 = new_arr

    # Set new length
    mov %r14, 0(%r13)

    # Copy elements from arr1
    mov 0(%rbx), %rcx
    test %rcx, %rcx
    jz .Lconcat_copy_arr2
    mov 16(%rbx), %rsi                  # src = arr1->data_ptr
    mov 16(%r13), %rdi                  # dst = new_arr->data_ptr
    cld
    rep movsq

.Lconcat_copy_arr2:
    mov 0(%r12), %rcx
    test %rcx, %rcx
    jz .Lconcat_done
    mov 16(%r12), %rsi                  # src = arr2->data_ptr
    mov 16(%r13), %rdi                  # dst = new_arr->data_ptr
    mov 0(%rbx), %rax
    lea (%rdi, %rax, 8), %rdi           # dst + len1 * 8
    cld
    rep movsq

.Lconcat_done:
    mov %r13, %rax
    pop %r14; pop %r13; pop %r12; pop %rbx
    leave; ret

.global new_map
new_map:
    push %rbp; mov %rsp, %rbp
    mov $16, %rdi
    call _malloc
    movq $2, 0(%rax)
    add $8, %rax
    movq $0, 0(%rax)
    leave; ret

.global map_len
map_len: mov (%rdi), %rcx; xor %rax, %rax; .Lml: test %rcx, %rcx; jz .mld; inc %rax; mov 16(%rcx), %rcx; jmp .Lml; .mld: shl $1, %rax; or $1, %rax; ret

.global map_get
map_get:
    mov (%rdi), %rcx
    mov %rsi, %rax
    and $1, %rax
    jnz .Lmap_get_index

.Lmap_g:
    test %rcx, %rcx; jz .Lmap_null
    mov 0(%rcx), %r8
    push %rdi; push %rsi; push %rcx
    mov %r8, %rdi
    call runtime_eq
    pop %rcx; pop %rsi; pop %rdi
    cmp $3, %rax; je .Lmap_g_fnd
    mov 16(%rcx), %rcx; jmp .Lmap_g

.Lmap_g_fnd:
    mov 8(%rcx), %rax; ret

.Lmap_get_index:
    mov %rsi, %r9; sar $1, %r9

.Lmap_idx_loop:
    test %rcx, %rcx; jz .Lmap_null
    test %r9, %r9; jz .Lmap_g_fnd
    dec %r9; mov 16(%rcx), %rcx; jmp .Lmap_idx_loop

.Lmap_null:
    mov $1, %rax; ret

.global map_set
map_set:
    push %rbp; mov %rsp, %rbp
    test $1, %rsi
    jnz .Lmap_barrier_skip1
    push %rdi; push %rsi; push %rdx
    mov %rsi, %rdi
    call make_grey
    pop %rdx; pop %rsi; pop %rdi

.Lmap_barrier_skip1:
    test $1, %rdx
    jnz .Lmap_barrier_skip2
    push %rdi; push %rsi; push %rdx
    mov %rdx, %rdi
    call make_grey
    pop %rdx; pop %rsi; pop %rdi

.Lmap_barrier_skip2:
    mov (%rdi), %rcx

.Lmap_upd:
    test %rcx, %rcx; jz .Lmap_new
    mov 0(%rcx), %r8
    push %rdi; push %rsi; push %rdx; push %rcx
    mov %r8, %rdi
    call runtime_eq
    pop %rcx; pop %rdx; pop %rsi; pop %rdi
    cmp $3, %rax; je .Lmap_found
    mov 16(%rcx), %rcx; jmp .Lmap_upd

.Lmap_found:
    mov %rdx, 8(%rcx)
    leave; ret

.Lmap_new:
    push %rdi; push %rsi; push %rdx
    mov $32, %rdi
    call _malloc

    pop %rdx; pop %rsi; pop %rdi
    movq $6, 0(%rax)
    add $8, %rax
    mov %rsi, 0(%rax)
    mov %rdx, 8(%rax)
    mov (%rdi), %rcx
    mov %rcx, 16(%rax)
    mov %rax, (%rdi)
    push %rax
    push %rdi
    mov %rax, %rdi
    call make_grey

    pop %rdi
    pop %rax
    leave; ret

.global map_delete
map_delete:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12; push %r13; push %r14
    mov %rdi, %r14
    mov %rsi, %r13
    mov %r14, %r12
    mov (%r14), %rbx

.Ldel_loop:
    test %rbx, %rbx; jz .Ldel_not_found
    mov 0(%rbx), %rdi; mov %r13, %rsi; call runtime_eq
    cmp $3, %rax; je .Ldel_found
    lea 16(%rbx), %r12; mov 16(%rbx), %rbx; jmp .Ldel_loop

.Ldel_found:
    mov 16(%rbx), %rax
    mov %rax, (%r12)
    mov $3, %rax
    jmp .Ldel_done

.Ldel_not_found:
    mov $1, %rax

.Ldel_done:
    pop %r14; pop %r13; pop %r12; pop %rbx; leave; ret

.global map_head
map_head: mov (%rdi), %rax; ret
.global node_key
node_key: mov 0(%rdi), %rax; ret
.global node_val
node_val: mov 8(%rdi), %rax; ret
.global node_next
node_next: mov 16(%rdi), %rax; ret

.global get_type_str
get_type_str:
    push %rbp; mov %rsp, %rbp
    mov %rdi, %rax; and $1, %rax; cmp $1, %rax; je .Lti
    test %rdi, %rdi; jz .Ltu
    mov -8(%rdi), %rax
    cmp $1, %rax; je .Lts
    cmp $2, %rax; je .Ltm
    cmp $3, %rax; je .Ltl
    cmp $4, %rax; je .Ltf

.Ltu: lea .Lstr_unknown(%rip), %rdi; jmp .Lta
.Lti: lea .Lstr_int(%rip), %rdi; jmp .Lta
.Lts: lea .Lstr_string(%rip), %rdi; jmp .Lta
.Ltm: lea .Lstr_map(%rip), %rdi; jmp .Lta
.Ltl: lea .Lstr_list(%rip), %rdi; jmp .Lta
.Ltf: lea .Lstr_float(%rip), %rdi; jmp .Lta
.Lta: call string_new; leave; ret

.global string_new
string_new:
    push %rbp; mov %rsp, %rbp; push %rbx; push %r14
    mov %rdi, %rbx; xor %rcx, %rcx

.snl: cmpb $0, (%rbx, %rcx); je .sna; inc %rcx; jmp .snl
.sna: mov %rcx, %rdi; add $9, %rdi; call _malloc
    movq $1, 0(%rax); add $8, %rax; mov %rbx, %rsi; mov %rax, %rdi

.snc: movb (%rsi), %cl; movb %cl, (%rdi); test %cl, %cl; jz .snd; inc %rsi; inc %rdi; jmp .snc
.snd: pop %r14; pop %rbx; leave; ret

.global newton_strcmp
newton_strcmp: xor %rax, %rax; .nsc: movb (%rdi), %al; movb (%rsi), %cl; cmp %al, %cl; jne .nsd; test %al, %al; jz .nsm; inc %rdi; inc %rsi; jmp .nsc; .nsd: mov $1, %rax; ret; .nsm: xor %rax, %rax; ret

.global _keys_equal
_keys_equal: jmp newton_strcmp

.global runtime_get_arg
runtime_get_arg:
    push %rbp; mov %rsp, %rbp; push %rbx; push %r12; push %r13
    sar $1, %rdi; inc %rdi; cmp __argc(%rip), %rdi; jge .Largv_null
    mov __sys_argv(%rip), %rax; mov (%rax, %rdi, 8), %rbx; xor %rcx, %rcx

.Largv_len: cmpb $0, (%rbx, %rcx); je .Largv_alloc; inc %rcx; jmp .Largv_len
.Largv_alloc: mov %rcx, %r12; mov %rcx, %rdi; add $9, %rdi; call _malloc
    movq $1, 0(%rax); add $8, %rax; mov %rax, %rdi; mov %rbx, %rsi; mov %r12, %rcx; rep movsb
    movb $0, (%rdi); sub %r12, %rdi; mov %rdi, %rax
    pop %r13; pop %r12; pop %rbx; leave; ret

.Largv_null: mov $1, %rax; pop %r13; pop %r12; pop %rbx; leave; ret

.global newton_box_float
newton_box_float:
    push %rbp; mov %rsp, %rbp; sub $16, %rsp; movsd %xmm0, (%rsp); mov $16, %rdi; call _malloc
    movsd (%rsp), %xmm0; add $16, %rsp; movq $4, 0(%rax); movsd %xmm0, 8(%rax); add $8, %rax; leave; ret

.global F_alloc_array
F_alloc_array:
    push %rbp; mov %rsp, %rbp; mov 16(%rbp), %rax; sar $1, %rax; push %rax
    mov %rax, %rdi; shl $3, %rdi; add $16, %rdi; call _malloc
    mov %rax, %r8; movq $3, 0(%r8); pop %rcx; mov %rcx, 8(%r8)
    lea 16(%r8), %rdi; mov %rcx, %rbx; mov %rbx, %rcx; mov $1, %rax; cld; rep stosq
    lea 8(%r8), %rax; leave; ret

.global alloc_flat_array
alloc_flat_array:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12
    push %rdi
    sub $40, %rsp
    mov %rcx, %rbx
    sar $1, %rbx
    mov %rbx, %rcx
    shl $3, %rcx
    add $16, %rcx
    call _malloc

    mov %rax, %r12
    movq $3, 0(%r12)
    mov %rbx, 8(%r12)
    lea 16(%r12), %rdi
    mov %rbx, %rcx
    mov $1, %rax
    cld
    rep stosq

    lea 8(%r12), %rax
    add $40, %rsp
    pop %rdi
    pop %r12; pop %rbx
    leave; ret
