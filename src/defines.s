; Picocomputer 6502 BASIC variant configuration.
; Replaces upstream src/msbasic/defines.s + defines_<variant>.s.
;
; All bug fixes, none of the platform-specific baggage, plus CONFIG_FILE
; so the file-support infrastructure is wired in for Phase 3. No
; CBM/CBM_ALL/DATAFLG/SCRTCH_ORDER markers — those only gate code paths
; in our owned files, which we strip.

; --- exported from rp6502.cfg ---
.import __INPUT_START__
.import __BASRAM_START__, __BASRAM_SIZE__
.import __CHRGET_SIZE__

; --- config flags for mist64 sources ---
CONFIG_FILE                   := 1     ; TODO file I/O
CONFIG_NO_CR                  := 1     ; no auto-CR, terminal line wraps
CONFIG_NO_LINE_EDITING        := 1     ; host owns line editing
CONFIG_NO_INPUTBUFFER_ZP      := 1     ; INPUTBUFFER lives in main RAM
CONFIG_NO_READ_Y_IS_ZERO_HACK := 1     ; bug fix
CONFIG_PEEK_SAVE_LINNUM       := 1     ; bug fix
CONFIG_SAFE_NAMENOTFOUND      := 1     ; bug fix: NAMENOTFOUND high-byte retaddr check

; --- enable all fixes up to latest version 2.0C ---
CONFIG_2C  := 1
CONFIG_2B  := 1
CONFIG_2A  := 1
CONFIG_2   := 1
CONFIG_11A := 1
CONFIG_11  := 1
CONFIG_10A := 1

; --- 6502 ---
STACK          := $0100
STACK2         := STACK

; --- RP6502 ---
INPUTBUFFER    := __INPUT_START__
INPUTBUFFERX   := INPUTBUFFER & $FF00
MAX_OPEN_FILES := 8                     ; LFTAB size; valid OPEN# lfn range
                                        ; is 0..MAX_OPEN_FILES-1. Costs that
                                        ; many bytes of zp.

; --- BASIC sizing constants ---
SPACE_FOR_GOSUB := $3E
STACK_TOP       := $FF
chrget_size     := 24                  ; bytes of GENERIC_CHRGET in chrget.s;
                                       ; zeropage.s .res's this for the
                                       ; runtime-copied routine, and chrget.s
                                       ; asserts the assembled length matches

; --- I/O hooks ---
; MONRDKEY/GETIN: non-blocking ("get key if one's ready"), A=0,Z=1 on empty.
; CHRIN: blocking line-input read used by INLIN's GETLN — must wait for a
;        byte and translate the host's LF to CR.
MONCOUT  := rp6502_chrout
MONRDKEY := rp6502_getin
ISCNTC   := rp6502_iscntc
CHRIN    := rp6502_inlin
CHROUT   := rp6502_chrout
GETIN    := rp6502_getin

; --- Stubbed keyword handlers (parser tokenizes them, dispatch RTSes) ---
SYS    := rp6502_rts_stub

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
