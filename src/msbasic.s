; Picocomputer 6502 BASIC top-level. Mirrors upstream src/msbasic/msbasic.s.
;
; Each .include "<file>.s" resolves to src/<file>.s first (the current-
; file-directory search precedes --asm-include-dir), so any file we
; shadow under src/ wins; the rest fall through to src/msbasic/<file>.s.

.debuginfo +
.macpack longbranch

.include "rp6502.inc"
.include "fcntl.inc"

.include "defines.s"
.include "macros.s"
.include "zeropage.s"
; chrget.s defines TXTPTR / CHRGOT / CHRGOT2 zp aliases. Must come
; before any file that references them (program.s, eval.s, etc.)
; otherwise ca65 sees them as undefined and falls back to absolute
; addressing.
.include "chrget.s"

.include "header.s"
.include "token.s"
.include "error.s"
.include "message.s"
.include "memory.s"
.include "program.s"
.include "flow1.s"
.include "loadsave.s"
.include "file.s"
.include "flow2.s"
.include "misc1.s"
.include "print.s"
.include "input.s"
.include "eval.s"
.include "var.s"
.include "array.s"
.include "misc2.s"
.include "string.s"
.include "misc3.s"
.include "poke.s"
.include "float.s"
.include "rnd.s"
.include "trig.s"
.include "init.s"
.include "extra.s"
.include "caps.s"
