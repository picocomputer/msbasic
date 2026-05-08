; --- 6502 STACK ---
STACK           := $0100
STACK_TOP       := $FF
SPACE_FOR_GOSUB := $3E

; --- linker config ---
.import __LFTAB_START__, __LFTAB_SIZE__
.assert __LFTAB_SIZE__ <= 256, error, "__LFTAB_START__ size must fit in X (<=256)"
.import __FOUTBUF_START__, __FOUTBUF_SIZE__
.assert __FOUTBUF_SIZE__ = $11, error, "__FOUTBUF_START__ size must be 17 bytes"
.import __INBUF1_START__, __INBUF1_SIZE__
.assert __INBUF1_SIZE__ = 1, error, "__ INBUF_1__ must be 1 byte"
.import __INBUF_START__, __INBUF_SIZE__
.assert __INBUF_SIZE__ = $100, error, "__INBUF_START__ size must be a full page"
.assert (__INBUF_START__ & $FF) = 0, error, "__INBUF_START__ must be page-aligned"
.assert __INBUF1_START__ + 1 = __INBUF_START__, error, "__ INBUF_1__ must be immediately before __INBUF_START__"
.import __BASRAM_START__, __BASRAM_SIZE__
TXTTAB := __BASRAM_START__ + 1
MEMSIZ := __BASRAM_START__ + __BASRAM_SIZE__

; --- size math derived from BYTES_FP ---
BYTES_FP           := 5
BYTES_PER_ELEMENT  := BYTES_FP
BYTES_PER_VARIABLE := BYTES_FP + 2
MANTISSA_BYTES     := BYTES_FP - 1
BYTES_PER_FRAME    := 2 * BYTES_FP + 8
FOR_STACK1         := 2 * BYTES_FP + 5
FOR_STACK2         := BYTES_FP + 4
MAX_EXPON          := 10

; CR/LF are universal ASCII;
CR     := 13
LF     := 10
