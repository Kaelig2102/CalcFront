; CalcFront - hand-written eZ80 row filler for the setup map preview
; (src/ce/render.c, r_preview())
;
; void asm_fill_row(const uint8_t *src, uint8_t *dst, const uint8_t *hmap);
;   Fills 320 pixels: dst[px] = colLUT[src[hmap[px]]], px = 0..319 (SCR_W).
;   src is the base of one map row; hmap was built once by build_hmap().
;   The palette is the global colLUT[] in render.c (20-cycle immediate load
;   per pixel, instead of a 32-cycle pointer reload from .bss).
;   Arguments are the CE toolchain's 24-bit stack args:
;     (sp+3) src, (sp+6) dst, (sp+9) hmap.
;   Uses AF, BC, DE, HL, IY and shadow AF (free for the callee in this ABI).
;   IX is callee-saved here: save it in .bss and restore it before RET.
;   The 320-pixel loop is split into 5 x 64 so an 8-bit counter in the
;   shadow AF' tracks the inner count; the outer count lives in a byte
;   in .bss (touched only 5 times per row).
;
;   Inner loop, per pixel:
;     A  = hmap[px]          (IX walks hmap)
;     BC = tile              -> HL = src + tile
;     A  = src[tile]         -> HL restored with SBC (carry cleared by OR A)
;     BC = map byte          -> IY = colLUT + byte
;     A  = colLUT[byte]      -> stored at DE, DE/IX advanced
;     IY reloaded from the global; AF' holds the 64-count (EX AF,AF' per pixel).
;
; The C fallback (asm_fill_row_c in render.c) has identical output; the
; PC harness uses it (HOST / CF_NOASM).

	.assume	ADL = 1

	.section	.bss
fill_outer:	.space	1
saved_ix:	.space	3		; IX is callee-saved in this ABI
saved_sp:	.space	3		; stack args are caller-cleaned here

	.extern	_colLUT
	.section	.text._asm_fill_row,"ax",@progbits
	.globl	_asm_fill_row
	.type	_asm_fill_row,@function
_asm_fill_row:
	push	ix			; save caller's IX (callee-saved)
	pop	iy			; IY = old IX
	ld	(saved_ix), iy		; stash it for the return
	ld	(saved_sp), sp		; caller cleans the 3 stack args: restore SP on exit
	pop	bc			; return address (3 bytes in ADL mode)
	pop	hl			; src  -> HL
	pop	de			; dst  -> DE
	pop	ix			; hmap -> IX
	push	bc			; return address back on the stack

	ld	a, 5
	ld	(fill_outer), a
	ld	b, 0			; BC high byte stays 0 for the whole row
.Louter:
	ld	a, 64
	ex	af, af'		; A' = inner counter
.Linner:
	ld	a, (ix+0)		; tile = hmap[px]
	ld	c, a			; BC = tile (B stays 0)
	add	hl, bc			; HL = src + tile
	ld	a, (hl)			; map byte
	or	a			; clear carry before SBC
	sbc	hl, bc			; HL = src (row base restored)
	ld	c, a			; BC = map byte (B still 0)
	add	iy, bc			; IY = colLUT + map byte
	ld	a, (iy)			; final colour
	ld	(de), a			; dst[px] = colour
	inc	de
	inc	ix
	ld	iy, _colLUT		; restore IY = colLUT base (20 cycles)
	ex	af, af'		; A = inner counter, A' = colour
	dec	a
	ex	af, af'		; counter back in A', colour in A
	jr	nz, .Linner

	ld	a, (fill_outer)
	dec	a
	ld	(fill_outer), a
	jr	nz, .Louter
	ld	sp, (saved_sp)		; back to the call frame (caller pops the args)
	ld	ix, (saved_ix)		; restore caller's IX before returning
	ret
	.size	_asm_fill_row, .-_asm_fill_row
