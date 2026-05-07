; Key change vs. upstream: L29B9 (INLIN line termination) RETURNS without
; falling into CRDO. The host terminal already advanced its line on the
; user's Enter, so an extra CRLF would produce a stray blank line on every
; input.

.segment "CODE"

; ----------------------------------------------------------
; PRINT statement entry. A holds the next char (CHRGOT-style
; — Z=1 means end-of-statement, $00 or ':').
; ----------------------------------------------------------
PRINT:
        beq CRDO                  ; bare PRINT → newline
print_dispatch:
        beq L29DD                 ; end of statement → exit
        cmp #TOKEN_TAB
        beq print_tab_or_spc
        cmp #TOKEN_SPC
        clc                       ; carry clear flags SPC
        beq print_tab_or_spc
        cmp #','
        beq print_comma
        cmp #';'
        beq print_advance
        jsr FRMEVL                ; evaluate expression
        bit VALTYP
        bmi PRSTRING              ; type bit 7 set → string
        jsr FOUT                  ; format number into string buffer
        jsr STRLIT                ; load descriptor for FOUT result
        jsr STRPRT
        jsr OUTSP                 ; trailing space after a printed number
        bra print_after_item

PRSTRING:
        jsr STRPRT
print_after_item:
        jsr CHRGOT
        jmp PRINT

print_advance:
        jsr CHRGET
        jmp print_dispatch

print_comma:
        ; Tab to next 10-column field.
        lda POSX
        sec
:       sbc #$0A
        bcs :-
        eor #$FF
        adc #$01                  ; A = 10 - (POSX mod 10), in [1..10]
        tax
:       jsr OUTSP
        dex
        bne :-
        jmp print_advance

print_tab_or_spc:
        php                       ; save carry: TAB=1 / SPC=0
        jsr GTBYTC                ; parse byte arg, X = byte
        cmp #')'
        jne SYNERR4
        plp
        bcc print_emit_x_spaces   ; SPC(n) → X = n
        ; TAB(n): emit (n - POSX) spaces if n > POSX
        txa
        sec
        sbc POSX
        bcc print_advance         ; n < POSX → no movement
        beq print_advance         ; n == POSX
        tax
print_emit_x_spaces:
        inx
:       dex
        beq print_advance
        jsr OUTSP
        bra :-

L29DD:
        rts

; ----------------------------------------------------------
; CRDO — end-of-line for current output target. tty: needs CR+LF
; (the terminal expects raw bytes; LF alone advances the row but
; doesn't reset the column). SAVE files use LF only. We branch
; on out_fd to pick the form. POSX is reset explicitly because
; OUTDO's CR-handler only fires for the tty path.
; ----------------------------------------------------------
CRDO:
        lda out_fd
        cmp tty_fd
        bne crdo_lf
        lda #CR
        jsr OUTDO
crdo_lf:
        lda #LF
        jsr OUTDO
        lda #$00                  ; NOT stz POSX: callers (e.g. LIST's
        sta POSX                  ; per-line loop `jsr CRDO; tay; lda
                                  ; (LOWTRX),y`) depend on A=0 here to
                                  ; use as a Y=0 indirect index.
        rts

; ----------------------------------------------------------
; STROUT(Y:A) — print null-terminated string at Y:A.
; Goes through STRLIT/FREFAC so temporary BASIC strings get
; freed correctly (matches upstream contract).
; ----------------------------------------------------------
STROUT:
        jsr STRLIT
        ; falls into STRPRT

; ----------------------------------------------------------
; STRPRT — print BASIC string (descriptor in FAC).
; ----------------------------------------------------------
STRPRT:
        jsr FREFAC                ; A = length, INDEX = pointer
        tax
        ldy #$00
        inx
:       dex
        beq strprt_done
        lda (INDEX),y
        jsr OUTDO
        iny
        bra :-
strprt_done:
        rts

; ----------------------------------------------------------
; OUTSP — output a space.
; OUTQUES — output '?'.
; ----------------------------------------------------------
OUTSP:
        lda #$20
        bra OUTDO

OUTQUES:
        lda #$3F
        ; falls into OUTDO

; ----------------------------------------------------------
; OUTDO — write A through CHROUT.
;   - Z14 bit 7 suppresses output (BASIC's "no output" flag).
;   - POSX is incremented for printable chars (>= $20) so that
;     PRINT comma/TAB/SPC alignment works.
; ----------------------------------------------------------
OUTDO:
        bit Z14
        bmi outdo_done            ; Z14 bit 7 set → suppress
        cmp #CR
        bne :+                    ; CR returns to col 0 → reset POSX
        stz POSX                  ;   (and falls through into cmp #$20
:       cmp #$09                  ;   path below — CR is < $20 so emit
        bne :+                    ;   without inc)
        ; TAB advances POSX to the next multiple of 8:
        ;   POSX = (POSX | 7) + 1
        pha
        lda POSX
        ora #$07
        sta POSX
        inc POSX
        pla
        bra outdo_emit
:       cmp #$20
        bcc outdo_emit            ; other control chars: emit, no inc
        inc POSX
outdo_emit:
        jmp CHROUT               ; tail call
outdo_done:
        rts
