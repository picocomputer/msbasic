; Picocomputer 6502 BASIC file I/O. Implements OPEN, CLOSE, INPUT#,
; CHKIN, CHKOUT, CLRCH, plus the GETLN-shaped reader rp6502_filin.
; PRINT#, GET#, and CMD are already implemented in misc1.s/input.s
; and just consume CHKOUT/CHKIN/CLRCH as black-box stubs — those
; stubs come live here.
;
; The logical-file table LFTAB lives in zero page (zeropage.s);
; entries are kernel fds, $FF for unused. Lfn 0..15 index directly.
; Lfn 0 is reserved (BASIC convention: 0 = default I/O).
;
; Read semantics: a read returning fewer bytes than requested is EOF
; (cc65 / RP6502 OS convention; matches loadsave.s). We never loop
; on short reads — pipe-style polling is the BASIC programmer's job
; via GET# in a BASIC loop. INPUT# treats short read as EOF and sets
; Z96 bit 1; the existing INPUT path at input.s:131-137 then bails
; cleanly via LCAD6 + jmp DATA.
;
; Modes for OPEN are Unix-style strings:
;   "r"  → O_RDONLY               (default if mode omitted)
;   "w"  → O_WRONLY|O_CREAT|O_TRUNC
;   "a"  → O_WRONLY|O_CREAT|O_APPEND
;   "rw" or "r+" → O_RDWR
;   "w+" → O_RDWR|O_CREAT|O_TRUNC
;   "a+" → O_RDWR|O_CREAT|O_APPEND
; Anything else → ?FILE DATA ERROR.

.segment "CODE"

; ============================================================
; OPEN <lfn>, <name$> [, <mode$>]
; ============================================================
OPEN:
        jsr     GETBYT                  ; X = lfn
        cpx     #8
        bcs     file_err                ; lfn must be 0..7
        lda     LFTAB,x
        cmp     #$FF
        bne     file_err                ; slot already in use
        phx                             ; stash lfn on the 6502 stack —
                                        ; CHARAC isn't safe (FRMEVL's
                                        ; STRLIT path writes $22 to it,
                                        ; see string.s:48-49). Error
                                        ; paths below leave it on the
                                        ; stack; ERROR's STKINI resets
                                        ; SP for us.

        lda     #','
        jsr     SYNCHR                  ; require comma before name

        jsr     rp6502_push_string      ; FRMEVL → CHKSTR → push reversed
                                        ; bytes onto RIA_XSTACK; null
                                        ; terminator short-stacks for free.
                                        ; From here on, any abort before
                                        ; RIA_OP_OPEN consumes the xstack
                                        ; must route through file_err_zx.

        ; Optional mode: another comma + string. Default O_RDONLY.
        jsr     CHRGOT
        beq     @default_mode           ; end of statement → default
        cmp     #','
        bne     file_err_zx
        jsr     CHRGET                  ; advance past ','
        jsr     FRMEVL
        jsr     CHKSTR
        jsr     FREFAC                  ; A = length, INDEX = ptr to bytes
        jsr     mode_to_flags           ; A → O_* flags, or jmps to file_err_zx
        bra     @open
@default_mode:
        lda     #O_RDONLY
@open:
        jsr     rp6502_open             ; consumes xstack on success or errno
        bcs     @open_failed
        tay                             ; save kernel fd; pla clobbers A
        pla                             ; A = lfn
        tax
        tya                             ; A = kernel fd
        sta     LFTAB,x
        rts
@open_failed:
        pla                             ; drop the saved lfn
        jmp     file_err

file_err:
        jmp     lsav_err_baddata        ; ?FILE DATA ERROR

; Same destination, but first drains any pushed xstack bytes.
; Used by error paths between lsav_push_filename and rp6502_open.
file_err_zx:
        rp6502_zxstack
        jmp     lsav_err_baddata

; ------------------------------------------------------------
; mode_to_flags
;   In:  A = mode-string length, INDEX = ptr to mode bytes.
;   Out: A = O_* flag bits, or jmp @err on unknown mode.
;   Recognized: "r" "w" "a" "rw" "r+" "w+" "a+" (case-insensitive
;   — ora #$20 normalizes A-Z to a-z; '+' is unaffected).
; ------------------------------------------------------------
mode_to_flags:
        cmp     #1
        beq     @len1
        cmp     #2
        bne     @bad
        ldy     #$01
        lda     (INDEX),y
        ora     #$20
        cmp     #'+'
        beq     @plus
        cmp     #'w'
        bne     @bad
        ldy     #$00
        lda     (INDEX),y
        ora     #$20
        cmp     #'r'
        bne     @bad
        lda     #O_RDWR
        rts
@plus:
        ldy     #$00
        lda     (INDEX),y
        ora     #$20
        cmp     #'r'
        beq     @rplus
        cmp     #'w'
        beq     @wplus
        cmp     #'a'
        beq     @aplus
@bad:
        jmp     file_err_zx
@rplus:
        lda     #O_RDWR
        rts
@wplus:
        lda     #O_RDWR | O_CREAT | O_TRUNC
        rts
@aplus:
        lda     #O_RDWR | O_CREAT | O_APPEND
        rts
@len1:
        ldy     #$00
        lda     (INDEX),y
        ora     #$20
        cmp     #'r'
        beq     @r
        cmp     #'w'
        beq     @w
        cmp     #'a'
        beq     @a
        bne     @bad
@r:
        lda     #O_RDONLY
        rts
@w:
        lda     #O_WRONLY | O_CREAT | O_TRUNC
        rts
@a:
        lda     #O_WRONLY | O_CREAT | O_APPEND
        rts

; ============================================================
; CLOSE <lfn>
; Idempotent on already-closed slots. tty:/con: are no-ops in the
; OS so no special-case guard is needed when the user does
; OPEN n,"tty:" then CLOSE n.
; ============================================================
CLOSE:
        jsr     GETBYT                  ; X = lfn
        cpx     #8
        bcs     @done                   ; out-of-range → silently ignore
        lda     LFTAB,x
        cmp     #$FF
        beq     @done                   ; already closed
        phx                             ; save lfn across the close
        jsr     rp6502_close
        plx
        lda     #$FF
        sta     LFTAB,x
@done:
        rts

; ============================================================
; INPUTH — INPUT# <lfn>, <var>[, <var>...]
; Pattern mirrors PRINTH/CMD in misc1.s: parse lfn, swap I/O via
; CHKIN, jsr the INPUT body, fall through to LCAD6 cleanup. EOF
; mid-statement is handled inside INPUT itself (input.s:131-137)
; via the Z96-bit-1 flag rp6502_filin sets on short read.
; ============================================================
INPUTH:
        ; Clear Z96 bit 1 (EOF) at entry so a previous file's EOF
        ; can't leak into this statement.
        lda     Z96
        and     #$FD
        sta     Z96

        jsr     GETBYT                  ; X = lfn
        lda     #','
        jsr     SYNCHR                  ; require comma; advances past
        jsr     CHKIN
        stx     CURDVC
        jsr     L2A9E                   ; INPUT body (skips prompt-string parse)
        jmp     LCAD6                   ; restore default I/O, zero CURDVC

; ============================================================
; CHKIN — redirect input from lfn (X = lfn).
; Looks up the kernel fd, stores it in in_fd, and points
; getln_vec at rp6502_filin so INLIN's per-byte reads route
; through the file. Preserves X for the caller's stx CURDVC.
; ============================================================
CHKIN:
        cpx     #8
        bcs     @bad
        lda     LFTAB,x
        cmp     #$FF
        beq     @bad
        sta     in_fd
        lda     #<rp6502_filin
        sta     getln_vec
        lda     #>rp6502_filin
        sta     getln_vec+1
        rts
@bad:
        jmp     file_err

; ============================================================
; CHKOUT — redirect output to lfn (X = lfn).
; Looks up the kernel fd and stores it in out_fd; rp6502_chrout
; already routes there and retries partial writes for tty:
; flow control. Preserves X.
; ============================================================
CHKOUT:
        cpx     #8
        bcs     @bad
        lda     LFTAB,x
        cmp     #$FF
        beq     @bad
        sta     out_fd
        rts
@bad:
        jmp     file_err

; ============================================================
; CLRCH — restore default I/O routing.
; Called by LCAD6 (input.s:71-76) at the tail of INPUT#/PRINT#/
; GET# and by program.s on RUN/RESTART. Idempotent.
; ============================================================
CLRCH:
        lda     tty_fd
        sta     out_fd
        sta     in_fd
        lda     #<rp6502_inlin
        sta     getln_vec
        lda     #>rp6502_inlin
        sta     getln_vec+1
        rts

; ============================================================
; rp6502_filin — GETLN hook for INPUT# mode.
; Reads one byte from in_fd, translates LF→CR, returns it in A.
; On short read (bytes_returned < 1) or errno: sets Z96 bit 1
; (EOF) and returns CR so INLIN closes the line cleanly; the
; existing INPUT path (input.s:131-137) sees the EOF flag and
; bails through LCAD6 + jmp DATA.
;
; X and Y are preserved across RIA_SPIN via the 6502 stack
; (matches lsav_load_chrin's contract — INLIN holds its buffer
; index in X across each GETLN call).
; ============================================================
rp6502_filin:
        phx
        phy
        lda     #$01
        sta     RIA_XSTACK              ; count = 1; hi short-stacks to 0
        lda     in_fd
        sta     RIA_A
        lda     #RIA_OP_READ_XSTACK
        sta     RIA_OP
        jsr     RIA_SPIN
        cpx     #$FF                    ; errno → EOF
        beq     @eof
        cmp     #$01
        bne     @eof                    ; short read → EOF
        lda     RIA_XSTACK              ; pop the byte
        cmp     #$0A
        bne     @ret
        lda     #$0D                    ; LF → CR
@ret:
        ply
        plx
        rts
@eof:
        ; Set Z96 bit 1 (EOF flag) and return CR so INLIN finishes
        ; whatever line it has accumulated. The empty-line case
        ; (no bytes read on this line) is the one INPUT's EOF
        ; check at input.s:131-137 actually fires on; mid-line
        ; EOF terminates the current line with CR and the next
        ; INPUT-loop NXIN sees the empty buffer.
        lda     Z96
        ora     #$02
        sta     Z96
        ply
        plx
        lda     #$0D
        rts
