; Picocomputer ASCII SAVE/LOAD. Replaces upstream src/msbasic/loadsave.s
; (which is just a variant dispatcher and zero bytes for our config).
;
; SAVE writes the program out as plain text — same byte stream LIST
; emits — by redirecting CHROUT (via out_fd) to the save fd and
; calling LIST.
;
; LOAD installs lsav_load_chrin as the GETLN hook so the existing
; INLIN / interpreter loop reads each line from the file as if the
; user were typing it. NUMBERED_LINE inserts the line and tail-jumps
; back to L2351, which reads the next line, until lsav_load_chrin
; hits EOF — at which point it closes the file, restores GETLN to
; con:, prints "OK", and returns CR so INLIN finishes its current
; line and the main loop falls back to reading from con: as usual.
;
; Hooking GETLN sidesteps the fact that NUMBERED_LINE → SETPTRS goes
; through STKINI (which rebases SP to STACK_TOP every line) — that
; makes calling NUMBERED_LINE as a subroutine impossible, so we let
; the existing tail-jump architecture do the work.

.segment "CODE"

lsav_err_baddata:
        ldx     #ERR_BADDATA
        jmp     ERROR

; ============================================================
; SAVE "filename"
; Open file for write (creating/truncating), redirect CHROUT
; to the file fd, JSR LIST to detokenize the program, restore
; CHROUT back to tty, close the file.
; ============================================================
SAVE:
        jsr     ria_push_string
        lda     #O_WRONLY | O_CREAT | O_TRUNC
        jsr     ria_open
        bcs     lsav_err_baddata
        sta     lsav_fd
        sta     out_fd                 ; redirect CHROUT to the file

        ; LIST is normally entered from statement dispatch with A and
        ; the carry flag set up by CHRGOT (A = current char, carry
        ; set on non-digits). Re-establish that state from the
        ; end-of-stmt $00 left over after FRMEVL so LIST's internal
        ; LINGET sees "no line range given" rather than walking off
        ; into garbage.
        jsr     CHRGOT
        jsr     LIST

        ; Restore output to tty and close. Clear lsav_fd before SPIN
        ; so that a CLOSE failure (failed flush ⇒ truncated file)
        ; can route through ERROR with the LOAD-active flag already
        ; down — otherwise program.s's guard would mistake the next
        ; direct command for a stray non-numbered line.
        lda     tty_fd
        sta     out_fd
        lda     lsav_fd
        stz     lsav_fd
        jsr     ria_close
        cpx     #$FF
        beq     lsav_err_baddata       ; flush failed ⇒ file truncated
        rts

; ============================================================
; lsav_abort — release SAVE-mid-LIST state when Ctrl-C interrupts
; LIST's iteration. Restores out_fd to the terminal so the BREAK
; message goes there (not into the save file), closes the file
; fd, and clears the LOAD-active flag. A no-op when out_fd is
; already tty (the only redirector is SAVE). Called from
; ISCNTC before jmp STOP; STKINI in the STOP→ERROR→RESTART
; path resets SP, so we don't preserve registers.
; ============================================================
lsav_abort:
        lda     out_fd
        cmp     tty_fd
        beq     @done
        lda     tty_fd
        sta     out_fd
        lda     lsav_fd
        jsr     ria_close
        stz     lsav_fd
@done:
        rts

; ============================================================
; lsav_panic — recover I/O state on any BASIC error mid-LOAD or
; mid-SAVE. Restores out_fd to tty, restores GETLN to the
; default INLIN, closes lsav_fd if open, and cancels any
; pending auto-run. Idempotent: when no LOAD/SAVE is active
; this is all no-ops, so calling it from ERROR's prologue
; covers the rare cases that don't have a dedicated teardown
; (e.g. OOMERR while NUMBERED_LINE inserts a loaded line, or
; any future error path inside LIST during SAVE) without
; disturbing normal-error flow. Preserves X across RIA_SPIN
; because ERROR uses X as the message-table offset.
; ============================================================
lsav_panic:
        lda     tty_fd
        sta     out_fd
        sta     in_fd                  ; CHKIN may have redirected input
                                       ; for INPUT#; restore so the next
                                       ; GET#/INPUT# starts clean
        lda     #<CHRIN
        sta     getln_vec
        lda     #>CHRIN
        sta     getln_vec+1
        stz     auto_run
        lda     lsav_fd
        beq     @done
        stz     lsav_fd
        phx
        jsr     ria_close
        plx
@done:
        rts

; ============================================================
; LOAD "filename"
; Open file, clear current program, install the GETLN hook, and
; jmp into the interpreter's input loop. The hook (lsav_load_chrin)
; feeds bytes from the file; on EOF it closes the file, restores
; the default GETLN, resets the stack, and jmps to RESTART.
; ============================================================
LOAD:
        jsr     ria_push_string
        lda     #O_RDONLY
        jsr     ria_open
        jcs     lsav_err_baddata
        sta     lsav_fd
        stz     TEMP1                  ; LOAD borrows TEMP1 as the
                                       ; per-line byte counter (float/
                                       ; string scratch, idle here)

        jsr     SCRTCH                 ; clear current program

        lda     #<lsav_load_chrin
        sta     getln_vec
        lda     #>lsav_load_chrin
        sta     getln_vec+1

        jmp     L2351                  ; into the interpreter input loop

; ============================================================
; lsav_load_err — abort an in-progress LOAD due to bad data
; (line >255 chars, or a non-numbered line — both indicate either
; a corrupt save file or a stray text file). Closes the fd,
; restores the default GETLN, clears the LOAD-active flag, and
; routes through ERROR. The program built up before the bad line
; is preserved, so the user can LIST to see how far LOAD got.
; STKINI inside ERROR resets SP, so we don't bother cleaning up
; whatever the caller pushed on entry.
; ============================================================
lsav_load_err:
        lda     lsav_fd
        jsr     ria_close
        lda     #<CHRIN
        sta     getln_vec
        lda     #>CHRIN
        sta     getln_vec+1
        stz     lsav_fd
        stz     auto_run               ; cancel any pending auto-run
        ldx     #ERR_BADDATA
        jmp     ERROR

; ============================================================
; lsav_load_chrin — GETLN hook for LOAD mode.
; Reads one byte from lsav_fd and returns it in A, translating
; LF→CR to match what INLIN expects. On EOF: close the file,
; restore the default GETLN, print "OK", and return CR so INLIN
; finishes its current line cleanly.
; ============================================================
lsav_load_chrin:
        ; INLIN holds its buffer index in X across each jsr GETLN, and
        ; RIA_SPIN clobbers X. Preserve via the 6502 stack.
        phx
        phy

        ; auto_run state machine for cold-boot auto-load:
        ;   0/1 = read from file (1 = auto-load mode; same byte path
        ;         as a user-typed LOAD, but takes the auto-run branch
        ;         on EOF).
        ;   2..4 = post-EOF: emit "UN\r" one byte per call (the 'R'
        ;         was emitted directly from the EOF path).
        lda     auto_run
        cmp     #$02
        bcs     @emit_run

        lda     #$01
        sta     RIA_XSTACK             ; count = 1; hi byte short-stacks to 0
        lda     lsav_fd
        sta     RIA_A
        lda     #RIA_OP_READ_XSTACK
        sta     RIA_OP
        jsr     RIA_SPIN
        cpx     #$FF                   ; errno → surface as bad data
        beq     @read_err              ; rather than silent EOF
        cmp     #$01
        bne     @eof
        lda     RIA_XSTACK             ; pop the byte
        cmp     #$0A
        bne     @check_cr
        lda     #$0D
@check_cr:
        cmp     #$0D
        beq     @reset_count
        ; Non-CR byte. Bump the per-line counter; wrap to 0 → line is
        ; too long (>=256 bytes without a terminator) → fail the LOAD.
        inc     TEMP1
        beq     @too_long
        bra     @done
@reset_count:
        stz     TEMP1
@done:
        ply                            ; PLX/PLY don't touch A, so the
        plx                            ; byte we just computed survives
        rts

@too_long:
@read_err:
        bra     lsav_load_err          ; STKINI in ERROR resets SP

@eof:
        ; STROUT below clobbers CHROUT's scratch slots, but X/Y are on
        ; the 6502 stack from entry, safe there.
        lda     lsav_fd
        jsr     ria_close
        stz     lsav_fd                ; clear LOAD-active flag

        lda     auto_run
        cmp     #$01
        beq     @start_auto_run

        ; Normal LOAD EOF: restore vec, print "OK", return CR.
        lda     #<CHRIN
        sta     getln_vec
        lda     #>CHRIN
        sta     getln_vec+1
        lsr     Z14
        lda     #<QT_OK
        ldy     #>QT_OK
        jsr     STROUT
        ply
        plx
        lda     #$0D
        rts

@start_auto_run:
        ; Cold-boot auto-load: emit 'R' now, queue "UN\r" for
        ; subsequent calls. Don't restore getln_vec yet — we want
        ; the OS to keep routing GETLN through us until "RUN\r" is
        ; fully delivered to INLIN.
        lda     #$02                   ; next call → emit_run with idx 0
        sta     auto_run
        ply
        plx
        lda     #'R'
        rts

@emit_run:
        ; auto_run = 2/3/4 → emit "UN\r"[auto_run-2].
        sec
        sbc     #$02
        tay
        lda     @run_tail,y
        inc     auto_run
        cmp     #$0D
        bne     @emit_done
        ; CR is the last char. Restore vec and idle the state machine
        ; before INLIN exits with "RUN" in INPUTBUFFER and RESTART
        ; dispatches it.
        stz     auto_run
        ldy     #<CHRIN
        sty     getln_vec
        ldy     #>CHRIN
        sty     getln_vec+1
@emit_done:
        ply
        plx
        rts

@run_tail:
        .byte   "UN", $0D
