.section .rodata
	FLOAT_TEN: .double 10.0

.section .text

.global int_to_string
int_to_string:
    push %rbp
    mov %rsp, %rbp
    push %rbx
    push %r12
    push %r13
    push %r14
    sar $1, %rdi
    mov %rdi, %rax
    movq $0, %r12
    cmp $0, %rax
    jge .Lconvert_start
    neg %rax
    movq $1, %r12
.Lconvert_start:
    push %rax
    # [FIX] Alloc 48 bytes to fit the hardcoded offset 30
    mov $48, %rdi
    call _malloc
    mov %rax, %r14
    pop %rax
    movq $1, (%r14)
    add $8, %r14
    lea 30(%r14), %rbx
    movb $0, (%rbx)
    dec %rbx
    mov %r14, %r13
    cmp $0, %rax
    jne .Ldigit_loop
    movb $'0', (%rbx)
    dec %rbx
    jmp .Lfinish_conversion
.Ldigit_loop:
    cmp $0, %rax
    je .Lsign_check
    xor %rdx, %rdx
    mov $10, %rcx
    div %rcx
    add $'0', %dl
    movb %dl, (%rbx)
    dec %rbx
    jmp .Ldigit_loop
.Lsign_check:
    cmp $1, %r12
    jne .Lfinish_conversion
    movb $'-', (%rbx)
    dec %rbx
.Lfinish_conversion:
    inc %rbx
    mov %rbx, %rsi
    mov %r13, %rdi
.Lmove_loop:
    movb (%rsi), %cl
    movb %cl, (%rdi)
    test %cl, %cl
    je .Ldone_move
    inc %rsi
    inc %rdi
    jmp .Lmove_loop
.Ldone_move:
    mov %r13, %rax
    pop %r14
    pop %r13
    pop %r12
    pop %rbx
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
    # unknown? return self
.ret_self:
    mov %rdi, %rax
    ret

.global get_double_value
get_double_value:
    mov %rdi, %rax
    test $1, %rax
    jz .read_obj
    
    sar $1, %rax
    cvtsi2sd %rax, %xmm0
    ret

.read_obj:
    movsd 0(%rdi), %xmm0
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

.global runtime_eq
runtime_eq:
    push %rbp
    mov %rsp, %rbp
    cmp %rdi, %rsi
    je .Leq_true
    test %rdi, %rdi
    jz .Leq_false
    test %rsi, %rsi
    jz .Leq_false
    mov %rdi, %rax
    or %rsi, %rax
    and $1, %rax
    cmp $1, %rax
    je .Leq_false
    mov -8(%rdi), %rax
    mov -8(%rsi), %rcx
    cmp %rax, %rcx
    jne .Leq_false
    cmp $1, %rax
    je .Leq_string_check
    jmp .Leq_false
.Leq_string_check:
    push %rdi
    push %rsi
    call newton_strcmp
    pop %rsi
    pop %rdi
    test %rax, %rax
    jz .Leq_true
    jmp .Leq_false
.Leq_true:
    mov $3, %rax
    leave
    ret
.Leq_false:
    mov $1, %rax
    leave
    ret

.global runtime_neq
runtime_neq:
    push %rbp
    mov %rsp, %rbp
    sub $16, %rsp
    call runtime_eq
    mov $4, %rcx
    sub %rax, %rcx
    mov %rcx, %rax
    leave
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
    # RDI & RSI
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
    # NOT only cares about RSI (Right operand in our parser hack)
    mov %rsi, %rax
    xor $2, %rax        # Flip bit 1 (1->3, 3->1)
    ret

.global runtime_to_int
runtime_to_int:
    push %rbp
    mov %rsp, %rbp
    
    mov %rdi, %rax
    test $1, %rax
    jnz .ret_int     # Return as-is
    
    call get_double_value
    
    cvttsd2siq %xmm0, %rax
    
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
    
    sar $1, %rdi          # Untag
    cvtsi2sd %rdi, %xmm0  # Convert to Double
    
    call newton_box_float 
    leave
    ret

.is_ptr:
    mov %rdi, %rax
    leave
    ret
