/*
 * ===============================================================================
 * Maniac Mansion Plus/4 - Main Program
 *
 * Entry point that initializes the system and loads/displays a room.
 * This is a simple test harness for Phase 1.
 * ===============================================================================
 */

// Set program start address (standard Plus/4 BASIC start)
.pc = $1001 "BASIC Upstart"
:BasicUpstart(main)

// Import all modules
#import "plus4_constants.inc"
#import "plus4_init.asm"
#import "plus4_loader.asm"
#import "plus4_room_render.asm"

/*
 * ===========================================
 * Main program entry point
 * ===========================================
 */
.pc = $1100 "Main Program"
main:
       // Print startup message
       jsr print_startup_message

       // Initialize Plus/4 hardware
       jsr init_plus4

       // Initialize disk system
       jsr init_disk

       // Load room (start with room 0)
       lda #DEFAULT_ROOM
       sta current_room

       jsr load_current_room
       bne main_error

       // Render the room
       jsr render_room

       // Main loop (wait for input)
main_loop:
       jsr GETIN             // Check for keypress
       beq main_loop         // No key, keep waiting

       // Handle key input
       cmp #KEY_SPACE        // Space = reload room
       beq reload_room

       cmp #KEY_LEFT         // Left arrow = previous room
       beq prev_room

       cmp #KEY_RIGHT        // Right arrow = next room
       beq next_room

       cmp #'Q'              // Q = quit
       beq quit_program

       jmp main_loop

/*
 * ===========================================
 * Reload current room
 * ===========================================
 */
reload_room:
       jsr load_current_room
       bne main_error
       jsr render_room
       jmp main_loop

/*
 * ===========================================
 * Load previous room (with wraparound)
 * ===========================================
 */
prev_room:
       lda current_room
       beq wrap_to_last      // If room 0, wrap to last room
       dec current_room
       jmp reload_room

wrap_to_last:
       lda #ROOM_MAX_INDEX
       sta current_room
       jmp reload_room

/*
 * ===========================================
 * Load next room (with wraparound)
 * ===========================================
 */
next_room:
       lda current_room
       cmp #ROOM_MAX_INDEX
       beq wrap_to_first     // If last room, wrap to room 0
       inc current_room
       jmp reload_room

wrap_to_first:
       lda #$00
       sta current_room
       jmp reload_room

/*
 * ===========================================
 * Load current room
 *
 * Loads the room specified by current_room variable.
 *
 * Output: A = 0 (success), non-zero (error)
 * ===========================================
 */
load_current_room:
       // Set destination to room data area
       lda #<ROOM_DATA_BASE
       sta load_dest
       lda #>ROOM_DATA_BASE
       sta load_dest + 1

       // Load room by number
       lda current_room
       jsr load_room

       // Check status
       lda io_status
       rts

/*
 * ===========================================
 * Error handler
 * ===========================================
 */
main_error:
       // Print error message
       lda #<error_msg
       sta print_ptr
       lda #>error_msg
       sta print_ptr + 1
       jsr print_string

       // Read and display disk status
       jsr read_disk_status
       jsr print_disk_error

       // Wait for key
wait_error:
       jsr GETIN
       beq wait_error

       // Return to main loop (try to continue)
       jmp main_loop

/*
 * ===========================================
 * Quit program
 * ===========================================
 */
quit_program:
       // Close all files
       jsr close_all_files

       // Print goodbye message
       lda #<quit_msg
       sta print_ptr
       lda #>quit_msg
       sta print_ptr + 1
       jsr print_string

       // Return to BASIC
       rts

/*
 * ===========================================
 * Print startup message
 * ===========================================
 */
print_startup_message:
       lda #<startup_msg
       sta print_ptr
       lda #>startup_msg
       sta print_ptr + 1
       jsr print_string
       rts

/*
 * ===========================================
 * Print null-terminated string
 *
 * Input: print_ptr = pointer to string
 * ===========================================
 */
print_string:
       ldy #$00
print_loop:
       lda (print_ptr),y
       beq print_done
       jsr CHROUT
       iny
       jmp print_loop
print_done:
       rts

/*
 * ===========================================
 * Print disk error message
 * ===========================================
 */
print_disk_error:
       lda #<disk_error_prefix
       sta print_ptr
       lda #>disk_error_prefix
       sta print_ptr + 1
       jsr print_string

       lda #<error_message
       sta print_ptr
       lda #>error_message
       sta print_ptr + 1
       jsr print_string

       // Print newline
       lda #$0D
       jsr CHROUT
       rts

/*
 * ===========================================
 * KERNAL routines
 * ===========================================
 */
.const GETIN = $FFE4          // Get character from keyboard

/*
 * ===========================================
 * Variables
 * ===========================================
 */
.label print_ptr       = $64   // Pointer for string printing
.label current_room    = $66   // Current room number

.const DEFAULT_ROOM    = $00   // Start room (entry room)
.const ROOM_DATA_BASE  = $4000 // Where to load room data

/*
 * ===========================================
 * Messages
 * ===========================================
 */
startup_msg:
       .encoding "petscii_mixed"
       .text "MANIAC MANSION - PLUS/4 PORT"
       .byte $0D
       .text "PHASE 1: ROOM DISPLAY TEST"
       .byte $0D, $0D
       .text "KEYS:"
       .byte $0D
       .text "  SPACE = RELOAD"
       .byte $0D
       .text "  <- -> = CHANGE ROOM"
       .byte $0D
       .text "  Q     = QUIT"
       .byte $0D, $0D
       .text "LOADING ROOM..."
       .byte $0D, $00

error_msg:
       .encoding "petscii_mixed"
       .byte $0D
       .text "ERROR LOADING ROOM!"
       .byte $0D, $00

disk_error_prefix:
       .encoding "petscii_mixed"
       .text "DISK STATUS: "
       .byte $00

quit_msg:
       .encoding "petscii_mixed"
       .byte $0D
       .text "THANKS FOR TESTING!"
       .byte $0D, $00

/*
 * ===========================================
 * Build notes
 * ===========================================
 *
 * To build this program:
 * 1. Assemble with KickAssembler or compatible
 * 2. Create disk with room data files: ROOM00, ROOM01, etc.
 * 3. Each room file should be raw room resource (with 4-byte header)
 * 4. Load on Plus/4 and run
 *
 * Disk layout example:
 *   ROOM00  - Entry room
 *   ROOM01  - First room
 *   ROOM02  - Second room
 *   ...
 *   ROOM36  - Last room (54 decimal = $36 hex)
 *
 * To create room files from C64 data:
 * 1. Extract room resources from C64 version
 * 2. Save each as separate file with format:
 *    Byte 0-1: Size (lo/hi)
 *    Byte 2:   Type ($03 = room)
 *    Byte 3:   Index
 *    Byte 4+:  Room data (metadata + compressed layers)
 * ===========================================
 */
