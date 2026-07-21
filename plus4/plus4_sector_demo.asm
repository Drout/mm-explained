/*
 * plus4_sector_demo.asm
 *
 * Minimal Plus/4 program: read track 1 sector 1 into memory at $2000.
 * Uses DOS U1 block-read via KERNAL IEC routines. No includes.
 *
 * Assemble: java -jar KickAss.jar plus4_sector_demo.asm
 * Result:   256 bytes at $2000 contain raw sector data.
 */

// -----------------------------------------------------------------------
// KERNAL entry points (Plus/4)
// -----------------------------------------------------------------------
.const K_SETLFS = $FFBA     // Set logical file: A=LFN, X=device, Y=SA
.const K_SETNAM = $FFBD     // Set filename:     A=len, X/Y=addr lo/hi
.const K_OPEN   = $FFC0     // Open logical file
.const K_CLOSE  = $FFC3     // Close logical file (A=LFN)
.const K_CHKIN  = $FFC6     // Set input channel  (X=LFN)
.const K_CHKOUT = $FFC9     // Set output channel (X=LFN)
.const K_CHRIN  = $FFCF     // Read one byte -> A
.const K_CHROUT = $FFD2     // Write one byte <- A
.const K_CLRCHN = $FFCC     // Restore default channels

// -----------------------------------------------------------------------
// I/O configuration
// -----------------------------------------------------------------------
.const DEVICE   = 8         // Disk drive device number
.const CMD_LFN  = 15        // Logical file for command channel
.const DAT_LFN  = 2         // Logical file for data channel
.const DAT_SA   = 2         // Secondary address for "#" buffer
.const SEC_DRIVE = 0        // Drive number within the unit

// -----------------------------------------------------------------------
// Destination buffer
// -----------------------------------------------------------------------
.const SEC_BUFFER = $2000   // 256-byte sector lands here

// -----------------------------------------------------------------------
// Zero-page temporaries for PrintDecIO
// -----------------------------------------------------------------------
.const PTR_NEXT  = $60      // hundreds digit saved between loops
.label sec_track  = $61     // track to read (1-based)
.label sec_sector = $62     // sector to read (0-based)

// -----------------------------------------------------------------------
// BASIC upstart: 10 SYS 4352  ($1100)
// -----------------------------------------------------------------------
* = $1001
    .word next_line         // pointer to next BASIC line
    .word 10                // line number 10
    .byte $9E               // SYS token
    .text "4352"            // decimal address of start
    .byte $00               // end of line
next_line:
    .word $0000             // end of BASIC program

* = $1100
start:
    // -- set track and sector to read -----------------------------------
    lda #1
    sta sec_track
    lda #1
    sta sec_sector

    // -- open command channel: OPEN 15,8,15 (empty filename) ------------
    lda #$00
    jsr K_SETNAM            // filename length 0, address irrelevant
    lda #CMD_LFN
    ldx #DEVICE
    ldy #CMD_LFN
    jsr K_SETLFS
    jsr K_OPEN

    // -- open data channel: OPEN 2,8,2,"#" --------------------------------
    lda #$01                // filename length = 1
    ldx #<hash_name
    ldy #>hash_name
    jsr K_SETNAM
    lda #DAT_LFN
    ldx #DEVICE
    ldy #DAT_SA
    jsr K_SETLFS
    jsr K_OPEN

    // -- send U1 command on channel 15 ------------------------------------
    // Builds: "U1 <ch> <drive> <track> <sector>"
    ldx #CMD_LFN
    jsr K_CHKOUT            // direct output to command channel

    ldy #$00                // send "U1 " prefix
send_prefix:
    lda u1_prefix,y
    jsr K_CHROUT
    iny
    cpy #3
    bne send_prefix

    lda #DAT_LFN            // channel number
    jsr PrintDecIO
    lda #' '
    jsr K_CHROUT
    lda #SEC_DRIVE          // drive number
    jsr PrintDecIO
    lda #' '
    jsr K_CHROUT
    lda sec_track           // track
    jsr PrintDecIO
    lda #' '
    jsr K_CHROUT
    lda sec_sector          // sector
    jsr PrintDecIO

    jsr K_CLRCHN            // restore channels

    // -- read 256 bytes from data channel into SEC_BUFFER -----------------
    ldx #DAT_LFN
    jsr K_CHKIN             // set data channel as input

    ldy #$00
read_loop:
    jsr K_CHRIN             // read one byte -> A
    sta SEC_BUFFER,y        // store at $2000 + Y
    iny
    bne read_loop           // Y wraps 255->0, loop 256 times total

    jsr K_CLRCHN            // restore channels

    // -- close both channels ----------------------------------------------
    lda #DAT_LFN
    jsr K_CLOSE
    lda #CMD_LFN
    jsr K_CLOSE

    // -- done: return to BASIC -------------------------------------------
    rts

// PrintDecIO -- output byte in A as decimal ASCII to current output channel.
// Suppresses leading zeros (minimum output is a single "0" digit).
// Clobbers A, X. Uses PTR_NEXT ($60) as scratch.
PrintDecIO:
    ldx #0
pd_h:
    cmp #100
    bcc pd_tens             // A < 100: done counting hundreds
    sbc #100                // carry set by cmp above, so sbc = A-100
    inx
    jmp pd_h
pd_tens:
    stx PTR_NEXT            // save hundreds digit
    ldx #0
pd_t:
    cmp #10
    bcc pd_ones             // A < 10: done counting tens
    sbc #10                 // carry set by cmp above, so sbc = A-10
    inx
    jmp pd_t
pd_ones:
    pha                     // save ones digit
    lda PTR_NEXT
    beq pd_no_h             // hundreds == 0: suppress it
    clc
    adc #48                 // '0' + hundreds digit
    jsr K_CHROUT
pd_no_h:
    txa                     // tens digit
    bne pd_do_t             // tens != 0: always print it
    lda PTR_NEXT
    beq pd_no_t             // both hundreds and tens are 0: suppress tens
pd_do_t:
    txa
    clc
    adc #48                 // '0' + tens digit
    jsr K_CHROUT
pd_no_t:
    pla
    clc
    adc #48                 // '0' + ones digit (always printed)
    jsr K_CHROUT
    rts

// -----------------------------------------------------------------------
// Data
// -----------------------------------------------------------------------
hash_name:
    .text "#"

u1_prefix:
    .text "U1 "              // 3-byte prefix; remainder sent via PrintDecIO
