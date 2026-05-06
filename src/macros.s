; htasc - set the hi bit on the last byte of a string for termination
; (by Tom Greene)
.macro htasc str
	.repeat	.strlen(str)-1,I
		.byte	.strat(str,I)
	.endrep
	.byte	.strat(str,.strlen(str)-1) | $80
.endmacro

; Two-bin keyword name tables. KEYWORDS_A holds names for tokens
; $80..$BF (statements). KEYWORDS_B holds $C0..$FF (operators,
; reserved, functions, GO). The walkers in program.s pick a bin by
; bit 6 of the token byte. Each bin has its own DUMMY counter so
; tokens get values from their bin's base ($80 or $C0).
;
; Macro-type implies bin:
;   keyword_rts  → bin A  (statements with RTS-style address)
;   keyword      → bin B  (operators, reserved, GO; no address)
;   keyword_addr → bin B  (functions with addr-style vector)

.macro init_token_tables
        .segment "VECTORS"
TOKEN_ADDRESS_TABLE:
        .segment "KEYWORDS_A"
TOKEN_NAME_TABLE_A:
        .segment "KEYWORDS_B"
TOKEN_NAME_TABLE_B:
        .segment "DUMMY_A"
DUMMY_A_START:
        .segment "DUMMY_B"
DUMMY_B_START:
.endmacro

.macro define_token_a token
        .segment "DUMMY_A"
		.ifnblank token
			token := <(*-DUMMY_A_START)+$80
		.endif
		.res 1
.endmacro

.macro define_token_b token
        .segment "DUMMY_B"
		.ifnblank token
			token := <(*-DUMMY_B_START)+$C0
		.endif
		.res 1
.endmacro

; lay down a keyword (bin B), optionally define a token symbol
.macro keyword key, token
		.segment "KEYWORDS_B"
		htasc	key
		define_token_b token
.endmacro

; lay down a keyword and an address (RTS style, bin A statement),
; optionally define a token symbol
.macro keyword_rts key, vec, token
        .segment "VECTORS"
		.word	vec-1
		.segment "KEYWORDS_A"
		htasc	key
		define_token_a token
.endmacro

; lay down a keyword and an address (function in bin B; vector in
; UNFNC), optionally define a token symbol
.macro keyword_addr key, vec, token
        .segment "VECTORS"
		.addr	vec
		.segment "KEYWORDS_B"
		htasc	key
		define_token_b token
.endmacro

.macro count_tokens
        .segment "DUMMY_A"
		NUM_TOKENS := <(*-DUMMY_A_START)
.endmacro

.macro init_error_table
        .segment "ERROR"
ERROR_MESSAGES:
.endmacro

.macro define_error error, msg
        .segment "ERROR"
		error := <(*-ERROR_MESSAGES)
		htasc msg
.endmacro

;---------------------------------------------
; set the MSB of every byte of a string
.macro asc80 str
	.repeat	.strlen(str),I
		.byte	.strat(str,I)+$80
	.endrep
.endmacro
