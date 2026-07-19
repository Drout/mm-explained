/*
 * ===============================================================================
 * Plus/4 Room Rendering Module
 *
 * Simplified room renderer for Plus/4:
 * - Single buffer (no double-buffering)
 * - No scrolling (static display)
 * - Decompress and display tile matrix
 * - Color support
 *
 * This is Phase 1: Basic Room Display
 * ===============================================================================
 */
#importonce
#import "plus4_constants.inc"
#import "plus4_decompressor.asm"

/*
 * ===========================================
 * Zero-page variables for room rendering
 * ===========================================
 */
.label room_base           = $C3    // 16-bit pointer to room resource base
.label room_width          = $41    // Room width in tiles
.label room_height         = $42    // Room height in tiles (always 17)
.label dest_ptr            = $15    // 16-bit destination pointer for decompression

// Room background colors (from room metadata)
.label room_bg0            = $43
.label room_bg1            = $44
.label room_bg2            = $45

.const ROOM_META_BASE      = RSRC_HDR_BYTES

// Tile matrix/color/mask decompressed buffers
// Using addresses from plus4_constants.inc:
// ROOM_TILE_MATRIX  = $2000
// ROOM_COLOR_BUFFER = $2400
// ROOM_MASK_BUFFER  = $2800

/*
 * ===========================================
 * Load and display a room
 *
 * Input: room_base = pointer to room resource (at 4-byte header)
 *
 * Process:
 * 1. Read room metadata (width, height, colors, layer offsets)
 * 2. Decompress tile definitions to character RAM (ROOM_CHARSET_BASE)
 * 3. Decompress tile matrix to temporary buffer
 * 4. Decompress color layer to temporary buffer
 * 5. Copy visible portion to screen RAM with colors applied
 * ===========================================
 */
render_room:
       // Read room metadata
       jsr read_room_metadata

       // Decompress tile definitions to character RAM
       jsr decompress_tile_definitions

       // Now that a valid tile font exists at ROOM_CHARSET_BASE, point the TED character
       // generator at it. $FF13 encodes the base as (address / 1024) << 2,
       // so $3000 -> $30 (see TED_CHARBASE_TILES). Doing this only after the
       // font is present avoids drawing characters from empty RAM and avoids
       // overwriting the program, which occupies $1001-$19xx.
       lda #TED_CHARBASE_TILES
       sta TED_CHAR_BASE

       // Decompress tile matrix
       jsr decompress_tile_matrix

       // Decompress color layer
       jsr decompress_color_layer

       // Copy to screen with colors
       jsr copy_room_to_screen

       rts

/*
 * ===========================================
 * Read room metadata from resource
 *
 * Reads from room_base + offsets defined in room format:
 * +$00: width
 * +$01: height
 * +$03-05: background colors
 * +$06-07: tile definitions offset
 * +$08-09: tile matrix offset
 * +$0A-0B: color layer offset
 * ===========================================
 */
read_room_metadata:
       // Read width
       ldy #ROOM_META_BASE + ROOM_META_WIDTH
       lda (room_base),y
       sta room_width

       // Read height (should always be 17)
       ldy #ROOM_META_BASE + ROOM_META_HEIGHT
       lda (room_base),y
       sta room_height

       // Read background colors
       ldy #ROOM_META_BASE + ROOM_META_BG0
       lda (room_base),y
       jsr convert_c64_color
       sta room_bg0

       ldy #ROOM_META_BASE + ROOM_META_BG1
       lda (room_base),y
       jsr convert_c64_color
       sta room_bg1

       ldy #ROOM_META_BASE + ROOM_META_BG2
       lda (room_base),y
       jsr convert_c64_color
       sta room_bg2

       // Mirror observed C64 runtime behavior:
       // shared background slot b0 is effectively forced to black.
       lda #P4_BLACK
       sta TED_BG_COLOR

       // In practice, the next two shared multicolor slots align best as:
       // b1 <- room bg0, b2 <- room bg1.
       lda room_bg0
       sta TED_CHAR_COLOR1
       lda room_bg1
       sta TED_CHAR_COLOR2

       rts

/*
 * ===========================================
 * Decompress tile definitions to character RAM
 *
 * Reads compressed tile data from room resource and
 * decompresses to ROOM_CHARSET_BASE (character RAM)
 * ===========================================
 */
decompress_tile_definitions:
       // Get offset to tile definitions from room metadata
       ldy #ROOM_META_BASE + ROOM_META_TILEDEF
       lda (room_base),y
       tax                          // Save low byte
       iny
       lda (room_base),y            // Get high byte

       // Add offset to room_base to get absolute pointer
       stx decomp_src_ptr
       sta decomp_src_ptr + 1

       clc
       lda decomp_src_ptr
       adc room_base
       sta decomp_src_ptr
       lda decomp_src_ptr + 1
       adc room_base + 1
       sta decomp_src_ptr + 1

       // Initialize decompressor dictionary
       jsr decomp_dict4_init

       // Set destination to character RAM
       lda #<ROOM_CHARSET_BASE
       sta dest_ptr
       lda #>ROOM_CHARSET_BASE
       sta dest_ptr + 1

       // Decompress ROOM_TILES_SIZE bytes ($0800 = 2048 bytes)
       ldx #$08                     // High byte count
       ldy #$00                     // Low byte (0 = 256)
       jsr decompress_block

       rts

/*
 * ===========================================
 * Decompress tile matrix
 *
 * Decompresses tile matrix (which tile at each position)
 * to temporary buffer at ROOM_TILE_MATRIX
 * ===========================================
 */
decompress_tile_matrix:
       // Get offset to tile matrix from room metadata
       ldy #ROOM_META_BASE + ROOM_META_TILEMATRIX
       lda (room_base),y
       tax
       iny
       lda (room_base),y

       // Add offset to room_base
       stx decomp_src_ptr
       sta decomp_src_ptr + 1

       clc
       lda decomp_src_ptr
       adc room_base
       sta decomp_src_ptr
       lda decomp_src_ptr + 1
       adc room_base + 1
       sta decomp_src_ptr + 1

       // Initialize decompressor
       jsr decomp_dict4_init

       // Set destination to tile matrix buffer
       lda #<ROOM_TILE_MATRIX
       sta dest_ptr
       lda #>ROOM_TILE_MATRIX
       sta dest_ptr + 1

       // Decompress width × height bytes
       // For 40×17 = 680 = $2A8 bytes
       lda room_width
       sta decomp_count_lo
       lda room_height
       sta decomp_count_hi

       jsr decompress_variable_block

       rts

/*
 * ===========================================
 * Decompress color layer
 *
 * Decompresses color layer to ROOM_COLOR_BUFFER
 * ===========================================
 */
decompress_color_layer:
       // Get offset to color layer from room metadata
       ldy #ROOM_META_BASE + ROOM_META_COLOR
       lda (room_base),y
       tax
       iny
       lda (room_base),y

       // Add offset to room_base
       stx decomp_src_ptr
       sta decomp_src_ptr + 1

       clc
       lda decomp_src_ptr
       adc room_base
       sta decomp_src_ptr
       lda decomp_src_ptr + 1
       adc room_base + 1
       sta decomp_src_ptr + 1

       // Initialize decompressor
       jsr decomp_dict4_init

       // Set destination to color buffer
       lda #<ROOM_COLOR_BUFFER
       sta dest_ptr
       lda #>ROOM_COLOR_BUFFER
       sta dest_ptr + 1

       // Decompress width × height bytes
       lda room_width
       sta decomp_count_lo
       lda room_height
       sta decomp_count_hi

       jsr decompress_variable_block

       rts

/*
 * ===========================================
 * Copy room to screen
 *
 * Copies tile matrix to screen RAM, applying colors.
 * Only copies the visible 40×17 viewport.
 * ===========================================
 */
copy_room_to_screen:
       // Room layers are decompressed in column-major order: each column
       // contains 17 consecutive bytes (top-to-bottom rows).
       // Blit the first 40 columns into the visible 40x17 viewport.

       // Source pointers start at column 0 for tile/color buffers.
       lda #<ROOM_TILE_MATRIX
       sta src_tile
       lda #>ROOM_TILE_MATRIX
       sta src_tile + 1

       lda #<ROOM_COLOR_BUFFER
       sta src_color
       lda #>ROOM_COLOR_BUFFER
       sta src_color + 1

       ldx #$00                     // X = visible column 0..39
copy_col_loop:
       // Destination points to row 1, current column X.
       lda #<(PLUS4_SCREEN_RAM + SCREEN_COLS)
       sta dest_screen
       lda #>(PLUS4_SCREEN_RAM + SCREEN_COLS)
       sta dest_screen + 1

       lda #<(PLUS4_COLOR_RAM + SCREEN_COLS)
       sta dest_color
       lda #>(PLUS4_COLOR_RAM + SCREEN_COLS)
       sta dest_color + 1

       txa
       clc
       adc dest_screen
       sta dest_screen
       bcc copy_col_dest_ok
       inc dest_screen + 1
copy_col_dest_ok:

       txa
       clc
       adc dest_color
       sta dest_color
       bcc copy_col_color_dest_ok
       inc dest_color + 1
copy_col_color_dest_ok:

       // Copy one full column: 17 rows, source contiguous, destination +40.
       ldy #$00
copy_col_rows:
       lda (src_tile),y
       sty temp_y
       ldy #$00
       sta (dest_screen),y
       ldy temp_y

       // Treat room color-layer bytes as C64 multicolor cell attributes:
       // low 3 bits = per-cell color index, bit3 = multicolor-cell enable.
       // This avoids feeding full TED 121-color values into the cell-attribute
       // byte, which can produce mode artifacts.
       lda (src_color),y
       and #$07
       ora #$08
       sty temp_y
       ldy #$00
       sta (dest_color),y
       ldy temp_y

       // Advance destination by one screen row (40 chars).
       clc
       lda dest_screen
       adc #SCREEN_COLS
       sta dest_screen
       bcc copy_col_no_carry
       inc dest_screen + 1
copy_col_no_carry:

       clc
       lda dest_color
       adc #SCREEN_COLS
       sta dest_color
       bcc copy_col_color_no_carry
       inc dest_color + 1
copy_col_color_no_carry:

       iny
       cpy #ROOM_VIEWPORT_ROWS
       bne copy_col_rows

       // Advance source pointers to next room column (+17 bytes).
       clc
       lda src_tile
       adc #ROOM_VIEWPORT_ROWS
       sta src_tile
       bcc copy_col_tile_ok
       inc src_tile + 1
copy_col_tile_ok:

       clc
       lda src_color
       adc #ROOM_VIEWPORT_ROWS
       sta src_color
       bcc copy_col_color_ok
       inc src_color + 1
copy_col_color_ok:

       inx
       cpx #ROOM_VIEWPORT_COLS
       beq copy_cols_done
       jmp copy_col_loop
copy_cols_done:

       rts

/*
 * ===========================================
 * Decompress a fixed-size block
 *
 * Input: X = high byte count, Y = low byte (0 = 256)
 *        dest_ptr = destination address
 *        decomp_src_ptr = source (already initialized with dict)
 * ===========================================
 */
decompress_block:
       stx decomp_pages
       sty decomp_remain

decomp_block_loop:
       // Get next decompressed byte
       jsr decomp_stream_next

       // Store to destination
       ldy #$00
       sta (dest_ptr),y

       // Advance destination pointer
       inc dest_ptr
       bne decomp_no_carry
       inc dest_ptr + 1

decomp_no_carry:
       // Decrement counter
       dec decomp_remain
       bne decomp_block_loop

       // Finished a page
       dec decomp_pages
       bne decomp_block_loop

       rts

/*
 * ===========================================
 * Decompress a variable-size block
 *
 * Input: decomp_count_lo, decomp_count_hi = byte count
 *        dest_ptr = destination address
 * ===========================================
 */
decompress_variable_block:
       // This is a multiplication: width × height
       // For 40×17 = 680 bytes = $2A8
       // We'll use a simple approach: loop height times, each time processing width bytes

       ldx room_height              // Outer loop: rows
decomp_var_outer:
       ldy room_width              // Inner loop: columns
decomp_var_inner:
       jsr decomp_stream_next

       // Store to destination
       sty temp_y
       ldy #$00
       sta (dest_ptr),y
       ldy temp_y

       // Advance dest pointer
       inc dest_ptr
       bne decomp_var_no_carry
       inc dest_ptr + 1

decomp_var_no_carry:
       dey
       bne decomp_var_inner

       dex
       bne decomp_var_outer

       rts

/*
 * ===========================================
 * Convert C64 color to Plus/4 color (wrapper)
 * ===========================================
 */
convert_c64_color:
       tax
       lda c64_to_plus4_colors,x
       rts

/*
 * ===========================================
 * Variables
 * ===========================================
 */
.label decomp_pages        = $50
.label decomp_remain       = $51
.label decomp_count_lo     = $52
.label decomp_count_hi     = $53

.label src_tile            = $54    // Source tile matrix pointer
.label src_color           = $56    // Source color buffer pointer
.label dest_screen         = $58    // Destination screen pointer
.label dest_color          = $50    // Destination color RAM pointer
.label temp_y              = $5A    // Temporary Y storage
