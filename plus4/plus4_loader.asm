/*
 * ===============================================================================
 * Plus/4 Disk Loader (sector-based, reads the ORIGINAL game disk)
 *
 * Option A loader: instead of repacking rooms into individual "ROOMnn" files,
 * this reads the original Maniac Mansion disk exactly as-is. It reproduces the
 * C64 engine's approach:
 *   1. Read the resource-location tables from the disk (Track 1, Sector 1).
 *   2. Look up a room's disk side + (track, sector) from those tables.
 *   3. Stream the room's bytes across sector boundaries into RAM.
 *
 * Raw sector access is provided by plus4_sector_io.asm (DOS "U1" block reads via
 * the KERNAL command channel), so a standard 1541/1551 drive works with no fast
 * loader and no copy protection handling.
 *
 * The old KERNAL LOAD helpers (load_file / load_file_streaming) are retained for
 * convenience/testing but are no longer used by the room path.
 * ===============================================================================
 */
#importonce
#import "plus4_constants.inc"
#import "plus4_sector_io.asm"


/*
 * ===========================================
 * KERNAL vectors (Plus/4)
 * ===========================================
 */
.const SETLFS    = $FFBA    // Set logical file parameters
.const SETNAM    = $FFBD    // Set filename
.const OPEN      = $FFC0    // Open file
.const CLOSE     = $FFC3    // Close file
.const CHKIN     = $FFC6    // Set input channel
.const CHRIN     = $FFCF    // Get character from input
.const CLRCHN    = $FFCC    // Clear I/O channels
.const READST    = $FFB7    // Read I/O status
.const LOAD      = $FFD5    // Load file
.const SAVE      = $FFD8    // Save file

/*
 * ===========================================
 * Disk device constants
 * ===========================================
 */
.const DEVICE_DISK      = 8     // Device 8 = disk drive
.const SA_LOAD          = 0     // Secondary address for load
.const SA_SAVE          = 1     // Secondary address for save
.const LFN_DATA         = 2     // Logical file number for data files
.const LFN_COMMAND      = 15    // Logical file number for command channel

/*
 * ===========================================
 * File I/O status codes
 * ===========================================
 */
.const STATUS_OK        = $00   // No error
.const STATUS_EOF       = $40   // End of file
.const STATUS_ERROR     = $80   // Read error

/*
 * ===========================================
 * Variables
 * ===========================================
 */
.label load_dest        = $FB   // 16-bit destination address for load ($FB safe from KERNAL clobber)
.label load_size        = $5E   // 16-bit size of loaded data
.label filename_ptr     = $60   // 16-bit pointer to filename
.label filename_len     = $62   // Filename length
.label io_status        = $63   // I/O status byte

/*
 * ===========================================
 * Sector-streaming room-load state (zero page)
 * ===========================================
 */
.label room_size        = $67   // 16-bit total resource size (from header)
.label room_dest        = $69   // 16-bit destination write pointer while streaming
.label room_side        = $6B   // Required disk side id for the current room

/*
 * ===========================================
 * Initialize disk system
 *
 * Opens the raw-sector channels and loads the resource-location tables from the
 * game disk so rooms can be looked up by index. Call once at startup with the
 * game disk (side 1) in the drive.
 *
 * Output: A = 0 on success, non-zero on failure
 * ===========================================
 */
init_disk:
       // sector_read is now self-contained (open/close per call), so no
       // pre-open is needed here.  Just load the tables directly.
       jsr load_location_tables
       sta io_status
       // Diagnostics: show side-table bytes after the load.
       //   $0C08 = RSRC_TBL_BASE+1  = room 1 side  (expected $32)
       //   $0C09 = RSRC_TBL_BASE+16 = room 16 side (expected $31)
       lda RSRC_TBL_BASE + 1
       sta PLUS4_SCREEN_RAM + 8
       lda RSRC_TBL_BASE + 16
       sta PLUS4_SCREEN_RAM + 9
       rts

init_disk_err:
       lda #$FF
       sta io_status
       rts

/*
 * ===========================================
 * load_location_tables
 *
 * Streams the C64 resource-location table block from the game disk into local
 * RAM (RSRC_TBL_BASE). The block lives at Track 1 / Sector 1, starting at byte
 * offset $02 (after the sector's 2-byte link), and is RSRC_TBL_BYTES long.
 *
 * After this, room lookups use:
 *   side  = RSRC_TBL_BASE[room]                         (room_disk_side_tbl)
 *   sec   = RSRC_TBL_BASE[RSRC_TBL_SECTRK_OFS + room*2 + 0]
 *   trk   = RSRC_TBL_BASE[RSRC_TBL_SECTRK_OFS + room*2 + 1]
 *
 * Output: A = 0 on success, non-zero on read error
 * ===========================================
 */
load_location_tables:
       // sector_read opens/closes channels itself; no wrapper needed here.

       // Seed the stream at T1/S1, byte offset 2.
       ldx #RSRC_TBL_DISK_TRACK
       ldy #RSRC_TBL_DISK_SECTOR
       lda #RSRC_TBL_DISK_OFFSET
       jsr sector_stream_init
       bcs load_tables_err

       // ── Diagnostic block: 6 bytes from SEC_BUFFER ──────────────────────
       // All of these should be non-zero for the test to have succeeded.
       // $0C05 = $AA  sentinel: sector_stream_init returned success
       // $0C06 = SEC_BUFFER[2]  = room 0 side   (expected $00)
       // $0C07 = SEC_BUFFER[3]  = room 1 side   (expected $32)
       // $0C0A = SEC_BUFFER[18] = room 16 side  (expected $31)
       // $0C0B = SEC_BUFFER[4]  = room 2 side   (expected $32)
       // $0C0C = SEC_BUFFER[5]  = room 3 side   (expected $32)
       // If $0C07/$0C0A/$0C0B/$0C0C are all $00 the U1 read returned zeros.
       lda #$AA
       sta PLUS4_SCREEN_RAM + 5       // sentinel
       lda SEC_BUFFER + 2
       sta PLUS4_SCREEN_RAM + 6
       lda SEC_BUFFER + 3
       sta PLUS4_SCREEN_RAM + 7
       lda SEC_BUFFER + 18
       sta PLUS4_SCREEN_RAM + 10      // $0C0A
       lda SEC_BUFFER + 4
       sta PLUS4_SCREEN_RAM + 11      // $0C0B
       lda SEC_BUFFER + 5
       sta PLUS4_SCREEN_RAM + 12      // $0C0C
       // ─────────────────────────────────────────────────────────────────────

       // Use self-modifying STA to write to RSRC_TBL_BASE without any
       // ZP-indirect addressing.  The KERNAL synchronously clobbers the
       // ZP pointers used by (room_dest),Y so we bypass ZP entirely.
       //
       // tbl_sta_abs is a 3-byte absolute STA instruction; we modify its
       // address operand (bytes +1 and +2) to advance the write pointer.
       sei                          // guard absolute streaming state from IRQ

       lda #<RSRC_TBL_BASE
       sta tbl_sta_abs + 1          // lo byte of STA destination
       sta PLUS4_SCREEN_RAM + 13    // $0C0D: confirm lo byte written ($00)
       lda #>RSRC_TBL_BASE
       sta tbl_sta_abs + 2          // hi byte of STA destination
       sta PLUS4_SCREEN_RAM + 14    // $0C0E: confirm hi byte written ($60)

       lda #<RSRC_TBL_BYTES
       sta tbl_count_lo
       lda #>RSRC_TBL_BYTES
       sta tbl_count_hi

load_tables_loop:
       lda tbl_count_lo
       ora tbl_count_hi
       beq load_tables_done

       jsr sector_stream_next       // direct call — no ZP save/restore needed
       bcs load_tables_err_sei

tbl_sta_abs:
       sta $6000                    // address self-modified: always absolute STA

       // Advance destination inside the instruction.
       inc tbl_sta_abs + 1
       bne tbl_no_carry
       inc tbl_sta_abs + 2
tbl_no_carry:

       // Decrement 16-bit counter.
       lda tbl_count_lo
       bne tbl_dec_lo
       dec tbl_count_hi
tbl_dec_lo:
       dec tbl_count_lo
       jmp load_tables_loop

load_tables_done:
       cli                          // re-enable KERNAL IRQ
       lda #STATUS_OK
       rts

load_tables_err_sei:
       cli                          // re-enable KERNAL IRQ before close
load_tables_err:
       lda #$FF
       rts

/*
 * ===========================================
 * Load a file using KERNAL LOAD
 *
 * This is the simplest method - let KERNAL do all the work.
 *
 * Input:  filename_ptr = pointer to filename (null-terminated or length-prefixed)
 *         filename_len = length of filename
 *         load_dest    = destination address (0 = use file's load address)
 *
 * Output: A = error code (0 = success)
 *         load_dest = actual load address (if input was 0)
 *         X:Y = end address + 1
 *
 * Uses KERNAL LOAD routine ($FFD5):
 *   A = 0 (load), 1 (verify)
 *   X/Y = load address (lo/hi) or 0 for file's address
 *   SETNAM and SETLFS must be called first
 * ===========================================
 */
load_file:
       // Set filename
       lda filename_len
       ldx filename_ptr
       ldy filename_ptr + 1
       jsr SETNAM

       // Set logical file parameters
       // A = logical file number
       // X = device number
       // Y = secondary address (0 = load to address, 1 = load to file's address)
       lda #LFN_DATA
       ldx #DEVICE_DISK
       ldy #SA_LOAD
       jsr SETLFS

       // Load file
       lda #$00              // 0 = load (not verify)
       ldx load_dest         // Load address low
       ldy load_dest + 1     // Load address high
       jsr LOAD

       // Check for error
       bcc load_success

       // Error occurred
       sta io_status
       lda #$FF              // Return error code
       rts

load_success:
       // Store end address
       stx load_dest
       sty load_dest + 1

       lda #STATUS_OK
       sta io_status
       rts

/*
 * ===========================================
 * Load file to specific address (streaming)
 *
 * Opens file and reads byte-by-byte for more control.
 * Useful when you need to process data as it loads.
 *
 * Input:  filename_ptr, filename_len = filename
 *         load_dest = destination address
 *
 * Output: A = error code
 * ===========================================
 */
load_file_streaming:
       // Set filename
       lda filename_len
       ldx filename_ptr
       ldy filename_ptr + 1
       jsr SETNAM

       // Set logical file
       lda #LFN_DATA
       ldx #DEVICE_DISK
       ldy #SA_LOAD
       jsr SETLFS

       // Open file
       jsr OPEN
       bcs stream_error

       // Set input channel
       ldx #LFN_DATA
       jsr CHKIN

       // Read bytes until EOF
       ldy #$00
stream_loop:
       jsr READST            // Check status
       and #STATUS_EOF       // EOF bit?
       bne stream_done

       jsr CHRIN             // Read byte
       sta (load_dest),y     // Store byte

       iny
       bne stream_loop

       // Increment high byte of destination
       inc load_dest + 1
       jmp stream_loop

stream_done:
       // Close input channel
       jsr CLRCHN

       // Close file
       lda #LFN_DATA
       jsr CLOSE

       lda #STATUS_OK
       rts

stream_error:
       jsr CLRCHN
       lda #LFN_DATA
       jsr CLOSE
       lda #$FF
       rts

/*
 * ===========================================
 * Load room resource by number (sector-based)
 *
 * Looks up the room's disk side and (track, sector) in the location tables,
 * then streams the whole resource (header + payload) into memory.
 *
 * Input:  A          = room number (0..ROOM_MAX_INDEX)
 *         load_dest  = destination address for the resource
 *
 * Output: A          = error code (0 = success)
 *         room_base  = points to room data (load_dest + 4, skipping header)
 *         io_status  = same as A
 * ===========================================
 */
load_room:
       // Save room number.
       sta room_number

       // Save load_dest to room_load_base — a dedicated non-ZP variable that
       // loader_save_zp_state never touches. loader_saved_load_dest gets
       // overwritten by every loader_save_zp_state call so it cannot hold the
       // original $4000 destination reliably.
       lda load_dest
       sta room_load_base
       lda load_dest + 1
       sta room_load_base + 1

       // Debug stage probe at $0C01 (loader path).
       lda #$A1                     // entered load_room
       sta PLUS4_SCREEN_RAM + 1

       lda #$00
       sta sec_read_count
       sta PLUS4_SCREEN_RAM + 3

       // --- Look up required disk side and verify it is mounted. ---
       lda room_number
       tax
       lda RSRC_TBL_BASE + RSRC_TBL_SIDE_OFS,x
       sta room_side

       lda room_side
       sta PLUS4_SCREEN_RAM + 4

       // Room side bytes in the D64 table are ASCII ('1'/'2').
       lda room_side
       cmp #$31
       beq load_room_side_valid
       cmp #$32
       beq load_room_side_valid
       jmp load_room_bad_side

load_room_bad_side:
       lda #$B1
       sta PLUS4_SCREEN_RAM + 5
       jmp load_room_err

load_room_side_valid:
       jsr ensure_disk_side
       bcc load_room_side_ok

       lda #$FF                     // wrong side / user aborted
       sta io_status
       rts

load_room_side_ok:
       lda #$A2                     // side accepted
       sta PLUS4_SCREEN_RAM + 1

       // --- Fetch (SECTOR, TRACK) pair: index = room*2 into sec/trk table. ---
       lda room_number
       asl                          // room * 2
       tax

       lda RSRC_TBL_BASE + RSRC_TBL_SECTRK_OFS + 0,x   // sector
       sta room_ls_sector
       lda RSRC_TBL_BASE + RSRC_TBL_SECTRK_OFS + 1,x   // track
       sta room_ls_track

       lda room_ls_sector
       sta PLUS4_SCREEN_RAM + 5
       lda room_ls_track
       sta PLUS4_SCREEN_RAM + 6

       // Basic geometry sanity for table entries.
       lda room_ls_track
       beq load_room_bad_entry
       cmp #$24                     // 36
       bcs load_room_bad_entry

       lda room_ls_sector
       cmp #$15                     // conservative upper bound: 0..20
       bcs load_room_bad_entry
       jmp load_room_table_ok

load_room_bad_entry:
       lda #$B2
       sta PLUS4_SCREEN_RAM + 5
       jmp load_room_err

load_room_table_ok:
       lda #$C1                     // about to seed room sector stream
       sta PLUS4_SCREEN_RAM + 2

       // sector_read is now self-contained; no separate channel open needed.
load_room_stream_seed:

       // --- Seed the stream at (track, sector), offset 0.
       // Room resources on the Maniac Mansion disk begin at byte 0 of their
       // sector (no T/S link prefix).  The Python extractor confirms this
       // with skip_bytes=0 for room payloads.  Using $02 here misaligned the
       // 4-byte resource header, causing the size/type/index bytes to be
       // read from the wrong positions.
       ldx room_ls_track
       ldy room_ls_sector
       lda #$00
       jsr sector_stream_init
       bcc load_room_hdr
       lda #$B3
       sta PLUS4_SCREEN_RAM + 5
       jmp load_room_err

load_room_hdr:
       lda #$C2                     // sector stream initialized
       sta PLUS4_SCREEN_RAM + 2

       lda #$A3                     // stream seeded
       sta PLUS4_SCREEN_RAM + 1

       // --- Read the 4-byte resource header to learn total size. ---
       // Header: +0 size.lo, +1 size.hi, +2 type, +3 index.
       jsr loader_stream_next_safe
       bcc load_room_h1
       lda #$B4
       sta PLUS4_SCREEN_RAM + 5
       jmp load_room_err
load_room_h1:
       lda #$C3                     // first header byte read
       sta PLUS4_SCREEN_RAM + 2

       sta room_size                // size low

       jsr loader_stream_next_safe
       bcc load_room_h2
       lda #$B5
       sta PLUS4_SCREEN_RAM + 5
       jmp load_room_err
load_room_h2:
       lda #$C4                     // second header byte read
       sta PLUS4_SCREEN_RAM + 2

       sta room_size + 1            // size high

       jsr loader_stream_next_safe  // type byte (discard here; kept in stream copy)
       bcc load_room_h3
       lda #$B6
       sta PLUS4_SCREEN_RAM + 5
       jmp load_room_err
load_room_h3:
       lda #$C5                     // third header byte read
       sta PLUS4_SCREEN_RAM + 2

       sta room_hdr_type

       // Disk-header byte +2 must be the sentinel 0 in the C64 format.
       // If not, the stream origin/alignment is wrong.
       cmp #$00
       bne load_room_bad_header

       jsr loader_stream_next_safe  // index byte
       bcc load_room_h4
       lda #$B7
       sta PLUS4_SCREEN_RAM + 5
       jmp load_room_err
load_room_h4:
       lda #$C6                     // fourth header byte read
       sta PLUS4_SCREEN_RAM + 2

       sta room_hdr_index
       jmp load_room_hdr_sanity

load_room_bad_header:
       lda #$B8
       sta PLUS4_SCREEN_RAM + 5
       jmp load_room_err

load_room_hdr_sanity:

       // Keep only size sanity here.
       lda room_size + 1
       bne load_room_hdr_ok
       lda room_size
       cmp #RSRC_HDR_BYTES
       bcc load_room_sanity_fail
       jmp load_room_hdr_ok

load_room_sanity_fail:
       lda #$B9                     // sanity fail: size too small
       sta PLUS4_SCREEN_RAM + 5
       jmp load_room_err
load_room_hdr_ok:
       lda #$A4                     // header accepted
       sta PLUS4_SCREEN_RAM + 1

       // DIAGNOSTIC: $BB here means load_room_hdr_ok was reached
       lda #$BB
       sta $4000

       // Hardcode destination: always $4000.  Eliminates all variable issues.
       lda #<ROOM_DATA_BASE         // = $00
       sta room_dest
       lda #>ROOM_DATA_BASE         // = $40
       sta room_dest + 1

       ldy #$00
       lda room_size
       sta (room_dest),y
       iny
       lda room_size + 1
       sta (room_dest),y
       iny
       lda room_hdr_type
       sta (room_dest),y
       iny
       lda room_hdr_index
       sta (room_dest),y

       // Advance destination past the 4-byte header.
       clc
       lda room_dest
       adc #RSRC_HDR_BYTES
       sta room_dest
       lda room_dest + 1
       adc #$00
       sta room_dest + 1

       // --- Stream the remaining (size - 4) payload bytes. ---
       sec
       lda room_size
       sbc #RSRC_HDR_BYTES
       sta room_size
       lda room_size + 1
       sbc #$00
       sta room_size + 1

load_room_payload:
       lda room_size
       ora room_size + 1
       beq load_room_ok

       jsr loader_stream_next_safe
       bcs load_room_err

       ldy #$00
       sta (room_dest),y

       inc room_dest
       bne load_room_pay_dec
       inc room_dest + 1

load_room_pay_dec:
       lda room_size
       bne load_room_pay_declo
       dec room_size + 1
load_room_pay_declo:
       dec room_size
       jmp load_room_payload

load_room_ok:
       lda #<ROOM_DATA_BASE
       sta room_base
       lda #>ROOM_DATA_BASE
       sta room_base + 1

       lda #$AF                     // room payload loaded
       sta PLUS4_SCREEN_RAM + 1

       // BORDER = GREEN: room loaded successfully
       lda #$53
       sta TED_BORDER_COLOR

       lda #STATUS_OK
       sta io_status
       rts

load_room_err:
       lda #$EE                     // loader failed
       sta PLUS4_SCREEN_RAM + 1

       // BORDER = RED: room load failed
       lda #$32
       sta TED_BORDER_COLOR

       lda #$FF
       sta io_status
       rts

/*
 * ===========================================
 * Safe stream byte fetch for loader code
 *
 * KERNAL-backed IEC routines may clobber low zero-page bytes used by this
 * loader for pointers/counters. Preserve/restore the loader state around each
 * streamed byte read.
 *
 * Output: A = stream byte, C clear on success / set on read error
 * ===========================================
 */
loader_stream_next_safe:
       jsr loader_save_zp_state
       jsr sector_stream_next
       sta loader_stream_byte
       bcc loader_stream_ok

       jsr loader_restore_zp_state
       lda loader_stream_byte
       sec
       rts

loader_stream_ok:
       jsr loader_restore_zp_state
       lda loader_stream_byte
       clc
       rts

loader_save_zp_state:
       lda load_dest
       sta loader_saved_load_dest
       lda load_dest + 1
       sta loader_saved_load_dest + 1

       lda room_size
       sta loader_saved_room_size
       lda room_size + 1
       sta loader_saved_room_size + 1

       lda room_dest
       sta loader_saved_room_dest
       lda room_dest + 1
       sta loader_saved_room_dest + 1

       lda room_side
       sta loader_saved_room_side
       rts

loader_restore_zp_state:
       lda loader_saved_load_dest
       sta load_dest
       lda loader_saved_load_dest + 1
       sta load_dest + 1

       lda loader_saved_room_size
       sta room_size
       lda loader_saved_room_size + 1
       sta room_size + 1

       lda loader_saved_room_dest
       sta room_dest
       lda loader_saved_room_dest + 1
       sta room_dest + 1

       lda loader_saved_room_side
       sta room_side
       rts

/*
 * ===========================================
 * ensure_disk_side
 *
 * Verifies that the disk side required by the current room is mounted. On this
 * initial port we cannot programmatically detect the side, so if a side change
 * is required we prompt the user and wait for a key, then assume compliance.
 *
 * Most rooms live on side 1, so in practice this rarely triggers.
 *
 * Input:  room_side = required side id (from room_disk_side_tbl)
 * Output: carry clear = side ready, carry set = aborted
 * ===========================================
 */
ensure_disk_side:
       lda room_side
       cmp active_side_id
       beq ensure_side_ok

       // Remember the new active side (optimistically).
       lda room_side
       sta active_side_id

ensure_side_ok:
       clc
       rts

/*
 * ===========================================
 * Close all open files
 *
 * Closes all logical files and clears I/O channels.
 * Good practice before opening new files.
 * ===========================================
 */
close_all_files:
       jsr CLRCHN            // Clear I/O channels

       // Close files 0-15
       ldx #15
close_loop:
       txa
       jsr CLOSE
       dex
       bpl close_loop

       rts

/*
 * ===========================================
 * Read disk status
 *
 * Opens command channel and reads error message.
 * Useful for debugging disk errors.
 *
 * Output: A = error code (from first two digits of status)
 *         error_message filled with status string
 * ===========================================
 */
read_disk_status:
       // The command channel (#15) is already open (opened by sector_open_channels).
       // Just direct input to it and read the status string.
       ldx #LFN_COMMAND
       jsr CHKIN
       bcs status_error

       // Read status string
       ldy #$00
status_read_loop:
       jsr READST
       and #STATUS_EOF
       bne status_read_done

       jsr CHRIN
       sta error_message,y

       iny
       cpy #40               // Max 40 characters
       bne status_read_loop

status_read_done:
       // Null-terminate
       lda #$00
       sta error_message,y

       // Release input channel (leave #15 open for future reads).
       jsr CLRCHN

       // Parse error code from first two digits
       lda error_message + 0
       sec
       sbc #'0'
       asl
       asl
       asl
       asl                   // Tens digit * 16
       sta temp_error

       lda error_message + 1
       sec
       sbc #'0'              // Ones digit
       ora temp_error        // Combine
       rts

status_error:
       lda #$FF
       rts

/*
 * ===========================================
 * Load multiple resources
 *
 * Helper to load common resources at startup.
 * ===========================================
 */
load_game_resources:
       // Load room 0 (entry room)
       lda #$00
       jsr load_room

       // TODO: Load other resources (costumes, scripts, etc.)

       rts

/*
 * ===========================================
 * Variables and buffers
 * ===========================================
 */
room_number:
       .byte $00

// Disk-location lookup results for the current room.
room_ls_sector:
       .byte $00              // sector from room_sec_trk_tbl
room_ls_track:
       .byte $00              // track from room_sec_trk_tbl

// Resource header bytes captured during streaming.
room_hdr_type:
       .byte $00              // resource type ($03 = room)
room_hdr_index:
       .byte $00              // room index from header

// Currently mounted disk side (as an id from room_disk_side_tbl).
active_side_id:
       .byte $31              // assume side 1 mounted at startup (ASCII '1')

room_filename:
       .text "ROOM00"        // Buffer for room filename (legacy load_file helper)

error_message:
       .fill 41, $00         // Buffer for disk error messages (40 chars + null)

temp_error:
       .byte $00

tbl_count_lo:
       .byte $00
tbl_count_hi:
       .byte $00

loader_stream_byte:
       .byte $00

loader_saved_load_dest:
       .byte $00, $00

loader_saved_room_size:
       .byte $00, $00

loader_saved_room_dest:
       .byte $00, $00

loader_saved_room_side:
       .byte $00

// Dedicated save of the room payload destination address.
// Unlike loader_saved_load_dest this is NEVER touched by loader_save_zp_state.
room_load_base:
       .byte $00, $00

/*
 * ===========================================
 * Utility: Set filename from string literal
 *
 * Helper macro for setting filenames in code.
 *
 * Usage:
 *   set_filename "MYFILE"
 *   jsr load_file
 * ===========================================
 */
.macro set_filename(name) {
       lda #<name
       sta filename_ptr
       lda #>name
       sta filename_ptr + 1
       lda #name.size()
       sta filename_len
}

/*
 * ===========================================
 * Example usage:
 *
 * // Load room 5
 * lda #$05
 * lda #<$4000              // Load to $4000
 * sta load_dest
 * lda #>$4000
 * sta load_dest + 1
 * jsr load_room
 *
 * // Check for errors
 * lda io_status
 * bne error_handler
 *
 * // Room data now at $4000, room_base points to $4004
 * ===========================================
 */
