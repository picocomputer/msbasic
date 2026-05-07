.segment "EXTRA"

;---------------------------------------------
; rp6502_zxstack — synchronous xstack drain.
; RIA_OP_ZXSTACK is $00 and the op fires on the write to RIA_OP
; with no SPIN, so this is a single 65C02 stz. Macro keeps the
; intent named at every call site without paying the jsr/rts
; cost a real subroutine would.
.macro rp6502_zxstack
        stz     RIA_OP
.endmacro

; ------------------------------------------------------------
; rp6502_open
;   In:  A = O_* flags. Filename bytes already pushed to RIA_XSTACK
;        in reverse order; trailing 0 short-stacks for free.
;   Out: A/X = SPIN return (kernel fd / hi byte).
;        C clear on success, C set on errno (X = $FF).
;   Side effect: consumes the pushed filename either way.
; ------------------------------------------------------------
rp6502_open:
        sta     RIA_A
        lda     #RIA_OP_OPEN
        sta     RIA_OP
        jsr     RIA_SPIN
        cpx     #$FF
        bne     :+
        sec
        rts
:       clc
        rts

; ------------------------------------------------------------
; rp6502_close
;   In:  A = kernel fd.
;   Out: SPIN return; A = bytes-related result, X = errno indicator.
;   tty:/con: are no-ops in the OS so closing them is harmless.
; ------------------------------------------------------------
rp6502_close:
        sta     RIA_A
        lda     #RIA_OP_CLOSE
        sta     RIA_OP
        jmp     RIA_SPIN              ; tail-call

; ------------------------------------------------------------
; rp6502_attr_get
;   In:  A = RIA_ATTR_* id.
;   Out: A/X = low/high bytes of the attr value (RIA_SPIN
;        convention). RIA_SREG holds bytes 2..3 for 32-bit
;        attrs (LRAND).
; ------------------------------------------------------------
rp6502_attr_get:
        sta     RIA_A
        lda     #RIA_OP_ATTR_GET
        sta     RIA_OP
        jmp     RIA_SPIN

; ------------------------------------------------------------
; rp6502_push_string
;   Evaluate the next BASIC expression as a string and push its
;   bytes onto RIA_XSTACK in reverse order. Trailing 0 comes
;   from short-stacking past the bottom. Errors (?FILE DATA)
;   on empty string or non-string type via lsav_err_baddata.
;   Trashes A/X/Y.
; ------------------------------------------------------------
rp6502_push_string:
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
; rp6502_init_io
;   Open "tty:" O_WRONLY into tty_fd, "con:" O_RDONLY into con_fd.
;   Also wipes LFTAB and resets in_fd/out_fd/lsav_fd so a warm
;   start doesn't carry stale fds from the prior run — the OS
;   side has invalidated all of them by the time we reach here.
; ------------------------------------------------------------
rp6502_init_io:
        ; Wipe LFTAB to all $FF (no lfn open).
        ldx #(MAX_OPEN_FILES - 1)
        lda #$FF
@wipe_lftab:
        sta LFTAB,x
        dex
        bpl @wipe_lftab
        stz in_fd
        stz out_fd
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
        jsr rp6502_open
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
        jsr rp6502_open
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
        ; it to rp6502_filin for INPUT#.
        lda #<CHRIN
        sta getln_vec
        lda #>CHRIN
        sta getln_vec+1
        rts

; ------------------------------------------------------------
; CHROUT
;   Write A to the current out_fd (tty: by default, file fd
;   during SAVE) — or, if tab completion has flipped chrout_ptr
;   on, append A to the INPUTBUFFER staging area instead.
;   Preserves A, X, Y. Loops on partial writes (op may return
;   bytes_written < 1 while the OS-side tx queue drains).
; ------------------------------------------------------------
CHROUT:
        phx
        phy
        tay                       ; Y holds the byte across RIA_SPIN
                                  ; (which clobbers A and X but not Y)

        ; Buffer-redirect path: tab completion sets chrout_ptr to
        ; INPUTBUFFER and uses the high byte as a "buffer mode" flag
        ; (INPUTBUFFER lives at $FE00 so hi is always non-zero when
        ; active). Sink the byte into the buffer instead of out_fd.
        lda chrout_ptr+1
        beq @write_fd
        tya
        sta (chrout_ptr)          ; 65C02 zp-indirect
        inc chrout_ptr
        bne @buf_done
        inc chrout_ptr+1
@buf_done:                        ; A still = byte (sta/inc/bne don't touch A)
        ply
        plx
        rts

@write_fd:
        sty RIA_XSTACK
        lda out_fd
        sta RIA_A
        lda #RIA_OP_WRITE_XSTACK
        sta RIA_OP
        jsr RIA_SPIN
        cpx #$FF                  ; X=$FF on errno (write failed)
        beq @write_err
        lda RIA_A                 ; bytes_written, low byte
        cmp #1
        bcc @write_fd             ; partial write — re-push, retry
        tya                       ; A = original byte
        ply                       ; PLY/PLX preserve A
        plx
        rts

@write_err:
        ; tty: write errors are unrecoverable — ERROR's own message
        ; would just re-enter CHROUT — so eat them. File-fd errors
        ; (SAVE in progress, e.g. disk full) abort the SAVE: ZXSTACK
        ; flushes the partial WRITE_XSTACK state, lsav_abort restores
        ; out_fd to tty before close, then BADDATA reports it.
        lda out_fd
        cmp tty_fd
        beq @write_drop
        rp6502_zxstack
        ply
        plx
        jsr lsav_abort
        jmp lsav_err_baddata
@write_drop:
        tya
        ply
        plx
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
; rp6502_tab_completion
;   Called from CHRIN's wait loop when the user presses TAB.
;   Peeks the current readline buffer; if it parses as a single
;   decimal line number that exists in the program, replaces the
;   editor's contents with `<lineno> <detokenized text>` so the
;   user can edit the line in place.
; ------------------------------------------------------------
rp6502_tab_completion:
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
        ; Drain remaining xstack and bail.
        rp6502_zxstack
        rts

@parsed:
        tya                       ; empty buffer (Y=0) → skip
        beq @done
        jsr FNDLIN                ; C=1 if line found, LOWTR=line ptr
        bcc @done

        ; --- Phase C: list the line into INPUTBUFFER via redirect. ---
        ; Setting chrout_ptr+1 (now $FE) flips rp6502_chrout to
        ; buffer-fill mode. Enter LIST's per-line emitter at L25A6X
        ; with LOWTRX (= LOWTR) pre-loaded by FNDLIN; LINNUM is
        ; both range bounds, so the walker prints the matched line,
        ; CRDOs, advances to the next line, then exits via the
        ; range check (next line number is strictly higher).
        lda #<INPUTBUFFER
        sta chrout_ptr
        lda #>INPUTBUFFER
        sta chrout_ptr+1
        jsr L25A6X
        ; Restore normal CHROUT-to-fd and capture the buffer length,
        ; trimming the trailing CR LF that the end-of-line CRDO wrote.
        sec
        lda chrout_ptr
        sbc #<INPUTBUFFER
        sbc #2                    ; -2 for CR LF (carry already set)
        tay                       ; Y = listing length, expected ≥ 1
        stz chrout_ptr+1          ; back to file-write mode
        beq @done                 ; defensive: nothing to push

        ; --- Phase D: push poke to xstack. ---
        ; LIFO: listing in reverse, then the ANSI clear-line prefix
        ; in reverse. The OS pops ESC[H (home), then ESC[256P (DCH
        ; ×256 wipes the line), then the listing bytes; the
        ; trailing 0 terminator comes from short-stacking past the
        ; bottom.
@push_list:
        dey
        lda INPUTBUFFER,y
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
        lda #RIA_ATTR_SIGINT
        jsr rp6502_attr_get
        cmp #$01
        beq @sigint

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
        bne @drain_lastkey
        lda RIA_XSTACK            ; pop the one byte
        cmp #$09                  ; TAB?
        bne @wait
        jsr rp6502_tab_completion
        bra @wait

@drain_lastkey:
        beq @wait                 ; 0 bytes — nothing on xstack
        rp6502_zxstack
        bra @wait

@sigint:
        ; Poke CR so the OS line editor releases whatever the user
        ; had typed (if anything) plus the CR onto con:.
        lda #$0D
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
        rp6502_zxstack

        ; Return A=$03 as the cancel sentinel. Our INLIN matches it
        ; via `cmp #$03; beq @cancel`, resets its accumulator, and
        ; exits with A=$03. INPUT (after jsr NXIN) checks A and
        ; bails through `sec; jmp CONTROL_C_TYPED` to "?BREAK IN
        ; <line>" + RESTART. Distinct from blank Enter (A=$0D, empty
        ; INPUTBUFFER → continue with "" / 0) — upstream conflates
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
;   ria_attr_get(RIA_ATTR_SIGINT) returns the latched Ctrl-C flag
;   and clears it atomically (com_get_sigint in the RIA OS), so
;   the SIGINT poll itself doesn't compete with GET for tty: bytes.
;   A=0 → no break (rts). A=1 → break:
;     1. Drain tty: of any $03 bytes the user's Ctrl-C also queued
;        (without this, a CONT'd GET would assign chr$(3) to its
;        variable).
;     2. Call lsav_abort to tear down SAVE state if LIST was mid-
;        iteration; otherwise the BREAK message would land in the
;        save file (out_fd) instead of the terminal.
;     3. Set up STOP entry: A=0, C=1, Z=1 so `bcs END2` is taken
;        and END2's `bne RET1` falls through into the BREAK path.
;        END4's `pla; pla` pops our caller's JSR ISCNTC frame;
;        RESTART → STKINI resets SP.
;
;   While tab completion is filling INPUTBUFFER (chrout_ptr+1
;   non-zero), break checks are suspended: LIST's L25A6X calls
;   ISCNTC mid-listing, and a STOP from there would unwind with
;   CHROUT still routed to the buffer.
; ------------------------------------------------------------
ISCNTC:
        lda chrout_ptr+1          ; tab completion in progress: skip
        bne @done                 ; (see header comment)
        lda #RIA_ATTR_SIGINT
        jsr rp6502_attr_get
        cmp #$01
        bne @done
        lda #$FF                  ; drain tty: of the user's Ctrl-C
        sta RIA_XSTACK            ; count lo = 255; hi short-stacks
        lda tty_fd
        sta RIA_A
        lda #RIA_OP_READ_XSTACK
        sta RIA_OP
        jsr RIA_SPIN
        rp6502_zxstack
        jsr lsav_abort            ; restore I/O if SAVE was mid-LIST
        sec                       ; C=1 for STOP entry
        jmp STOP
@done:
        rts

; ------------------------------------------------------------
; rp6502_lrand — pull 31 bits from the OS hardware RNG.
;   ria_attr_get(RIA_ATTR_LRAND) returns 32-bit axsreg with the high
;   bit cleared (com.c masks 0x7FFFFFFF). On return:
;     A         = byte 0 (LSB)        ← also at RIA_A
;     X         = byte 1              ← also at RIA_X
;     RIA_SREG  = byte 2
;     RIA_SREG+1= byte 3 (MSB, high bit always 0)
;   Caller reads from the RIA registers — the RTS-side LDA/LDX in
;   the fastcall return only carry the low 16 bits.
; ------------------------------------------------------------
rp6502_lrand:
        lda #RIA_ATTR_LRAND
        jmp rp6502_attr_get       ; tail-call

; ------------------------------------------------------------
; rp6502_linprt — like upstream LINPRT but skips the leading
; sign-position space FOUT normally emits. Used by LIST/SAVE
; (listings start at column 0) and the cold-boot banner. Same
; logic as LINPRT in float.s, but enters FOUT at FOUT1 with Y=0
; (the STR$-style entry that drops the sign char).
; ------------------------------------------------------------
rp6502_linprt:
        sta     FAC+1
        stx     FAC+2
        ldx     #$90
        sec
        jsr     FLOAT2
        ldy     #$00
        jsr     FOUT1
        jmp     STROUT
