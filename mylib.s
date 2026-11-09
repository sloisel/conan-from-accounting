	.macro _add16imm(result,a,b) {
	clc
	lda a
	adc #<b
	sta result
	lda a+1
	adc #>b
	sta result+1
	}
	.macro _add16a(result,a) {
	clc
	adc a
	sta result
	lda a+1
	adc #0
	sta result+1
	}
	.macro _add16(result,a,b) {
	clc
	lda a
	adc b
	sta result
	lda a+1
	adc b+1
	sta result+1
	}
	.pseudocommand add16 al:ah:bl:bh:cl:ch {
		clc
		lda bl
		adc cl
		.if (al.getType()!=AT_NONE) sta al
		lda bh
		adc ch
		.if (ah.getType()!=AT_NONE) sta ah
	}
	.pseudocommand sub16 al:ah:bl:bh:cl:ch {
		sec
		lda bl
		sbc cl
		.if (al.getType()!=AT_NONE) sta al
		lda bh
		sbc ch
		.if (ah.getType()!=AT_NONE) sta ah
	}
	.pseudocommand set8 a:b {
	lda b
	sta a
	}
	.macro set16(a,b) {
	lda #<b
	sta a
	lda #>b
	sta a+1
	}
	.macro shl16(z) {
	asl z
	rol z+1
	}
	.macro _shr16(z) {
		lsr z+1
		ror z
	}
	.pseudocommand shr16 zl:zh {
		lsr zh
		ror zl
	}
	.macro asr16(z) {
		lda z+1
		cmp #$80
		ror z+1
		ror z
	}


// rand256: return a random number between 0 and 255 in the accumulator.
.pseudocommand rand256 {
	ldx rand_index
	lda randperm,x
	inc rand_index
}

// randfilter range:filter: return a random number between 0 and range-1 in the accumulator.
// Arguments:
// range: the random number is in the range 0 to range-1 inclusive.
// filter: Should be one of $1, $3, $7, $f, $1f, $3f, $7f, $ff.
//    Pick filter smallest possible so that filter >= range.
// Returns the random number in the accumulator.
.pseudocommand randfilter range:filter {
randfilter_loop:
	rand256
	and filter
	cmp range
	bcs randfilter_loop
}

