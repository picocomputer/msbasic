.zeropage

RNDSEED:       .res BYTES_FP
LINNUM:        .res 2
CHARAC:        .res 1
ENDCHR:        .res 1
EOLPNTR:       .res 1
DIMFLG:        .res 1
VALTYP:        .res 2
DATAFLG:       .res 1
SUBFLG:        .res 1
INPUTFLG:      .res 1
CPRMASK:       .res 1
Z14:           .res 1
CURDVC:        .res 1
POSX:          .res 1
Z96:           .res 1
TEMPPT:        .res 1
LASTPT:        .res 2
TEMPST:        .res 9
INDEX:         .res 2
DEST:          .res 2
RESULT:        .res BYTES_FP
RESULT_LAST  = RESULT + BYTES_FP-1
VARTAB:        .res 2
ARYTAB:        .res 2
STREND:        .res 2
FRETOP:        .res 2
FRESPC:        .res 2
CURLIN:        .res 2
OLDLIN:        .res 2
OLDTEXT:       .res 2
Z8C:           .res 2
DATPTR:        .res 2
INPTR:         .res 2
VARNAM:        .res 2
VARPNT:        .res 2
FORPNT:        .res 2
LASTOP:        .res 2
TXPSV:         .res 2
CPRTYP:        .res 1
FNCNAM:
TEMP3:         .res 2 ; spans +DSCPTR
TOKBASE      = TEMP3 ; tokenize/LIST keyword-table base (program.s).
                     ; TEMP3's only other writers are FPWRT and TAN —
                     ; expression evaluation, never live during
                     ; PARSE_INPUT_LINE or LIST. LIST's line numbers go
                     ; through FOUT, which touches no TEMPs.
DSCPTR:        .res 3
DSCLEN:        .res 2
JMPADRS      = DSCLEN + 1
Z52:           .res 1
ARGEXTENSION:  .res 1
TEMP1:         .res 1 ; spans +HIGHDS+HIGHTR
inbuf_off    = TEMP1 ; chrout_buf's INBUF write offset (extra.s)
TEMP1X       = TEMP1+(5-BYTES_FP) ; FP rounding scratch (float.s, trig.s)
; TEMP1's users are mutually exclusive. FP's 5-byte rounding scratch
; (TEMP1X..TEMP1X+BYTES_FP-1) is written only by POLYNOMIAL_ODD and
; TAN — expression evaluation; FOUT touches no TEMPs, so the LINPRTNS
; call inside tab completion's LIST capture can't clobber inbuf_off.
; LOAD's per-line counter (loadsave.s, init.s) is live only while
; getln_vec is hooked to lsav_load_chrin, where tab completion can't
; fire; line insertion between LOADed lines is safe because BLT uses
; HIGHDS/HIGHTR (TEMP1+1..+4, not TEMP1) and REASON saves/restores
; TEMP1..FAC-1 around GARBAG.
HIGHDS:        .res 2
HIGHTR:        .res 2
TEMP2:         .res 1 ; spans +INDX+LOWTR
TOKBASE_TOKEN = TEMP2 ; tokenizer bin marker, $80/$C0 (program.s).
                      ; TEMP2's only other writer is the POLYNOMIAL
                      ; series loop — never live while tokenizing
                      ; (PARSE_INPUT_LINE makes no calls at all).
INDX:
TMPEXP:        .res 1
EXPON:         .res 1
LOWTR:
LOWTRX:        .res 1
EXPSGN:        .res 1
FAC:           .res BYTES_FP
FAC_LAST     = FAC + BYTES_FP-1
FACSIGN:       .res 1
SERLEN:        .res 1
SHIFTSIGNEXT:  .res 1
ARG:           .res BYTES_FP
ARG_LAST     = ARG + BYTES_FP-1
ARGSIGN:       .res 1
STRNG1:        .res 2
SGNCPR       = STRNG1
FACEXTENSION = STRNG1+1
STRNG2:        .res 2

tty_fd:        .res 1   ; fd for RP6502 tty: device
con_fd:        .res 1   ; fd for RP6502 con: device
out_fd:        .res 1   ; current output fd; tty_fd by default
in_fd:         .res 1   ; current input fd; tty_fd by default
lsav_fd:       .res 1   ; SAVE/LOAD active fd
getln_vec:     .res 2   ; GETLN indirection; CHRIN by default, swapped by LOAD
chrout_vec:    .res 2   ; CHROUT dispatch target: chrout_fd (default), chrout_buf
                        ; (tab completion), or chrout_pager (LIST --More-- hook).
more_height:   .res 1   ; LIST pager: terminal rows
more_width:    .res 1   ; LIST pager: terminal cols
more_rows_left:.res 1   ; LIST pager: rows of headroom before next --More--
more_col:      .res 1   ; LIST pager: tracked column 0..more_width
auto_run:      .res 1   ; cold-boot auto-load + RUN state machine
                        ;   0   = idle (normal LOAD)
                        ;   1   = auto-load mode (file read in progress)
                        ;   2..4 = post-EOF emitting "UN\r" through INLIN
                        ;          (the 'R' is emitted directly from
                        ;          the EOF→start_auto_run handoff)
