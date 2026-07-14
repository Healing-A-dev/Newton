.extern BCryptGenRandom

.section .rodata
	FLOAT_TEN: .double 10.0

.section .text

.global int_to_string
int_to_string:
    push %rbp
    mov %rsp, %rbp
    sub $32, %rsp      # Create a 32-byte local buffer on the stack
    
    # 1. Untag the Newton integer
    sar $1, %rdi
    mov %rdi, %rax
    
    # 2. Handle Zero explicitly
    test %rax, %rax
    jnz .Lits_nonzero
    
    mov $2, %rdi       # Alloc 2 bytes ("0" + "\0")
    call _malloc
    movq $1, 0(%rax)   # Tag as Type 1 String
    add $8, %rax       # Shift to perfectly aligned payload
    movw $0x0030, 0(%rax) # Write '0' and '\0'
    leave
    ret

.Lits_nonzero:
    movq $0, -8(%rbp)  # is_neg = false
    cmp $0, %rax
    jge .Lits_pos
    neg %rax
    movq $1, -8(%rbp)  # is_neg = true

.Lits_pos:
    lea -10(%rbp), %rcx
    movb $0, (%rcx)    # Null terminator
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
    inc %rcx           # %rcx now points to the first character!
    
    # 3. Calculate Exact Length
    lea -10(%rbp), %r9
    sub %rcx, %r9      # r9 = length (excluding \0)
    
    # 4. Allocate Exact Heap Memory
    mov %r9, %rdi
    add $9, %rdi           # Add 1 for \0
    
    push %rcx          # Preserve registers across _malloc
    push %r9
    call _malloc
    pop %r9
    pop %rcx
    
    movq $1, 0(%rax)   # Tag as Type 1
    add $8, %rax       # Shift to perfectly aligned payload!
    
    # 5. Copy from Stack to GC-Safe Heap Buffer
    mov %rax, %rdi
    mov %rcx, %rsi
    mov %r9, %rcx
    rep movsb
    movb $0, (%rdi)    # Null terminate securely
    
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
    test %rdi, %rdi         # [FIX] Prevent Segfaults on uninitialized variables!
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
    pxor %xmm0, %xmm0       # Coalesce NULL to 0.0
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

    # 1. Compare lengths first (O(1) rejection)
    mov %rbx, %rdi; call string_len; mov %rax, %r13
    mov %r12, %rdi; call string_len
    cmp %rax, %r13; jne .Lsc_false

    # 2. Resolve Pointer A
    mov %rbx, %rdi; mov -8(%rdi), %rcx
    cmp $5, %rcx; jne .Lsc_ptr1
    mov 0(%rdi), %rdi
.Lsc_ptr1:

    # 3. Resolve Pointer B
    mov %r12, %rsi; mov -8(%rsi), %rcx
    cmp $5, %rcx; jne .Lsc_ptr2
    mov 0(%rsi), %rsi
.Lsc_ptr2:

    # 4. Hardware Byte Comparison
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
    cmp %rdi, %rsi; je .Lreq_true     # Fast-path: Identical pointers

    mov %rdi, %rax; and $1, %rax; jnz .Lreq_false
    mov %rsi, %rax; and $1, %rax; jnz .Lreq_false
    test %rdi, %rdi; jz .Lreq_false
    test %rsi, %rsi; jz .Lreq_false

    # Verify both are Strings (Type 1 or 5)
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

.Lreq_true: mov $3, %rax; leave; ret   # Return Tagged True
.Lreq_false: mov $1, %rax; leave; ret  # Return Tagged False

# --- SAFE NULL HANDLER ---
.Leq_check_null:
    test %rsi, %rsi
    jz .Leq_true           # If both are 0, they are equal!
    jmp .Leq_false         # If RDI is 0 but RSI is valid, not equal

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
    mov $3, %rax        # True (1 | 2)
    leave; ret

.Leq_false:
    mov $1, %rax        # False (0 | 1)
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
    jnz .ret_int     # Return as-is (already an int)

    # Check the VM Object Type Header!
    # Data Pointers have their type located 8 bytes before the pointer.
    mov -8(%rdi), %rcx
    cmp $1, %rcx
    je .parse_string # Type 1 = String! Let's parse it!

    # Otherwise, assume it's a Float and fallback to old logic
    call get_double_value
    cvttsd2siq %xmm0, %rax
    shl $1, %rax
    or $1, %rax
    jmp .ret_int

.parse_string:
    xor %rax, %rax      # Result Accumulator = 0
    xor %r9, %r9        # Sign Flag = 0 (positive)
    xor %rcx, %rcx      # String Index = 0
    mov $10, %r8        # Base 10 multiplier

    # Check for negative sign on the first character
    movzx (%rdi), %rdx
    cmp $'-', %rdx
    jne .ps_loop
    mov $1, %r9         # Set Sign Flag to 1 (negative)
    inc %rcx            # Skip the '-' character

.ps_loop:
    movzx (%rdi, %rcx), %rdx  # Read 1 character
    test %rdx, %rdx
    jz .ps_done               # If NULL terminator, we are done

    # Ensure character is between '0' and '9'
    cmp $'0', %rdx
    jl .ps_done
    cmp $'9', %rdx
    jg .ps_done

    # Convert ASCII to Int: Accumulator = (Accumulator * 10) + (Char - '0')
    sub $'0', %rdx
    imul %r8, %rax
    add %rdx, %rax

    inc %rcx
    jmp .ps_loop

.ps_done:
    # Apply negative sign if necessary
    test %r9, %r9
    jz .ps_tag
    neg %rax

.ps_tag:
    # Tag the final integer for the Newton VM!
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

.global runtime_xor
runtime_xor:
    mov %rdi, %rax
    xor %rsi, %rax
    # Newton Integer Tags end in 1. (A | 1) ^ (B | 1) ends in 0.
    # We MUST retag it with an OR instruction!
    or $1, %rax
    ret

.global runtime_random
runtime_random:
    push %rbp; mov %rsp, %rbp
    
    # 1. Allocate 48 bytes (32-byte Shadow Space + 16-byte local buffers)
    sub $48, %rsp
    and $-16, %rsp

    # 2. Untag the max boundary limit
    sar $1, %rdi
    cmp $0, %rdi
    jle .Lrand_zero

    mov %rdi, 32(%rsp)      # Save un-tagged limit safely into our local stack

    # --- WINDOWS ABI BRIDGE FOR BCryptGenRandom ---
    mov $0, %rcx            # Arg 1: hAlgorithm = NULL
    lea 40(%rsp), %rdx      # Arg 2: pbBuffer = Address of our 8-byte stack buffer
    mov $8, %r8             # Arg 3: cbBuffer = 8 bytes
    mov $2, %r9             # Arg 4: dwFlags = BCRYPT_USE_SYSTEM_PREFERRED_RNG (0x02)
    call BCryptGenRandom
    # ----------------------------------------------

    # 3. Read the 8 random bytes we just got from the Windows Kernel
    mov 40(%rsp), %rax
    btr $63, %rax

    # 4. Modulo arithmetic (Random % Max)
    xor %rdx, %rdx
    mov 32(%rsp), %rcx
    div %rcx

    # 5. Tag remainder and return to Newton VM!
    mov %rdx, %rax
    shl $1, %rax
    or $1, %rax

    leave; ret

.Lrand_zero:
    mov $1, %rax            # Tagged integer 0
    leave; ret


.global runtime_mod
runtime_mod:
    push %rbp; mov %rsp, %rbp
    sar $1, %rdi      # Untag integer A
    sar $1, %rsi      # Untag integer B
    mov %rdi, %rax
    cqo
    idiv %rsi         # Hardware division (Remainder automatically goes to %rdx)
    mov %rdx, %rax    # Move remainder to return register
    shl $1, %rax      # Re-tag as Newton Integer
    or $1, %rax
    leave; ret

.global runtime_shr
runtime_shr:
    push %rbp; mov %rsp, %rbp
    sar $1, %rdi
    sar $1, %rsi
    mov %rsi, %rcx    # Shift amount must be in %cl
    mov %rdi, %rax
    sar %cl, %rax     # Hardware Shift Right
    shl $1, %rax      # Re-tag
    or $1, %rax
    leave; ret

.global runtime_shl
runtime_shl:
    push %rbp; mov %rsp, %rbp
    sar $1, %rdi      # Untag Integer A
    sar $1, %rsi      # Untag Integer B
    mov %rsi, %rcx    # Shift amount MUST be placed in the %cl register
    mov %rdi, %rax    
    shl %cl, %rax     # Hardware Shift Left
    shl $1, %rax      # Re-tag as a Newton Integer
    or $1, %rax
    leave; ret

.global newton_to_int
newton_to_int:
    push %rbp; mov %rsp, %rbp
    test %rdi, %rdi; jz .Lnti_zero
    
    # 1. Check String Type (Offset -8)
    mov -8(%rdi), %rcx
    cmp $1, %rcx; je .Lnti_type1
    cmp $5, %rcx; je .Lnti_type5
    jmp .Lnti_zero

.Lnti_type1:
    mov %rdi, %rsi      # Type 1: Char pointer is the string itself
    xor %r8, %r8
.Lnti_t1_len:           # Find length using null-terminator
    cmpb $0, (%rsi, %r8); je .Lnti_parse
    inc %r8; jmp .Lnti_t1_len

.Lnti_type5:
    mov 0(%rdi), %rsi   # Type 5: Raw char pointer is at offset 0
    mov 8(%rdi), %r8    # Type 5: Exact length is at offset 8
    
.Lnti_parse:
    xor %rax, %rax      # Result = 0
    xor %r9, %r9        # Index = 0
    xor %r10, %r10      # Sign = 0 (Positive)
    test %r8, %r8; jz .Lnti_zero
    
    # Check for Negative Sign '-'
    cmpb $45, (%rsi, %r9)
    jne .Lnti_loop
    mov $1, %r10
    inc %r9
    
.Lnti_loop:
    cmp %r8, %r9; jge .Lnti_done
    movzx (%rsi, %r9), %rcx
    
    # Verify character is between '0' (48) and '9' (57)
    cmp $48, %rcx; jl .Lnti_done
    cmp $57, %rcx; jg .Lnti_done
    
    sub $48, %rcx       # Convert ASCII to integer
    imul $10, %rax      # Multiply current result by 10
    add %rcx, %rax      # Add new digit
    
    inc %r9
    jmp .Lnti_loop
    
.Lnti_done:
    test %r10, %r10; jz .Lnti_ret
    neg %rax            # Apply negative sign if needed
.Lnti_ret:
    shl $1, %rax        # Re-tag as a Newton Integer
    or $1, %rax
    leave; ret
    
.Lnti_zero:
    mov $1, %rax        # Tagged 0
    leave; ret

.global newton_sizeof
newton_sizeof:
    push %rbp; mov %rsp, %rbp
    test %rdi, %rdi; jz .Lns_zero

    mov -8(%rdi), %rcx

    cmp $1, %rcx; je .Lns_type1     
    cmp $2, %rcx; je .Lns_type3     # Route Maps
    cmp $3, %rcx; je .Lns_type3     # Route Arrays
    cmp $5, %rcx; je .Lns_type5     # Route Slices
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
    mov $1, %rdi            # [FIX] Coalesce NULL loop counter to Tagged 0
.Lni_do:
    sar $1, %rdi
    inc %rdi
    shl $1, %rdi
    or $1, %rdi
    mov %rdi, %rax
    leave; ret
