.segment "EXTRA"

; ------------------------------------------------------------
; CLOCK_FN — "CLOCK" function. CLOCK(x) = seconds since boot
; as a float with 0.01s resolution, from RIA_OP_CLOCK's 32-bit
; centisecond count. The argument is evaluated and discarded
; (FRE/POS convention — UNARY has no zero-arity parse).
;   In:  FAC = evaluated argument (any type)
;   Out: FAC = centiseconds/100, VALTYP numeric for UNARY's CHKNUM
; ------------------------------------------------------------
CLOCK_FN:
        lda     VALTYP            ; arg is ignored; release a string
        beq     :+                ; temp like FRE does so it doesn't
        jsr     FREFAC            ; pile up in TEMPST
:       stz     VALTYP            ; result is numeric (CHKNUM runs on return)
        lda     #RIA_OP_CLOCK
        sta     RIA_OP
        jsr     RIA_SPIN          ; A=b0(LSB), X=b1, RIA_SREG=b2, RIA_SREG+1=b3
        sta     FAC+4             ; FAC+1..4 = the count as unsigned
        stx     FAC+3             ; 32-bit int, MSB first
        lda     RIA_SREG
        sta     FAC+2
        lda     RIA_SREG+1
        sta     FAC+1
        lda     #$A0              ; exponent 2^32 (cf. $90 for the
        sta     FAC               ; 16-bit float in LINPRTNS)
        stz     FACSIGN
        stz     FACEXTENSION      ; participates in NORMALIZE's shifts
        sec                       ; positive
        jsr     NORMALIZE_FAC1
        jsr     COPY_FAC_TO_ARG_ROUNDED
        lda     #<CONHUND
        ldy     #>CONHUND
        ldx     #$00
        jmp     DIV               ; FAC = ARG/100 (DIV10's entry, float.s)

CONHUND:
        .byte   $87,$48,$00,$00,$00     ; 100.0 (cf. CONTEN 10.0 in float.s)

; ------------------------------------------------------------
; TIMESTR_FN — "TIME$" function. TIME$(f$) = local time formatted
; by the OS's strftime with format f$ ("" stays "", per ISO C).
;   In:  FAC = evaluated argument (must be a string)
;   Out: temp string descriptor via PUTNEW
;
; The three OS calls chain on the xstack with no RAM buffers:
; TIME_GET leaves its 64-bit time_t exactly as LOCALTIME wants
; its input (LSB on top, short widths zero-fill), and LOCALTIME
; leaves its 18-byte struct tm exactly as STRFTIME wants beneath
; the format (tm byte 0 on top). Only the $00 terminator and the
; reversed format string need pushing — the terminator can't
; short-stack because the tm sits below it.
; ------------------------------------------------------------
TIMESTR_FN:
        jsr     FRESTR            ; CHKSTR + FREFAC: A=len, INDEX=ptr to bytes
        pha                       ; len; RIA_SPIN clobbers A/X, not the stack
        lda     #RIA_OP_TIME_GET
        sta     RIA_OP
        jsr     RIA_SPIN          ; 64-bit time_t now on xstack
        bmi     @err
        lda     #RIA_OP_LOCALTIME
        sta     RIA_OP
        jsr     RIA_SPIN          ; 18-byte struct tm now on xstack
        bmi     @err
        lda     #0
        sta     RIA_XSTACK        ; format terminator
        pla
        tay                       ; push format reversed (ria_push_string
        beq     @go               ; pattern); "" pushes terminator only
@push:
        dey
        lda     (INDEX),y
        sta     RIA_XSTACK
        tya
        bne     @push
@go:
        lda     #RIA_OP_STRFTIME
        sta     RIA_OP
        jsr     RIA_SPIN          ; A = result length, X = high byte
        bmi     @err
        cpx     #0
        bne     @toolong          ; 256+ chars can't be a BASIC string
        jsr     STRSPA            ; A=len → FAC=len, FAC+1/2=addr
        tax
        beq     @copied           ; empty result: nothing to pop
        ldy     #0
@copy:
        lda     RIA_XSTACK        ; result pops in forward order
        sta     (FAC+1),y
        iny
        dex
        bne     @copy
@copied:
        ria_zxstack               ; drain leftovers, idempotent
        pla                       ; discard UNARY's return so its
        pla                       ; jmp CHKNUM is skipped (CHR$ pattern)
        jmp     PUTNEW            ; temp descriptor, VALTYP=$FF, rts to FRMEVL

@toolong:
        ria_zxstack
        ldx     #ERR_STRLONG
        jmp     ERROR
@err:
        ria_zxstack               ; stack state is the OS's on error
        ldx     #ERR_ILLQTY
        jmp     ERROR
