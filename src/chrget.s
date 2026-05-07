; Shadow of src/mist64/chrget.s. Strips the dead KBD ifdef and
; brings the CHRGET / TXTPTR / CHRGOT / CHRGOT2 zp aliases into
; this file — their values are derived from offsets within the
; routine defined here, so they belong adjacent to the routine.
;
; This file does double duty:
;   * .include'd by msbasic.s for the BASIC build. msbasic.cfg
;     places the CHRGET segment first in ZP (file=""), so the
;     24-byte routine reserves zp $00-$17 (and ZEROPAGE follows
;     at $18) while the bytes themselves are discarded from the
;     ROM output.
;   * Standalone link target via chrget.cfg, which emits the
;     same 24 bytes to a raw binary that rp6502_asset() loads
;     to zp at boot. The asset overwrites the placeholder bytes
;     before the routine ever runs.
;
; The routine is self-modifying: the address operand of the
; "lda $EA60" instruction at GENERIC_TXTPTR is what code writes
; when it stores into TXTPTR / TXTPTR+1. The $EA60 here is just
; a placeholder; it never actually executes — the operand bytes
; are overwritten by stores to TXTPTR before the lda runs.

; Layout contract owned by this file. CHRGET must match the
; CHRGET-segment placement in src/msbasic.cfg and src/chrget.cfg
; (and the address passed to rp6502_asset() in CMakeLists.txt).
CHRGET      := $0000
chrget_size := 24

.segment "CHRGET"
; CHRGET:

; ZP entry points. (GENERIC_X - GENERIC_CHRGET) is a same-segment
; label diff = assembly-time constant; CHRGET is the literal above.
; The < operator forces a byte expression so each equate resolves
; to a zp address and `inc TXTPTR` / `lda CHRGOT` pick up zp
; encoding.
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

.assert chrget_routine_end - GENERIC_CHRGET = chrget_size, error, "chrget_size out of sync with the chrget routine length"
