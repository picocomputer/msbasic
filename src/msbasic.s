.debuginfo +
.macpack longbranch

; --- exported from rp6502.cfg ---
.import __INPUT_START__
.import __BASRAM_START__, __BASRAM_SIZE__

; --- cc65 library includes ---
.include "rp6502.inc"
.include "fcntl.inc"

; --- our application code ---
.include "defines.s"
.include "macros.s"
.include "chrget.s"
.include "zeropage.s"
.include "header.s"
.include "extra.s"
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
.include "caps.s"
