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
       ora #$80
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
       lda #<$0C00
       sta scr_ptr
       lda #>$0C00
       sta scr_ptr + 1

       lda #$00
       sta code_val

       // Fill 4 contiguous 256-byte pages = 1024 bytes.
       ldx #$04
screen_page_loop:
       ldy #$00
screen_byte_loop:
       lda code_val
       sta (scr_ptr),y
       inc code_val
       iny
       bne screen_byte_loop

       inc scr_ptr + 1
       dex
       bne screen_page_loop
       rts

/*
 * ===========================================
 * fill_color_ram
 *
 * Use one fixed color attribute so shape reading is easy.
 * ===========================================
 */
fill_color_ram:
       lda #<$0800
       sta col_ptr
       lda #>$0800
       sta col_ptr + 1

       // White on black, single-color text cell.
       lda #$01
       sta color_val

       // Fill 4 contiguous 256-byte pages = 1024 bytes.
       ldx #$04
color_page_loop:
       ldy #$00
color_byte_loop:
       lda color_val
       sta (col_ptr),y
       iny
       bne color_byte_loop

       inc col_ptr + 1
       dex
       bne color_page_loop
       rts

/*
 * ===========================================
 * ZP vars
 * ===========================================
 */
.label cs_ptr    = $70
.label scr_ptr   = $72
.label col_ptr   = $74
.label code_val  = $76
.label color_val = $77

.pc = $3000 "Custom Charset"
CHAR_A_ACUTE:
    .byte $08, $10, $00, $38, $44, $7C, $44, $44
    .byte $08, $10, $00, $38, $44, $7C, $44, $44