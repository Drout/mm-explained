/*
 * ===============================================================================
 * Plus/4 Initialization Module
 *
 * Sets up the Plus/4 TED chip for room display:
 * - Text mode, 40×25 characters
 * - Screen RAM at $0C00
 * - Room character set later loaded at $3000
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

       // Clear screen and color RAM first so we start from deterministic text
       // and per-cell colors.
       jsr clear_screen
       jsr clear_color_ram

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

       // Configure video mode: multicolor text.
       // TED MCM is bit 4 of $FF07; ECM is in a separate register ($FF06 bit 6).
       // Just set MCM without disturbing other bits.
       lda TED_VIDEO_MODE
       ora #TED_TEXT_MULTICOLOR // set bit 4 (MCM)
       sta TED_VIDEO_MODE

       // Force TED to fetch glyphs from RAM charset, not ROM charset.
       // $FF12 bit 2: 0 = RAM charset, 1 = ROM charset.
       lda $FF12
       and #%11111011
       sta $FF12

       // Configure character and screen base addresses
       //
       // Screen base ($FF14): bits 7-3 hold the address / 1024, shifted into
       // bits 7-3. $0C00 -> ($0C00 / 1024) << 3 = 3 << 3 = $18. This matches
       // the KERNAL default (screen RAM at $0C00) so KERNAL text printing and
       // the room renderer share the same screen memory.
       lda #TED_SCREENBASE_0C00     // Screen base at $0C00
       sta TED_SCREEN_BASE

       // NOTE: We deliberately DO NOT repoint the character generator here.
       // The tile font lives at ROOM_CHARSET_BASE but is only filled in once a room is
       // decompressed. Switching the character base there now (before any
       // font exists there) would draw every on-screen character from empty
       // RAM, producing scrambled glyphs. render_room switches the character
       // base to the tile font (TED_CHARBASE_TILES) after the tiles are
       // decompressed. Until then we keep the KERNAL ROM font so the startup
       // and status messages remain readable.

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
       rts

/*
 * ===========================================
 * Copy character set from ROM to RAM
 *
 * The Plus/4 has character ROM at $D000-$DFFF when mapped in.
 * We would copy it to ROOM_CHARSET_BASE if we wanted a RAM font template.
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
 * Set a color in the color matrix
 *
 * In Plus/4 text mode, screen codes live in screen RAM ($0C00 by default) and
 * per-cell colors live in a separate 1 KB color RAM area ($0800 by default).
 * This differs from the C64's fixed $D800 nibble RAM, but it is still a
 * distinct memory area rather than metadata packed into the screen-code bytes.
 * ===========================================
 */
set_screen_color:
       // Placeholder for a future generic color-write helper.
       rts

/*
 * ===========================================
 * Clear color RAM (fill with black)
 * ===========================================
 */
clear_color_ram:
       ldx #$00
       // Keep text visible during startup/error paths.
       // The room renderer overwrites viewport colors after a successful load.
       lda #P4_WHITE
clear_color_loop:
       sta PLUS4_COLOR_RAM,x
       sta PLUS4_COLOR_RAM + $100,x
       sta PLUS4_COLOR_RAM + $200,x
       sta PLUS4_COLOR_RAM + $300,x
       inx
       bne clear_color_loop
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
