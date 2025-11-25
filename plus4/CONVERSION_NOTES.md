# Maniac Mansion C64 to Plus/4 Conversion Notes

## Project Goal
Port the room rendering system from Commodore 64 to Commodore Plus/4, initially ignoring sprites and sound to focus on getting rooms displayed on screen.

## Hardware Comparison

### Commodore 64 (VIC-II)
- **Video chip**: VIC-II (6567/6569)
- **Colors**: 16 fixed colors
- **Sprites**: 8 hardware sprites, 24×21 pixels each
- **Screen modes**: Multiple bitmap and text modes, multicolor support
- **Memory map**: I/O at $D000-$DFFF, Color RAM at $D800-$DBFF (1K, 4-bit nibbles)
- **Video bank**: Configurable via CIA2, 16K banks
- **Raster IRQ**: Precise raster line interrupts for multiplexing

### Commodore Plus/4 (TED)
- **Video chip**: TED 7360 (Text Editing Device)
- **Colors**: 121 colors (16 hues × 8 luminance levels, minus 1 duplicate)
- **Sprites**: None (software sprites only)
- **Screen modes**: Text 40×25, multicolor text, bitmap, multicolor bitmap
- **Memory map**: TED registers at $FF00-$FF3F, no separate color RAM
- **Video memory**: Standard RAM, no banking constraints
- **Raster IRQ**: Available but less commonly used

## C64 Room Rendering Architecture

### Memory Layout (C64)
```
$C800-$CACF : Room scene frame buffer #1 (40×17 tiles = 680 bytes)
$CC00-$CC27 : Message bar (40 bytes)
$CC28-$CECF : Room scene frame buffer #2 (40×17 tiles = 680 bytes)
$CED0-$CEF7 : Sentence bar (40 bytes)
$D000-$D7FF : Tile definitions (2048 bytes, banked under I/O)
$D800-$D827 : Message bar color
$D828-$DACF : Room scene color (copied from buffer)
$E000-$E800 : Sprite data bank 1
$E800-$F000 : Sprite data bank 2
$F800-$FBFF : Text character definitions (1024 bytes)

Color buffer (before copy to $D828):
$6D89-$7030 : Room scene color RAM buffer (680 bytes)

Mask layer:
$6AE1-$6D88 : Room scene mask layer (680 bytes)
```

### Rendering Pipeline (C64)
1. **Load room resource** - Contains compressed tile matrix, color layer, mask layer
2. **Decompress layers**:
   - Tile definitions → $D800 (8×8 char defs, ~2KB)
   - Tile matrix → frame buffer (which tile per cell)
   - Color layer → color buffer → hardware color RAM
   - Mask layer → mask buffer (for foreground occlusion)
3. **Scrolling**:
   - Shift 39 bytes per row left/right
   - Decode only newly revealed column (17 tiles)
   - Uses per-column snapshots for O(1) resume
4. **IRQ chain**: 17 handlers for sprite multiplexing and mode changes

### Compression Format
- **RLE-like scheme**: 4-byte symbol dictionary, then compressed stream
- **Two modes**: Direct copy or run-length encoding
- **Packed state**: bit7=mode, bits6..0=remaining count
- **Per-column snapshots**: Source pointer, packed mode+count, run symbol

## Plus/4 Port Strategy

### Phase 1: Basic Room Display (Current Focus)
- [x] Analyze C64 rendering system
- [ ] Create Plus/4 register definitions
- [ ] Port decompressor (CPU code, should work unchanged)
- [ ] Implement single-buffer room rendering
- [ ] Display static room (no scrolling yet)

### Phase 2: Scrolling
- [ ] Port scrolling logic
- [ ] Adapt per-column decode snapshots
- [ ] Implement smooth scrolling

### Phase 3: Objects and Masking
- [ ] Port object rendering
- [ ] Adapt masking system
- [ ] Implement depth sorting

### Phase 4: UI Elements
- [ ] Message bar
- [ ] Sentence bar
- [ ] Verb/inventory display

### Phases Explicitly Excluded
- ~~Sprite system~~ (no hardware sprites on Plus/4)
- ~~Sound system~~ (different sound chip)
- ~~Raster IRQ multiplexing~~ (not needed without sprites)

## Plus/4 Implementation Plan

### Memory Layout (Plus/4 - Proposed)
```
$0C00-$0FFF : Screen RAM (1000 bytes, 40×25)
              Use rows 4-20 for room (40×17 = 680 bytes)
$1000-$1FFF : Character definitions (4KB)
              Tile definitions here
$2000-$3FFF : Additional graphics/data area
$4000-$BFFF : Room data, game logic, decompressed layers
```

### TED Register Mapping (Key Registers)
```
$FF06 : Keyboard scan
$FF07 : Background color
$FF08 : Character/bitmap mode control
$FF09-$FF0B : Color registers
$FF0C-$FF0D : Character blink/reverse
$FF0E-$FF0F : Border colors
$FF12-$FF13 : Character base / screen base address
$FF14 : Video address high / character base
$FF15 : Screen position
$FF1A : Raster counter low
$FF1B : Raster counter high
$FF1C : Horizontal position
$FF1D : Vertical position
$FF1E : Horizontal scroll
$FF1F : Vertical scroll
```

### Color Mapping
Map C64's 16 colors to closest Plus/4 equivalents:
```
C64 → Plus/4 (hue:luminance notation)
$0 Black    → $00 (0:0 Black)
$1 White    → $71 (7:1 White)
$2 Red      → $32 (3:2 Red)
$3 Cyan     → $63 (6:3 Cyan)
$4 Purple   → $42 (4:2 Purple)
$5 Green    → $53 (5:3 Green)
$6 Blue     → $14 (1:4 Blue)
$7 Yellow   → $73 (7:3 Yellow)
$8 Orange   → $25 (2:5 Orange)
$9 Brown    → $15 (1:5 Brown)
$A Lt Red   → $34 (3:4 Light Red)
$B Dk Grey  → $02 (0:2 Dark Grey)
$C Md Grey  → $03 (0:3 Medium Grey)
$D Lt Green → $55 (5:5 Light Green)
$E Lt Blue  → $16 (1:6 Light Blue)
$F Lt Grey  → $05 (0:5 Light Grey)
```

### Technical Changes Required

#### 1. Register Access
- Replace all `$D011`-`$D02E` (VIC-II) with `$FF06`-`$FF1F` (TED)
- Remove color RAM special handling ($D800-$DBFF doesn't exist)
- Update memory banking (no CIA2 bank switching needed)

#### 2. Video Setup
- Simplify to single frame buffer (no raster tricks)
- Set TED character base register
- Configure text mode with correct screen base
- Remove IRQ chain (not needed without sprites)

#### 3. Color Handling
- Store colors directly in screen RAM attributes (no separate color RAM)
- Convert color values using mapping table
- Possibly use luminance for lighting effects

#### 4. Decompressor
- Should work unchanged (pure CPU code)
- May need memory address adjustments
- Keep 4-byte dictionary format

#### 5. Scrolling
- Software scrolling only (copy bytes)
- No hardware smooth scrolling initially
- Per-column decode can stay the same

## Current Status

**Completed:**
- Analysis of C64 room rendering system
- Understanding of compression format
- Hardware comparison documentation

**In Progress:**
- Plus/4 register definitions file creation
- Memory map planning

**Next Steps:**
1. Create `plus4_constants.inc` with TED registers
2. Create `plus4_init.asm` for basic Plus/4 initialization
3. Port `decompressor.asm` (minimal changes expected)
4. Create `plus4_room_render.asm` for simplified rendering
5. Test with one hardcoded room

## Testing Strategy

### Minimal Test Program
1. Initialize Plus/4 (screen mode, colors)
2. Load one room resource
3. Decompress tile definitions to character RAM
4. Decompress tile matrix to screen RAM
5. Set colors appropriately
6. Display static image

### Success Criteria
- Room graphics visible on screen
- Correct colors displayed
- No corruption or crashes

## Files to Create

### Core Plus/4 Files
- `plus4/plus4_constants.inc` - TED registers, color mappings
- `plus4/plus4_init.asm` - Initialization code
- `plus4/plus4_room_render.asm` - Room rendering
- `plus4/plus4_test.asm` - Test harness
- `plus4/CONVERSION_NOTES.md` - This file

### Modified C64 Files (Adapted)
- Port from `decompressor.asm`
- Adapt from `room_loader.asm`
- Simplify from `view.asm`

## Known Challenges

1. **No hardware sprites**: Actors will need software sprites or different representation
2. **Different color system**: May not perfectly match original look
3. **Memory constraints**: Plus/4 has less RAM (64K vs C64's effective 64K with banking)
4. **Performance**: Software rendering may be slower than C64's hardware features
5. **Masking**: Foreground occlusion may need different approach

## Future Enhancements (Beyond Initial Goal)

- Software sprites for actors
- Sound using Plus/4's TED sound capabilities
- Save/load game functionality
- Input handling (keyboard/joystick)
- Full game logic port
- Optimization for Plus/4's specific architecture
