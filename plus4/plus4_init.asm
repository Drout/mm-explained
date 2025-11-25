/*
 * ===============================================================================
 * Plus/4 Initialization Module
 *
 * Sets up the Plus/4 TED chip for room display:
 * - Text mode, 40×25 characters
 * - Screen RAM at $0C00
 * - Character set at $1000
 * - Colors configured for room rendering
 * ===============================================================================
 */
#importonce
#import "plus4_constants.inc"

/*
 * ===========================================
 * Initialize Plus/4 for room display
 *
 * Sets up:
 * - Screen mode (text mode)
 * - Screen and character memory locations
 * - Colors (background, border)
 * - Clear screen
 * ===========================================
 */
init_plus4:
       // Disable interrupts during init
       sei

       // Clear screen first (fill with spaces)
       jsr clear_screen

       // Set background color to black
       lda #P4_BLACK
       sta TED_BG_COLOR

       // Set border color to black
       sta TED_BORDER_COLOR

       // Set multicolor registers (for multicolor text mode if needed)
       lda #P4_DARK_GREY
       sta TED_CHAR_COLOR1

       lda #P4_MEDIUM_GREY
       sta TED_CHAR_COLOR2

       lda #P4_LIGHT_GREY
       sta TED_CHAR_COLOR3

       // Configure video mode
       // Bits: 7=reverse, 6=NTSC/PAL, 5=?, 4=multicolor, 3=text mode
       // We want standard text mode: bit 3 = 1, others = 0
       lda #TED_TEXT_MODE
       sta TED_VIDEO_MODE

       // Configure character and screen base addresses
       // TED_CHAR_BASE ($FF13):
       //   Bits 7-2: Character base address / 1024
       //   $1000 / 1024 = 4, so bits 7-2 = 000100 = $04
       lda #$04              // Character base at $1000
       sta TED_CHAR_BASE

       // TED_SCREEN_BASE ($FF14):
       //   Bits 7-3: Screen base address / 1024
       //   $0C00 / 1024 = 3, so bits 7-3 = 00011 = $18
       lda #$18              // Screen base at $0C00
       sta TED_SCREEN_BASE

       // Re-enable interrupts
       cli
       rts

/*
 * ===========================================
 * Clear the screen (fill with spaces)
 * ===========================================
 */
clear_screen:
       ldx #$00
       lda #SPACE_CHAR       // Space character
clear_loop:
       sta PLUS4_SCREEN_RAM,x
       sta PLUS4_SCREEN_RAM + $100,x
       sta PLUS4_SCREEN_RAM + $200,x
       sta PLUS4_SCREEN_RAM + $300,x  // Only need first 1000 bytes
       inx
       bne clear_loop

       // Clear the last 24 bytes (1000 - 4*256 = 24)
       ldx #$18
clear_tail:
       sta PLUS4_SCREEN_RAM + $3E8,x
       dex
       bpl clear_tail
       rts

/*
 * ===========================================
 * Copy character set from ROM to RAM
 *
 * The Plus/4 has character ROM at $D000-$DFFF when mapped in.
 * We need to copy it to RAM at $1000 so we can modify it for tiles.
 *
 * Note: This is a placeholder - in the actual port, we'll load
 * tile definitions from the room resource instead.
 * ===========================================
 */
copy_charset_from_rom:
       // This would need proper ROM banking to access character ROM
       // For now, we'll skip this and assume tiles are loaded directly
       rts

/*
 * ===========================================
 * Set a color in the color attribute
 *
 * Plus/4 uses luminance/color attributes stored in screen RAM
 * along with the character code. This is different from C64!
 *
 * Screen RAM format per character:
 *   Lower 8 bits: Character code
 *   Upper 8 bits: Color/luminance attribute
 *
 * For now, we'll implement simple color setting
 * ===========================================
 */
set_screen_color:
       // On Plus/4, colors are set via character attributes
       // This is more complex than C64 and depends on the video mode
       // For basic text mode, we'll use the multicolor registers
       rts

/*
 * ===========================================
 * Utility: Wait for specific raster line
 *
 * Input: A = raster line to wait for (low 8 bits)
 * ===========================================
 */
wait_raster:
       cmp TED_RASTER_LO
       bne wait_raster
       rts

/*
 * ===========================================
 * Convert C64 color to Plus/4 color
 *
 * Input:  A = C64 color value (0-15)
 * Output: A = Plus/4 color value
 * ===========================================
 */
convert_c64_color:
       tax
       lda c64_to_plus4_colors,x
       rts

/*
 * ===========================================
 * Constants for screen operations
 * ===========================================
 */
.const SPACE_CHAR = $20

/*
 * ===========================================
 * Display a test pattern on screen
 * (For debugging initialization)
 * ===========================================
 */
test_pattern:
       ldx #$00
test_loop:
       txa
       sta PLUS4_SCREEN_RAM,x
       inx
       bne test_loop
       rts
