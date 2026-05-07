.segment "CODE"

INLIN:
        ldx #$00
@loop:
        jsr GETLN
        cmp #$03                  ; Ctrl-C sentinel from CHRIN's
        beq @cancel               ; @sigint — see input.s for the
                                  ; cmp/bne/sec/jmp CONTROL_C_TYPED
                                  ; that turns A=$03 into "?BREAK IN"
        cmp #$0D                  ; CR terminates the line
        beq @done
        sta INPUTBUFFER,x
        inx
        bne @loop                 ; 256-char overflow falls into @done
@done:                            ; A = $0D (or last byte on overflow)
        lda #$00
        bra @term                 ; signal "normal exit" via A=0
@cancel:
        ldx #$00                  ; throw away anything accumulated
        lda #$03                  ; signal "cancel" via A=3
@term:
        stz INPUTBUFFER,x         ; null-terminate (X=0 if @cancel,
                                  ; accumulated count if @done)
        ldx #<(INPUTBUFFER-1)
        ldy #>(INPUTBUFFER-1)
        rts                       ; X/Y = INPUTBUFFER-1, A = signal

; GETLN is indirected through getln_vec so LOAD can hook it: when LOAD is
; active, the vector points at lsav_load_chrin which reads from the file
; instead of con:. The vector is initialized to CHRIN in init_io.
GETLN:
        jmp (getln_vec)
