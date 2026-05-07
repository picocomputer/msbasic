.segment "CODE"

CONRND1:
        .byte   $98,$35,$44,$7A
CONRND2:
        .byte   $68,$28,$B1,$46

RND:
        jsr     SIGN
        tax
        bmi     L3F01
        lda     #<RNDSEED
        ldy     #>RNDSEED
        jsr     LOAD_FAC_FROM_YA
        txa
        beq     RTS19
        lda     #<CONRND1
        ldy     #>CONRND1
        jsr     FMULT
        lda     #<CONRND2
        ldy     #>CONRND2
        jsr     FADD
L3F01:
        ldx     FAC_LAST
        lda     FAC+1
        sta     FAC_LAST
        stx     FAC+1
        stz     FACSIGN
        lda     FAC
        sta     FACEXTENSION
        lda     #$80
        sta     FAC
        jsr     NORMALIZE_FAC2
        ldx     #<RNDSEED
        ldy     #>RNDSEED
GOMOVMF:
        jmp     STORE_FAC_AT_YX_ROUNDED
