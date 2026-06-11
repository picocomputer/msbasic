.segment "EXTRA"

; ------------------------------------------------------------
; more_prompt — emit "--More--" to tty, then run the pico-firmware
; monitor's 3-state escape-sequence eater (mon.c) — WAIT →
; WAIT_ESC → WAIT_CSI → END — block-waiting on GETIN at every
; transition. q/Q/Ctrl-C in WAIT trigger ?BREAK; inside
; WAIT_ESC/WAIT_CSI they're just sequence bytes. On dismissal,
; erase the prompt with BS×8 SP×8 BS×8.
;
; Block-wait (not bounded poll) is deliberate: terminals over
; slow links can send the bytes of an escape sequence seconds
; apart, and a poll budget drops late arrivals into the next OK
; prompt. The tradeoff is that bare Esc parks the pager in
; WAIT_ESC until the user presses another key.
;
; Overlay bytes (--More--, BS/SP/BS erase) go through chrout_fd
; directly so they bypass chrout_pager.
;
; Preserves A (pha at entry, pla before rts) so the chrout_pager
; caller can re-emit its byte. Clobbers X. Refills more_rows_left
; from more_height-1 on the way out so each chrout_pager call site
; doesn't have to repeat that. @break jmps to break_to_stop and
; never returns; STKINI discards the stray pha.
; ------------------------------------------------------------
more_prompt:
        pha                               ; save caller's byte
        ldx     #0
@emit:  lda     more_prompt_str,x
        beq     @wait_first
        jsr     chrout_fd
        inx
        bra     @emit

@wait_first:                              ; state: WAIT
        bit     RIA_IRQ                   ; SIGINT latched while scrolling?
        bvs     @break
        jsr     GETIN
        beq     @wait_first               ; block-spin until a byte arrives
        cmp     #$0A                      ; n
        beq     @wait_first
        cmp     #$03                      ; Ctrl-C byte from tty:
        beq     @break
        cmp     #'q'
        beq     @break
        cmp     #'Q'
        beq     @break
        cmp     #$1B                      ; ESC → WAIT_ESC
        bne     @erase                    ; non-ESC → END

@wait_esc:                                ; state: WAIT_ESC
        jsr     GETIN
        beq     @wait_esc                 ; block-spin for next byte
        cmp     #'['
        beq     @wait_csi
        cmp     #'O'
        bne     @erase                    ; non-CSI-intro → END

@wait_csi:                                ; state: WAIT_CSI
        jsr     GETIN
        beq     @wait_csi                 ; block-spin for next byte
        cmp     #$40
        bcc     @wait_csi                 ; <$40: param/intermediate byte
        cmp     #$7F
        bcs     @wait_csi                 ; ≥$7F: not a CSI final byte
        ; $40..$7E → CSI final → END, fall through to erase

@erase:
        ldx     #0
@er:    lda     more_erase_str,x
        beq     @done
        jsr     chrout_fd
        inx
        bra     @er
@done:
        lda     more_height               ; refill row budget for next page
        sec
        sbc     #1
        sta     more_rows_left
        pla                               ; restore caller's byte
        rts

@break:
        jmp     break_to_stop

more_prompt_str: .byte "--MORE--", 0
more_erase_str:  .byte $08, $08, $08, $08, $08, $08, $08, $08
                 .byte $20, $20, $20, $20, $20, $20, $20, $20
                 .byte $08, $08, $08, $08, $08, $08, $08, $08, 0

; ------------------------------------------------------------
; chrout_pager — chrout_vec target while the LIST pager is
; armed. Tracks the pager's cursor, fires more_prompt when a
; byte would land on an overflow row, then tail-calls chrout_fd
; to actually emit the byte.
;
; Rule per byte:
;   $0A (LF)        — row-advance (invisible). MORE-check on
;                     entry (rows_left == 0 means a prior advance
;                     already pushed us to overflow); then emit,
;                     dec rows_left.
;   $0D (CR)        — more_col := 0, emit. No row tracking.
;   < $20 (other)   — emit, no tracking.
;   ≥ $20 printable — if more_col == more_width, the terminal
;                     auto-wraps this byte to col 1 of the NEXT
;                     row (no explicit CR/LF emitted). dec
;                     rows_left (the wrap IS the row-advance)
;                     and MORE-check the new state — if the
;                     wrap put this char on an overflow row,
;                     MORE before it emits. Else just inc more_col.
;
; LF's MORE-check is lazy (on entry) because the LF itself
; doesn't print visible content; the prompt fires on the first
; printable/LF that follows. Wrap's MORE-check is post-dec
; because the wrap char IS the first visible char of the new
; row — we have to decide overflow before emitting it, not
; after.
;
; A/X/Y preserved (matches chrout_fd's contract). Y saved on
; entry / restored on exit because column tracking clobbers it.
; X is preserved across more_prompt (more_prompt's own ldx/inx
; loops clobber X, and STRPRT uses X as its own loop counter).
; ------------------------------------------------------------
chrout_pager:
        phy
        cmp     #$0A
        beq     @lf
        cmp     #$0D
        beq     @cr
        cmp     #$20
        bcc     @done                     ; other control: pass through

        ; printable: decide wrap vs bump from current column.
        ldy     more_col
        cpy     more_width
        beq     @wrap
        ; col < width: normal printable. MORE-check on entry —
        ; if a prior LF left rows_left == 0, this char is the
        ; first printable of an overflow row.
        ldy     more_rows_left
        bne     @bump
        phx                               ; more_prompt preserves A
        jsr     more_prompt               ; and refills more_rows_left
        plx
@bump:
        inc     more_col
        bra     @done

@wrap:
        ; col == width: terminal auto-wraps this byte to col 1 of the
        ; next row (no explicit CRLF). The wrap IS the row-advance, so
        ; dec rows_left and MORE-check post-dec before the byte emits.
        ; A keeps the printable throughout, so @done emits it into the
        ; terminal's pending-wrap at col 1 of the new row.
        ldy     more_rows_left
        beq     @wrap_check               ; already 0: skip dec, don't underflow
        dec     more_rows_left
@wrap_check:
        ldy     more_rows_left
        bne     @wrap_emit
        phx                               ; more_prompt clobbers X
        jsr     more_prompt
        plx
@wrap_emit:
        ldy     #1                        ; use Y so A keeps the byte for emit
        sty     more_col
        bra     @done

@cr:
        stz     more_col
        bra     @done

@lf:
        ldy     more_rows_left
        bne     @lf_emit
        phx
        jsr     more_prompt
        plx
@lf_emit:
        dec     more_rows_left            ; safe: >0 after MORE-check
        ; fall through

@done:
        ply                               ; restore caller's Y
        jmp     chrout_fd                 ; tail-call (preserves A/X/Y)

; ------------------------------------------------------------
; pager_arm — call at LIST entry. Validates the pager-enable
; gates; on success reads width/height from RIA, primes the
; row budget, and installs chrout_pager into chrout_vec.
;
; Gates:
;   - direct mode only (CURLIN+1 == $FF). LIST from inside a
;     running program keeps upstream's straight-through behavior.
;   - no CMD redirect (CURDVC == $FF). When the user has done
;     `OPEN n,"tty:","w":CMD n`, the lfn's fd matches tty_fd so
;     the out_fd check below can't tell us apart from default
;     routing — CURDVC is the only reliable signal.
;   - out_fd == tty_fd (catches SAVE, which swaps out_fd to a
;     file fd without touching CURDVC — no --More-- bytes should
;     land in saved files).
;   - terminal dims ≥ 2 in each axis (degenerate values disable).
;
; pager_arm is only reachable from the LIST: entry point, which
; is only reachable from the OK-prompt loop after CHRIN has
; returned — so chrout_vec is always chrout_fd here and we don't
; need a saved-vec slot.
;
; Preserves nothing; called once per LIST.
; ------------------------------------------------------------
pager_arm:
        stz     more_height               ; default = disarmed
        lda     CURLIN+1
        cmp     #$FF
        bne     @ret
        lda     CURDVC                    ; CMD redirect active?
        cmp     #$FF
        bne     @ret                      ; yes — user wants raw stream
        lda     out_fd
        cmp     tty_fd
        bne     @ret
        lda     #RIA_ATTR_RLN_WIDTH
        sta     RIA_A
        lda     #RIA_OP_ATTR_GET
        sta     RIA_OP
        jsr     RIA_SPIN
        cmp     #2
        bcc     @ret
        sta     more_width
        lda     #RIA_ATTR_RLN_HEIGHT
        sta     RIA_A
        lda     #RIA_OP_ATTR_GET
        sta     RIA_OP
        jsr     RIA_SPIN
        cmp     #2
        bcc     @ret
        sta     more_height               ; pager now considered armed
        sec
        sbc     #1                        ; reserve one row for the prompt
        sta     more_rows_left
        stz     more_col
        lda     #<chrout_pager
        sta     chrout_vec
        lda     #>chrout_pager
        sta     chrout_vec+1
@ret:   rts
