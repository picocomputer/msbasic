.segment "EXTRA"

; ------------------------------------------------------------
; chrout_buf — tab completion's CHROUT target. Appends A to
; INBUF[inbuf_off], saturating at $FF so a >256-char detokenized
; line can't walk past INBUF into the RIA register page at $FF00;
; ria_tab_completion checks inbuf_off == $FF after L25A6X to
; detect overflow and abandon the completion.
; Preserves A, X, Y.
; ------------------------------------------------------------
chrout_buf:
        phy
        ldy inbuf_off
        cpy #$FF                  ; buffer full → silently drop
        beq @done
        sta __INBUF_START__,y
        inc inbuf_off
@done:
        ply
        rts

; ------------------------------------------------------------
; ria_tab_completion
;   Called from CHRIN's wait loop when the user presses TAB.
;   Peeks the current readline buffer; if it parses as a single
;   decimal line number (with an optional single trailing space)
;   that exists in the program, replaces the editor's contents with
;   `<lineno> <detokenized text>` so the user can edit the line in
;   place.
;   Caller drains xstack after return (paths that bail early may
;   leave bytes on it).
; ------------------------------------------------------------
ria_tab_completion:
        ; --- Phase A: peek current readline buffer onto xstack. ---
        lda #RIA_OP_RLN_PEEK
        sta RIA_OP
        jsr RIA_SPIN
        lda RIA_XSTACK            ; discard cursor pos byte at top

        ; --- Phase B: parse digits off xstack into LINNUM. ---
        ; Pop top-down: chars come out in forward order, terminated
        ; by 0 (short-stacking past the buffer end). One trailing
        ; space before the terminator is allowed (see @space).
        ; Non-digit, overflow, or empty buffer → abort.
        stz LINNUM
        stz LINNUM+1
        ldy #$00                  ; digit count
@parse:
        lda RIA_XSTACK
        beq @parsed               ; 0 terminator → done
        cmp #' '
        beq @space                ; one trailing space allowed (see @space)
        sec
        sbc #'0'
        cmp #10
        bcs @bad                  ; not a digit
        sta CHARAC                ; save digit (CHARAC is scratch here)
        ; LINNUM = LINNUM*10 + CHARAC, with overflow → @bad.
        ;   ×2 (preserved in A:X across the two ASLs that follow)
        asl LINNUM
        rol LINNUM+1
        bcs @bad
        lda LINNUM
        ldx LINNUM+1              ; A:X = LINNUM ×2
        ;   ×8
        asl LINNUM
        rol LINNUM+1
        bcs @bad
        asl LINNUM
        rol LINNUM+1
        bcs @bad
        ;   + ×2
        clc
        adc LINNUM
        sta LINNUM
        txa
        adc LINNUM+1
        sta LINNUM+1
        bcs @bad
        ;   + digit
        clc
        lda LINNUM
        adc CHARAC
        sta LINNUM
        bcc @no_carry
        inc LINNUM+1
        beq @bad
@no_carry:
        iny
        bra @parse                ; overflow checks above bail long before Y wraps

@space:
        ; Accept a single space after the digits
        cpy #0
        beq @bad
        lda RIA_XSTACK
        bne @bad                  ; more bytes after the space → not a bare lineno
        bra @parsed

@bad:
        ; Bail with leftover digits on xstack — caller drains.
        rts

@parsed:
        tya                       ; empty buffer (Y=0) → skip
        beq @done
        jsr FNDLIN                ; C=1 if line found, LOWTR=line ptr
        bcc @done

        ; --- Phase C: list the line into INBUF via redirect. ---
        ; Install chrout_buf into chrout_vec so LIST's CHROUT calls
        ; sink into INBUF[inbuf_off]. Enter LIST's per-line emitter
        ; at L25A6X with LOWTRX (= LOWTR) pre-loaded by FNDLIN;
        ; LINNUM is both range bounds, so the walker prints the
        ; matched line, CRDOs, advances to the next line, then
        ; exits via the range check (next line number is strictly
        ; higher).
        stz inbuf_off
        lda #<chrout_buf
        sta chrout_vec
        lda #>chrout_buf
        sta chrout_vec+1
        jsr L25A6X
        jsr chrout_vec_reset      ; back to default chrout_fd
        ; chrout_buf saturates at $FF on overflow — pushing a
        ; truncated listing would corrupt the edit buffer, so bail.
        lda inbuf_off
        cmp #$FF
        beq @done
        sec
        sbc #2                    ; -2 for CR LF
        tay                       ; Y = listing length

        ; --- Phase D: push poke to xstack. ---
        ; LIFO: listing in reverse, then the ANSI clear-line prefix
        ; in reverse. The OS pops ESC[H (home), then ESC[256P (DCH
        ; ×256 wipes the line), then the listing bytes; the
        ; trailing 0 terminator comes from short-stacking past the
        ; bottom.
@push_list:
        dey
        lda __INBUF_START__,y
        sta RIA_XSTACK
        tya
        bne @push_list
        ldx #(esc_clear_line_end - esc_clear_line - 1)
@push_esc:
        lda esc_clear_line,x
        sta RIA_XSTACK
        dex
        bpl @push_esc

        ; --- Phase E: replace the readline buffer with our poke. ---
        lda #RIA_OP_RLN_POKE
        sta RIA_OP
        jsr RIA_SPIN
@done:
        rts

esc_clear_line: .byte $1B, '[', 'H', $1B, '[', '2', '5', '6', 'P'
esc_clear_line_end:
