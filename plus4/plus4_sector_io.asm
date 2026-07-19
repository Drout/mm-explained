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
 *   SEC_BUFFER ($0700..$07FF) holds the most recently read 256-byte sector.
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

.const SEC_BUFFER      = $0700  // 256-byte raw sector buffer (page-aligned)

/*
 * ===========================================
 * Zero-page streaming state
 *
 * These mirror the C64 engine's streaming cursor so the higher-level room loader
 * can pull bytes without caring about sector boundaries.
 * ===========================================
 */
.label sec_cur_track   = $A7    // Current physical track being streamed
.label sec_cur_sector  = $A8    // Current physical sector (0-based) being streamed
.label sec_buf_off     = $A9    // 0..255 read cursor within SEC_BUFFER

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
sector_open_channels:
       // --- Open command channel: OPEN 15,8,15,"" ---
       lda #$00                     // filename length 0
       jsr K_SETNAM
       lda #SEC_CMD_LFN
       ldx #SEC_DEVICE
       ldy #SEC_CMD_LFN             // SA 15 = command channel
       jsr K_SETLFS
       jsr K_OPEN
       bcs sector_open_fail

       // --- Open data channel: OPEN 2,8,2,"#" ---
       lda #$01                     // filename length 1
       ldx #<sec_hash_name
       ldy #>sec_hash_name
       jsr K_SETNAM
       lda #SEC_DATA_LFN
       ldx #SEC_DEVICE
       ldy #SEC_DATA_SA             // SA 2 = direct-access buffer
       jsr K_SETLFS
       jsr K_OPEN
       bcs sector_open_fail

       clc
       rts

sector_open_fail:
       sec
       rts

sec_hash_name:
       .text "#"                    // request any free drive buffer

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

       // Visual probe: flash border during each physical sector read so disk
       // activity is obvious in emulators and on real hardware.
       lda TED_BORDER_COLOR
       sta sec_saved_border
       lda #P4_RED
       sta TED_BORDER_COLOR

       // Build the U1 command string in sec_cmd_buf.
       jsr sector_build_u1
       bcs sector_read_fail         // build failed (shouldn't happen)

       // Send the command on the command channel (#15).
       ldx #SEC_CMD_LFN
       jsr K_CHKOUT
       bcs sector_read_fail

       ldy #$00
sector_cmd_send:
       lda sec_cmd_buf,y
       cmp #$FF                     // $FF = end-of-string sentinel
       beq sector_cmd_sent
       jsr K_CHROUT
       iny
       bne sector_cmd_send

sector_cmd_sent:
       jsr K_CLRCHN

       // Now read 256 data bytes back from the data channel (#2).
       ldx #SEC_DATA_LFN
       jsr K_CHKIN
       bcs sector_read_fail

       ldy #$00
sector_data_read:
       jsr K_READST                 // check drive/serial status
       bne sector_read_status_bad   // any non-zero status aborts
       jsr K_CHRIN
       sta SEC_BUFFER,y
       iny
       bne sector_data_read         // loop until 256 bytes read (Y wraps to 0)

       jsr K_CLRCHN
       lda sec_saved_border
       sta TED_BORDER_COLOR
       clc
       rts

sector_read_status_bad:
       jsr K_CLRCHN
sector_read_fail:
       lda sec_saved_border
       sta TED_BORDER_COLOR
       sec
       rts

/*
 * ===========================================
 * sector_build_u1
 *
 * Builds an ASCII "U1 ch drv track sector" command string terminated with $FF.
 *
 * Input:  sec_rd_track, sec_rd_sector
 * Output: sec_cmd_buf populated; carry clear
 * ===========================================
 */
sector_build_u1:
       ldx #$00                     // write index into sec_cmd_buf

       lda #'U'
       sta sec_cmd_buf,x
       inx
       lda #'1'
       sta sec_cmd_buf,x
       inx
       lda #' '
       sta sec_cmd_buf,x
       inx

       // data channel number (single digit)
       lda #SEC_DATA_LFN
       clc
       adc #'0'
       sta sec_cmd_buf,x
       inx
       lda #' '
       sta sec_cmd_buf,x
       inx

       // drive number (single digit)
       lda #SEC_DRIVE
       clc
       adc #'0'
       sta sec_cmd_buf,x
       inx
       lda #' '
       sta sec_cmd_buf,x
       inx

       // track (1-3 decimal digits)
       lda sec_rd_track
       jsr sector_emit_dec
       lda #' '
       sta sec_cmd_buf,x
       inx

       // sector (1-3 decimal digits)
       lda sec_rd_sector
       jsr sector_emit_dec

       // terminator
       lda #$FF
       sta sec_cmd_buf,x

       clc
       rts

/*
 * ===========================================
 * sector_emit_dec
 *
 * Appends the decimal representation of A (0..255) to sec_cmd_buf at index X.
 * Suppresses leading zeros but always emits at least one digit.
 *
 * Input:  A = value, X = current write index into sec_cmd_buf
 * Output: X advanced past the digits written; A/Y clobbered
 * ===========================================
 */
sector_emit_dec:
       sta sec_dec_val

       // Hundreds digit
       ldy #$00
sec_dec_hund:
       lda sec_dec_val
       cmp #100
       bcc sec_dec_hund_done
       sec
       sbc #100
       sta sec_dec_val
       iny
       jmp sec_dec_hund
sec_dec_hund_done:
       cpy #$00
       beq sec_dec_skip_hund        // no hundreds -> skip (leading zero)
       tya
       clc
       adc #'0'
       sta sec_cmd_buf,x
       inx
       lda #$01
       sta sec_dec_emitted
       jmp sec_dec_tens
sec_dec_skip_hund:
       lda #$00
       sta sec_dec_emitted

sec_dec_tens:
       ldy #$00
sec_dec_tens_loop:
       lda sec_dec_val
       cmp #10
       bcc sec_dec_tens_done
       sec
       sbc #10
       sta sec_dec_val
       iny
       jmp sec_dec_tens_loop
sec_dec_tens_done:
       // Emit tens digit if non-zero OR a higher digit was already emitted.
       cpy #$00
       bne sec_dec_emit_tens
       lda sec_dec_emitted
       beq sec_dec_ones             // suppress leading zero
sec_dec_emit_tens:
       tya
       clc
       adc #'0'
       sta sec_cmd_buf,x
       inx

sec_dec_ones:
       // Ones digit is always emitted.
       lda sec_dec_val
       clc
       adc #'0'
       sta sec_cmd_buf,x
       inx
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
       rts                          // carry reflects sector_read result

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
sec_dec_val:
       .byte $00
sec_dec_emitted:
       .byte $00
sec_stream_byte:
       .byte $00
sec_wrap_off:
       .byte $00
sec_saved_border:
       .byte $00

sec_cmd_buf:
       .fill 20, $00                // "U1 c d ttt sss" + $FF terminator
