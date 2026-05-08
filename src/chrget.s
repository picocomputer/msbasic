; CHRGET — 24-byte self-modifying zp char-fetcher.
;
; Self-modifying: bytes 7-8 of the routine are the absolute
; operand of `lda $EA60`. Stores into TXTPTR rewrite that operand
; before the lda runs; the $EA60 here is just a placeholder.

.import __CHRGET_RUN__         ; segment-defined export from msbasic.cfg / chrget.cfg

CHRGET   = <__CHRGET_RUN__     ; `<` forces zp addressing without a size-mismatch warning
CHRGOT   = CHRGET + 6          ; lda — re-entry that re-tests the current char
TXTPTR   = CHRGET + 7          ; the lda's absolute operand (the cursor)
CHRGOT2  = CHRGET + 9          ; cmp #$20 — re-entry when A is already loaded

.segment "CHRGET"
chrget_routine:
        inc     TXTPTR
        bne     :+
        inc     TXTPTR+1
:
        lda     $EA60
        cmp     #$3A
        bcs     :+
        cmp     #$20
        beq     chrget_routine
        sec
        sbc     #$30
        sec
        sbc     #$D0
:
        rts

.assert * - chrget_routine = 24, error, "CHRGET length error"
