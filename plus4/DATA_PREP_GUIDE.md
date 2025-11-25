# Data Preparation Guide for Plus/4 Port

This guide explains how to extract room data from the C64 version and prepare it for the Plus/4 port.

## Overview

The Plus/4 port uses the **same room data format** as the C64 version, but loads files using standard IEC calls instead of the custom fast loader. Each room is stored as a separate file on disk.

## File Naming Convention

Rooms are named using the pattern: `ROOMnn`

Where `nn` is a two-digit decimal room number:
- `ROOM00` - Room 0
- `ROOM01` - Room 1
- ...
- `ROOM09` - Room 9
- `ROOM10` - Room 10
- ...
- `ROOM54` - Room 54 (last room, $36 in hex)

## Room File Format

Each room file contains:

```
Offset  Size  Description
------  ----  -----------
+$00    2     Resource size (16-bit, lo/hi)
+$02    1     Resource type ($03 = room)
+$03    1     Room index (0-54)
+$04    ...   Room data (see below)
```

### Room Data Structure (offset +$04 onwards)

```
Offset  Size  Description
------  ----  -----------
+$00    1     Width (in tiles)
+$01    1     Height (in tiles, always $11 = 17)
+$02    1     Video flag (usually $00)
+$03    1     Background color 0
+$04    1     Background color 1
+$05    1     Background color 2
+$06    2     Offset to tile definitions (compressed)
+$08    2     Offset to tile matrix (compressed)
+$0A    2     Offset to color layer (compressed)
+$0C    2     Offset to mask layer (compressed)
+$0E    2     Offset to mask indexes (compressed)
+$10    1     Object count
+$11    1     Boundary box start offset
+$12    1     Sound count
+$13    1     Script count
+$14    2     Exit script offset
+$16    2     Entry script offset
+$18+   ...   Variable-length sections (objects, sounds, scripts)
```

All multi-byte offsets are stored little-endian (lo byte, hi byte).

## Extraction Process

### Method 1: From C64 Memory Dump

If you have the C64 version running in an emulator:

1. **Load a room in C64 emulator**
   - Get to the point where a room is loaded
   - Use monitor/debugger to find room resource in memory

2. **Locate room resource**
   - Room resources are type $03
   - Search for 4-byte header: `size_lo size_hi 03 room_index`
   - Note the address

3. **Dump to file**
   - Save memory from `address` to `address + size`
   - Name file according to room index (e.g., `ROOM05`)

4. **Repeat for all rooms**
   - Load each room (0-54)
   - Dump each to separate file

### Method 2: From C64 Disk Image

If you have the original C64 disk files:

1. **Extract disk image**
   - Use tool like `c1541` or disk image editor
   - Extract all room files

2. **Identify room data**
   - C64 version may have different file structure
   - May need to parse loader format

3. **Repackage for Plus/4**
   - Ensure 4-byte header is present
   - Save as sequential files

### Method 3: Manual Extraction

For research/preservation purposes:

1. **Disassemble C64 data**
   - Find room data in disassembly
   - Locate compressed data streams

2. **Extract raw bytes**
   - Copy entire room resource
   - Include all compressed layers

3. **Create SEQ files**
   - Write as sequential files for disk

## Compression Format (Preserved)

The room data uses **hybrid RLE + 4-symbol dictionary compression**:

### Compressed Sections
Each compressed section starts with:
- **4-byte dictionary** (symbols 0-3)
- **Compressed stream** (control bytes + data)

### Control Byte Format
- `00LLLLLL` - Direct mode: copy next (L+1) bytes literally
- `01LLLLLL` + byte - Ad-hoc run: repeat byte (L+1) times
- `1IILLLLL` - Dictionary run: repeat dict[II] (L+1) times

This format is **unchanged** from C64 - the Plus/4 decompressor is a direct port.

## Creating Disk Image for Plus/4

### Using c1541 (Command-Line Tool)

```bash
# Create new disk image
c1541 -format "maniac,01" d64 maniac.d64

# Add room files
c1541 maniac.d64 -write room00.prg "ROOM00"
c1541 maniac.d64 -write room01.prg "ROOM01"
# ... repeat for all rooms

# Verify
c1541 maniac.d64 -dir
```

### Using GUI Tool (e.g., DirMaster)

1. Create new D64 image
2. Drag/drop room files
3. Rename to "ROOM00", "ROOM01", etc.
4. Save image

### File Type Considerations

- **SEQ files** (Sequential) - Recommended, simplest
- **PRG files** (Program) - Also works, but load address is ignored
- **USR files** (User) - Can work, treated as SEQ

The loader uses KERNAL `LOAD` which handles all these types.

## Testing Individual Room Files

### Test Program (Plus/4 BASIC)

```basic
10 REM LOAD AND VERIFY ROOM FILE
20 INPUT "ROOM NUMBER (0-54)"; R
30 N$="ROOM"+RIGHT$("00"+STR$(R),2)
40 PRINT "LOADING ";N$
50 DOPEN#1,N$,D8
60 IF DS THEN PRINT "ERROR: ";DS$:GOTO 20
70 PRINT "SIZE: ";DSIZE#1;" BYTES"
80 GET#1,A$,B$:REM SKIP FIRST 4 BYTES
90 GET#1,A$,B$
100 DCLOSE#1
110 PRINT "LOADED OK"
120 GOTO 20
```

### Verification Checklist

For each room file, verify:
- [ ] File exists on disk
- [ ] Filename format is "ROOMnn" (two digits)
- [ ] File size > 100 bytes (rooms are substantial)
- [ ] First 4 bytes form valid header
- [ ] Byte 2 = $03 (room type)
- [ ] Byte 3 matches room number
- [ ] Can load without disk errors

## Room Data Size Estimates

Typical room file sizes:
- **Small rooms**: 1-2 KB
- **Medium rooms**: 2-4 KB
- **Large rooms**: 4-8 KB

Total for all 55 rooms: ~150-250 KB (fits on single 1541 disk)

## Disk Layout Recommendations

### Single Disk Layout
```
Block 0-17:   DIR + BAM
Block 18+:    ROOM00 through ROOM54
              (in order, sequential allocation)
```

### Multi-Disk Layout (if needed)
```
Disk 1: ROOM00-ROOM27 (first half)
Disk 2: ROOM28-ROOM54 (second half)
```

The loader can prompt for disk changes if needed.

## Data Integrity

### Checksum Verification (Optional)

Create checksum file for verification:

```
CHECKSUMS:
ROOM00: $ABCD
ROOM01: $1234
...
```

Compute simple XOR checksum of entire file.

### Header Validation

The loader should verify:
1. Byte 2 = $03 (room type)
2. Byte 3 = expected room number
3. Size field is reasonable (< 10KB)

## Common Issues

### Issue: "FILE NOT FOUND"
- Check filename case (may be case-sensitive)
- Ensure two-digit format (ROOM03, not ROOM3)
- Verify disk is formatted

### Issue: "FILE TOO SHORT"
- Room file may be truncated
- Re-extract from source
- Check header (4 bytes minimum)

### Issue: Decompression Fails
- Dictionary corrupt (first 4 bytes)
- Compressed stream damaged
- Verify source extraction

### Issue: Wrong Colors/Graphics
- Wrong room loaded
- Color mapping issue (C64 → Plus/4)
- Tile definitions corrupt

## Advanced: Custom File Format

For more efficient storage, you could create a **container file**:

```
Offset  Size   Description
------  -----  -----------
+$00    2      Magic number ($4D4D = "MM")
+$02    1      Version
+$03    1      Room count (55 = $37)
+$04    110    Directory (55 × 2-byte offsets)
+$72    ...    Room data (concatenated)
```

This requires custom loader but reduces disk fragmentation.

## Summary

**Simple approach** (recommended for Phase 1):
1. Extract each room to separate file
2. Name files ROOM00 through ROOM54
3. Create D64 disk image
4. Test with plus4_main.asm

**Advanced approach** (for optimization):
1. Create container format
2. Custom loader with directory
3. Faster loading, less seeking

The Plus/4 port preserves the C64 data format completely, so no conversion or decompression is needed during preparation - just file extraction and organization.
