.segment "EXTRA"

; ------------------------------------------------------------
; chrout_fd — default CHROUT target.
;   Writes A to out_fd. Retries when bytes_written == 0 (OS-side
;   tx queue full; tty: backpressures by reporting 0 until drain).
;   Preserves A, X, Y.
; ------------------------------------------------------------
chrout_fd:
        phx
        phy
        tay                       ; stash byte in Y; RIA_SPIN clobbers A/X, not Y
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
        bcc @write_fd             ; 0 bytes (tx queue full) — re-push, retry
        tya                       ; A = original byte (PLY/PLX preserve it)
        ply
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
; chrout_vec_reset — unconditionally restore chrout_vec to
; chrout_fd and zero more_height. Idempotent. Called from:
;   - normal LIST exit (RESTART, before reading the next OK line)
;   - break_to_stop (ISCNTC, or more_prompt's q/Q/Ctrl-C)
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
; CHRIN
;   Blocking read of one byte from "con:" (line-cooked). MS BASIC's
;   GETLN calls this to assemble interactive lines and INPUT replies;
;   "con:" delivers a line ending in LF (per the OS), translated to
;   CR here so BASIC's $0D line-terminator check matches.
;
;   While waiting for the first byte (user still typing), polls two
;   sidechannels: RIA_ATTR_SIGINT for break (Ctrl-C at the OK prompt
;   or during INPUT), and RIA_OP_RLN_LASTKEY to catch a TAB and run
;   line-number completion. LASTKEY pushes a "consumed" flag on top
;   of the key bytes — true when the line editor already acted on the
;   key (typing, arrows, backspace, etc.); we drop those so only keys
;   the editor passed through (TAB) reach the completion path.
;   Once con: starts releasing bytes, the read_xstack call succeeds
;   on the first try (the line is queued end-to-end), so the side
;   polls run only while the user is typing.
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
        cmp #1                    ; exactly one key byte? (TAB is 1-byte)
        bne @drain                ; 0 or 2+ key bytes — just drain
        lda RIA_XSTACK            ; pop consumed flag (pushed last → on top)
        bne @drain                ; line editor already acted on it — ignore
        lda RIA_XSTACK            ; pop the key byte
        cmp #$09                  ; TAB?
        bne @wait                 ; xstack already empty here
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

        ; Drain con:
        lda #$FF
        sta RIA_XSTACK
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
