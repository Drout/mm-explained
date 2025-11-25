# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a reconstructed and commented disassembly of the C64 implementation of Maniac Mansion, for educational and research purposes. It includes:

- Main game engine code (6502 assembly)
- Custom disk loader system with copy protection
- Roughly 97% of code is commented

**Important**: This is a disassembly of commercial software from the 1980s. All work is for preservation, education, and research. Do not improve or augment malicious code aspects (copy protection that could be used maliciously). Analysis and documentation are appropriate.

## File Organization

The codebase is organized into functional modules (33 .asm files) plus supporting documentation:

### Core Engine Files
- `init_engine.asm` - System initialization, memory setup, IRQ configuration
- `memory_mgmt.asm` - Dynamic memory allocator with best-fit allocation, compaction, and coalescing
- `irq_handlers.asm` - Raster interrupt chain for VIC-II timing and sprite multiplexing

### Actor/Animation System
- `actor.asm` - Actor state management
- `actor_animation.asm` - Animation frame sequencing
- `actor_motion.asm` - Movement and pathfinding integration
- `render_actor.asm` - Actor sprite rendering
- `pathing.asm` - Pathfinding within walkboxes

### Rendering System
- `view.asm` - Camera and viewport management
- `camera.asm` - Camera positioning and scrolling
- `blit_cel.asm` - Cel (sprite frame) blitting
- `render_object.asm` - Object rendering
- `masking.asm` - Foreground masking for depth

### Room/Resource Management
- `room_loader.asm` - Room loading and initialization
- `room_gfx_rsrc.asm` - Room graphics resource handling
- `rsrc_mgmt.asm` - General resource management
- `decompressor.asm` - Custom compression format decoder

### UI/Input
- `ui_interaction.asm` - User interface interaction logic
- `ui_messages.asm` - Message display system
- `cursor.asm` - Cursor management
- `input_scan.asm` - Input scanning and processing
- `key_handler.asm` - Keyboard handling

### Game Logic
- `sentence_action.asm` - Sentence-based action execution (verb+object)
- `sentence_text.asm` - Sentence construction and text generation
- `destination.asm` - Actor destination management
- `walkbox.asm` - Walkbox (navigable area) system

### Disk I/O
- `disk_high_level.asm` - High-level disk operations
- `disk_low_level.asm` - Low-level disk operations
- `loader/` - Multi-stage fast loader with copy protection (10 stages)

### Metadata and Constants
- `constants.inc` - Game constants and magic values
- `globals.inc` - Zero-page and global variable definitions
- `registers.inc` - Hardware register definitions
- `data_structures.txt` - Comprehensive data structure documentation (700 lines)
- `hotspots_metadata.inc` - Hotspot definitions
- `rsrc_metadata.inc` - Resource metadata
- `text_data.inc` - Text string data

### Documentation
- `maniac_mansion_main_code.txt` - Memory map and high-level overview
- `diagrams/` - Memory layout and loader flow diagrams
- `loader/loader overview.txt` - Fast loader architecture explanation

## Architecture Overview

### Memory Management
The game uses a custom dynamic memory allocator managing variable-size blocks:
- **Allocation**: Best-fit scan with optional splitting
- **Deallocation**: Append to free list, normalize by address order, coalesce adjacent blocks
- **Compaction**: "Bubble left" algorithm moves used blocks over leading free space
- **Block header**: 4 bytes (size lo/hi, next lo/hi for free blocks; size lo/hi, type, index for used blocks)

Key routines: `mem_alloc` (resilient wrapper with retry), `mem_release`, `mem_alloc_bestfit`, `mem_compact_leading_free`, `mem_sort_free_ao`, `mem_coalesce_right`

### Resource System
Resources are typed and indexed:
- **Types**: Object (1), Costume (2), Room (3), Room Layers (4), Script (5), Sound (6)
- **Formats**: Custom compression using 4-byte symbol dictionaries
- **Loading**: Multi-stage: allocate → load from disk → decompress → relocate

Room resources contain: tile definitions, tile matrix, color layer, mask layer, objects, bounding boxes, sounds, scripts (entry/exit)

### Costume/Animation System
Hierarchical animation structure:
1. **Costume** - Visual structure for an actor (8 limbs max)
2. **Limb** - Independently animated body part
3. **Cel** - Single frame bitmap (6-byte header + row data)
4. **Cel sequence** - Ordered list of cels (animation cycle for one limb)
5. **Clip** - Full-body animation combining one cel sequence per limb (8 bytes, one per limb)

Clips encode: `bit7=flip, bits6..0=cel_sequence_index, $FF=unused_limb`

Indirection layers: Clip table → Cel sequences table → Cel index table → Cel offset tables (lo/hi) → Cel data

### Rendering and Display
**Triple-buffer approach**:
- Two screen buffers ($C800, $CC00) alternate as front/back buffers
- Color RAM buffer ($6D89-$7030) copied to hardware color RAM

**Raster IRQ chain**: 17 handlers divide frame into bands:
- `irq_handler1` (line 251) - Frame setup, video mode changes, sprite shape updates
- `irq_handler2..16` - Sprite multiplexing (reposition 4 hardware sprites for multiple actors)
- `irq_handler17` (line 195) - UI/input/sound housekeeping, cursor update

**Sprite multiplexing**: 4 hardware sprites reused for multiple logical actors by changing Y position, shape, and X position during vertical blank between bands (21-pixel spacing)

### Walkbox System
Rectangular navigable regions with optional diagonal boundaries:
- 5-byte record: LEFT, RIGHT, TOP, BOTTOM, ATTR
- ATTR.bit7=1 enables diagonal handling (slope codes $08=up-left, $0C=down-right)
- Pathfinding uses walkbox connectivity graph

### Sentence-Based Interface
Player constructs sentences: `[VERB] [OBJECT1] [PREPOSITION] [OBJECT2]`
- Verbs: Open, Close, Give, Turn On/Off, Fix, New Kid, Unlock, Push, Pull, Use, Read, Walk To, Pick Up, What Is
- Prepositions: None, With, To
- Sentence stack: 6 tokens max, $FF = empty

Action execution: Parse sentence → validate preposition needs → execute verb handler script

### Disk Loader
10-stage fast loader system:
1. Load hijack (BASIC warm-start vector overwrite)
2. Autoloader (load next stage)
3. Drive configurator (send code to 1541)
4. Drive job setup (validate, fingerprint ROM)
5. Drive fast send (custom GCR decoder, stream sectors)
6. Computer fast receive (CIA2 bit-pair sampling)
7. Intermediate decryptor (XOR stream)
8. Integrity checks (U1 sector fingerprint, B-E protection block, M-R drive RAM)
9. Drive copy-protection check (half-track sweep 35.0→35.5→36.0)
10. Final decryptor (3-byte mixer from checksums)

Copy protection influences decryption keys; wrong disk → wrong keys → unrunnable code.

## Key Technical Details

### Zero-Page Usage
Critical ZP pointers (see `globals.inc`):
- `$19-$1A` - Multi-purpose pointer (fill_dest_ptr, copy_src, fill_ptr)
- `$1B-$1C` - Multi-purpose counter (fill_byte_cnt, copy_dest, fill_count)
- `$27-$28` - decomp_src_ptr (decompressor input)
- `$84-$85` - cel_seq_tbl (current actor cel sequence table)
- `$86-$87` - mask_row_ptr (foreground mask layer)

### VIC-II Memory Layouts
Two alternating layouts for double-buffering:
- Layout 1: Screen $C800, Char $D800, Sprites $CBF8
- Layout 2: Screen $CC00, Char $D800, Sprites $CFF8

Video setup modes (`video_setup_mode`):
- $00 = No change
- $01 = Switch to layout 1 + copy color RAM
- $02 = Switch to layout 2 + copy color RAM
- $03 = Copy color RAM only

### Actor Attributes
`object_attributes` nibble/bit encoding:
- Bit 7: Requires render overlay
- Bit 6: Unused
- Bit 5: Removed from room (location ignored)
- Bits 3-0: Owner ($0F=in room, $0D=limbo, $01-$07=kid index)

### Important Constants
- `ROOM_MAX_INDEX = $36` (54 rooms)
- `COSTUME_MAX_INDEX = $18` (24 costumes)
- `SCRIPT_MAX_INDEX = $9F` (159 scripts)
- `SOUND_MAX_INDEX = $45` (69 sounds)
- `ACTOR_COUNT_TOTAL = 4` (0..3)
- `VIEW_ROWS = $11` (17 tiles), `VIEW_COLS = $28` (40 tiles)

## Working with This Code

### Navigation Tips
- Start with `data_structures.txt` for comprehensive data format documentation
- `constants.inc` and `globals.inc` are essential references
- Each .asm file has detailed header comments explaining its purpose
- `maniac_mansion_main_code.txt` provides memory map overview
- Use file:line references like `actor_motion.asm:712` when discussing code

### Common Patterns
- **Resource access**: Check type byte at offset +$02, index at +$03
- **Memory block traversal**: Read 4-byte header, size includes header
- **Decompression**: 4-byte dictionary at start, followed by compressed stream
- **Actor state**: Check `actor_state` ($02=stopped), `anim_flags` ($20=refresh, $01=needs_draw)
- **Direction codes**: $00=right, $01=left, $80=down, $81=up

### Addressing Modes
6502 assembly addressing modes used throughout:
- Immediate: `LDA #$42`
- Zero-page: `LDA $19`
- Absolute: `LDA $C800`
- Indexed: `LDA $C800,X` or `LDA ($19),Y`
- Indirect: `JMP ($FFFE)`

### Code Style
- Labels use snake_case: `mem_alloc_bestfit`, `irq_handler1`
- Constants use UPPER_SNAKE_CASE: `RSRC_TYPE_COSTUME`, `CLIP_STAND_RIGHT`
- Extensive inline comments explain logic and data flow
- Multi-line comment blocks describe algorithms and data structures

## Analysis Guidelines

When analyzing or documenting this code:

1. **Respect the historical context**: This is 1980s commercial software with sophisticated techniques for its era (sprite multiplexing, custom compression, fast loaders, copy protection)

2. **Cross-reference data structures**: Use `data_structures.txt` to understand binary formats; actual parsing code is scattered across multiple files

3. **Follow the flow**:
   - Boot: loader stages 1-10 → decrypt → jump to $0400
   - Game loop: IRQ chain → actor updates → rendering → input → repeat
   - Room transition: release old room → load new room → decompress → initialize actors

4. **Memory constraints**: C64 has 64KB RAM, with I/O and ROM in address space. Memory manager aggressively reclaims space. Understanding memory pressure is key to understanding design decisions.

5. **Timing is critical**: Raster IRQ handlers run on tight schedules. Code is optimized for cycle counts, not readability.

## File Conventions

- `.asm` - Assembly source (KickAssembler dialect)
- `.inc` - Include files (constants, globals, registers, metadata)
- `.txt` - Documentation and annotated disassembly
- No build system - these are reference disassemblies, not reassemblable source

## Additional Notes

- 6502 CPU: 8-bit accumulator, X/Y index registers, zero-page addressing
- VIC-II graphics chip: 320x200 multicolor bitmap or 40x25 text mode
- SID sound chip: 3 voices, filters, ADSR envelopes
- 1541 disk drive: 6502 CPU, GCR encoding, programmable via serial bus
- Memory banking: CPU port $01 controls ROM/RAM/I/O visibility

The loader demonstrates sophisticated copy protection that was common in commercial C64 software. This is documented for historical preservation.

---

# Plus/4 Conversion Project

## Overview

An active conversion project is underway to port the Maniac Mansion room rendering system from Commodore 64 to Commodore Plus/4. This is a progressive port focusing initially on basic functionality before expanding to full features.

**Current Phase**: Phase 1 - Basic Room Display

**Scope Limitations**: Sprites and sound are explicitly excluded from the initial port.

## Plus/4 Hardware Differences

### TED Chip vs VIC-II
The Plus/4 uses the TED 7360 (Text Editing Device) instead of the VIC-II:
- **No hardware sprites** - Software sprites would need to be implemented
- **Different color system** - 121 colors (16 hues × 8 luminance levels) vs 16 fixed colors
- **Simplified video architecture** - No separate color RAM hardware
- **TED registers at $FF00-$FF3F** vs VIC-II at $D000-$D02E
- **Single video bank** vs VIC-II's 4 configurable banks
- **No raster IRQ sprite multiplexing needed** (no sprites to multiplex)

### Memory Map Changes
- **Screen RAM**: $0C00 (Plus/4) vs $C800/$CC00 (C64 double-buffer)
- **Character RAM**: $1000 (Plus/4) vs $D800 (C64)
- **No I/O hole**: Plus/4 has simpler banking, no $D000-$DFFF I/O conflict
- **Color handling**: Integrated with character attributes vs separate color RAM

## Port Architecture

### Directory Structure
```
plus4/
├── CONVERSION_NOTES.md          # Detailed conversion documentation
├── DATA_PREP_GUIDE.md           # Guide for extracting/preparing room data files
├── README.md                    # Quick start guide
├── plus4_constants.inc          # TED registers, color maps, memory layout
├── plus4_decompressor.asm       # Compression decoder (direct port)
├── plus4_init.asm               # System initialization
├── plus4_loader.asm             # Standard IEC disk loader (NEW)
├── plus4_room_render.asm        # Simplified room renderer
└── plus4_main.asm               # Main program and test harness (NEW)
```

### Completed Components

#### 1. Constants and Register Definitions (`plus4_constants.inc`)
- TED register definitions ($FF00-$FF3F)
- Memory layout constants
- C64-to-Plus/4 color mapping table (16 C64 colors → 121 Plus/4 colors)
- Screen layout definitions (40×25, with 40×17 room viewport)
- Compression format constants (unchanged from C64)

#### 2. Decompressor (`plus4_decompressor.asm`)
Direct port of C64 decompressor with minimal changes:
- **Algorithm unchanged**: Hybrid RLE + 4-symbol dictionary
- **Pure CPU code**: No hardware dependencies
- **Control byte formats preserved**:
  - Direct mode: `00LLLLLL` (emit L+1 literal bytes)
  - Ad-hoc run: `01LLLLLL` + byte (repeat L+1 times)
  - Dictionary run: `1IILLLLL` (repeat dict[II] L+1 times)
- **Entry points**: `decomp_dict4_init`, `decomp_stream_next`, `decomp_skip_16bit`, `decomp_skip_8bit`

#### 3. Initialization (`plus4_init.asm`)
- TED chip setup for text mode
- Screen and character base configuration
- Background and border color setup
- Screen clearing utility
- C64 color conversion helper
- Test pattern routine for debugging

#### 4. Room Renderer (`plus4_room_render.asm`)
Simplified single-buffer renderer:
- Read room metadata (width, height, colors, layer offsets)
- Decompress tile definitions → character RAM ($1000)
- Decompress tile matrix → temporary buffer ($2000)
- Decompress color layer → temporary buffer ($2400)
- Copy visible 40×17 viewport to screen RAM

**Simplifications from C64 version**:
- Single buffer only (no double-buffering)
- No scrolling support yet
- No sprite rendering
- No raster IRQ chain
- Static display only

#### 5. Disk Loader (`plus4_loader.asm`)
Standard IEC disk loader using KERNAL calls (replaces C64's 10-stage fast loader):
- **KERNAL-based I/O**: Uses `SETLFS`, `SETNAM`, `OPEN`, `LOAD`, `CLOSE`, `CHKIN`, `CHRIN`
- **Simple file loading**: `load_file` - Load complete file to memory
- **Streaming mode**: `load_file_streaming` - Byte-by-byte reading for processing
- **Room loader**: `load_room` - Loads rooms by number using "ROOMnn" naming convention
- **Filename builder**: Converts room index (0-54) to "ROOM00"-"ROOM54" format
- **Error handling**: `read_disk_status` reads drive error messages
- **Standard device**: Device 8 (1541/1551 compatible)

**Key differences from C64**:
- No custom serial protocol - uses standard IEC
- No drive-side code - all KERNAL-based
- Slower but simpler and more compatible
- No copy protection checks
- Room-per-file structure vs streaming

#### 6. Main Program (`plus4_main.asm`)
Test harness and entry point:
- BASIC upstart (loads at $1001, starts at $1100)
- Interactive room browser:
  - **Space**: Reload current room
  - **←/→**: Previous/next room (wraps around)
  - **Q**: Quit to BASIC
- Startup sequence: Init hardware → Init disk → Load room → Render
- Error handling with disk status display
- Room data loaded to $4000

### Key Conversion Decisions

#### Color Mapping Strategy
Mapped C64's 16 colors to closest Plus/4 equivalents using hue:luminance notation:
```
C64 Black    ($0) → Plus/4 $00 (0:0)
C64 White    ($1) → Plus/4 $71 (7:1)
C64 Red      ($2) → Plus/4 $32 (3:2)
C64 Cyan     ($3) → Plus/4 $63 (6:3)
[... etc, see plus4_constants.inc for full table]
```

#### Memory Layout
```
$0C00-$0FFF : Screen RAM (1000 bytes)
              Rows 1-17 used for room display (40×17 = 680 bytes)
              Row 0 for message bar, rows 18+ for UI
$1000-$1FFF : Character definitions (tiles)
$2000-$23FF : Decompressed tile matrix (temporary buffer)
$2400-$27FF : Decompressed color layer (temporary buffer)
$2800-$2BFF : Decompressed mask layer (temporary buffer)
$4000+      : Room data, game logic, resources
```

#### Rendering Pipeline (Plus/4)
1. Load room resource into memory
2. Parse room metadata header (width, height, colors, offsets)
3. Set background color from room metadata (converted from C64 color)
4. Decompress tile definitions to $1000 (2KB character RAM)
5. Decompress tile matrix to $2000 (width × height bytes)
6. Decompress color layer to $2400 (width × height bytes)
7. Copy visible 40×17 portion to screen RAM starting at row 1

#### Data File Structure
**File naming**: Rooms stored as separate files: `ROOM00`, `ROOM01`, ... `ROOM54`

**File format** (identical to C64 resource format):
```
Offset  Size  Description
------  ----  -----------
+$00    2     Size (lo/hi)
+$02    1     Type ($03 = room)
+$03    1     Room index
+$04    ...   Room data (metadata + compressed layers)
```

**Loading process**:
1. Build filename from room number (e.g., 5 → "ROOM05")
2. Use KERNAL `LOAD` to read file into memory at $4000
3. Set `room_base` to $4004 (skip 4-byte header)
4. Parse and render

**Disk layout**: All 55 rooms (~150-250KB total) fit on single 1541 disk

**Compatibility**: Same data format as C64 - no conversion needed, just extraction to individual files

### Deferred Features

**Phase 2 - Scrolling** (Not yet implemented):
- Per-column decode snapshots
- Left/right scrolling with column-wise decompression
- Camera tracking

**Phase 3 - Objects and Masking** (Not yet implemented):
- Object rendering
- Mask layer for foreground occlusion
- Depth sorting

**Phase 4 - UI Elements** (Not yet implemented):
- Message bar (row 0)
- Sentence bar (row 18)
- Verb list (rows 19-23)
- Inventory display

**Not Planned**:
- Hardware sprites (Plus/4 doesn't have them)
- Sound system (different chip - TED vs SID)
- Raster IRQ multiplexing (not needed without sprites)

## Working with Plus/4 Port

### File Relationships
- **plus4_constants.inc** - Analogous to `constants.inc` + `registers.inc`
- **plus4_decompressor.asm** - Direct port of `decompressor.asm`
- **plus4_init.asm** - Subset of `init_engine.asm` functionality
- **plus4_room_render.asm** - Simplified version of `view.asm` + `room_gfx_rsrc.asm`

### Zero-Page Usage (Plus/4 Port)
Maintains similar ZP allocation to C64 version:
- `$27-$28` - decomp_src_ptr (decompressor input pointer)
- `$29` - decomp_emit_mode (direct/run mode flag)
- `$2A` - decomp_emit_rem (remaining count)
- `$2B` - decomp_run_symbol (run byte value)
- `$C3-$C4` - room_base (room resource pointer)
- `$15-$16` - dest_ptr (general destination pointer)

### TED Register Reference (Most Used)
```
$FF07 : TED_VIDEO_MODE        # Text/bitmap, multicolor
$FF13 : TED_CHAR_BASE         # Character generator base / 1024
$FF14 : TED_SCREEN_BASE       # Screen memory base / 1024
$FF15 : TED_BG_COLOR          # Background color
$FF19 : TED_BORDER_COLOR      # Border color
$FF1C : TED_RASTER_LO         # Current raster line (low)
```

### Current Limitations
1. **Static display only** - No scrolling, no camera movement
2. **Single buffer** - No smooth transitions between rooms
3. **Basic color support** - Color attributes not fully implemented
4. **No mask layer rendering** - Objects don't occlude properly
5. **No actors** - Would require software sprite implementation
6. **No UI** - Message bar, verbs, inventory not implemented

### Testing Strategy

#### Data Preparation
1. **Extract room data from C64**:
   - Use emulator memory dump or disk extraction
   - Each room is a resource with 4-byte header + data
   - See `DATA_PREP_GUIDE.md` for detailed instructions

2. **Create disk image**:
   - Name files ROOM00 through ROOM54 (two digits)
   - Use c1541 or DirMaster to create D64
   - All 55 rooms fit on single 1541 disk

3. **Verify files**:
   - Check filename format (exactly "ROOMnn")
   - Verify byte 2 = $03 (room type)
   - Verify byte 3 = room index

#### Running the Test Program
1. Load `plus4_main.prg` on Plus/4
2. Insert disk with room files
3. Run program
4. Use keys:
   - **Space**: Reload room
   - **←/→**: Browse rooms
   - **Q**: Quit
5. Verify display and colors

### Next Steps for Development
1. **Test basic display** - Verify decompression and rendering work
2. **Debug color handling** - Plus/4 color attributes need refinement
3. **Add scrolling** - Port per-column snapshot system
4. **Implement camera** - Track viewport position in wide rooms
5. **Add object rendering** - Decompress and display room objects
6. **Implement masking** - Foreground occlusion for depth

## Conversion Progress Tracking

**Status**: ✓ Phase 1 code complete, awaiting testing

### Completed (Phase 1)
- [x] Hardware analysis and documentation
- [x] TED register definitions
- [x] Memory map planning
- [x] Color mapping table
- [x] Decompressor port
- [x] Initialization code
- [x] Basic room renderer structure
- [x] Standard IEC disk loader
- [x] Main program and test harness
- [x] Data preparation documentation

### Pending (Phase 1)
- [ ] Test with actual room data
- [ ] Debug rendering issues
- [ ] Verify color display
- [ ] Create test harness program

### Future Phases
- [ ] Phase 2: Scrolling support
- [ ] Phase 3: Objects and masking
- [ ] Phase 4: UI elements
- [ ] Phase 5: Input handling
- [ ] Phase 6: Game logic (if desired)

## Reference Materials

### Plus/4 Specific
- **CONVERSION_NOTES.md** - Comprehensive conversion documentation with hardware comparison, implementation plan, and technical details
- **DATA_PREP_GUIDE.md** - How to extract room data from C64 and prepare disk files
- **README.md** - Quick start guide for the Plus/4 port
- **plus4_constants.inc** - All TED registers, memory locations, and constants
- **plus4_loader.asm** - Standard IEC disk loading routines
- **plus4_main.asm** - Test program with interactive room browser
- TED chip datasheet (external reference recommended)

### C64 Source Materials
- **data_structures.txt** - Room resource format (unchanged)
- **decompressor.asm** - Original compression algorithm
- **room_loader.asm** - Room loading logic
- **view.asm** - Rendering pipeline architecture

### Key Differences Summary
| Feature | C64 | Plus/4 Port |
|---------|-----|-------------|
| Video chip | VIC-II | TED 7360 |
| Colors | 16 fixed | 121 (mapped from 16) |
| Sprites | 8 hardware | None (excluded) |
| Screen RAM | $C800/$CC00 | $0C00 |
| Char RAM | $D800 | $1000 |
| Color RAM | Hardware $D800 | Attributes in screen RAM |
| Buffers | Double | Single (initially) |
| Scrolling | Hardware + software | Software only |
| IRQ chain | 17 handlers | Not needed |

## Contributing to Plus/4 Port

When working on the Plus/4 conversion:
1. Preserve the C64 decompression format (unchanged data files)
2. Document Plus/4-specific technical decisions
3. Keep Phase 1 simple (static display only)
4. Test incrementally with known room data
5. Update CONVERSION_NOTES.md with findings
6. Consider Plus/4 hardware limitations (no sprites, different timing)
7. Maintain code comments explaining deviations from C64 version
