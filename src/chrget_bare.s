; Standalone build of the CHRGET routine for asset packaging.
; chrget.s expects CHRGET (zp base) and chrget_size in scope; in
; the BASIC build those come from zeropage.s and defines.s. Here
; we provide them directly. CHRGET must match the ZPCHRGET-segment
; placement in src/rp6502.cfg ($0000) and the address passed to
; rp6502_asset() in the top-level CMakeLists.txt.

CHRGET      := $0000
chrget_size := 24

.include "chrget.s"
