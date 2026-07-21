/*
 * ===============================================================================
 * Plus/4 Custom Charset Demo
 *
 * Standalone diagnostic program:
 * - Sets TED screen RAM to $0C00
 * - Sets TED character generator to $3000
 * - Builds a custom 256-char charset in RAM
 * - Fills screen with character codes so mapping is visible
 *
 * Purpose: isolate charset/screen setup from Maniac room loading/decompression.
 * ===============================================================================
 */

.pc = $1001 "BASIC Upstart"
:BasicUpstart(main)

/*
 * ===========================================
 * Main
 * ===========================================
 */
.pc = $1100 "Charset Demo"
main:
       //sei

       // Configure TED for text mode, black background/border.
       lda $FF07
       ora #$90
       sta $FF07

       lda #$00
       sta $FF15
       sta $FF19

        // $FF12 Bit 2: 0 = RAM Charset, 1 = ROM Charset
        lda $FF12
        and #%11111011 
        sta $FF12
       // Screen at $0C00, charset at $3000.
       lda #$30
       sta $FF13

       // $FF14 = $08 selects color RAM $0800 and screen RAM $0C00.
       lda #$08
       sta $FF14

       // Fill screen and color RAM with a visible test pattern.
       jsr fill_screen_codes
       jsr fill_color_ram

       //cli

hang:
       jmp hang



/*
 * ===========================================
 * fill_screen_codes
 *
 * Fill 40x25 screen with incrementing char codes.
 * This lets us verify 256-char addressing quickly.
 * ===========================================
 */
fill_screen_codes:
       // Fill $0C00-$0FFF directly (4 x 256 bytes).
       ldx #$00
screen_fill_loop:
       txa
       sta $0C00,x
       sta $0D00,x
       sta $0E00,x
       sta $0F00,x
       inx
       bne screen_fill_loop
       rts

/*
 * ===========================================
 * fill_color_ram
 *
 * Use one fixed color attribute so shape reading is easy.
 * ===========================================
 */
fill_color_ram:
       // White on black, single-color text cell.
       lda #$7F

       // Fill $0800-$0BFF directly (4 x 256 bytes).
       ldx #$00
color_fill_loop:
       sta $0800,x
       sta $0900,x
       sta $0A00,x
       sta $0B00,x
       inx
       bne color_fill_loop
       rts

/*
 * ===========================================
 * ZP vars
 * ===========================================
 */
// None needed for this simplified demo.

.pc = $3000 "Custom Charset"
CHAR_A_ACUTE:
    .byte $08, $10, $00, $38, $44, $7C, $44, $44
    .byte $08, $10, $00, $38, $44, $7C, $44, $44