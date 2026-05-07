; Picocomputer "CAPS" statement — sets the RIA OS readline editor's
; caps mode. Modes: 0 = off (echo as typed), 1 = all caps (default),
; 2 = invert (lower↔upper). The boot-time -c<n> argv parser writes
; the same attribute, so init.s and CAPS share rp6502_caps_set.

.segment "CODE"

; ----------------------------------------------------------
; rp6502_caps_set — set RIA_ATTR_RLN_CAPS = X (mode 0/1/2).
; Upper 24 bits of the long arg short-stack to 0.
; ----------------------------------------------------------
rp6502_caps_set:
        stx     RIA_XSTACK
        lda     #RIA_ATTR_RLN_CAPS
        sta     RIA_A
        lda     #RIA_OP_ATTR_SET
        sta     RIA_OP
        jmp     RIA_SPIN

; ----------------------------------------------------------
; "CAPS <expr>" statement. Valid modes 0..2 dispatch to
; rp6502_caps_set; everything else raises ?ILLEGAL QUANTITY.
; ----------------------------------------------------------
CAPS:
        jsr     GETBYT             ; X = parsed byte (0..255)
        cpx     #$03
        bcc     rp6502_caps_set
        ldx     #ERR_ILLQTY
        jmp     ERROR
