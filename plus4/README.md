# Maniac Mansion - Plus/4 Port

This directory contains the Commodore Plus/4 port of the Maniac Mansion room rendering system.

## Quick Start

### Files in This Directory
- **CONVERSION_NOTES.md** - Comprehensive conversion documentation (read this first!)
- **plus4_constants.inc** - TED chip registers, memory layout, color mappings
- **plus4_decompressor.asm** - Compression decoder (ported from C64)
- **plus4_init.asm** - Plus/4 initialization and setup routines
- **plus4_room_render.asm** - Room rendering engine

### Current Status
**Phase 1: Basic Room Display** - Code complete, awaiting testing

✓ Hardware analysis
✓ Register definitions
✓ Decompressor ported
✓ Initialization code
✓ Room renderer structure
☐ Testing with actual data

## Project Goals

Convert Maniac Mansion from C64 to Plus/4, focusing on room rendering:
- Display rooms on screen (static, no scrolling initially)
- Decompress C64 room data using original compression format
- Map C64 colors to Plus/4's 121-color palette
- Exclude sprites and sound (Plus/4 hardware limitations)

## Architecture Overview

### C64 → Plus/4 Key Changes
- **Video**: VIC-II → TED 7360
- **Colors**: 16 → 121 (mapped)
- **Screen RAM**: $C800/$CC00 → $0C00
- **Character RAM**: $D800 → $1000
- **Sprites**: Hardware → None (excluded)
- **Buffers**: Double → Single

### Memory Layout
```
$0C00 : Screen RAM (40×25)
$1000 : Character definitions (tiles)
$2000 : Tile matrix buffer
$2400 : Color layer buffer
$2800 : Mask layer buffer
```

### Rendering Pipeline
1. Initialize TED chip (`init_plus4`)
2. Load room resource
3. Read room metadata (width, height, colors)
4. Decompress tile definitions → $1000
5. Decompress tile matrix → $2000
6. Decompress color layer → $2400
7. Copy viewport to screen

## Development Roadmap

### Phase 1: Basic Room Display ✓ (Code Complete)
- TED chip initialization
- Single-buffer static display
- Decompression working
- Basic color support

### Phase 2: Scrolling (Not Started)
- Per-column decode snapshots
- Left/right scrolling
- Camera tracking

### Phase 3: Objects and Masking (Not Started)
- Object rendering
- Foreground masking
- Depth sorting

### Phase 4: UI Elements (Not Started)
- Message bar
- Sentence bar
- Verbs and inventory

## Technical Details

### TED Registers Used
```
$FF07 : Video mode (text/bitmap)
$FF13 : Character base address
$FF14 : Screen base address
$FF15 : Background color
$FF19 : Border color
```

### Color Mapping
C64's 16 colors mapped to Plus/4 using hue:luminance:
```
$0 Black  → $00 (0:0)
$1 White  → $71 (7:1)
$2 Red    → $32 (3:2)
$3 Cyan   → $63 (6:3)
... (see plus4_constants.inc for full table)
```

### Compression Format
Unchanged from C64 (hybrid RLE + 4-symbol dictionary):
- 4-byte dictionary initialization
- Control byte determines mode:
  - `00LLLLLL` : Direct (emit L+1 literals)
  - `01LLLLLL` : Ad-hoc run (repeat next byte L+1 times)
  - `1IILLLLL` : Dictionary run (repeat dict[II] L+1 times)

## Testing

To test the port:
1. Obtain C64 room resource data
2. Load into Plus/4 memory
3. Set `room_base` pointer
4. Call `init_plus4`
5. Call `render_room`
6. Verify display

## Documentation

- **CONVERSION_NOTES.md** - Full technical documentation
- **../CLAUDE.md** - Main project guide (includes Plus/4 section)
- **../data_structures.txt** - Room resource format (unchanged)

## Known Limitations

Current limitations (Phase 1):
- Static display only (no scrolling)
- Single buffer (no smooth transitions)
- Basic colors (attributes incomplete)
- No mask layer rendering
- No actors/sprites
- No UI elements

## Future Work

Planned improvements:
- Add scrolling support
- Implement object rendering
- Add mask layer (foreground occlusion)
- Create UI elements
- Optimize rendering performance
- Add input handling

## Contributing

When working on this port:
1. Read CONVERSION_NOTES.md first
2. Preserve C64 data format compatibility
3. Document Plus/4-specific decisions
4. Test incrementally
5. Update documentation

## References

### Plus/4 Resources
- TED 7360 chip documentation
- Plus/4 memory map
- Plus/4 KERNAL/BASIC ROM

### C64 Source
- ../decompressor.asm
- ../room_loader.asm
- ../view.asm
- ../data_structures.txt

## Contact / Status

This is an active conversion project. See ../CLAUDE.md for current status and the main README.md for project context.

**Status**: Phase 1 code complete, awaiting testing
**Next**: Test with actual room data
