/*
 * ===============================================================================
 * Plus/4 Standard IEC Disk Loader
 *
 * Uses standard KERNAL calls for disk I/O instead of custom fast loader.
 * Compatible with 1541, 1551, and other standard Commodore drives.
 *
 * This replaces the C64's complex 10-stage fast loader with simple KERNAL calls.
 * ===============================================================================
 */
#importonce
#import "plus4_constants.inc"

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
.const CHROUT    = $FFD2    // Output character
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
.label load_dest        = $5C   // 16-bit destination address for load
.label load_size        = $5E   // 16-bit size of loaded data
.label filename_ptr     = $60   // 16-bit pointer to filename
.label filename_len     = $62   // Filename length
.label io_status        = $63   // I/O status byte

/*
 * ===========================================
 * Initialize disk system
 *
 * Prepares the disk drive for I/O operations.
 * ===========================================
 */
init_disk:
       // Clear any previous errors
       jsr close_all_files

       // Initialize I/O status
       lda #STATUS_OK
       sta io_status

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
 * Load room resource by number
 *
 * Loads a room file from disk using naming convention:
 * "ROOM00", "ROOM01", ... "ROOM54" (0-54, $00-$36)
 *
 * Input:  A = room number (0-54)
 *         load_dest = destination address
 *
 * Output: A = error code
 *         room_base = points to loaded room data
 * ===========================================
 */
load_room:
       // Save room number
       sta room_number

       // Build filename "ROOMnn"
       jsr build_room_filename

       // Set filename pointer
       lda #<room_filename
       sta filename_ptr
       lda #>room_filename
       sta filename_ptr + 1
       lda #6                // "ROOMnn" = 6 characters
       sta filename_len

       // Load the file
       jsr load_file

       // If successful, set room_base to load_dest + 4 (skip header)
       cmp #STATUS_OK
       bne load_room_done

       lda load_dest
       clc
       adc #$04              // Skip 4-byte resource header
       sta room_base
       lda load_dest + 1
       adc #$00
       sta room_base + 1

load_room_done:
       rts

/*
 * ===========================================
 * Build room filename from room number
 *
 * Converts room number (0-54) to "ROOMnn" format.
 *
 * Input:  room_number = room index (0-54)
 * Output: room_filename = "ROOMnn" string
 * ===========================================
 */
build_room_filename:
       // "ROOM" prefix
       lda #'R'
       sta room_filename + 0
       lda #'O'
       sta room_filename + 1
       sta room_filename + 2
       lda #'M'
       sta room_filename + 3

       // Convert room number to two decimal digits
       lda room_number

       // Tens digit
       ldx #'0'              // Start at '0'
tens_loop:
       cmp #10
       bcc tens_done
       sbc #10               // A = A - 10 (carry is set)
       inx                   // Increment digit
       jmp tens_loop

tens_done:
       stx room_filename + 4 // Store tens digit

       // Ones digit
       clc
       adc #'0'              // Convert to ASCII
       sta room_filename + 5

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
       // Open command channel
       lda #LFN_COMMAND
       ldx #DEVICE_DISK
       ldy #LFN_COMMAND
       jsr SETLFS

       lda #$00              // No filename
       jsr SETNAM

       jsr OPEN
       bcs status_error

       // Set input to command channel
       ldx #LFN_COMMAND
       jsr CHKIN

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

       // Close command channel
       jsr CLRCHN
       lda #LFN_COMMAND
       jsr CLOSE

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

room_filename:
       .text "ROOM00"        // Buffer for room filename

error_message:
       .fill 41, $00         // Buffer for disk error messages (40 chars + null)

temp_error:
       .byte $00

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
