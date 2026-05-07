; All bug fixes, none of the platform-specific baggage, plus CONFIG_FILE.

; --- config flags for mist64 sources ---
CONFIG_FILE                   := 1     ; OPEN/CLOSE/etc.
CONFIG_NO_INPUTBUFFER_ZP      := 1     ; INPUTBUFFER lives in main RAM
CONFIG_PEEK_SAVE_LINNUM       := 1     ; bug fix
CONFIG_SAFE_NAMENOTFOUND      := 1     ; bug fix

; --- enable fixes up to latest version 2.0C ---
CONFIG_2C  := 1
CONFIG_2B  := 1
CONFIG_2A  := 1
CONFIG_2   := 1
CONFIG_11A := 1
CONFIG_11  := 1
CONFIG_10A := 1

; --- 6502 STACK ---
STACK           := $0100
STACK_TOP       := $FF
SPACE_FOR_GOSUB := $3E

; --- linker config ---
.import __BASRAM_START__, __BASRAM_SIZE__
TXTTAB := __BASRAM_START__ + 1
MEMSIZ := __BASRAM_START__ + __BASRAM_SIZE__
.import __FOUTBUF_START__, __FOUTBUF_SIZE__
FOUTBUF        := __FOUTBUF_START__
.assert __FOUTBUF_SIZE__ = $11, error, "FOUTBUF size must be 17 bytes"
.import __INBUF_START__, __INBUF_SIZE__
INPUTBUFFER    := __INBUF_START__
.assert __INBUF_SIZE__ = $100, error, "INPUTBUFFER size must be a full page"
.assert (INPUTBUFFER & $FF) = 0, error, "INPUTBUFFER must be page-aligned"

; --- Logicial file numbers for OPEN/CLOSE ---
MAX_OPEN_FILES := 8 ; LFTAB size; valid OPEN# lfn range, 1 zp each

; --- size math derived from BYTES_FP (replaces defines.s:52-93) ---
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
