/*
 * ===============================================================================
 * Module: Hybrid RLE + 4-symbol dictionary decompressor (Plus/4 port)
 *
 * This is a direct port of the C64 decompressor.asm to Plus/4.
 * The algorithm is pure CPU code and works unchanged.
 *
 * See the original decompressor.asm for full documentation of the algorithm.
 * ===============================================================================
 */
#importonce
#import "plus4_constants.inc"

/*
 * ===========================================
 * Zero-page variables
 * ===========================================
 */
.label decomp_src_ptr      = $27    // 16-bit pointer to compressed input stream
.label decomp_emit_mode    = $29    // current mode flag ($00 = direct, $FF = run)
.label decomp_emit_rem     = $2A    // remaining outputs for current operation
.label decomp_run_symbol   = $2B    // byte value to output in run mode
.label decomp_y_save       = $2D    // temporary storage for Y register
.label decomp_skip_rem     = $2E    // skip counter (low at $2E, high at $2F)

.label decomp_dict4        = $0100  // dictionary of 4 symbols ($0100-$0103)

.const DIRECT_MODE         = $00    // constant: direct mode selector
.const RUN_MODE            = $FF    // constant: run mode selector

* = $0104
/*
 * ===========================================
 * Initializes the symbol dictionary with 4 entries.
 * ===========================================
 */
decomp_dict4_init:
       // Copy 4 dictionary bytes from input: Y = 3..0
       ldy #$03
dict_copy_loop:
       lda (decomp_src_ptr),Y   // read source byte at ptr+Y
       sta decomp_dict4,Y       // store to dictionary [$0100..$0103]
       dey
       bpl dict_copy_loop

       // Advance input pointer by 4 (past the dictionary)
       clc
       lda decomp_src_ptr
       adc #$04
       sta decomp_src_ptr
       lda decomp_src_ptr + 1
       adc #$00
       sta decomp_src_ptr + 1

       // Reset state: no active operation, counter = 0
       lda #$00
       sta decomp_emit_rem
       sta decomp_emit_mode
       rts

/*
 * ===========================================
 * Retrieves the next decompressed byte from the stream
 *
 * Returns:
 * 	A — The next decompressed byte.
 * ===========================================
 */
decomp_stream_next:
       // Preserve Y (routine uses Y)
       sty decomp_y_save
       // If an operation is already active (counter > 0), continue it
       lda decomp_emit_rem
       bne repeat_operation

       // No active op: fetch a control byte and configure the next op
       jsr decomp_read_src_byte
       // Classify by top bits
       cmp #$40
       bcs ctrl_ge_40

       // DIRECT: ctrl < $40 → L in A. Set counter=L and output first raw byte.
       sta decomp_emit_rem
       // Set direct mode (bit7 clear)
       lda #DIRECT_MODE
       jmp set_emit_mode

ctrl_ge_40:
       cmp #$80
       bcs ctrl_ge_80

       // AD-HOC RUN: $40 ≤ ctrl < $80
       // Low 6 bits = L (repeat count-1), next byte = literal to repeat
       and #$3F
       sta decomp_emit_rem
       // Get the literal to repeat
       jsr decomp_read_src_byte
       jmp latch_run_symbol

       // DICTIONARY RUN: ctrl ≥ $80
       // Bits 4..0 = L, bits 6..5 = dictionary index
ctrl_ge_80:
       // Extract L (run length-1) to counter
       tax
       and #$1F
       sta decomp_emit_rem
       // Recover full ctrl in A
       txa
       // Compute index = (ctrl >> 5) & 3
       lsr
       lsr
       lsr
       lsr
       lsr
       and #$03
       tax
       // Fetch symbol from dictionary
       lda decomp_dict4,X

       // Initialize run with chosen symbol, then mark mode as RUN
latch_run_symbol:
       sta decomp_run_symbol
       // Set run mode (bit7 set)
       lda #RUN_MODE
set_emit_mode:
       sta decomp_emit_mode
       // New op just set up: skip the pre-decrement path and emit first byte
       jmp emit_by_mode

repeat_operation:
       // Active op: decrement remaining count before emitting this byte
       dec decomp_emit_rem

emit_by_mode:
       // Decide emission path by bit7 of mode: RUN (negative) vs DIRECT (non-negative)
       bit decomp_emit_mode
       bmi emit_run_byte

       // DIRECT: output next raw byte from input
       jsr decomp_read_src_byte
       jmp return_byte

       // RUN: output previously latched decomp_run_symbol
emit_run_byte:
       lda decomp_run_symbol

return_byte:
       // Restore Y and return byte in A
       ldy decomp_y_save
       rts

/*
 * ===========================================
 * Reads one byte from the compressed data stream.
 * ===========================================
 */
decomp_read_src_byte:
       ldy #$00                     // Y=0 so (ptr),Y reads at ptr
       lda (decomp_src_ptr),Y   	// fetch byte
       inc decomp_src_ptr       	// bump low byte
       bne return_read              // if not wrapped, done
       inc decomp_src_ptr + 1   	// else bump high byte
return_read:
       rts

/*
 * ===========================================
 * Skips a specified amount of decompressed data (16-bit count).
 * ===========================================
 */
decomp_skip_16bit:
       // If decomp_skip_rem == 0, nothing to skip
       lda decomp_skip_rem
       ora decomp_skip_rem + 1
       bne skip16_step
       rts

skip16_step:
       // Consume one decompressed byte (discard result)
       jsr decomp_stream_next
       // Decrement 16-bit decomp_skip_rem (low then high if needed)
       lda decomp_skip_rem
       bne dec_skip_lo
       // decomp_skip_rem low is zero → borrow from high
       dec decomp_skip_rem + 1

dec_skip_lo:
       dec decomp_skip_rem
       jmp decomp_skip_16bit

/*
 * ===========================================
 * Skips a specified amount of decompressed data (8-bit count).
 * ===========================================
 */
decomp_skip_8bit:
       // Load 8-bit count once; if zero, done
       ldy decomp_skip_rem
       bne skip8_step
       rts

skip8_step:
       // Consume one decompressed byte (discard result)
       jsr decomp_stream_next
       dey
       bne skip8_step
       rts
