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
TEMP3:         .res 2
DSCPTR:        .res 3
DSCLEN:        .res 2
JMPADRS      = DSCLEN + 1
Z52:           .res 1
ARGEXTENSION:  .res 1
TEMP1:         .res 1
HIGHDS:        .res 2
HIGHTR:        .res 2
TEMP2:         .res 1
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
auto_run:      .res 1   ; cold-boot auto-load + RUN state machine
                        ;   0   = idle (normal LOAD)
                        ;   1   = auto-load mode (file read in progress)
                        ;   2..4 = post-EOF emitting "UN\r" through INLIN
                        ;          (the 'R' is emitted directly from
                        ;          the EOF→start_auto_run handoff)
more_height:   .res 1   ; LIST pager: terminal rows (held while armed).
more_width:    .res 1   ; LIST pager: terminal cols.
more_rows_left:.res 1   ; LIST pager: rows of headroom before next --More--.
more_col:      .res 1   ; LIST pager: tracked column 0..more_width.
