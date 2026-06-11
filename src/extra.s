.segment "EXTRA"

;---------------------------------------------
; ria_zxstack — synchronous xstack drain.
; RIA_OP_ZXSTACK is $00 and the op fires on the write to RIA_OP
; with no SPIN, so this is a single 65C02 stz. Macro keeps the
; intent named at every call site without paying the jsr/rts
; cost a real subroutine would.
.macro ria_zxstack
        stz     RIA_OP
.endmacro

; ------------------------------------------------------------
; ria_open
;   In:  A = O_* flags. Filename bytes already pushed to RIA_XSTACK
;        in reverse order; trailing 0 short-stacks for free.
;   Out: A/X = SPIN return (kernel fd / hi byte).
;        C clear on success, C set on failure (rc<0).
;   Side effect: consumes the pushed filename either way.
; ------------------------------------------------------------
ria_open:
        sta     RIA_A
        lda     #RIA_OP_OPEN
        sta     RIA_OP
        jsr     RIA_SPIN
        bmi     :+
        clc
        rts
:       sec
        rts

; ------------------------------------------------------------
; ria_close
;   In:  A = kernel fd.
;   Out: A/X = SPIN return (X<0 on failure).
;   tty:/con: are no-ops in the OS so closing them is harmless.
; ------------------------------------------------------------
ria_close:
        sta     RIA_A
        lda     #RIA_OP_CLOSE
        sta     RIA_OP
        jmp     RIA_SPIN              ; tail-call

; ------------------------------------------------------------
; ria_push_string
;   Evaluate the next BASIC expression as a string and push its
;   bytes onto RIA_XSTACK in reverse order. Trailing 0 comes
;   from short-stacking past the bottom. Errors (?FILE DATA)
;   on empty string or non-string type via lsav_err_baddata.
;   Trashes A/X/Y.
; ------------------------------------------------------------
ria_push_string:
        jsr     FRMEVL
        jsr     CHKSTR
        jsr     FREFAC                 ; A=length, INDEX=ptr to bytes
        tay
        jeq     lsav_err_baddata       ; empty string ⇒ error. jeq, not beq:
                                       ; target's in CODE, out of branch range.
@push_loop:
        dey
        lda     (INDEX),y
        sta     RIA_XSTACK
        tya
        bne     @push_loop
        rts

; ------------------------------------------------------------
; LINPRTNS — like upstream LINPRT but skips the leading
; sign-position space FOUT normally emits. Used by LIST/SAVE
; (listings start at column 0) and the cold-boot banner. Same
; logic as LINPRT in float.s, but enters FOUT at FOUT1 with Y=0
; (the STR$-style entry that drops the sign char).
; ------------------------------------------------------------
LINPRTNS:
        sta     FAC+1
        stx     FAC+2
        ldx     #$90
        sec
        jsr     FLOAT2
        ldy     #$00
        jsr     FOUT1
        jmp     STROUT
