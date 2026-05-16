; chrout_buf borrows TEMP1 as its INBUF write offset. Other TEMP1
; users are LOAD's per-line byte counter (loadsave.s) and FP, whose
; 5-byte scratch starts at TEMP1 and lives through TEMP1X. Tab
; completion only runs inside CHRIN's input wait — never overlaps
; with LOAD (OK-prompt only) or FP (interpretation only).
inbuf_off = TEMP1

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
        jsr     FRMEVL                 ; evaluate expression → FAC
        jsr     CHKSTR                 ; bomb out if not a string
        jsr     FREFAC                 ; A=length, INDEX=ptr to bytes
        tay                            ; Y=length
        jeq     lsav_err_baddata       ; empty string ⇒ error (long
                                       ; branch — lsav_err_baddata is
                                       ; in the CODE segment, beq's
                                       ; ±127 range can't reach)
@push_loop:
        dey                            ; Y goes length-1 → 0
        lda     (INDEX),y
        sta     RIA_XSTACK
        tya
        bne     @push_loop
        rts

; ------------------------------------------------------------
; ria_init_io
;   Open "tty:" O_WRONLY into tty_fd, "con:" O_RDONLY into con_fd.
;   Also wipes LFTAB and resets in_fd/out_fd/lsav_fd so a warm
;   start doesn't carry stale fds from the prior run — the OS
;   side has invalidated all of them by the time we reach here.
; ------------------------------------------------------------
ria_init_io:
        ; Wipe LFTAB to all $FF (no lfn open).
        ldx #<(__LFTAB_SIZE__ - 1)
        lda #$FF
@wipe_lftab:
        sta __LFTAB_START__,x
        dex
        bpl @wipe_lftab
        stz lsav_fd

        lda #':'
        sta RIA_XSTACK
        lda #'y'
        sta RIA_XSTACK
        lda #'t'
        sta RIA_XSTACK
        lda #'t'
        sta RIA_XSTACK
        lda #O_WRONLY
        jsr ria_open
        sta tty_fd

        lda #':'
        sta RIA_XSTACK
        lda #'n'
        sta RIA_XSTACK
        lda #'o'
        sta RIA_XSTACK
        lda #'c'
        sta RIA_XSTACK
        lda #O_RDONLY
        jsr ria_open
        sta con_fd

        ; Default CHROUT target = tty_fd. SAVE temporarily swaps this
        ; to a file fd to capture LIST output to disk; CHKOUT swaps
        ; it to a user fd for PRINT#.
        lda tty_fd
        sta out_fd
        ; Default GET / GETIN source = tty_fd. CHKIN redirects it
        ; for GET#.
        sta in_fd
        ; Default GETLN target = CHRIN. LOAD swaps this to its
        ; own per-byte file-reader, then restores on EOF; CHKIN swaps
        ; it to ria_filin for INPUT#.
        lda #<CHRIN
        sta getln_vec
        lda #>CHRIN
        sta getln_vec+1
        ; Default CHROUT dispatch goes to chrout_fd. Tab completion
        ; and the LIST --More-- pager swap this transiently.
        lda #<chrout_fd
        sta chrout_vec
        lda #>chrout_fd
        sta chrout_vec+1
        rts

; ------------------------------------------------------------
; chrout_fd — default CHROUT target.
;   Writes A to out_fd. Loops on partial writes (op may return
;   bytes_written < 1 while the OS-side tx queue drains).
;   Preserves A, X, Y.
; ------------------------------------------------------------
chrout_fd:
        phx
        phy
        tay                       ; Y holds the byte across RIA_SPIN
                                  ; (which clobbers A and X but not Y)
@write_fd:
        sty RIA_XSTACK
        lda out_fd
        sta RIA_A
        lda #RIA_OP_WRITE_XSTACK
        sta RIA_OP
        jsr RIA_SPIN
        bmi @write_err            ; rc<0 on failure
        lda RIA_A                 ; bytes_written, low byte
        cmp #1
        bcc @write_fd             ; partial write — re-push, retry
        tya                       ; A = original byte
        ply                       ; PLY/PLX preserve A
        plx
        rts

@write_err:
        ; tty: write failures are unrecoverable — ERROR's own message
        ; would just re-enter CHROUT — so eat them. Non-tty out_fd
        ; means either SAVE redirected to a file (disk full mid-LIST)
        ; or CHKOUT redirected to a user PRINT# fd; either way route
        ; through ERROR. lsav_panic prologue restores out_fd to tty
        ; and tears down any active LOAD/SAVE state, idempotent when
        ; neither is active — so PRINT# write errors get the right
        ; teardown without a spurious close on lsav_fd=0.
        ; ria_zxstack on a failed op is unneeded (OS already drained)
        ; but harmless; kept here for explicitness.
        lda out_fd
        cmp tty_fd
        beq @write_drop
        ria_zxstack
        ply
        plx
        jmp lsav_err_baddata
@write_drop:
        tya
        ply
        plx
        rts

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
; GETIN
;   Non-blocking read of one byte from in_fd (defaults to tty:; CHKIN
;   redirects it for GET#). Returns A=char or A=0/Z=1 if no byte ready.
;   Preserves X, Y. Used by GET. On a redirected fd
;   at EOF the OS returns 0 too, so we just report "" — GET# never
;   sets Z96's EOF bit, so a BASIC loop polling a pipe stays clean.
; ------------------------------------------------------------
GETIN:
        phx
        phy
        lda #$01
        sta RIA_XSTACK            ; count = 1; hi byte short-stacks to 0
        lda in_fd
        sta RIA_A
        lda #RIA_OP_READ_XSTACK
        sta RIA_OP
        jsr RIA_SPIN
        cmp #1                    ; bytes read
        bne @no_data
        lda RIA_XSTACK            ; pop the byte
@done:
        ply                       ; PLY/PLX preserve A
        plx
        cmp #$00                  ; re-establish Z flag from A
        rts
@no_data:
        lda #$00
        bra @done

; ------------------------------------------------------------
; ria_tab_completion
;   Called from CHRIN's wait loop when the user presses TAB.
;   Peeks the current readline buffer; if it parses as a single
;   decimal line number that exists in the program, replaces the
;   editor's contents with `<lineno> <detokenized text>` so the
;   user can edit the line in place.
;   Caller drains xstack after return (paths that bail early may
;   leave bytes on it).
; ------------------------------------------------------------
ria_tab_completion:
        ; --- Phase A: peek current readline buffer onto xstack. ---
        lda #RIA_OP_RLN_PEEK
        sta RIA_OP
        jsr RIA_SPIN

        ; --- Phase B: parse digits off xstack into LINNUM. ---
        ; Pop top-down: chars come out in forward order, terminated
        ; by 0. Non-digit, overflow, or empty buffer → abort.
        stz LINNUM
        stz LINNUM+1
        ldy #$00                  ; digit count
@parse:
        lda RIA_XSTACK
        beq @parsed               ; 0 terminator → done
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
        bra @parse                ; the multiply checks above kill us
                                  ; long before iny could wrap Y to 0

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

more_prompt_str: .byte "--More--", 0
more_erase_str:  .byte $08, $08, $08, $08, $08, $08, $08, $08
                 .byte $20, $20, $20, $20, $20, $20, $20, $20
                 .byte $08, $08, $08, $08, $08, $08, $08, $08, 0

; ------------------------------------------------------------
; CHRIN
;   Blocking read of one byte from "con:" (line-cooked). MS BASIC's
;   GETLN calls this to assemble interactive lines and INPUT replies;
;   "con:" delivers a line ending in LF (per the OS), translated to
;   CR here so BASIC's $0D line-terminator check matches.
;
;   While waiting for the first byte (user still typing), polls two
;   sidechannels: RIA_ATTR_SIGINT for break (Ctrl-C at the OK prompt
;   or during INPUT), and RIA_OP_RLN_LASTKEY to catch a TAB and run
;   line-number completion. Once con: starts releasing bytes, the
;   read_xstack call succeeds on the first try (the line is queued
;   end-to-end), so the side polls run only while the user is typing.
; ------------------------------------------------------------
CHRIN:
        phx
        phy
@wait:
        ; SIGINT before anything else — once Ctrl-C has latched, we
        ; must not read another con: byte or feed one to the caller.
        bit RIA_IRQ               ; V = bit 6 (sigint latch); read clears
        bvs @sigint

        lda #$01
        sta RIA_XSTACK            ; count = 1; hi byte short-stacks to 0
        lda con_fd
        sta RIA_A
        lda #RIA_OP_READ_XSTACK
        sta RIA_OP
        jsr RIA_SPIN
        cmp #1
        beq @got_byte             ; line byte ready

        lda #RIA_OP_RLN_LASTKEY
        sta RIA_OP
        jsr RIA_SPIN
        cmp #1                    ; exactly one byte?
        bne @drain                ; 0 or 2+ bytes — just drain
        lda RIA_XSTACK            ; pop the one byte
        cmp #$09                  ; TAB?
        bne @wait
        jsr ria_tab_completion
@drain:
        ria_zxstack               ; idempotent: stz RIA_OP
        bra @wait

@sigint:
        ; Poke CTRL-C so the OS line editor releases with ^C notification.
        lda #$03
        sta RIA_XSTACK
        lda #RIA_OP_RLN_POKE
        sta RIA_OP
        jsr RIA_SPIN

        ; Drain the released bytes off con: into xstack and toss
        ; them. Without this drain, those bytes would leak into the
        ; next OK-prompt INLIN as if the user typed them.
        lda #$FF
        sta RIA_XSTACK            ; count lo = 255; hi short-stacks
        lda con_fd
        sta RIA_A
        lda #RIA_OP_READ_XSTACK
        sta RIA_OP
        jsr RIA_SPIN
        ria_zxstack

        ; Return A=$03 as the cancel sentinel. Our INLIN matches it
        ; via `cmp #$03; beq @cancel`, resets its accumulator, and
        ; exits with A=$03. INPUT (after jsr NXIN) checks A and
        ; bails through `sec; jmp CONTROL_C_TYPED` to "?BREAK IN
        ; <line>" + RESTART. Distinct from blank Enter (A=$0D, empty
        ; INBUF → continue with "" / 0) — upstream conflates
        ; them, we don't.
        lda #$03
        ply
        plx
        rts

@got_byte:
        lda RIA_XSTACK
        cmp #$0A
        bne @ret
        lda #$0D
@ret:
        ply                       ; PLY/PLX preserve A
        plx
        rts

; ------------------------------------------------------------
; ISCNTC — break detection via OS sidechannel.
;   BIT RIA_IRQ loads bit 6 (the latched Ctrl-C flag) into V and
;   the read clears the latch atomically, so the SIGINT poll itself
;   doesn't compete with GET for tty: bytes.
;   V=0 → no break (rts). V=1 → break:
;     1. Drain tty: of any $03 bytes the user's Ctrl-C also queued
;        (without this, a CONT'd GET would assign chr$(3) to its
;        variable).
;     2. Call lsav_abort to tear down SAVE state if LIST was mid-
;        iteration; otherwise the BREAK message would land in the
;        save file (out_fd) instead of the terminal.
;     3. Restore chrout_vec to chrout_fd via chrout_vec_reset:
;        ISCNTC can fire deep inside the tab-completion or pager
;        L25A6X loop, and STOP unwinds the whole stack without
;        returning through those routines' own restore code. The
;        reset is unconditional/idempotent — safe in non-overlay
;        cases too.
;     4. Set up STOP entry: A=0, C=1, Z=1 so `bcs END2` is taken
;        and END2's `bne RET1` falls through into the BREAK path.
;        END4's `pla; pla` pops our caller's JSR ISCNTC frame;
;        RESTART → STKINI resets SP.
; ------------------------------------------------------------
ISCNTC:
        bit RIA_IRQ               ; V = bit 6 (sigint latch); read clears
        bvs :+
        rts
:       lda #$FF                  ; drain tty: of the user's Ctrl-C
        sta RIA_XSTACK            ; count lo = 255; hi short-stacks
        lda tty_fd
        sta RIA_A
        lda #RIA_OP_READ_XSTACK
        sta RIA_OP
        jsr RIA_SPIN
        ria_zxstack
        ; fall through to break_to_stop

break_to_stop:
        jsr lsav_abort            ; restore I/O if SAVE was mid-LIST
        jsr chrout_vec_reset      ; restore CHROUT dispatch (pager/tab)
        lda #$00                  ; Z=1 for STOP entry (the jsr above
                                  ; clobbered Z via lda #>chrout_fd, and
                                  ; STOP→END2's `bne RET1` would otherwise
                                  ; short-circuit out of the BREAK path).
        sec                       ; C=1 for STOP entry
        jmp STOP

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

; ------------------------------------------------------------
; pager_arm — call at LIST entry. Validates the pager-enable
; gates; on success reads width/height from RIA, primes the
; row budget, and installs chrout_pager into chrout_vec.
;
; Gates:
;   - direct mode only (CURLIN+1 == $FF). LIST from inside a
;     running program keeps upstream's straight-through behavior.
;   - out_fd == tty_fd (no CMD/SAVE redirect — no --More-- bytes
;     should land in saved files).
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

; ------------------------------------------------------------
; chrout_vec_reset — unconditionally restore chrout_vec to
; chrout_fd and zero more_height. Idempotent. Called from:
;   - normal LIST exit (program.s L25E5)
;   - ISCNTC break path
;   - more_prompt's @break (q/Q/Ctrl-C at the prompt)
;   - ria_tab_completion's end-of-listing restore
; Any "I'm done overlaying CHROUT" site lands here.
; ------------------------------------------------------------
chrout_vec_reset:
        stz     more_height
        lda     #<chrout_fd
        sta     chrout_vec
        lda     #>chrout_fd
        sta     chrout_vec+1
        rts

; ------------------------------------------------------------
; chrout_pager — chrout_vec target while the LIST pager is
; armed. Intercepts every byte at the CHROUT layer, tracks the
; pager's view of the cursor, pauses on row-advance events
; that would push content past the bottom of the screen, then
; tail-calls chrout_fd to actually emit the byte.
;
; Column model: delayed-wrap (xterm/vt100). After writing the
; W-th char, the cursor sits in a "pending wrap" cell at col W;
; the wrap fires only when the next printable arrives, which
; goes to col 1 of the new row.
;
; Per-byte:
;   $0A (LF)        — row advance; pause-if-budget-zero, dec budget.
;   $0D (CR)        — col := 0.
;   < $20 (other)   — passthru. CRUNCH drops $01..$1F inside
;                     string/REM literals, so LIST output is
;                     control-char-free in practice.
;   ≥ $20 printable — if col == width, this byte wraps:
;                     pause-if-budget-zero, dec budget, col := 1.
;                     Else col := col + 1.
;
; A/X/Y preserved (matches chrout_fd's contract; chrout_pager
; tail-calls chrout_fd so the contract holds end-to-end).
; Y is saved on entry / restored on exit because the body
; clobbers it for column tracking, and callers like STROUT
; iterate (INDEX),y across successive CHROUT calls — they
; rely on Y surviving the trip through CHROUT.
; ------------------------------------------------------------
chrout_pager:
        phy
        cmp     #$0A
        beq     @lf
        cmp     #$0D
        beq     @cr
        cmp     #$20
        bcc     @done                     ; other control: emit unchanged
        ; printable: delayed-wrap check
        ldy     more_col
        cpy     more_width
        bne     @bump
        ; col == width: emitting this byte causes a wrap. We prompt
        ; BEFORE the emit on this path — the prompt's own first byte
        ; triggers the same wrap, then erase brings the cursor back
        ; to col 0 of the new row, then the byte emits there. Going
        ; emit-first instead would leave the wrap byte visible at col
        ; 0 with "--More--" tacked on at cols 1..8 (the bug).
        ldy     #1                        ; cursor will be at col 1 post-emit
        sty     more_col
        pha                               ; preserve A across pause
        dec     more_rows_left
        bne     @wrap_emit
        jsr     more_prompt
        lda     more_height
        sec
        sbc     #1
        sta     more_rows_left
@wrap_emit:
        pla
        ply
        jmp     chrout_fd                 ; emit byte (post-prompt if paused)
@bump:
        iny
        sty     more_col
        bra     @done

@cr:
        stz     more_col
        bra     @done

@lf:
        ; LF: emit it FIRST so the cursor lands on the fresh row,
        ; THEN prompt. Prompting before LF would overlay line N's
        ; first 8 chars (CR has already pulled the cursor back to
        ; col 0 of N's row). Dec-then-bne (matching wrap) keeps
        ; more_rows_left in {1..height-1}: never sits at 0 between
        ; events, so the dec never underflows.
        ply
        jsr     chrout_fd                 ; emit LF (cursor → new row)
        pha                               ; preserve A across pause
        dec     more_rows_left
        bne     @lf_ret
        jsr     more_prompt
        lda     more_height
        sec
        sbc     #1
        sta     more_rows_left
@lf_ret:
        pla
        rts

@done:
        ply                               ; restore caller's Y before chrout_fd
        jmp     chrout_fd                 ; tail-call (chrout_fd preserves A/X/Y)


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
; ------------------------------------------------------------
more_prompt:
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
@done:  rts

@break:
        jmp     break_to_stop
