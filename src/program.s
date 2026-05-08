; error
; line input, line editing
; tokenize
; detokenize
; BASIC program memory management

; Tokenize/LIST scratch — aliases on FP scratch zp slots.
; TEMP3 (2 bytes) and TEMP2 (1 byte) are FP-only (float.s, trig.s),
; never touched during PARSE_INPUT_LINE or LIST. TEMP1 is reserved
; for lsav_load_chrin's per-line counter and must NOT be aliased.
TOKBASE       = TEMP3
TOKBASE_TOKEN = TEMP2

.segment "CODE"

MEMERR:
        ldx     #ERR_MEMFULL

; ----------------------------------------------------------------------------
; HANDLE AN ERROR
;
; (X)=OFFSET IN ERROR MESSAGE TABLE
; (ERRFLG) > 128 IF "ON ERR" TURNED ON
; (CURLIN+1) = $FF IF IN DIRECT MODE
; ----------------------------------------------------------------------------
ERROR:
        ; Tear down LOAD/SAVE state before any CHROUT: if LOAD was
        ; feeding lines (e.g. OOMERR in NUMBERED_LINE) we need to
        ; close the file and unhook getln_vec, otherwise RESTART
        ; would loop right back into the file. lsav_panic is a
        ; no-op when neither LOAD nor SAVE is active, and preserves
        ; X (the error-message offset) across the RIA close.
        jsr     lsav_panic
        lsr     Z14
        lda     CURDVC    ; output
        bmi     LC366     ; $FF = no redirect
        jsr     CLRCH     ; otherwise redirect output back to screen
        lda     #$FF
        sta     CURDVC
LC366:
        jsr     CRDO
        jsr     OUTQUES
L2329:
        lda     ERROR_MESSAGES,x
        pha
        and     #$7F
        jsr     OUTDO
        inx
        pla
        bpl     L2329
        jsr     STKINI
        lda     #<QT_ERROR
        ldy     #>QT_ERROR

; ----------------------------------------------------------------------------
; PRINT STRING AT (Y,A)
; PRINT CURRENT LINE # UNLESS IN DIRECT MODE
; FALL INTO WARM RESTART
; ----------------------------------------------------------------------------
PRINT_ERROR_LINNUM:
        jsr     STROUT
        ldy     CURLIN+1
        iny
        beq     RESTART
        jsr     INPRT

; ----------------------------------------------------------------------------
; WARM RESTART ENTRY
; ----------------------------------------------------------------------------
RESTART:
        lsr     Z14
        lda     auto_run                ; cold-boot auto-load suppresses
        bne     L2351                   ; the first "OK" so the program
                                        ; runs straight from the banner
        lda     #<QT_OK
        ldy     #>QT_OK
        jsr     STROUT
L2351:
        jsr     INLIN
        stx     TXTPTR
        sty     TXTPTR+1
        jsr     CHRGET
        tax
        beq     L2351
        ldx     #$FF
        stx     CURLIN+1
        bcc     NUMBERED_LINE
        ; First non-space char isn't a digit. If LOAD is feeding lines,
        ; that's bad data — saved files contain only numbered lines.
        ; Without this guard, a stray non-numbered line would execute
        ; mid-LOAD as if typed at the prompt.
        lda     lsav_fd
        jne     lsav_load_err
        jsr     PARSE_INPUT_LINE
        jmp     NEWSTT2

; ----------------------------------------------------------------------------
; HANDLE NUMBERED LINE
; ----------------------------------------------------------------------------
NUMBERED_LINE:
        jsr     LINGET
        jsr     PARSE_INPUT_LINE
        sty     EOLPNTR
        jsr     FNDLIN
        bcc     PUT_NEW_LINE
        ldy     #$01
        lda     (LOWTR),y
        sta     INDEX+1
        lda     VARTAB
        sta     INDEX
        lda     LOWTR+1
        sta     DEST+1
        lda     LOWTR
        dey
        sbc     (LOWTR),y
        clc
        adc     VARTAB
        sta     VARTAB
        sta     DEST
        lda     VARTAB+1
        adc     #$FF
        sta     VARTAB+1
        sbc     LOWTR+1
        tax
        sec
        lda     LOWTR
        sbc     VARTAB
        tay
        bcs     L23A5
        inx
        dec     DEST+1
L23A5:
        clc
        adc     INDEX
        bcc     L23AD
        dec     INDEX+1
        clc
L23AD:
        lda     (INDEX),y
        sta     (DEST),y
        iny
        bne     L23AD
        inc     INDEX+1
        inc     DEST+1
        dex
        bne     L23AD
; ----------------------------------------------------------------------------
PUT_NEW_LINE:
        jsr     SETPTRS
        jsr     LE33D
        lda     __INBUF_START__
        beq     L2351
        clc
        lda     VARTAB
        sta     HIGHTR
        adc     EOLPNTR
        sta     HIGHDS
        ldy     VARTAB+1
        sty     HIGHTR+1
        bcc     L23D6
        iny
L23D6:
        sty     HIGHDS+1
        jsr     BLTU
        lda     STREND
        ldy     STREND+1
        sta     VARTAB
        sty     VARTAB+1

; ---COPY LINE INTO PROGRAM-------
; Tokenized-line format at (LOWTR):
;   +0..+1   link to next line ($0101 placeholder; FIX_LINKS rewrites)
;   +2..+3   line number (LINNUM)
;   +4..     tokenized text plus trailing $00 terminator
; EOLPNTR is the total length (header + text + null). The link
; placeholder just needs link-high ≠ 0 so FIX_LINKS doesn't treat
; the new line as end-of-program before patching.
L23E6:
        ldy     #$00
        lda     #$01
        sta     (LOWTR),y                 ; link low (placeholder)
        iny
        sta     (LOWTR),y                 ; link high (placeholder, A=$01)
        iny
        lda     LINNUM
        sta     (LOWTR),y
        iny
        lda     LINNUM+1
        sta     (LOWTR),y

        ; Text-copy loop: walks Y from EOLPNTR-1 down to 4. INBUF
        ; offset 0 lines up with (LOWTR) offset 4, so the `-4` on the
        ; src keeps src and dest sharing Y.
        ldy     EOLPNTR
@txt:
        dey
        cpy     #$04
        bcc     @done
        lda     __INBUF_START__-4,y
        sta     (LOWTR),y
        bra     @txt
@done:

; ----------------------------------------------------------------------------
; CLEAR ALL VARIABLES
; RE-ESTABLISH ALL FORWARD LINKS
; ----------------------------------------------------------------------------
FIX_LINKS:
        jsr     SETPTRS
        jsr     LE33D
        jmp     L2351
LE33D:
        lda     #<(__TXTTAB_START__+1)
        ldy     #>(__TXTTAB_START__+1)
        sta     INDEX
        sty     INDEX+1
        clc
L23FA:
        ldy     #$01
        lda     (INDEX),y
        beq     RET3
        ldy     #$04
L2405:
        iny
        lda     (INDEX),y
        bne     L2405
        iny
        tya
        adc     INDEX
        tax
        ldy     #$00
        sta     (INDEX),y
        lda     INDEX+1
        adc     #$00
        iny
        sta     (INDEX),y
        stx     INDEX
        sta     INDEX+1
        bra     L23FA

; ----------------------------------------------------------------------------

RET3:
        rts

.include "inline.s"

; ----------------------------------------------------------------------------
; TOKENIZE THE INPUT LINE
; ----------------------------------------------------------------------------
PARSE_INPUT_LINE:
        ldx     TXTPTR
        ldy     #$04
        sty     DATAFLG
L246C:
        lda     __INBUF_START__,x
        cmp     #$20
        beq     L24AC
        sta     ENDCHR
        cmp     #$22
        beq     L24D0
        bit     DATAFLG
        bvs     L24AC
        cmp     #$3F
        bne     L2484
        lda     #TOKEN_PRINT
        bne     L24AC
L2484:
        cmp     #$30
        bcc     L248C
        cmp     #$3C
        bcc     L24AC
; ----------------------------------------------------------------------------
; SEARCH TOKEN NAME TABLE FOR MATCH STARTING
; WITH CURRENT CHAR FROM INPUT LINE
; ----------------------------------------------------------------------------
L248C:
        ; Reset bin-A pointer on every matcher entry. Earlier successful
        ; matches in this line may have left TOKBASE/TOKBASE_TOKEN
        ; pointing at bin B (e.g. the '=' operator), which would make
        ; this matcher invocation skip bin A entirely.
        lda     #<TOKEN_NAME_TABLE_A
        sta     TOKBASE
        lda     #>TOKEN_NAME_TABLE_A
        sta     TOKBASE+1
        lda     #$80
        sta     TOKBASE_TOKEN
        sty     STRNG2
        ldy     #$00
        sty     EOLPNTR
        dey
        stx     TXTPTR
        dex
L2496:
        iny
L2497:
        inx
L2498:
        lda     __INBUF_START__,x
        ; Reject high-bit-set input chars: the sbc-equals-$80 endmark below
        ; must only fire for the table's bit-7 terminator, never for the
        ; input byte. Must run BEFORE any cmp — cmp clobbers N with the
        ; comparison result, not the original A's bit 7.
        bmi     L24D7
        ; Case-fold a-z → A-Z so keywords are case-insensitive. The fold
        ; only happens here in the keyword-match path, NOT in the quoted-
        ; string copy path (L24D0), so string literals preserve case.
        cmp     #'a'
        bcc     L2498_NOFOLD
        cmp     #'z'+1
        bcs     L2498_NOFOLD
        and     #$DF
L2498_NOFOLD:
        sec
        sbc     (TOKBASE),y
        beq     L2496
        cmp     #$80
        bne     L24D7
        ora     EOLPNTR
        ; Inject bin base ($80 or $C0) into the matched-token byte.
        ; A is currently $80 | EOLPNTR; ORing with TOKBASE_TOKEN
        ; converts to $C0 | EOLPNTR when we're scanning bin B.
        ; EOLPNTR is bin-local: reset on every L248C entry (fresh
        ; matcher invocation) and again on bin switch in L24DB. It
        ; never accumulates across bins — the eval.s TAND/OR reuse
        ; of this slot is on a different code path.
        ora     TOKBASE_TOKEN
; ----------------------------------------------------------------------------
; STORE CHARACTER OR TOKEN IN OUTPUT LINE
; ----------------------------------------------------------------------------
L24AA:
        ldy     STRNG2
L24AC:
        inx
        iny
        cmp     #'a'                  ; fold a-z → A-Z so variable
        bcc     :+                    ; names match keyword behavior
        cmp     #'z'+1                ; (TOKEN bytes ≥$80 and digits
        bcs     :+                    ; <'a' both skip the fold)
        and     #$DF
:
        sta     __INBUF_START__-5,y
        lda     __INBUF_START__-5,y
        beq     L24EA
        sec
        sbc     #$3A
        beq     L24BF
        cmp     #$49
        bne     L24C1
L24BF:
        sta     DATAFLG
L24C1:
        sec
        sbc     #TOKEN_REM-':'
        bne     L246C
        sta     ENDCHR
; ----------------------------------------------------------------------------
; HANDLE LITERAL (BETWEEN QUOTES) OR REMARK,
; BY COPYING CHARS UP TO ENDCHR.
; ----------------------------------------------------------------------------
L24C8:
        lda     __INBUF_START__,x
        beq     L24AC
        cmp     ENDCHR
        beq     L24AC
L24D0:
        iny
        sta     __INBUF_START__-5,y
        inx
        bne     L24C8
; ----------------------------------------------------------------------------
; ADVANCE POINTER TO NEXT TOKEN NAME
; ----------------------------------------------------------------------------
L24D7:
        ldx     TXTPTR
        inc     EOLPNTR
L24DB:
        ; Y enters here at the position where the matcher's last sbc
        ; happened — that byte may be a regular char OR a high-bit
        ; terminator (mismatch on the LAST byte of a keyword). Check
        ; the terminator case explicitly before scanning forward.
        lda     (TOKBASE),y
        bmi     @past_term      ; already at terminator: just step past
@scan:
        iny
        lda     (TOKBASE),y
        bpl     @scan           ; scan forward to high-bit terminator
@past_term:
        iny
        lda     (TOKBASE),y
        bne     L2498
        ; Hit the bin's null terminator. If we're still in bin A,
        ; switch to bin B and resume scanning at its first keyword.
        ; If already in bin B, treat the input char as a literal.
        lda     TOKBASE_TOKEN
        cmp     #$C0
        bcs     @no_match
        lda     #<TOKEN_NAME_TABLE_B
        sta     TOKBASE
        lda     #>TOKEN_NAME_TABLE_B
        sta     TOKBASE+1
        lda     #$C0
        sta     TOKBASE_TOKEN
        ldy     #$00            ; index at bin B's first keyword
        stz     EOLPNTR
        bra     L2498
@no_match:
        lda     __INBUF_START__,x
        bpl     L24AA
        ; High-bit byte outside a string literal — neither a keyword
        ; (the bmi guard in L2498 prevented a match) nor a valid
        ; literal char. Substitute $7F and let the line tokenize so
        ; the user can edit it; the parser will syntax-error on the
        ; $7F at run time.
        lda     #$7F
        bra     L24AA
; ---END OF LINE — reached via L24AC's beq when a $00 has been stored.
L24EA:
        sta     __INBUF_START__-3,y
        dec     TXTPTR+1
        lda     #<(__INBUF_START__-1)
        sta     TXTPTR
        rts

; ----------------------------------------------------------------------------
; SEARCH FOR LINE
;
; (LINNUM) = LINE # TO FIND
; IF NOT FOUND:  CARRY = 0
;	LOWTR POINTS AT NEXT LINE
; IF FOUND:      CARRY = 1
;	LOWTR POINTS AT LINE
; ----------------------------------------------------------------------------
FNDLIN:
        lda     #<(__TXTTAB_START__+1)
        ldx     #>(__TXTTAB_START__+1)
FL1:
        ldy     #$01
        sta     LOWTR
        stx     LOWTR+1
        lda     (LOWTR),y
        beq     L251F
        iny
        iny
        lda     LINNUM+1
        cmp     (LOWTR),y
        bcc     L2520
        beq     L250D
        dey
        bne     L2516
L250D:
        lda     LINNUM
        dey
        cmp     (LOWTR),y
        bcc     L2520
        beq     L2520
L2516:
        dey
        lda     (LOWTR),y
        tax
        dey
        lda     (LOWTR),y
        bcs     FL1
L251F:
        clc
L2520:
        rts

; ----------------------------------------------------------------------------
; "NEW" STATEMENT
; ----------------------------------------------------------------------------
NEW:
        bne     L2520
SCRTCH:
        stz     __TXTTAB_START__+1
        stz     __TXTTAB_START__+2
        lda     #<(__TXTTAB_START__+3)
        sta     VARTAB
        lda     #>(__TXTTAB_START__+3)
        sta     VARTAB+1
; ----------------------------------------------------------------------------
SETPTRS:
        jsr     STXTPT
        bra     CLEARC

; ----------------------------------------------------------------------------
; "CLEAR" STATEMENT
; ----------------------------------------------------------------------------
CLEAR:
        bne     L256A
CLEARC:
        lda     #<(__TXTTAB_START__+__TXTTAB_SIZE__)
        ldy     #>(__TXTTAB_START__+__TXTTAB_SIZE__)
        sta     FRETOP
        sty     FRETOP+1
        lda     VARTAB
        ldy     VARTAB+1
        sta     ARYTAB
        sty     ARYTAB+1
        sta     STREND
        sty     STREND+1
        jsr     RESTORE
; ----------------------------------------------------------------------------
STKINI:
        ldx     #TEMPST
        stx     TEMPPT
        ply                       ; Y = return-low (was pla; tay)
        pla                       ; A = return-high
        ldx     #STACK_TOP
        txs
        pha                       ; push return-high
        phy                       ; push return-low (was tya; pha)
        stz     OLDTEXT+1
        stz     SUBFLG
L256A:
        rts

; ----------------------------------------------------------------------------
; SET TXTPTR TO BEGINNING OF PROGRAM
; ----------------------------------------------------------------------------
STXTPT:
        lda     #<__TXTTAB_START__
        sta     TXTPTR
        lda     #>__TXTTAB_START__
        sta     TXTPTR+1
        rts

; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; "LIST" STATEMENT
; ----------------------------------------------------------------------------
LIST:
        bcc     L2581
        beq     L2581
        cmp     #TOKEN_MINUS
        bne     L256A
L2581:
        jsr     LINGET
        jsr     FNDLIN
        jsr     CHRGOT
        beq     L2598
        cmp     #TOKEN_MINUS
        bne     L2520
        jsr     CHRGET
        jsr     LINGET
        bne     L2520
L2598:
        lda     LINNUM
        ora     LINNUM+1
        bne     L25A6
        lda     #$FF
        sta     LINNUM
        sta     LINNUM+1
L25A6:
L25A6X:
        ldy     #$01
        lda     (LOWTRX),y
        beq     L25E5
        jsr     ISCNTC
        iny
        lda     (LOWTRX),y
        tax
        iny
        lda     (LOWTRX),y
        cmp     LINNUM+1
        bne     L25C1
        cpx     LINNUM
        beq     L25C3
L25C1:
        bcs     L25E5
; ---LIST ONE LINE----------------
L25C3:
        sty     FORPNT
        jsr     LINPRTNS
        lda     #$20
L25CA:
        ldy     FORPNT
        and     #$7F
L25CE:
        jsr     OUTDO
        iny
        beq     L25E5
        lda     (LOWTRX),y
        bne     L25E8
        ; End of line: emit a trailing LF and advance to next line.
        ; Putting CRDO here (rather than at L25A6X's top) keeps the
        ; file format clean: each line is followed by exactly one LF,
        ; no leading blank line, and the last line is also LF-terminated
        ; so LOAD's INLIN can finish reading it before EOF.
        jsr     CRDO
        tay
        lda     (LOWTRX),y
        tax
        iny
        lda     (LOWTRX),y
        stx     LOWTRX
        sta     LOWTRX+1
        bne     L25A6
L25E5:
        rts
L25E8:
        bpl     L25CE
        sty     FORPNT          ; save program-memory Y BEFORE clobbering for table lookup
        ; Bit 7 always set on tokens, so "bit 6 set" ≡ "byte ≥ $C0".
        ; CMP preserves A and leaves carry already set for bin B's SBC.
        cmp     #$C0
        bcs     @bin_b
        sec
        sbc     #$7F            ; A = 1-based index in bin A
        ldx     #<TOKEN_NAME_TABLE_A
        ldy     #>TOKEN_NAME_TABLE_A
        bra     @set_base
@bin_b:
        sbc     #$BF            ; A = 1-based index in bin B (carry already set)
        ldx     #<TOKEN_NAME_TABLE_B
        ldy     #>TOKEN_NAME_TABLE_B
@set_base:
        stx     TOKBASE
        sty     TOKBASE+1
        tax
        ldy     #$FF
L25F2:
        dex
        beq     L25FD
L25F5:
        iny
        lda     (TOKBASE),y
        bpl     L25F5
        bmi     L25F2
L25FD:
        iny
        lda     (TOKBASE),y
        bmi     L25CA
        jsr     OUTDO
        bra     L25FD
