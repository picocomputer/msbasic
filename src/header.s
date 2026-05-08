; Picocomputer 6502 BASIC warm-entry shim. The hardware reset vector
; ($FFFC, RAM on this system) initially points at INIT ($1000); cold
; init runs once, rewrites $FFFC to here, then jmps RESTART. From
; that point on every hardware reset enters here as a warm restart:
; reset SP, clear decimal, reopen tty:/con: (the OS invalidates fds
; across resets), and resume at RESTART with program text intact.

.segment "HEADER"

rp6502_start:
        ldx #STACK_TOP
        txs
        cld
        jsr rp6502_init_io
        jmp RESTART
