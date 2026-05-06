.segment "ZPCHRGET"
CHRGET:        .res chrget_size  ; loaded as an asset

.zeropage
RNDSEED:       .res 5
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
TXTTAB:        .res 2
VARTAB:        .res 2
ARYTAB:        .res 2
STREND:        .res 2
FRETOP:        .res 2
FRESPC:        .res 2
MEMSIZ:        .res 2
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
LFTAB:         .res MAX_OPEN_FILES
                        ; logical-file-number → kernel fd. Valid lfn
                        ; range is 0..MAX_OPEN_FILES-1, indexed
                        ; directly. $FF means "slot unused". Wiped to
                        ; all $FF on every (re)init because warm-start
                        ; invalidates all OS-side fds.
tty_fd:        .res 1   ; fd for RP6502 tty: device
con_fd:        .res 1   ; fd for RP6502 con: device
out_fd:        .res 1   ; current MONCOUT target; tty_fd by default, redirected by SAVE/CHKOUT
in_fd:         .res 1   ; current input source for GET/INLIN's per-byte reads;
                        ; tty_fd by default, redirected by CHKIN
lsav_fd:       .res 1   ; SAVE/LOAD active fd. Set by both SAVE
                        ; and LOAD; doubles as the LOAD-active
                        ; flag (program.s:82 errors on a stray non-
                        ; numbered line while LOAD feeds INLIN).
getln_vec:     .res 2   ; GETLN indirection; rp6502_inlin by default, swapped by LOAD
chrout_ptr:    .res 2   ; rp6502_chrout target buffer; non-zero hi → buffer mode
auto_run:      .res 1   ; cold-boot auto-load + RUN state machine
                        ;   0   = idle (normal LOAD)
                        ;   1   = auto-load mode (file read in progress)
                        ;   2..4 = post-EOF emitting "UN\r" through INLIN
                        ;          (the 'R' is emitted directly from
                        ;          the EOF→start_auto_run handoff)
