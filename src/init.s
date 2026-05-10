.segment "INIT"

COLD_START:
        ; First-boot prologue. Reset vector points here on cold load
        ; (CMake RESET 0x1000); HEADER's warm shim does the same setup
        ; on every subsequent reset after we rewrite $FFFC below.
        ldx #STACK_TOP
        txs
        cld
        jsr ria_init_io

        ; Seed RNDSEED with 31 bits of OS entropy. RNDSEED is 5 bytes
        ; of FP: exponent + 4-byte mantissa. Set exponent $80 for a
        ; well-formed value; first RND(positive) normalizes. Bit 7
        ; of mantissa byte 1 is the sign bit in storage, so use
        ; RIA_SREG+1 there — lrand masks 0x7FFFFFFF, so that byte's
        ; high bit is guaranteed zero (positive). The other three
        ; bytes carry random bits with no sign-position constraint.
        lda #$80
        sta RNDSEED
        lda #RIA_ATTR_LRAND
        sta RIA_A
        lda #RIA_OP_ATTR_GET
        sta RIA_OP
        jsr RIA_SPIN
        sta RNDSEED+2
        stx RNDSEED+3
        lda RIA_SREG+1
        sta RNDSEED+1
        lda RIA_SREG
        sta RNDSEED+4

        ; CURLIN+1 = $FF marks direct mode; otherwise error handling
        ; would print bogus line numbers from ZP garbage on cold boot.
        lda #$FF
        sta CURLIN+1

        ; JMPADRS is a 3-byte ZP trampoline UNARY uses for function
        ; dispatch (eval.s patches +1/+2, calls jsr JMPADRS). Seed +0
        ; with the JMP-absolute opcode or PEEK/RND/FRE/etc. wedge.
        lda #$4C
        sta JMPADRS

        lda #$03
        sta DSCLEN

        stz SHIFTSIGNEXT
        stz LASTPT+1
        lda #$FF              ; "no I/O redirect" sentinel; CMD/INPUT#/
        sta CURDVC            ; GET# overwrite with lfn 0..7
        stz Z14
        stz POSX
        stz lsav_fd
        stz chrout_ptr+1      ; non-zero hi byte = chrout-to-buffer mode
        stz auto_run          ; auto-load/RUN state machine (see loadsave.s)
        ldx #TEMPST
        stx TEMPPT

        stz __TXTTAB_START__  ;synthetic "previous-line terminator"
        jsr SCRTCH            ; falls through to CLEARC, which sets FRETOP

        ; ZP and program-memory pointers are now valid, so HEADER's
        ; warm shim can take over. Hand future hardware resets to it.
        lda #<WARM_START
        sta $FFFC
        lda #>WARM_START
        sta $FFFD

        lda #<QT_BANNER
        ldy #>QT_BANNER
        jsr STROUT

        ldx #<(__TXTTAB_SIZE__ - 3)
        lda #>(__TXTTAB_SIZE__ - 3)
        jsr LINPRTNS
        lda #<QT_BYTES_FREE
        ldy #>QT_BYTES_FREE
        jsr STROUT

        ; Pull argv into INPUTBUFFER for parsing. The OS argv blob
        ; starts with a 2-byte offset table (offset_to_argv0,
        ; offset_to_argv1, …) null-terminated, followed by
        ; null-terminated string data; offsets are relative to the
        ; start of the blob, so an absolute pointer is INPUTBUFFER +
        ; offset. Bytes past the pushed count short-stack to 0, so
        ; a short argv just zero-fills trailing offset slots.
        lda #RIA_OP_ARGV
        sta RIA_OP
        jsr RIA_SPIN
        ldy #$00
@argv_pop:
        lda RIA_XSTACK
        sta __INBUF_START__,y
        iny
        bne @argv_pop
        ria_zxstack

        ; Walk argv[1..]: each -c[0-2] updates the caps mode (last
        ; one wins); the first non-flag argument is remembered as
        ; the filename to LOAD+RUN.
        ldx #$01                  ; X = caps mode (default 1)
        stz DEST                  ; DEST = first filename pointer (0 = none)
        stz DEST+1
        ldy #$02                  ; Y walks the offset table at INPUTBUFFER
@argv_loop:
        lda __INBUF_START__,y
        sta INDEX
        iny
        lda __INBUF_START__,y
        sta INDEX+1
        iny
        ; null entry → end of table
        lda INDEX
        ora INDEX+1
        beq @argv_done
        ; offset → absolute pointer
        clc
        lda INDEX
        adc #<__INBUF_START__
        sta INDEX
        lda INDEX+1
        adc #>__INBUF_START__
        sta INDEX+1

        phy                       ; save loop Y across the (INDEX),y reads
        ldy #$00
        lda (INDEX),y
        cmp #'-'
        bne @argv_filename
        iny
        lda (INDEX),y
        cmp #'c'
        bne @argv_filename
        iny
        lda (INDEX),y
        sec
        sbc #'0'
        cmp #$03
        bcs @argv_filename
        tax                       ; valid -c<n>
        bra @argv_next

@argv_filename:
        lda DEST+1                ; first non-flag wins
        bne @argv_next
        lda INDEX
        sta DEST
        lda INDEX+1
        sta DEST+1

@argv_next:
        ply
        bra @argv_loop

@argv_done:
        ; Apply caps mode (default or -c<n>); ria_caps_set takes X.
        jsr ria_caps_set

        ; If a filename was found, push it and auto-load.
        lda DEST+1
        beq @argv_skip_load
        lda DEST
        sta INDEX
        lda DEST+1
        sta INDEX+1

        ; Push filename ((INDEX) string) to xstack in reverse.
        ; OS-side terminator short-stacks to 0.
        ldy #$00
@argv_strlen:
        lda (INDEX),y
        beq @argv_open
        iny
        bne @argv_strlen
@argv_open:
        tya                       ; empty filename (Y=0) → skip
        beq @argv_skip_load
@argv_push:
        dey
        lda (INDEX),y
        sta RIA_XSTACK
        tya
        bne @argv_push

        lda #O_RDONLY
        jsr ria_open
        bcs @argv_open_failed     ; same path as a typed LOAD failure
        sta lsav_fd
        stz TEMP1                 ; lsav_load_chrin's per-line byte
                                  ; counter; must start at 0 (see
                                  ; loadsave.s)

        ; Hook GETLN to lsav_load_chrin and arm the auto-run state
        ; machine. RESTART → L2351 → INLIN feeds program lines from
        ; the file; on EOF, lsav_load_chrin emits "RUN\r" so the
        ; program kicks off automatically.
        lda #<lsav_load_chrin
        sta getln_vec
        lda #>lsav_load_chrin
        sta getln_vec+1
        lda #$01
        sta auto_run
@argv_skip_load:
        jmp RESTART
@argv_open_failed:
        jmp lsav_err_baddata      ; "?FILE DATA ERROR" then OK

QT_BANNER:
        .byte   "MICROSOFT BASIC", CR, LF, 0

QT_BYTES_FREE:
        .byte   " BYTES FREE", CR, LF, 0
