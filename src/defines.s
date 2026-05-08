; --- linker config ---
.import __TXTTAB_START__, __TXTTAB_SIZE__
.import __LFTAB_START__, __LFTAB_SIZE__
.assert __LFTAB_SIZE__ <= 256, error, "LFTAB size must fit in X (<=256)"
.import __FOUTBUF_START__, __FOUTBUF_SIZE__
.assert __FOUTBUF_SIZE__ = $11, error, "FOUTBUF size must be 17 bytes"
.import __INBUF1_START__, __INBUF1_SIZE__
.assert __INBUF1_SIZE__ = 1, error, "INBUF1 must be 1 byte"
.import __INBUF_START__, __INBUF_SIZE__
.assert __INBUF_SIZE__ = $100, error, "INBUF size must be a full page"
.assert (__INBUF_START__ & $FF) = 0, error, "INBUF must be page-aligned"
.assert __INBUF1_START__ + 1 = __INBUF_START__, error, "INBUF1 must be immediately before INBUF"

; --- 6502 STACK ---
STACK           := $0100
STACK_TOP       := $FF
SPACE_FOR_GOSUB := $3E

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
