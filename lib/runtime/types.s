.section .rodata
    .Lstr_int:    .string "int"
    .Lstr_string: .string "string"
    .Lstr_map:    .string "map"
    .Lstr_list:   .string "list"
    .Lstr_float:  .string "float"
    .Lstr_unknown:.string "unknown"

.section .text

# --- STRING OPS ---
.global string_len
string_len:
    test %rdi, %rdi     # Check for NULL
    jz .null_len
    xor %rax, %rax
.len_loop:
    cmpb $0, (%rdi, %rax)
    je .len_done
    inc %rax
    jmp .len_loop
.len_done:
    ret
.null_len:
    xor %rax, %rax
    ret

.global string_concat
string_concat:
    push %rbp
    mov %rsp, %rbp
    
    # Save Inputs
    push %rdi
    push %rsi
    
    # 1. Get Lengths
    call string_len
    mov %rax, %r8       # R8 = Len1
    
    mov (%rsp), %rdi    # Restore RSI (Str2) from stack
    call string_len
    mov %rax, %r9       # R9 = Len2
    
    # 2. Calculate Size
    mov %r8, %rcx
    add %r9, %rcx
    add $9, %rcx        # +8 Header, +1 Null
    
    # Save Lengths for Copying
    push %r8
    push %r9
    
    # 3. Allocate Memory
    mov %rcx, %rdi
    call _malloc
    mov %rax, %r11      # R11 = New Object
    
    # Restore Lengths & Inputs
    pop %r9
    pop %r8
    pop %rsi
    pop %rdi
    
    # [FIX] 4. Zero-Initialize Memory (Manual Implementation)
    # Since we do not have _memset, we use rep stosb to fill memory with 0.
    
    push %rdi           # Save registers we need later
    push %rsi
    push %rax           # Save New Pointer (Important!)
    push %r8
    push %r9
    
    mov %rax, %rdi      # Destination: New Memory Address
    mov %r8, %rcx       
    add %r9, %rcx
    add $9, %rcx        # Count: Total Bytes
    xor %rax, %rax      # Value: 0
    cld                 # Clear Direction Flag (Forward)
    rep stosb           # Write 0 to [RDI], increment RDI, decrement RCX
    
    pop %r9
    pop %r8
    pop %rax            # Restore New Pointer (RAX holds the base address again)
    pop %rsi
    pop %rdi
    
    # 5. Setup Header
    movq $1, 0(%rax)    # Type = String
    add $8, %rax        # RAX points to Data
    
    # 6. Copy Str1
    push %rax           # Save Result Data Ptr
    push %rsi           # Save Str2
    push %r9            # Save Len2
    
    mov %rdi, %rsi      # Source: Str1
    mov %rax, %rdi      # Dest: New Data
    mov %r8, %rcx       # Count: Len1
    cld
    rep movsb           # Copy RCX bytes from RSI to RDI
    
    # 7. Copy Str2
    pop %r9             # Restore Len2
    pop %rsi            # Restore Str2 (Source)
    
    mov %r9, %rcx       # Count: Len2
    rep movsb
    
    # 8. Null Terminate
    # RDI now points to end of Str2.
    movb $0, (%rdi)
    
    pop %rax            # Restore Result Ptr
    
    leave
    ret
        
.global string_substring
string_substring:
    push %rbp; mov %rsp, %rbp
    push %rbx; push %r12; push %r13; push %r14
    mov %rdi, %rbx; sar $1, %rsi; sar $1, %rdx
    cmp $0, %rdx; jle .Lsub_empty
    mov %rsi, %r12; mov %rdx, %r13
    mov %r13, %rdi; add $9, %rdi; call _malloc
    movq $1, (%rax); add $8, %rax
    mov %rbx, %rsi; add %r12, %rsi; mov %rax, %rdi; mov %r13, %rcx; rep movsb
    movb $0, (%rdi); sub %r13, %rdi; mov %rdi, %rax; jmp .Lsub_ret
.Lsub_empty:
    mov $9, %rdi; call _malloc; movq $1, (%rax); add $8, %rax; movb $0, (%rax)
.Lsub_ret: pop %r14; pop %r13; pop %r12; pop %rbx; leave; ret

# --- ARRAY OPS ---
.global new_array
new_array:
    push %rbp; mov %rsp, %rbp; push %rbx
    add $8, %rdi; call _malloc
    movq $3, (%rax); add $8, %rax; movq $0, (%rax)
    pop %rbx; leave; ret

.global array_set
array_set:
    sar $1, %rsi; mov (%rdi), %rcx
    cmp %rsi, %rcx; jg .Larr_set_do
    mov %rsi, %rcx; inc %rcx; mov %rcx, (%rdi)
.Larr_set_do: mov %rdx, 8(%rdi, %rsi, 8); ret

.global array_get
array_get: sar $1, %rsi; mov 8(%rdi, %rsi, 8), %rax; ret

.global array_len
array_len: mov (%rdi), %rax; shl $1, %rax; or $1, %rax; ret

.global array_concat
array_concat:
    push %rbp; mov %rsp, %rbp; push %rbx; push %r12; push %r13
    mov %rdi, %rbx; mov %rsi, %r12
    mov (%rbx), %r8; mov (%r12), %r9
    mov %r8, %rdi; add %r9, %rdi; shl $3, %rdi; add $8, %rdi
    push %r8; push %r9; call new_array; pop %r9; pop %r8
    mov %r8, %rcx; add %r9, %rcx; mov %rcx, (%rax)
    mov %rax, %r13
    lea 8(%rbx), %rsi; lea 8(%r13), %rdi; mov %r8, %rcx; rep movsq
    lea 8(%r12), %rsi; mov %r9, %rcx; rep movsq
    mov %r13, %rax; pop %r13; pop %r12; pop %rbx; leave; ret

# --- MAP OPS ---
.global new_map
new_map:
    push %rbp; mov %rsp, %rbp
    mov $8, %rdi; call _malloc
    movq $2, (%rax); add $8, %rax
    movq $0, (%rax); leave; ret

.global map_set
map_set:
    push %rbp; mov %rsp, %rbp; mov (%rdi), %rcx
.Lmap_upd:
    test %rcx, %rcx; jz .Lmap_new
    mov 0(%rcx), %r8
    push %rdi; push %rsi; push %rdx; push %rcx
    mov %r8, %rdi; call runtime_eq
    pop %rcx; pop %rdx; pop %rsi; pop %rdi
    cmp $3, %rax; je .Lmap_found
    mov 16(%rcx), %rcx; jmp .Lmap_upd
.Lmap_found: mov %rdx, 8(%rcx); leave; ret
.Lmap_new:
    push %rdi; push %rsi; push %rdx
    mov $24, %rdi; call _malloc; add $8, %rax
    pop %rdx; pop %rsi; pop %rdi
    mov %rsi, 0(%rax); mov %rdx, 8(%rax)
    mov (%rdi), %rcx; mov %rcx, 16(%rax); mov %rax, (%rdi); leave; ret

.global map_get
map_get:
    mov (%rdi), %rcx
.Lmap_g:
    test %rcx, %rcx; jz .Lmap_null
    mov 0(%rcx), %r8
    push %rdi; push %rsi; push %rcx
    mov %r8, %rdi; call runtime_eq
    pop %rcx; pop %rsi; pop %rdi
    cmp $3, %rax; je .Lmap_g_fnd
    mov 16(%rcx), %rcx; jmp .Lmap_g
.Lmap_g_fnd: mov 8(%rcx), %rax; ret
.Lmap_null: mov $1, %rax; ret

.global map_delete
map_delete:
    push %rbp; mov %rsp, %rbp
    mov (%rdi), %rcx; test %rcx, %rcx; jz .Lmd_end
    mov 0(%rcx), %r8
    push %rdi; push %rsi; push %rcx
    mov %r8, %rdi; call runtime_eq
    pop %rcx; pop %rsi; pop %rdi
    cmp $3, %rax; je .Lmd_head
    mov %rcx, %rdx; mov 16(%rcx), %rcx
.Lmd_lp:
    test %rcx, %rcx; jz .Lmd_end
    mov 0(%rcx), %r8
    push %rdi; push %rsi; push %rdx; push %rcx
    mov %r8, %rdi; call runtime_eq
    pop %rcx; pop %rdx; pop %rsi; pop %rdi
    cmp $3, %rax; je .Lmd_node
    mov %rcx, %rdx; mov 16(%rcx), %rcx; jmp .Lmd_lp
.Lmd_head: mov (%rdi), %rcx; mov 16(%rcx), %r8; mov %r8, (%rdi); jmp .Lmd_end
.Lmd_node: mov 16(%rcx), %r8; mov %r8, 16(%rdx)
.Lmd_end: leave; ret

.global map_len
map_len:
    mov (%rdi), %rcx; xor %rax, %rax
.Lml: test %rcx, %rcx; jz .mld; inc %rax; mov 16(%rcx), %rcx; jmp .Lml
.mld: shl $1, %rax; or $1, %rax; ret

.global map_head
map_head: mov (%rdi), %rax; ret
.global node_key
node_key: mov 0(%rdi), %rax; ret
.global node_val
node_val: mov 8(%rdi), %rax; ret
.global node_next
node_next: mov 16(%rdi), %rax; ret

# --- POLYMORPHISM ---
.global collection_len
collection_len:
    test %rdi, %rdi; jz .cz; mov -8(%rdi), %rax
    cmp $1, %rax; je .dsl; cmp $2, %rax; je map_len; cmp $3, %rax; je array_len
.cz: mov $1, %rax; ret
.dsl: call string_len; shl $1, %rax; or $1, %rax; ret

.global collection_get
collection_get:
    test %rdi, %rdi; jz .cz; mov -8(%rdi), %rax
    cmp $1, %rax; je .dsg; cmp $2, %rax; je map_get; cmp $3, %rax; je array_get
    mov $1, %rax; ret
.dsg: sar $1, %rsi; xor %rax, %rax; movb (%rdi, %rsi, 1), %al; shl $1, %rax; or $1, %rax; ret

.global collection_set
collection_set:
    test %rdi, %rdi; jz .csetr; mov -8(%rdi), %rax
    cmp $2, %rax; je map_set; cmp $3, %rax; je array_set
.csetr: ret

# --- TYPE HELPERS ---
.global get_type_str
get_type_str:
    push %rbp; mov %rsp, %rbp
    mov %rdi, %rax; and $1, %rax; cmp $1, %rax; je .ti
    test %rdi, %rdi; jz .tu
    mov -8(%rdi), %rax
    cmp $1, %rax; je .ts; cmp $2, %rax; je .tm; cmp $3, %rax; je .tl; cmp $4, %rax; je .tf
.tu: lea .Lstr_unknown(%rip), %rdi; jmp .ta
.ti: lea .Lstr_int(%rip), %rdi; jmp .ta
.ts: lea .Lstr_string(%rip), %rdi; jmp .ta
.tm: lea .Lstr_map(%rip), %rdi; jmp .ta
.tl: lea .Lstr_list(%rip), %rdi; jmp .ta
.tf: lea .Lstr_float(%rip), %rdi; jmp .ta
.ta: call string_new; leave; ret

.global string_new
string_new:
    push %rbp; mov %rsp, %rbp; push %rbx; push %r14
    mov %rdi, %rbx; xor %rcx, %rcx
.snl: cmpb $0, (%rbx, %rcx); je .sna; inc %rcx; jmp .snl
.sna: mov %rcx, %rdi; add $9, %rdi; call _malloc
    movq $1, (%rax); add $8, %rax; mov %rbx, %rsi; mov %rax, %rdi
.snc: movb (%rsi), %cl; movb %cl, (%rdi); test %cl, %cl; jz .snd; inc %rsi; inc %rdi; jmp .snc
.snd: pop %r14; pop %rbx; leave; ret

.global newton_strcmp
newton_strcmp:
    xor %rax, %rax
.nsc: movb (%rdi), %al; movb (%rsi), %cl; cmp %al, %cl; jne .nsd; test %al, %al; jz .nsm; inc %rdi; inc %rsi; jmp .nsc
.nsd: mov $1, %rax; ret
.nsm: xor %rax, %rax; ret

.global _keys_equal
_keys_equal: jmp newton_strcmp

.global newton_box_float
newton_box_float:
    push %rbp; mov %rsp, %rbp; sub $16, %rsp
    movsd %xmm0, (%rsp); mov $16, %rdi; call _malloc
    movsd (%rsp), %xmm0; add $16, %rsp; movq $4, (%rax); movsd %xmm0, 8(%rax); add $8, %rax; leave; ret

# --- [FIXED] ARGV WITH OFFSET ---
.global runtime_get_arg
runtime_get_arg:
    push %rbp; mov %rsp, %rbp; push %rbx; push %r12; push %r13
    sar $1, %rdi
    
    # [FIX] Offset index by 1 so '0' gets First Argument, not Program Name
    inc %rdi 
    
    cmp __argc(%rip), %rdi; jge .Largv_null
    mov __sys_argv(%rip), %rax
    mov (%rax, %rdi, 8), %rbx   # char*
    xor %rcx, %rcx
.Largv_len: cmpb $0, (%rbx, %rcx); je .Largv_alloc; inc %rcx; jmp .Largv_len
.Largv_alloc:
    mov %rcx, %r12
    mov %rcx, %rdi; add $9, %rdi; call _malloc
    movq $1, (%rax); add $8, %rax
    mov %rax, %rdi; mov %rbx, %rsi; mov %r12, %rcx; rep movsb
    movb $0, (%rdi); sub %r12, %rdi; mov %rdi, %rax
    pop %r13; pop %r12; pop %rbx; leave; ret
.Largv_null:
    mov $1, %rax; pop %r13; pop %r12; pop %rbx; leave; ret
