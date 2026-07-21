/*
 * ===============================================================================
 * Plus/4 Raw Sector I/O (1541 block-read via KERNAL command channel)
 *
 * This module lets the Plus/4 read the ORIGINAL Maniac Mansion game disk without
 * any repacking. It talks to a standard 1541/1551 drive using DOS "U1" (block
 * read) commands over the IEC bus, pulling raw 256-byte sectors into a buffer.
 *
 * Why this exists:
 *   The C64 game stores all room resources packed sequentially on disk and uses
 *   in-memory location tables (side, track, sector) to find each room. The C64's
 *   custom fast loader cannot run on the Plus/4 (different timing/hardware), but
 *   the DATA on the disk is perfectly readable using the drive's built-in block
 *   commands. This module provides that access so the higher-level room loader
 *   can stream a room across sector boundaries just like the original engine.
 *
 * How U1 block-read works:
 *   1. Open a direct-access buffer channel:   OPEN 2,8,2,"#"
 *   2. Send a command on the command channel:  "U1 <ch> <drv> <track> <sector>"
 *   3. Read 256 bytes back from the data channel (channel 2).
 *
 * Public routines:
 *   sector_open_channels   Open command (15) and data (2) channels once.
 *   sector_close_channels  Close both channels.
 *   sector_read            Read one sector: X = track, Y = sector -> SEC_BUFFER.
 *   sector_stream_init     Seed the streaming cursor at (track, sector, offset).
 *   sector_stream_next     Return next byte in A, auto-advancing across sectors.
 *   sector_next_phys       Advance (track, sector) to the next physical sector.
 *
 * Buffer:
 *   SEC_BUFFER ($1B00..$1BFF) holds the most recently read 256-byte sector.
 * ===============================================================================
 */
#importonce
#import "plus4_constants.inc"

/*
 * ===========================================
 * KERNAL vectors (Plus/4) used here
 * ===========================================
 */
.const K_SETLFS  = $FFBA    // Set logical file parameters
.const K_SETNAM  = $FFBD    // Set filename
.const K_OPEN    = $FFC0    // Open logical file
.const K_CLOSE   = $FFC3    // Close logical file
.const K_CHKIN   = $FFC6    // Set input channel
.const K_CHKOUT  = $FFC9    // Set output channel
.const K_CHRIN   = $FFCF    // Read byte from channel
.const K_CHROUT  = $FFD2    // Write byte to channel
.const K_CLRCHN  = $FFCC    // Restore default I/O channels
.const K_READST  = $FFB7    // Read I/O status
.const K_GETIN   = $FFE4    // Get character from input

/*
 * ===========================================
 * Channel / device constants
 * ===========================================
 */
.const SEC_DEVICE      = 8      // Disk device number
.const SEC_CMD_LFN     = 15     // Logical file # for command channel
.const SEC_DATA_LFN    = 2      // Logical file # for the direct-access buffer
.const SEC_DATA_SA     = 2      // Secondary address for the "#" buffer channel
.const SEC_DRIVE       = 0      // Drive number within the unit (single-drive = 0)

.const SEC_BUFFER      = $7B00  // 256-byte raw sector buffer (moved from $1B00: program now
                                // extends to ~$1B1C and must not overlap the sector buffer)

/*
 * ===========================================
 * Streaming state (absolute RAM, NOT zero-page)
 *
 * These were previously zero-page labels at $57-$60. The Plus/4 KERNAL's
 * IEC serial and IRQ routines clobber those ZP locations (especially $59)
 * during K_CHRIN, corrupting the intra-sector read cursor. Moving them to
 * absolute RAM (defined at the end of this file alongside sec_wrap_off)
 * prevents silent corruption of the streaming position.
 * ===========================================
 *
 * Forward declarations — the .byte storage is at the end of this file.
 * KickAssembler resolves these after a full pass, so they can be used
 * before their storage site.
 */

/*
 * ===========================================
 * sector_open_channels
 *
 * Opens the command channel (#15) and the direct-access data channel (#2).
 * The data channel is bound to a drive buffer via the "#" filename, which tells
 * the DOS to allocate any free buffer for U1/U2 block operations.
 *
 * Call once before doing any sector reads.
 *
 * Output: carry clear = success, carry set = open failed
 * ===========================================
 */
// sector_open_channels / sector_close_channels bracket each multi-sector
// loading session (table load and room load each open/close once).  This
// avoids the per-sector OPEN/CLOSE overhead while keeping YAPE happy.
sector_open_channels:
       lda #$00
       jsr K_SETNAM
       lda #SEC_CMD_LFN
       ldx #SEC_DEVICE
       ldy #SEC_CMD_LFN
       jsr K_SETLFS
       jsr K_OPEN
       bcs sector_open_fail

       lda #$01
       ldx #<sec_hash_name
       ldy #>sec_hash_name
       jsr K_SETNAM
       lda #SEC_DATA_LFN
       ldx #SEC_DEVICE
       ldy #SEC_DATA_SA
       jsr K_SETLFS
       jsr K_OPEN
       bcs sector_open_fail

       clc
       rts

sector_open_fail:
       sec
       rts

sec_hash_name:
       .text "#"

/*
 * ===========================================
 * sector_close_channels
 *
 * Closes the data and command channels. Safe to call even if some opens failed.
 * ===========================================
 */
sector_close_channels:
       jsr K_CLRCHN
       lda #SEC_DATA_LFN
       jsr K_CLOSE
       lda #SEC_CMD_LFN
       jsr K_CLOSE
       jsr K_CLRCHN
       rts

/*
 * ===========================================
 * sector_read
 *
 * Reads one raw sector into SEC_BUFFER using a DOS U1 block-read command.
 *
 * Input:  X = track (1-based), Y = sector (0-based)
 * Output: SEC_BUFFER filled with 256 bytes; carry clear = success
 *         A/X/Y clobbered
 *
 * Command string sent on the command channel:
 *   "U1 <data_channel> <drive> <track> <sector>"
 * ===========================================
 */
sector_read:
       stx sec_rd_track
       sty sec_rd_sector

       inc sec_read_count
       lda sec_read_count
       sta PLUS4_SCREEN_RAM + 3

       lda TED_BORDER_COLOR
       sta sec_saved_border
       lda #P4_RED
       sta TED_BORDER_COLOR

       // Open channels fresh for every read, exactly as the sector demo does.
       // The demo does NOT check carry from K_OPEN and it works — on Plus/4
       // K_OPEN for device 8 can return carry set as a status flag yet still
       // open the channel successfully.
       lda #$00
       jsr K_SETNAM
       lda #SEC_CMD_LFN
       ldx #SEC_DEVICE
       ldy #SEC_CMD_LFN
       jsr K_SETLFS
       jsr K_OPEN              // no carry check (matches sector demo)

       lda #$01
       ldx #<sec_hash_name
       ldy #>sec_hash_name
       jsr K_SETNAM
       lda #SEC_DATA_LFN
       ldx #SEC_DEVICE
       ldy #SEC_DATA_SA
       jsr K_SETLFS
       jsr K_OPEN              // no carry check (matches sector demo)

       // Send U1 command on channel 15.
       ldx #SEC_CMD_LFN
       jsr K_CHKOUT

       ldy #$00
sec_cmd_loop:
       lda sec_cmd_u1_prefix,y
       jsr K_CHROUT
       iny
       cpy #7
       bne sec_cmd_loop
       lda sec_rd_track
       jsr PrintDecIO
       lda #' '
       jsr K_CHROUT
       lda sec_rd_sector
       jsr PrintDecIO
       jsr K_CLRCHN

       // Read 256 bytes from data channel 2.
       ldx #SEC_DATA_LFN
       jsr K_CHKIN

       ldy #$00
sec_data_loop:
       jsr K_CHRIN
       sta SEC_BUFFER,y
       iny
       bne sec_data_loop
       jsr K_CLRCHN

       // Close channels (matches sector demo).
       lda #SEC_DATA_LFN
       jsr K_CLOSE
       lda #SEC_CMD_LFN
       jsr K_CLOSE

       lda sec_rd_track
       sta sec_cur_track
       lda sec_rd_sector
       sta sec_cur_sector

       lda sec_saved_border
       sta TED_BORDER_COLOR
       clc
       rts

sector_read_fail:
       jsr K_CLRCHN
       lda sec_saved_border
       sta TED_BORDER_COLOR
       sec
       rts

/*
 * ===========================================
 * PrintDecIO
 *
 * Emits A as decimal ASCII to the currently selected output channel.
 * Suppresses leading zeros but always outputs at least one digit.
 * Clobbers A, X. Uses PTR_NEXT ($60) as scratch.
 * ===========================================
 */
PrintDecIO:
       ldx #$00
pd_h:
       cmp #100
       bcc pd_tens             // A < 100: done counting hundreds
       sbc #100                // carry set by cmp, so sbc = A-100
       inx
       jmp pd_h
pd_tens:
       stx PTR_NEXT            // save hundreds digit
       ldx #$00
pd_t:
       cmp #10
       bcc pd_ones             // A < 10: done counting tens
       sbc #10                 // carry set by cmp, so sbc = A-10
       inx
       jmp pd_t
pd_ones:
       pha                     // save ones digit
       lda PTR_NEXT
       beq pd_no_h             // hundreds == 0: suppress it
       clc
       adc #'0'                // '0' + hundreds digit
       jsr K_CHROUT
pd_no_h:
       txa                     // tens digit
       bne pd_do_t             // tens != 0: always print
       lda PTR_NEXT
       beq pd_no_t             // both hundreds and tens 0: suppress tens
pd_do_t:
       txa
       clc
       adc #'0'                // '0' + tens digit
       jsr K_CHROUT
pd_no_t:
       pla
       clc
       adc #'0'                // '0' + ones digit (always printed)
       jsr K_CHROUT
       rts

/*
 * ===========================================
 * sector_stream_init
 *
 * Seeds the streaming cursor at a given (track, sector) and pre-reads that
 * sector, then positions the intra-sector byte offset.
 *
 * Input:  X = track, Y = sector, A = starting byte offset within the sector
 * Output: first sector loaded; carry clear = success
 * ===========================================
 */
sector_stream_init:
       sta sec_buf_off              // starting offset within first sector
       sta sec_wrap_off             // offset to apply after each sector refill
       stx sec_cur_track
       sty sec_cur_sector

       // Read the first sector into the buffer.
       ldx sec_cur_track
       ldy sec_cur_sector
       jsr sector_read
       bcs sector_stream_init_err
       // KERNAL calls inside sector_read clobber sec_buf_off ($A9).
       // Restore it from sec_wrap_off which is a non-ZP variable and is safe.
       lda sec_wrap_off
       sta sec_buf_off
       clc
       rts
sector_stream_init_err:
       sec
       rts

/*
 * ===========================================
 * sector_stream_next
 *
 * Returns the next byte of the stream in A, transparently advancing to the next
 * physical sector when the current 256-byte buffer is exhausted.
 *
 * Note: The 1541 stores a 2-byte "next track/sector" link at the start of every
 * sector (bytes 0..1). The game's packed resources are laid out in PHYSICAL
 * sector order and skip that link, so we advance geometry ourselves via
 * sector_next_phys rather than following the on-disk link. The higher-level
 * loader is responsible for starting at the correct offset (typically 2) so the
 * link bytes of the FIRST sector are skipped.
 *
 * Output: A = next stream byte; carry clear = success, carry set = read error
 * ===========================================
 */
sector_stream_next:
       ldy sec_buf_off
       lda SEC_BUFFER,y             // fetch current byte
       sta sec_stream_byte

       // Advance the intra-sector offset.
       inc sec_buf_off
       bne sector_stream_ok         // still within this sector -> done

       // Buffer exhausted: advance to the next physical sector and refill.
       jsr sector_next_phys
       ldx sec_cur_track
       ldy sec_cur_sector
       jsr sector_read
       bcs sector_stream_err

       // After a fresh sector, resume at the configured wrap offset.
       // For room resources this is 0; for table/file-like streams this is 2.
       lda sec_wrap_off
       sta sec_buf_off

sector_stream_ok:
       lda sec_stream_byte
       clc
       rts

sector_stream_err:
       lda sec_stream_byte
       sec
       rts

/*
 * ===========================================
 * sector_next_phys
 *
 * Advances (sec_cur_track, sec_cur_sector) to the next physical sector, wrapping
 * to sector 0 and incrementing the track when the current track's last sector is
 * passed. Mirrors the C64 engine's disk_next_sector_phys using standard 1541
 * zone geometry.
 *
 * Output: sec_cur_track / sec_cur_sector updated; A/Y clobbered
 * ===========================================
 */
sector_next_phys:
       inc sec_cur_sector

       // Look up this track's maximum 0-based sector index.
       ldy sec_cur_track
       lda sec_max_sector_by_track,y
       cmp sec_cur_sector
       bcs sector_next_ok           // max >= current -> still valid (>=, so ok when equal)

       // Passed the last sector on this track -> wrap to sector 0, next track.
       lda #$00
       sta sec_cur_sector
       inc sec_cur_track

sector_next_ok:
       rts

/*
 * ===========================================
 * sec_max_sector_by_track
 *
 * Per-track maximum 0-based sector index for a standard 1541 disk (35 tracks).
 * Index 0 is an unused placeholder (there is no track 0).
 * ===========================================
 */
sec_max_sector_by_track:
       .byte $00                                                   //  0: unused
       .byte TRK_ZONE1_MAXSEC, TRK_ZONE1_MAXSEC, TRK_ZONE1_MAXSEC  //  1- 3
       .byte TRK_ZONE1_MAXSEC, TRK_ZONE1_MAXSEC, TRK_ZONE1_MAXSEC  //  4- 6
       .byte TRK_ZONE1_MAXSEC, TRK_ZONE1_MAXSEC, TRK_ZONE1_MAXSEC  //  7- 9
       .byte TRK_ZONE1_MAXSEC, TRK_ZONE1_MAXSEC, TRK_ZONE1_MAXSEC  // 10-12
       .byte TRK_ZONE1_MAXSEC, TRK_ZONE1_MAXSEC, TRK_ZONE1_MAXSEC  // 13-15
       .byte TRK_ZONE1_MAXSEC, TRK_ZONE1_MAXSEC                    // 16-17
       .byte TRK_ZONE2_MAXSEC, TRK_ZONE2_MAXSEC, TRK_ZONE2_MAXSEC  // 18-20
       .byte TRK_ZONE2_MAXSEC, TRK_ZONE2_MAXSEC, TRK_ZONE2_MAXSEC  // 21-23
       .byte TRK_ZONE2_MAXSEC                                      // 24
       .byte TRK_ZONE3_MAXSEC, TRK_ZONE3_MAXSEC, TRK_ZONE3_MAXSEC  // 25-27
       .byte TRK_ZONE3_MAXSEC, TRK_ZONE3_MAXSEC, TRK_ZONE3_MAXSEC  // 28-30
       .byte TRK_ZONE4_MAXSEC, TRK_ZONE4_MAXSEC, TRK_ZONE4_MAXSEC  // 31-33
       .byte TRK_ZONE4_MAXSEC, TRK_ZONE4_MAXSEC                    // 34-35

/*
 * ===========================================
 * Scratch variables
 * ===========================================
 */
sec_rd_track:
       .byte $00
sec_rd_sector:
       .byte $00
sec_stream_byte:
       .byte $00
sec_wrap_off:
       .byte $00
sec_saved_border:
       .byte $00
sec_status_ch0:
       .byte $00
sec_status_ch1:
       .byte $00
// Streaming cursor — moved here from ZP to survive KERNAL IRQ clobbering.
sec_cur_track:
       .byte $00
sec_cur_sector:
       .byte $00
sec_buf_off:
       .byte $00
sec_read_count:
       .byte $00
// Scratch digit store for PrintDecIO (moved from ZP $60).
PTR_NEXT:
       .byte $00

sec_cmd_u1_prefix:
       .text "U1 2 0 "
