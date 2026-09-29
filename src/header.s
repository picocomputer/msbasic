.segment "HEADER"

WARM_START:
        ldx #STACK_TOP
        txs
        cld
        jsr ria_init_io
        stz input_fin_sp          ; a reset mid-FIN must not leave INPUT armed
        jmp RESTART
