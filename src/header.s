.segment "HEADER"

WARM_START:
        ldx #STACK_TOP
        txs
        cld
        jsr ria_init_io
        jmp RESTART
