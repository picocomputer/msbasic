; Picocomputer INPUT/GET/READ. Replaces upstream src/msbasic/input.s.
;
; Behavior change: a blank Enter at the INPUT prompt no longer silently
; breaks the program back to OK. For a numeric variable it prints
; "?REDO FROM START" and re-runs the INPUT statement (same as a
; malformed numeric response); for a string variable it assigns ""
; and continues.
;
; Upstream collapsed Ctrl-C and blank Enter into a single silent
; `clc; jmp CONTROL_C_TYPED` because most variants can't distinguish
; the two at the I/O layer. The RIA's SIGINT sidechannel can: INLIN
; returns A=$03 from CHRIN's @sigint for Ctrl-C, which we
; route through CONTROL_C_TYPED with C=1 so PRINT_ERROR_LINNUM
; prints "?BREAK IN <line>" before RESTART.
;
; INPUTH (INPUT# keyword handler) lives in file.s; it sets up the
; redirect via CHKIN, then jsr's L2A9E to enter the INPUT body
; past the prompt-string parse. L2A9E and LCAD6/LCAD8 are the
; cross-file entry/cleanup points.

.segment "CODE"

; ----------------------------------------------------------------------------
; INPUT CONVERSION ERROR: illegal char in numeric field. Distinguishes
; INPUT (?REDO FROM START), READ (line number from DATA), and GET
; (line number = $FFxx so SYNERR doesn't print a real line).
; ----------------------------------------------------------------------------
INPUTERR:
        lda     INPUTFLG
        beq     RESPERR             ; INPUT path
        bmi     L2A63               ; READ path
        ldy     #$FF                ; GET path
        bne     L2A67
L2A63:
        lda     Z8C
        ldy     Z8C+1
L2A67:
        sta     CURLIN
        sty     CURLIN+1
SYNERR4:
        jmp     SYNERR

RESPERR:
        lda     CURDVC
        bmi     LCA8F             ; $FF = no redirect → reprompt
        ldx     #ERR_BADDATA
        jmp     ERROR
LCA8F:
        lda     #<ERRREENTRY
        ldy     #>ERRREENTRY
        jsr     STROUT
        lda     OLDTEXT
        ldy     OLDTEXT+1
        sta     TXTPTR
        sty     TXTPTR+1
        rts

; ----------------------------------------------------------------------------
; CHKIN/CHKOUT cleanup helper: close any redirected I/O and reset CURDVC
; to $FF (the "no redirect" sentinel; lfn 0 is a valid file slot, so 0
; can't double as "no redirect").
; LCAD6 entry: also reload A from CURDVC (for callers that branch on it).
; LCAD8 entry: skip the load (CURDVC already in A or X).
; Referenced from misc1.s (jmp LCAD6) and from GET below (bpl LCAD8).
; ----------------------------------------------------------------------------
LCAD6:
        lda     CURDVC
LCAD8:
        jsr     CLRCH
        lda     #$FF
        sta     CURDVC
        rts

; ----------------------------------------------------------------------------
; "GET" STATEMENT
; ----------------------------------------------------------------------------
GET:
        jsr     ERRDIR
        cmp     #'#'                ; GET# — redirect input fd
        bne     LCAB6
        jsr     CHRGET
        jsr     GETBYT
        lda     #','
        jsr     SYNCHR
        jsr     CHKIN
        stx     CURDVC
LCAB6:
        ldx     #<(__INBUF_START__+1)
        ldy     #>(__INBUF_START__+1)
        stz     __INBUF_START__+1
        lda     #$40
        jsr     PROCESS_INPUT_LIST
        ldx     CURDVC              ; GET# — restore default fd
        bpl     LCAD8               ; $FF (no redirect) → just rts
        rts

; ----------------------------------------------------------------------------
; "INPUT" STATEMENT
; ----------------------------------------------------------------------------
INPUT:
        lsr     Z14
        cmp     #$22
        bne     L2A9E
        jsr     STRTXT
        lda     #$3B
        jsr     SYNCHR
        jsr     STRPRT
L2A9E:
        jsr     ERRDIR
        lda     #$2C
        sta     __INBUF1_START__
LCAF8:
        jsr     NXIN
        ; INLIN signals cancel via A=$03 (CHRIN's @sigint).
        ; Check before any other lda clobbers A. Bail through
        ; upstream's CONTROL_C_TYPED with C=1 so L2701's `bcc L270E`
        ; falls through to PRINT_ERROR_LINNUM — prints "?BREAK IN
        ; <line>" before landing at RESTART. The whole INLIN→NXIN
        ; chain has already RTS'd back here, so END4's pla;pla just
        ; pops the EXECUTE_STATEMENT frame.
        cmp     #$03
        bne     @no_cancel
        sec
        jmp     CONTROL_C_TYPED
@no_cancel:
        lda     CURDVC
        bmi     LCB0C               ; $FF = no redirect
        lda     Z96
        and     #$02
        beq     LCB0C
        jsr     LCAD6
        jmp     DATA
LCB0C:
        lda     __INBUF_START__
        bne     L2ABE
        lda     CURDVC
        bpl     LCAF8               ; redirected: retry input
        ; Empty buffer: don't short-circuit here — VALTYP isn't set
        ; yet. Fall into PROCESS_INPUT_LIST so PTRGET picks the
        ; numeric vs string path; L2B34 handles ?REDO for numeric,
        ; STRLT2 builds "" for string.
        jmp     L2ABE

NXIN:
        lda     CURDVC
        bpl     LCB21               ; redirected: skip the '? ' prompt
        jsr     OUTQUES             ; '?'
        jsr     OUTSP
LCB21:
        jmp     INLIN

; ----------------------------------------------------------------------------
; "READ" STATEMENT
; ----------------------------------------------------------------------------
READ:
        ldx     DATPTR
        ldy     DATPTR+1
        lda     #$98                ; READ
        .byte   $2C                 ; BIT abs — skip next 2 bytes
L2ABE:
        lda     #$00                ; INPUT (also the empty-line entry)

; ----------------------------------------------------------------------------
; PROCESS INPUT LIST
;   (Y,X) = address of input data string
;   (A)   = INPUTFLG: $00 INPUT, $40 GET, $98 READ
; ----------------------------------------------------------------------------
PROCESS_INPUT_LIST:
        sta     INPUTFLG
        stx     INPTR
        sty     INPTR+1
PROCESS_INPUT_ITEM:
        jsr     PTRGET
        sta     FORPNT
        sty     FORPNT+1
        lda     TXTPTR
        ldy     TXTPTR+1
        sta     TXPSV
        sty     TXPSV+1
        ldx     INPTR
        ldy     INPTR+1
        stx     TXTPTR
        sty     TXTPTR+1
        jsr     CHRGOT
        bne     INSTART
        bit     INPUTFLG
        bvc     L2AF0               ; not GET → reprompt path
        jsr     GETIN            ; GET: pull one key
        sta     __INBUF_START__
        ldx     #<(__INBUF_START__-1)
        ldy     #>(__INBUF_START__-1)
        bra     L2AF8
L2AF0:
        jmi     FINDATA             ; READ
        lda     CURDVC
        bpl     LCB64               ; redirected: skip '?' reprompt
        jsr     OUTQUES             ; '?' reprompt for next INPUT var
LCB64:
        jsr     NXIN
L2AF8:
        stx     TXTPTR
        sty     TXTPTR+1

; ----------------------------------------------------------------------------
INSTART:
        jsr     CHRGET
        bit     VALTYP
        bpl     L2B34
        bit     INPUTFLG
        bvc     L2B10
        inx                         ; GET fast path: 1-char string
        stx     TXTPTR
        lda     #$00
        sta     CHARAC
        beq     L2B1C
L2B10:
        sta     CHARAC
        cmp     #$22
        beq     L2B1D
        lda     #$3A                ; ':' as terminator
        sta     CHARAC
        lda     #$2C                ; ',' as terminator
L2B1C:
        clc
L2B1D:
        sta     ENDCHR
        lda     TXTPTR
        ldy     TXTPTR+1
        adc     #$00
        bcc     L2B28
        iny
L2B28:
        jsr     STRLT2
        jsr     POINT
        jsr     PUTSTR
        jmp     INPUT_MORE

; ----------------------------------------------------------------------------
L2B34:
        ; Empty field on the INPUT path → ?REDO FROM START rather
        ; than FIN-of-empty-as-0. READ ($98) and GET ($40) keep the
        ; legacy behavior — DATA items and key reads have their own
        ; conventions. A still holds CHRGET's char (BIT preserves A);
        ; tax and ldx set N/Z but leave A and C alone, so FIN still
        ; sees the CHRGET-set "C=0 iff digit" signal it requires.
        tax
        bne     @do_fin
        ldx     INPUTFLG
        bne     @do_fin
        jmp     RESPERR
@do_fin:
        jsr     FIN
        lda     VALTYP+1
        jsr     LET2

; ----------------------------------------------------------------------------
INPUT_MORE:
        jsr     CHRGOT
        beq     L2B48
        cmp     #$2C
        beq     L2B48
        jmp     INPUTERR
L2B48:
        lda     TXTPTR
        ldy     TXTPTR+1
        sta     INPTR
        sty     INPTR+1
        lda     TXPSV
        ldy     TXPSV+1
        sta     TXTPTR
        sty     TXTPTR+1
        jsr     CHRGOT
        beq     INPDONE
        jsr     CHKCOM
        jmp     PROCESS_INPUT_ITEM

; ----------------------------------------------------------------------------
FINDATA:
        jsr     DATAN
        iny
        tax
        bne     L2B7C
        ldx     #ERR_NODATA
        iny
        lda     (TXTPTR),y
        beq     GERR
        iny
        lda     (TXTPTR),y
        sta     Z8C
        iny
        lda     (TXTPTR),y
        iny
        sta     Z8C+1
L2B7C:
        lda     (TXTPTR),y
        tax
        jsr     ADDON
        cpx     #$83
        bne     FINDATA
        jmp     INSTART

; ---NO MORE INPUT REQUESTED------
INPDONE:
        lda     INPTR
        ldy     INPTR+1
        ldx     INPUTFLG
        bpl     L2B94               ; INPUT or GET
        jmp     SETDA               ; READ
L2B94:
        lda     (INPTR)             ; 65C02 zp-indirect
        beq     L2BA1
        lda     CURDVC
        bpl     L2BA1               ; redirected: suppress "?EXTRA IGNORED"
        lda     #<ERREXTRA
        ldy     #>ERREXTRA
        jmp     STROUT
L2BA1:
        rts

; ----------------------------------------------------------------------------
ERREXTRA:
        .byte   "?EXTRA IGNORED"
        .byte   $0D,$0A,$00
ERRREENTRY:
        .byte   "?REDO FROM START"
        .byte   $0D,$0A,$00
