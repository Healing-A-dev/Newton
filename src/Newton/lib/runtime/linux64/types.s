.section .rodata

    .align 8
    .quad 1
.Lstr_int:    .asciz "int"

    .align 8
    .quad 1
.Lstr_string: .asciz "string"

    .align 8
    .quad 1
.Lstr_map:    .asciz "map"

    .align 8
    .quad 1
.Lstr_list:   .asciz "list"

    .align 8
    .quad 1
.Lstr_float:  .asciz "float"

    .align 8
    .quad 1
.Lstr_unknown:.asciz "unknown"

.section .text

# ----------------------------------------
# STRING OPS
# ----------------------------------------

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
    mov $2048, %rdi
    call _malloc

    movq $3, 0(%rax)
    movq $0, 8(%rax)
    add $8, %rax
    leave; ret

.global array_set
array_set:
    push %rbp; mov %rsp, %rbp
    test $1, %rdx
    jnz .Larr_barrier_skip

    push %rdi; push %rsi; push %rdx; push %rcx
    mov %rdx, %rdi
    call make_grey

    pop %rcx; pop %rdx; pop %rsi; pop %rdi

.Larr_barrier_skip:
    sar $1, %rsi
    mov 0(%rdi), %rcx
    cmp %rsi, %rcx
    jg .Larr_set_do

    mov %rsi, %rcx
    inc %rcx
    mov %rcx, 0(%rdi)

.Larr_set_do:
    mov %rdx, 8(%rdi, %rsi, 8)
    leave; ret

.global array_get
array_get: sar $1, %rsi; mov 8(%rdi, %rsi, 8), %rax; ret

.global array_len
array_len: mov 0(%rdi), %rax; shl $1, %rax; or $1, %rax; ret

.global array_delete
array_delete:
    push %rbp; mov %rsp, %rbp
    sar $1, %rsi
    cmp $0, %rsi; jl .Larr_del_out_of_bounds
    mov 0(%rdi), %rcx
    cmp %rsi, %rcx; jle .Larr_del_out_of_bounds
    mov %rcx, %r8; sub %rsi, %r8; dec %r8
    test %r8, %r8; jz .Larr_del_finish
    lea 8(%rdi, %rsi, 8), %rdx
    lea 16(%rdi, %rsi, 8), %r9

.Larr_del_shift_loop:
    mov (%r9), %rax; mov %rax, (%rdx)
    add $8, %rdx; add $8, %r9; dec %r8
    jnz .Larr_del_shift_loop

.Larr_del_finish:
    dec %rcx; mov %rcx, 0(%rdi)
    mov $3, %rax
    leave; ret

.Larr_del_out_of_bounds:
    mov $1, %rax
    leave; ret

.global array_concat
array_concat:
    push %rbp; mov %rsp, %rbp; push %rbx; push %r12; push %r13
    mov %rdi, %rbx; mov %rsi, %r12; mov 0(%rbx), %r8; mov 0(%r12), %r9
    mov %r8, %rdi; add %r9, %rdi; shl $3, %rdi; add $16, %rdi; push %r8; push %r9; call _malloc
    mov %rax, %r13; pop %r9; pop %r8; movq $3, 0(%r13); mov %r8, %rcx; add %r9, %rcx; mov %rcx, 8(%r13)
    lea 8(%rbx), %rsi; lea 16(%r13), %rdi; mov %r8, %rcx; cld; rep movsq
    lea 8(%r12), %rsi; mov %r9, %rcx; rep movsq
    lea 8(%r13), %rax; pop %r13; pop %r12; pop %rbx; leave; ret

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

    push %rdi; push %rsi; push %rdx; push %rcx
    mov %rsi, %rdi
    call make_grey

    pop %rcx; pop %rdx; pop %rsi; pop %rdi

.Lmap_barrier_skip1:
    test $1, %rdx
    jnz .Lmap_barrier_skip2

    push %rdi; push %rsi; push %rdx; push %rcx
    mov %rdx, %rdi
    call make_grey

    pop %rcx; pop %rdx; pop %rsi; pop %rdi

.Lmap_barrier_skip2:
    mov (%rdi), %rcx

.Lmap_upd:
    test %rcx, %rcx; jz .Lmap_new
    mov 0(%rcx), %r8
    push %rdi; push %rsi; push %rdx; push %rcx
    mov %r8, %rdi
    call _keys_equal

    pop %rcx; pop %rdx; pop %rsi; pop %rdi
    cmp $0, %rax
    je .Lmap_found

    mov 16(%rcx), %rcx; jmp .Lmap_upd

.Lmap_found:
    mov %rdx, 8(%rcx)
    leave; ret

.Lmap_new:
    push %rdi; push %rsi; push %rdx; push %rcx
    mov $32, %rdi
    call _malloc

    pop %rcx; pop %rdx; pop %rsi; pop %rdi
    movq $6, 0(%rax)
    add $8, %rax
    mov %rsi, 0(%rax)
    mov %rdx, 8(%rax)
    mov (%rdi), %rcx
    mov %rcx, 16(%rax)
    mov %rax, (%rdi)
    push %rax; push %rdi; push %rsi; push %rdx
    mov %rax, %rdi

    call make_grey
    pop %rdx; pop %rsi; pop %rdi; pop %rax
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
map_head:
    test %rdi, %rdi; jz .Lmh_null
    mov 0(%rdi), %rax
    ret

.Lmh_null:
    xor %rax, %rax; ret

.global node_key
node_key:
    test %rdi, %rdi; jz .Lnk_null
    mov 0(%rdi), %rax
    ret

.Lnk_null:
    xor %rax, %rax; ret

.global node_val
node_val:
    test %rdi, %rdi; jz .Lnv_null
    mov 8(%rdi), %rax
    ret

.Lnv_null:
    xor %rax, %rax; ret

.global node_next
node_next:
    test %rdi, %rdi; jz .Lnn_null
    mov 16(%rdi), %rax
    ret

.Lnn_null:
    xor %rax, %rax; ret

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
_keys_equal:
    cmp %rdi, %rsi
    je .Lke_true

    mov %rdi, %rax
    and $1, %rax
    jnz .Lke_false

    mov %rsi, %rax
    and $1, %rax
    jnz .Lke_false
    jmp newton_strcmp

.Lke_true:
    mov $0, %rax
    ret

.Lke_false:
    mov $1, %rax
    ret

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
    mov %rdi, %rbx
    sar $1, %rbx
    mov %rbx, %rdi
    shl $3, %rdi
    add $16, %rdi
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
    pop %r12; pop %rbx
    leave; ret
