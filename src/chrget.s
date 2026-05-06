; Shadow of src/mist64/chrget.s. Strips the dead KBD ifdef and
; brings the TXTPTR / CHRGOT / CHRGOT2 zp aliases into this file —
; their values are derived from offsets within the routine
; defined here, so they belong adjacent to the routine.
;
; CHRGET (the zp base) is defined in zeropage.s with .res
; chrget_size; the routine bytes are built into a separate
; chrget.bin asset (see src/chrget_bare.s + src/chrget_bare.cfg)
; and loaded by rp6502_asset() to zp at boot, before COLD_START.
;
; This file is also .include'd by msbasic.s for the BASIC build.
; There the CHRGET segment is routed to DUMMY (file="") in
; rp6502.cfg so the labels resolve for TXTPTR/CHRGOT/CHRGOT2
; offset math but the routine bytes don't go into BASROM.
;
; The routine is self-modifying: the address operand of the
; "lda $EA60" instruction at GENERIC_TXTPTR is what code writes
; when it stores into TXTPTR / TXTPTR+1. The $EA60 here is just
; a placeholder; it never actually executes — the operand bytes
; are overwritten by stores to TXTPTR before the lda runs.

.segment "CHRGET"

; ZP entry points. (GENERIC_X - GENERIC_CHRGET) is a same-segment
; label diff = assembly-time constant; CHRGET is the zp label from
; zeropage.s. The < operator forces a byte expression so each
; equate resolves to a zp address and `inc TXTPTR` / `lda CHRGOT`
; pick up zp encoding.
TXTPTR  = <(GENERIC_TXTPTR  - GENERIC_CHRGET + CHRGET)
CHRGOT  = <(GENERIC_CHRGOT  - GENERIC_CHRGET + CHRGET)
CHRGOT2 = <(GENERIC_CHRGOT2 - GENERIC_CHRGET + CHRGET)

GENERIC_CHRGET:
        inc     TXTPTR
        bne     GENERIC_CHRGOT
        inc     TXTPTR+1
GENERIC_CHRGOT:
GENERIC_TXTPTR = GENERIC_CHRGOT + 1
        lda     $EA60
        cmp     #$3A
        bcs     L4058
GENERIC_CHRGOT2:
        cmp     #$20
        beq     GENERIC_CHRGET
        sec
        sbc     #$30
        sec
        sbc     #$D0
L4058:
        rts
chrget_routine_end:

.assert chrget_routine_end - GENERIC_CHRGET = chrget_size, error, "chrget_size in defines.s out of sync with the chrget routine length"
