#importonce

/*
================================================================================
Commodore Plus/4 Constants and Register Definitions
================================================================================

TED 7360 Chip - Text Editing Device
The TED chip handles video, sound, and some I/O functions.
All TED registers are located at $FF00-$FF3F.
*/

// ============================================================================
// TED Video Registers ($FF00-$FF1F)
// ============================================================================

// Timer registers
.const TED_TIMER1_LO        = $FF00    // Timer 1 low byte
.const TED_TIMER1_HI        = $FF01    // Timer 1 high byte
.const TED_TIMER2_LO        = $FF02    // Timer 2 low byte
.const TED_TIMER2_HI        = $FF03    // Timer 2 high byte
.const TED_TIMER3_LO        = $FF04    // Timer 3 low byte
.const TED_TIMER3_HI        = $FF05    // Timer 3 high byte

// Control registers
.const TED_CONTROL          = $FF06    // Control register (keyboard scan, sound)
.const TED_IRQ_CONTROL      = $FF09    // IRQ control register
.const TED_IRQ_RASTER_LO    = $FF0A    // Raster IRQ line (low 8 bits)
.const TED_IRQ_RASTER_HI    = $FF0B    // Raster IRQ line (high bit, bit 0)

// Cursor position registers
.const TED_CURSOR_HI        = $FF0C    // Cursor position high (bits 9-8)
.const TED_CURSOR_LO        = $FF0D    // Cursor position low (bits 7-0)

// Video control
.const TED_VIDEO_CTRL       = $FF06    // Video control and keyboard
.const TED_VIDEO_MODE       = $FF07    // Character/bitmap mode selection

// Character generator and screen memory
.const TED_CHAR_BASE        = $FF13    // Character generator base address
.const TED_SCREEN_BASE      = $FF14    // Screen memory base address / video address

// $FF14 bits 7-3 select a 2KB window (address bits A15-A11), not a 1KB one.
// Screen and color RAM are the two halves of that window: color = window
// base, screen = window base + $400 (they move together, not independently).
// For color $0800 / screen $0C00: field = $0800 >> 11 = 1, value = 1 << 3 = $08.
.const TED_SCREENBASE_0C00  = $08      // $FF14 value selecting color $0800 / screen $0C00

// Video timing
.const TED_RASTER_LO        = $FF1C    // Current raster line (bits 7-0)
.const TED_RASTER_HI        = $FF1D    // Current raster line (bit 8) and vertical position
.const TED_HORIZ_POS        = $FF1E    // Horizontal position
.const TED_VERT_POS         = $FF1F    // Vertical position

// ============================================================================
// Color Registers
// ============================================================================

.const TED_BG_COLOR         = $FF15    // Background color
.const TED_BORDER_COLOR     = $FF19    // Border color
.const TED_CHAR_COLOR1      = $FF16    // Multi-color 1 (for multicolor mode)
.const TED_CHAR_COLOR2      = $FF17    // Multi-color 2 (for multicolor mode)
.const TED_CHAR_COLOR3      = $FF18    // Multi-color 3 (for multicolor mode)

// ============================================================================
// Sound Registers ($FF11, $FF12)
// ============================================================================

.const TED_SOUND_VOICE1     = $FF0E    // Sound voice 1 frequency / volume
.const TED_SOUND_VOICE2     = $FF0F    // Sound voice 2 frequency
.const TED_SOUND_CONTROL    = $FF11    // Sound control register

// ============================================================================
// Video Mode Control Bits ($FF06)
// ============================================================================

.const TED_MODE_TEXT        = $08      // Bit 3: 0=bitmap, 1=text mode
.const TED_MODE_MULTICOLOR  = $10      // Bit 4: 0=hires, 1=multicolor
.const TED_MODE_BLANK       = $00      // Blank screen
.const TED_MODE_NTSC        = $40      // Bit 6: NTSC mode (vs PAL)
.const TED_MODE_REVERSE     = $80      // Bit 7: Reverse mode

// Standard mode presets
.const TED_TEXT_MODE        = $08      // Standard text mode
.const TED_TEXT_MULTICOLOR  = $18      // Multicolor text mode
.const TED_BITMAP_MODE      = $00      // Standard bitmap mode
.const TED_BITMAP_MULTICOLOR = $10     // Multicolor bitmap mode

// ============================================================================
// Memory Layout Constants
// ============================================================================

// Standard text-mode memory locations
// On the Plus/4, screen codes live at $0C00 and the per-cell color matrix is a
// separate 1 KB RAM area at $0800.
.const PLUS4_SCREEN_RAM     = $0C00    // Default screen RAM / video matrix (1000 bytes)
.const PLUS4_COLOR_RAM      = $0800    // Default text-mode color RAM / color matrix (1000 bytes)
.const PLUS4_CHARSET_ROM    = $D000    // Character ROM location (when mapped)
.const PLUS4_BASIC_ROM      = $8000    // BASIC ROM
.const PLUS4_KERNAL_ROM     = $FC00    // KERNAL ROM

// Room rendering memory layout
.const ROOM_SCREEN_BASE     = $0C00    // Screen memory for room display
// Wide rooms reach 160x17 tiles (= $0AA0 bytes per layer), so the transient
// tile/color buffers must be substantially larger than 1 KB.
.const ROOM_LAYER_MAX_BYTES = $0AA0    // Max decoded bytes for a room layer (160 * 17)
.const ROOM_TILE_MATRIX     = $1C00    // Decompressed tile matrix ($0AA0 bytes, safe above code end ~$1ABE)
.const ROOM_COLOR_BUFFER    = $2700    // Decompressed color layer ($0AA0 bytes, after tile matrix)
.const ROOM_MASK_BUFFER     = $3000    // Reserved for future mask decode path
// Keep the room tile charset above the transient layer buffers and below the
// room resource load address at $4000.
.const ROOM_CHARSET_BASE    = $3800    // Character set for room tiles (2KB used)

// $FF13 holds the character base in bits 7-2 (address / 1024, shifted into
// bits 7-2). For the room tile font at $3800: ($3800 / 1024) << 2 = 14 << 2 = $38.
.const TED_CHARBASE_TILES   = $38      // $FF13 value selecting a font at $3800

// ============================================================================
// Screen Layout Constants
// ============================================================================

.const SCREEN_COLS          = 40       // Screen width in characters
.const SCREEN_ROWS          = 25       // Screen height in characters
.const SCREEN_SIZE          = 1000     // Total screen size (40×25)

// Room viewing area (matching C64 layout)
.const ROOM_VIEWPORT_COLS   = 40       // Room viewport width
.const ROOM_VIEWPORT_ROWS   = 17       // Room viewport height
.const ROOM_VIEWPORT_SIZE   = 680      // 40×17 characters

.const ROOM_START_ROW       = 1        // First row for room display
.const ROOM_END_ROW         = 17       // Last row for room display (exclusive)

// UI areas
.const MESSAGE_BAR_ROW      = 0        // Top message bar
.const SENTENCE_BAR_ROW     = 18       // Sentence construction area
.const VERBS_START_ROW      = 19       // Verb list area
.const INVENTORY_ROW        = 24       // Inventory display row

// ============================================================================
// Plus/4 Color Values
// ============================================================================
// Format: High nibble = hue (0-7), Low nibble = luminance (0-7)
// Full range: $00-$7F (128 theoretical, 121 unique colors)

// Basic colors (matching C64 as closely as possible)
.const P4_BLACK             = $00      // 0:0 Black
.const P4_WHITE             = $71      // 7:1 White
.const P4_RED               = $32      // 3:2 Red
.const P4_CYAN              = $63      // 6:3 Cyan
.const P4_PURPLE            = $42      // 4:2 Purple
.const P4_GREEN             = $53      // 5:3 Green
.const P4_BLUE              = $14      // 1:4 Blue
.const P4_YELLOW            = $73      // 7:3 Yellow
.const P4_ORANGE            = $25      // 2:5 Orange
.const P4_BROWN             = $15      // 1:5 Brown
.const P4_LIGHT_RED         = $34      // 3:4 Light Red
.const P4_DARK_GREY         = $02      // 0:2 Dark Grey
.const P4_MEDIUM_GREY       = $03      // 0:3 Medium Grey
.const P4_LIGHT_GREEN       = $55      // 5:5 Light Green
.const P4_LIGHT_BLUE        = $16      // 1:6 Light Blue
.const P4_LIGHT_GREY        = $05      // 0:5 Light Grey

// ============================================================================
// C64 to Plus/4 Color Mapping Table
// ============================================================================
// This table maps C64 color indices (0-15) to Plus/4 color values
// Usage: LDA c64_color : TAX : LDA c64_to_plus4_colors,X

* = * "Plus/4 Color Map"
c64_to_plus4_colors:
    .byte P4_BLACK          // $0: C64 Black
    .byte P4_WHITE          // $1: C64 White
    .byte P4_RED            // $2: C64 Red
    .byte P4_CYAN           // $3: C64 Cyan
    .byte P4_PURPLE         // $4: C64 Purple
    .byte P4_GREEN          // $5: C64 Green
    .byte P4_BLUE           // $6: C64 Blue
    .byte P4_YELLOW         // $7: C64 Yellow
    .byte P4_ORANGE         // $8: C64 Orange
    .byte P4_BROWN          // $9: C64 Brown
    .byte P4_LIGHT_RED      // $A: C64 Light Red
    .byte P4_DARK_GREY      // $B: C64 Dark Grey
    .byte P4_MEDIUM_GREY    // $C: C64 Medium Grey
    .byte P4_LIGHT_GREEN    // $D: C64 Light Green
    .byte P4_LIGHT_BLUE     // $E: C64 Light Blue
    .byte P4_LIGHT_GREY     // $F: C64 Light Grey

// ============================================================================
// Character Set / Tile Constants
// ============================================================================

.const TILE_WIDTH           = 8        // Tile width in pixels
.const TILE_HEIGHT          = 8        // Tile height in pixels
.const TILE_SIZE_BYTES      = 8        // Bytes per character definition
.const CHARSET_SIZE         = 2048     // Full character set size (256 chars × 8 bytes)

// Room tile definitions size (from C64 version)
.const ROOM_TILES_SIZE      = $0800    // 2KB for tile definitions

// ============================================================================
// Compression Constants (from C64 version)
// ============================================================================

.const COMP_DICT_SIZE       = 4        // Dictionary size: 4 bytes
.const COMP_MODE_DIRECT     = $00      // Direct copy mode (bit 7 = 0)
.const COMP_MODE_RUN        = $80      // Run-length mode (bit 7 = 1)
.const COMP_COUNT_MASK      = $7F      // Mask for remaining count (bits 6-0)

// ============================================================================
// Room Resource Constants (from C64 version)
// ============================================================================

.const RSRC_TYPE_ROOM       = $03      // Resource type: Room
.const RSRC_TYPE_ROOM_LAYERS = $04     // Resource type: Room graphics layers

// Room metadata offsets (from room_base + 4)
.const ROOM_META_WIDTH      = $00      // Room width in tiles
.const ROOM_META_HEIGHT     = $01      // Room height in tiles (always $11 = 17)
.const ROOM_META_BG0        = $03      // Background color 0
.const ROOM_META_BG1        = $04      // Background color 1
.const ROOM_META_BG2        = $05      // Background color 2
.const ROOM_META_TILEDEF    = $06      // Offset to tile definitions (16-bit)
.const ROOM_META_TILEMATRIX = $08      // Offset to tile matrix (16-bit)
.const ROOM_META_COLOR      = $0A      // Offset to color layer (16-bit)
.const ROOM_META_MASK       = $0C      // Offset to mask layer (16-bit)

// Room resource on-disk header (before room_base + 4)
.const RSRC_HDR_SIZE_LO     = $00      // Resource header: total size low byte
.const RSRC_HDR_SIZE_HI     = $01      // Resource header: total size high byte
.const RSRC_HDR_TYPE        = $02      // Resource header: type / sentinel ($03 = room)
.const RSRC_HDR_INDEX       = $03      // Resource header: room index
.const RSRC_HDR_BYTES       = $04      // On-disk resource header size (bytes)

// ============================================================================
// Room Index Constants
// ============================================================================

.const ROOM_MAX_INDEX       = $36      // Highest valid room index (54); 55 rooms total (0..54)

// ============================================================================
// 1541 Disk Geometry / Resource Location Tables
// ============================================================================
// The C64 game keeps disk-location tables in memory (loaded from the game disk
// at Track 1, Sector 1, offset $02). Each room resource begins at the start of
// a sector, so a (side, track, sector) triple exactly locates a room.
//
// Table layout (as stored on disk, base offset $7401 in the C64 memory map):
//   room_disk_side_tbl  ($7401) : 1 byte  per room  -> disk side ('1'/'2' style id)
//   room_sec_trk_tbl    ($7438) : 2 bytes per room  -> [SECTOR, TRACK]
//
// We reproduce these tables locally on the Plus/4 by reading the same disk
// bytes into RAM, then indexing them exactly like the original game does.

.const RSRC_TBL_DISK_ADDR   = $7401    // Original C64 in-memory base of the tables
.const RSRC_TBL_SIDE_OFS    = $0000    // room_disk_side_tbl - $7401
.const RSRC_TBL_SECTRK_OFS  = $0037    // room_sec_trk_tbl   - $7401 ($7438 - $7401)
.const RSRC_TBL_BYTES       = $03A2    // Bytes of location tables to read (matches C64 start_game)

// The location tables live on the game disk at Track 1, Sector 1, starting at
// byte offset $02 within that sector (the first 2 bytes are the sector link).
.const RSRC_TBL_DISK_TRACK  = $01      // Track holding the resource location tables
.const RSRC_TBL_DISK_SECTOR = $01      // Sector holding the resource location tables
.const RSRC_TBL_DISK_OFFSET = $02      // Byte offset within that sector to start copying

// Where we stage the room-location tables in Plus/4 RAM
.const RSRC_TBL_BASE        = $6000    // Local copy of the C64 $7401 table block

// 1541 sector-count zones (max 0-based sector index per track)
.const TRK_ZONE1_MAXSEC     = $14      // Tracks  1-17 : 21 sectors (0..20)
.const TRK_ZONE2_MAXSEC     = $12      // Tracks 18-24 : 19 sectors (0..18)
.const TRK_ZONE3_MAXSEC     = $11      // Tracks 25-30 : 18 sectors (0..17)
.const TRK_ZONE4_MAXSEC     = $10      // Tracks 31-35 : 17 sectors (0..16)

.const DISK_SECTOR_SIZE     = 256      // Bytes per 1541 sector

// ============================================================================
// Character Constants
// ============================================================================

.const SPACE_CHAR           = $20      // Screen code / PETSCII space

// ============================================================================
// KERNAL Entry Points (shared)
// ============================================================================

.const CHROUT               = $FFD2    // Output character to current channel

// ============================================================================
// Keyboard Constants
// ============================================================================

.const KEY_NONE             = $FF      // No key pressed
.const KEY_SPACE            = $20      // Space key
.const KEY_RETURN           = $0D      // Return key
.const KEY_LEFT             = $9D      // Cursor left
.const KEY_RIGHT            = $1D      // Cursor right
.const KEY_UP               = $91      // Cursor up
.const KEY_DOWN             = $11      // Cursor down

// ============================================================================
// Generic Constants
// ============================================================================

.const FALSE                = $00
.const TRUE                 = $01
.const NULL                 = $00

// ============================================================================
// Debug and Utility
// ============================================================================

.const DEBUG_BORDER_COLOR   = P4_RED   // Use for debugging (flash border)
.const DEBUG_BG_COLOR       = P4_BLUE  // Use for debugging (background)
