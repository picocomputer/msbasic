.segment "CODE"

QT_BANNER:
        .byte   "MICROSOFT BASIC", CR, LF, 0

QT_BYTES_FREE:
        .byte   " BYTES FREE", CR, LF, 0

QT_ERROR:
        .byte   " ERROR", 0

QT_IN:
        .byte   " IN", 0

QT_OK:
	.byte   CR, LF, "OK", CR, LF, 0

QT_BREAK:
	.byte   CR, LF, "BREAK", 0
