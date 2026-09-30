.section .rodata
	FLOAT_TEN: .double 10.0

.section .text

.global int_to_string
int_to_string:
    push %rbp
    mov %rsp, %rbp
    sub $32, %rsp
    sar $1, %rdi
    mov %rdi, %rax
    test %rax, %rax
    jnz .Lits_nonzero
    mov $2, %rdi
    call _malloc
    movq $1, 0(%rax)
    add $8, %rax
    movw $0x0030, 0(%rax)
    leave
    ret

.Lits_nonzero:
    movq $0, -8(%rbp)
    cmp $0, %rax
    jge .Lits_pos
    neg %rax
    movq $1, -8(%rbp)

.Lits_pos:
    lea -10(%rbp), %rcx
    movb $0, (%rcx)
    dec %rcx

    mov $10, %r8
.Lits_loop:
    test %rax, %rax
    jz .Lits_sign
    xor %rdx, %rdx
    div %r8
    add $'0', %dl
    movb %dl, (%rcx)
    dec %rcx
    jmp .Lits_loop

.Lits_sign:
    cmpq $1, -8(%rbp)
    jne .Lits_alloc
    movb $'-', (%rcx)
    dec %rcx

.Lits_alloc:
    inc %rcx
    lea -10(%rbp), %r9
    sub %rcx, %r9
    mov %r9, %rdi
    add $9, %rdi
    push %rcx
    push %r9
    call _malloc
    pop %r9
    pop %rcx
    movq $1, 0(%rax)
    add $8, %rax
    mov %rax, %rdi
    mov %rcx, %rsi
    mov %r9, %rcx
    rep movsb
    movb $0, (%rdi)
    leave
    ret

.global float_to_string
float_to_string:
    push %rbp
    mov %rsp, %rbp
    push %rbx
    push %r12
    movsd (%rdi), %xmm0
    mov $40, %rdi
    call _malloc
    movq $1, (%rax)
    add $8, %rax
    mov %rax, %rbx
    mov %rax, %r12
    pxor %xmm1, %xmm1
    ucomisd %xmm1, %xmm0
    jae .FTS_pos
    movb $'-', (%rbx)
    inc %rbx
    subsd %xmm0, %xmm1
    movapd %xmm1, %xmm0

.FTS_pos:
    cvttsd2si %xmm0, %rax
    mov %rax, %r8
    mov %rax, %rcx
    mov $1, %r9
    mov $10, %rsi

.FTS_count_loop:
    cmp $10, %rcx
    jl .FTS_write_start
    xor %rdx, %rdx
    mov %rcx, %rax
    div %rsi
    mov %rax, %rcx
    inc %r9
    jmp .FTS_count_loop

.FTS_write_start:
    add %r9, %rbx
    mov %rbx, %rcx
    mov %r8, %rax

.FTS_write_loop:
    dec %rcx
    xor %rdx, %rdx
    div %rsi
    add $'0', %dl
    movb %dl, (%rcx)
    test %rax, %rax
    jnz .FTS_write_loop
    movb $'.', (%rbx)
    inc %rbx
    cvtsi2sd %r8, %xmm1
    subsd %xmm1, %xmm0
    mov $6, %rcx

.FTS_frac_loop:
    mulsd FLOAT_TEN(%rip), %xmm0
    cvttsd2si %xmm0, %rax
    add $'0', %al
    movb %al, (%rbx)
    inc %rbx
    sub $'0', %al
    cvtsi2sd %rax, %xmm1
    subsd %xmm1, %xmm0
    dec %rcx
    jnz .FTS_frac_loop
    movb $0, (%rbx)
    mov %r12, %rax
    pop %r12
    pop %rbx
    leave
    ret

.global runtime_to_string
runtime_to_string:
    test $1, %rdi
    jnz int_to_string
    mov -8(%rdi), %rax
    cmp $1, %rax
    je .ret_self
    cmp $4, %rax
    je float_to_string

.ret_self:
    mov %rdi, %rax
    ret

.global get_double_value
get_double_value:
    test %rdi, %rdi
    jz .Lgdv_null
    mov %rdi, %rax
    test $1, %rax
    jz .read_obj
    sar $1, %rax
    cvtsi2sd %rax, %xmm0
    ret

.read_obj:
    movsd 0(%rdi), %xmm0
    ret

.Lgdv_null:
    pxor %xmm0, %xmm0
    ret

.global runtime_add
runtime_add:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp
    mov %rdi, %rax
    and %rsi, %rax
    and $1, %rax
    cmp $1, %rax
    je .Ladd_ints
    test $1, %rdi
    jnz .Lcheck_float_add
    mov -8(%rdi), %rax
    cmp $1, %rax
    je .Ldispatch_string_concat
    cmp $3, %rax
    je .Ldispatch_array_concat

.Lcheck_float_add:
    mov %rsi, -8(%rbp)
    call get_double_value
    movsd %xmm0, -16(%rbp)
    mov -8(%rbp), %rdi
    call get_double_value
    movsd %xmm0, %xmm1
    movsd -16(%rbp), %xmm0
    addsd %xmm1, %xmm0
    call newton_box_float
    leave
    ret

.Ladd_ints:
    mov %rdi, %rax
    add %rsi, %rax
    dec %rax
    leave
    ret

.Ldispatch_string_concat:
    call string_concat
    leave
    ret

.Ldispatch_array_concat:
    call array_concat
    leave
    ret

.global runtime_sub
runtime_sub:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp
    mov %rdi, %rax
    and %rsi, %rax
    and $1, %rax
    cmp $1, %rax
    je .Lsub_ints
    mov %rsi, -8(%rbp)
    call get_double_value
    movsd %xmm0, -16(%rbp)
    mov -8(%rbp), %rdi
    call get_double_value
    movsd %xmm0, %xmm1
    movsd -16(%rbp), %xmm0
    subsd %xmm1, %xmm0
    call newton_box_float
    leave
    ret

.Lsub_ints:
    mov %rdi, %rax
    sub %rsi, %rax
    inc %rax
    leave
    ret

.global runtime_mul
runtime_mul:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp
    mov %rdi, %rax
    and %rsi, %rax
    and $1, %rax
    cmp $1, %rax
    je .Lmul_ints
    mov %rsi, -8(%rbp)
    call get_double_value
    movsd %xmm0, -16(%rbp)
    mov -8(%rbp), %rdi
    call get_double_value
    movsd %xmm0, %xmm1
    movsd -16(%rbp), %xmm0
    mulsd %xmm1, %xmm0
    call newton_box_float
    leave
    ret

.Lmul_ints:
    sar $1, %rdi
    sar $1, %rsi
    mov %rdi, %rax
    imul %rsi, %rax
    shl $1, %rax
    or $1, %rax
    leave
    ret

.global runtime_div
runtime_div:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp
    mov %rsi, -8(%rbp)
    call get_double_value
    movsd %xmm0, -16(%rbp)
    mov -8(%rbp), %rdi
    call get_double_value
    movsd %xmm0, %xmm1
    movsd -16(%rbp), %xmm0
    divsd %xmm1, %xmm0
    call newton_box_float
    leave
    ret

.global string_compare_fast
string_compare_fast:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12; push %r13
    mov %rdi, %rbx; mov %rsi, %r12
    mov %rbx, %rdi; call string_len; mov %rax, %r13
    mov %r12, %rdi; call string_len
    cmp %rax, %r13; jne .Lsc_false
    mov %rbx, %rdi; mov -8(%rdi), %rcx
    cmp $5, %rcx; jne .Lsc_ptr1
    mov 0(%rdi), %rdi

.Lsc_ptr1:
    mov %r12, %rsi; mov -8(%rsi), %rcx
    cmp $5, %rcx; jne .Lsc_ptr2
    mov 0(%rsi), %rsi

.Lsc_ptr2:
    mov %r13, %rcx
    test %rcx, %rcx; jz .Lsc_true
    cld
    repe cmpsb
    jne .Lsc_false

.Lsc_true: mov $1, %rax; jmp .Lsc_done
.Lsc_false: mov $0, %rax
.Lsc_done: pop %r13; pop %r12; pop %rbx; leave; ret

.global runtime_eq
runtime_eq:
    push %rbp; mov %rsp, %rbp
    cmp %rdi, %rsi; je .Lreq_true
    mov %rdi, %rax; and $1, %rax; jnz .Lreq_false
    mov %rsi, %rax; and $1, %rax; jnz .Lreq_false
    test %rdi, %rdi; jz .Lreq_false
    test %rsi, %rsi; jz .Lreq_false
    mov -8(%rdi), %r8
    cmp $1, %r8; je .Lreq_str
    cmp $5, %r8; je .Lreq_str
    jmp .Lreq_false

.Lreq_str:
    mov -8(%rsi), %r9
    cmp $1, %r9; je .Lreq_do_str
    cmp $5, %r9; je .Lreq_do_str
    jmp .Lreq_false

.Lreq_do_str:
    call string_compare_fast
    cmp $1, %rax; je .Lreq_true
    jmp .Lreq_false

.Lreq_true: mov $3, %rax; leave; ret
.Lreq_false: mov $1, %rax; leave; ret

# --- SAFE NULL HANDLER ---
.Leq_check_null:
    test %rsi, %rsi
    jz .Leq_true
    jmp .Leq_false

.Leq_ints:
    cmp %rdi, %rsi
    je .Leq_true
    jmp .Leq_false

.Leq_strings:
    call newton_strcmp
    test %rax, %rax
    jz .Leq_true
    jmp .Leq_false

.Leq_true:
    mov $3, %rax
    leave; ret

.Leq_false:
    mov $1, %rax
    leave; ret

.global runtime_neq
runtime_neq:
	call runtime_eq
	xor $2, %rax
	ret

.global runtime_gt
runtime_gt:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp
    mov %rdi, %rax
    and %rsi, %rax
    and $1, %rax
    cmp $1, %rax
    je .Lgt_ints
    mov %rsi, -8(%rbp)
    call get_double_value
    movsd %xmm0, -16(%rbp)
    mov -8(%rbp), %rdi
    call get_double_value
    movsd %xmm0, %xmm1
    movsd -16(%rbp), %xmm0
    ucomisd %xmm1, %xmm0
    ja .Ltrue
    jmp .Lfalse

.Lgt_ints:
    cmp %rsi, %rdi
    jg .Ltrue
    jmp .Lfalse

.global runtime_lt
runtime_lt:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp
    mov %rdi, %rax
    and %rsi, %rax
    and $1, %rax
    cmp $1, %rax
    je .Llt_ints
    mov %rsi, -8(%rbp)
    call get_double_value
    movsd %xmm0, -16(%rbp)
    mov -8(%rbp), %rdi
    call get_double_value
    movsd %xmm0, %xmm1
    movsd -16(%rbp), %xmm0
    ucomisd %xmm1, %xmm0
    jb .Ltrue
    jmp .Lfalse

.Llt_ints:
    cmp %rsi, %rdi
    jl .Ltrue
    jmp .Lfalse

.global runtime_ge
runtime_ge:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp
    mov %rdi, %rax
    and %rsi, %rax
    and $1, %rax
    cmp $1, %rax
    je .Lge_ints
    mov %rsi, -8(%rbp)
    call get_double_value
    movsd %xmm0, -16(%rbp)
    mov -8(%rbp), %rdi
    call get_double_value
    movsd %xmm0, %xmm1
    movsd -16(%rbp), %xmm0
    ucomisd %xmm1, %xmm0
    jae .Ltrue
    jmp .Lfalse

.Lge_ints:
    cmp %rsi, %rdi
    jge .Ltrue
    jmp .Lfalse

.global runtime_le
runtime_le:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp
    mov %rdi, %rax
    and %rsi, %rax
    and $1, %rax
    cmp $1, %rax
    je .Lle_ints
    mov %rsi, -8(%rbp)
    call get_double_value
    movsd %xmm0, -16(%rbp)
    mov -8(%rbp), %rdi
    call get_double_value
    movsd %xmm0, %xmm1
    movsd -16(%rbp), %xmm0
    ucomisd %xmm1, %xmm0
    jbe .Ltrue
    jmp .Lfalse

.Lle_ints:
    cmp %rsi, %rdi
    jle .Ltrue
    jmp .Lfalse

.Ltrue:
    mov $3, %rax
    leave
    ret
.Lfalse:
    mov $1, %rax
    leave
    ret


.global runtime_and
runtime_and:
    mov %rdi, %rax
    and %rsi, %rax
    ret

.global runtime_or
runtime_or:
    mov %rdi, %rax
    or %rsi, %rax
    ret

.global runtime_not
runtime_not:
    mov %rsi, %rax
    xor $2, %rax
    ret

.global runtime_to_int
runtime_to_int:
    push %rbp
    mov %rsp, %rbp
    mov %rdi, %rax
    test $1, %rax
    jnz .ret_int
    mov -8(%rdi), %rcx
    cmp $1, %rcx
    je .parse_string
    call get_double_value
    cvttsd2siq %xmm0, %rax
    shl $1, %rax
    or $1, %rax
    jmp .ret_int

.parse_string:
    xor %rax, %rax
    xor %r9, %r9
    xor %rcx, %rcx
    mov $10, %r8
    movzx (%rdi), %rdx
    cmp $'-', %rdx
    jne .ps_loop
    mov $1, %r9
    inc %rcx

.ps_loop:
    movzx (%rdi, %rcx), %rdx
    test %rdx, %rdx
    jz .ps_done
    cmp $'0', %rdx
    jl .ps_done
    cmp $'9', %rdx
    jg .ps_done
    sub $'0', %rdx
    imul %r8, %rax
    add %rdx, %rax
    inc %rcx
    jmp .ps_loop

.ps_done:
    test %r9, %r9
    jz .ps_tag
    neg %rax

.ps_tag:
    shl $1, %rax
    or $1, %rax

.ret_int:
    leave
    ret

.global runtime_to_float
runtime_to_float:
    push %rbp
    mov %rsp, %rbp
    test $1, %rdi
    jz .is_ptr
    sar $1, %rdi
    cvtsi2sd %rdi, %xmm0
    call newton_box_float
    leave
    ret

.is_ptr:
    mov %rdi, %rax
    leave
    ret

.global runtime_xor
runtime_xor:
    mov %rdi, %rax
    xor %rsi, %rax
    or $1, %rax
    ret

.global runtime_random
runtime_random:
    push %rbp; mov %rsp, %rbp; sub $16, %rsp
    sar $1, %rdi
    cmp $0, %rdi
    jle .Lrand_zero
    mov %rdi, -16(%rbp)
    mov $318, %rax
    lea -8(%rbp), %rdi
    mov $8, %rsi
    mov $0, %rdx
    syscall

    mov -8(%rbp), %rax
    btr $63, %rax
    xor %rdx, %rdx
    mov -16(%rbp), %rcx
    div %rcx
    mov %rdx, %rax
    shl $1, %rax
    or $1, %rax
    leave; ret

.Lrand_zero:
    mov $1, %rax
    leave; ret

.global runtime_mod
runtime_mod:
    push %rbp; mov %rsp, %rbp
    sar $1, %rdi
    sar $1, %rsi
    mov %rdi, %rax
    cqo
    idiv %rsi
    mov %rdx, %rax
    shl $1, %rax
    or $1, %rax
    leave; ret

.global runtime_shr
runtime_shr:
    push %rbp; mov %rsp, %rbp
    sar $1, %rdi
    sar $1, %rsi
    mov %rsi, %rcx
    mov %rdi, %rax
    sar %cl, %rax
    shl $1, %rax
    or $1, %rax
    leave; ret

.global runtime_shl
runtime_shl:
    push %rbp; mov %rsp, %rbp
    sar $1, %rdi
    sar $1, %rsi
    mov %rsi, %rcx
    mov %rdi, %rax
    shl %cl, %rax
    shl $1, %rax
    or $1, %rax
    leave; ret

.global newton_to_int
newton_to_int:
    push %rbp; mov %rsp, %rbp
    test %rdi, %rdi; jz .Lnti_zero
    mov -8(%rdi), %rcx
    cmp $1, %rcx; je .Lnti_type1
    cmp $5, %rcx; je .Lnti_type5
    cmp $4, %rcx; je .Lnti_type4
    jmp .Lnti_zero

.Lnti_type4:
    movsd 0(%rdi), %xmm0
    cvttsd2siq %xmm0, %rax
    jmp .Lnti_ret

.Lnti_type1:
    mov %rdi, %rsi
    xor %r8, %r8
.Lnti_t1_len:
    cmpb $0, (%rsi, %r8); je .Lnti_parse
    inc %r8; jmp .Lnti_t1_len

.Lnti_type5:
    mov 0(%rdi), %rsi
    mov 8(%rdi), %r8

.Lnti_parse:
    xor %rax, %rax
    xor %r9, %r9
    xor %r10, %r10
    test %r8, %r8; jz .Lnti_zero
    cmpb $45, (%rsi, %r9)
    jne .Lnti_loop
    mov $1, %r10
    inc %r9

.Lnti_loop:
    cmp %r8, %r9; jge .Lnti_done
    movzx (%rsi, %r9), %rcx
    cmp $48, %rcx; jl .Lnti_done
    cmp $57, %rcx; jg .Lnti_done
    sub $48, %rcx
    imul $10, %rax
    add %rcx, %rax
    inc %r9
    jmp .Lnti_loop

.Lnti_done:
    test %r10, %r10; jz .Lnti_ret
    neg %rax
.Lnti_ret:
    shl $1, %rax
    or $1, %rax
    leave; ret

.Lnti_zero:
    mov $1, %rax
    leave; ret

.global newton_sizeof
newton_sizeof:
    push %rbp; mov %rsp, %rbp
    test %rdi, %rdi; jz .Lns_zero
    mov -8(%rdi), %rcx
    cmp $1, %rcx; je .Lns_type1
    cmp $2, %rcx; je .Lns_type3
    cmp $3, %rcx; je .Lns_type3
    cmp $5, %rcx; je .Lns_type5
    jmp .Lns_zero

.Lns_type1:
    mov %rdi, %rsi
    xor %rax, %rax
.Lns_t1_loop:
    cmpb $0, (%rsi, %rax); je .Lns_ret
    inc %rax; jmp .Lns_t1_loop

.Lns_type3:
    call collection_len
    leave; ret

.Lns_type5:
    mov 8(%rdi), %rax
    jmp .Lns_ret

.Lns_ret:
    shl $1, %rax; or $1, %rax
    leave; ret

.Lns_zero:
    mov $1, %rax
    leave; ret

.global newton_inc
newton_inc:
    push %rbp; mov %rsp, %rbp
    test %rdi, %rdi; jnz .Lni_do
    mov $1, %rdi
.Lni_do:
    sar $1, %rdi
    inc %rdi
    shl $1, %rdi
    or $1, %rdi
    mov %rdi, %rax
    leave; ret
