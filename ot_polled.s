; ============================================================================
; ot_polled.s - the game owns the machine (built with -DPOLLED=1)
;
; QDOS's 50 Hz interrupts cost 12.8% of a 128K QL (5.1 ms per 40 ms frame,
; measured by prof_irqcost).  So after initialisation the game runs in
; supervisor mode with interrupts OFF, on its own stack:
;
;  * CLOCK: the frame interrupt still raises bit 3 of PC_INTR ($18021).
;    POLL tests it; poll_tick clears it and counts `clock`.  The flag holds
;    ONE tick, so NOTHING between two POLLs may take 20 ms or more, or a tick
;    is lost and the game and the music run slow.  poll_tick's TICK HOOK runs
;    the 25 Hz audio step (AY music + SFX) on every 2nd tick: a fixed
;    timebase, independent of frame overruns.
;  * KEYBOARD: KEYROW read straight from the IPC (protocol as Revs), ONE row:
;    row 1 = arrows, SPACE, ESC, ENTER (= joystick 1 too).  ENTER resets the
;    level (R and W/A/S/D are gone: each extra row costs ~1.57 ms).  A changed row
;    is re-read until two reads agree (Q-emuLator's IPC sometimes answers
;    wrongly after a BEEP), $FF is "nothing".  kb_cur = held game keys,
;    kb_new = keys that went down this scan.  A held direction repeats moves.
;  * QDOS calls still work: MT.IPCOM (beeper) as before; file I/O in the
;    profiler briefly re-enables interrupts (see prof_write_file).
;  * Leaving: drain the IPC's keystrokes, restore QDOS's stack, interrupts on,
;    user mode - only from the top level (exit_game), where no return
;    addresses are pending.
; ============================================================================

; (PC_INTR, PC_IPCWR/RD, SV_PCINT_A, RTC_SECS and POLL: oldtower.s header)
IPC_WAIT        equ     4000            ; IPC handshake polls before giving up
POLLED_STACK    equ     1536

; game key bits in kb_cur / kb_new
KB_UP           equ     0
KB_DOWN         equ     1
KB_LEFT         equ     2
KB_RIGHT        equ     3
KB_SPACE        equ     4
KB_ESC          equ     5
KB_ENTER        equ     7

; (TO_QDOS / FROM_QDOS: oldtower.s header)
        even
clock:          dc.w    0               ; 50 Hz ticks seen by POLL
pc_clear_f:     dc.w    0               ; mask bits | frame clear (low byte)
pc_clear_i:     dc.w    0               ; mask bits | IPC clear (low byte)
qdos_ssp:       dc.l    0               ; QDOS's supervisor stack, for leaving
kb_cur:         dc.w    0
kb_new:         dc.w    0
row_last:       dc.b    0,0,0,0,0,0,0,0 ; each row as last believed
        even

; ----------------------------------------------------------------------------
; enter_polled_mode - call with bsr from the TOP LEVEL (start).
; ----------------------------------------------------------------------------
enter_polled_mode:
        movea.l (sp)+,a0                ; return address (user stack)
        moveq   #0,d0
        move.b  SV_PCINT_A,d0
        andi.b  #$E0,d0                 ; the mask bits QDOS keeps
        move.w  d0,d1
        ori.w   #PC_INTRF,d1
        lea     pc_clear_f(pc),a1
        move.w  d1,(a1)
        ori.w   #PC_INTRI,d0
        lea     pc_clear_i(pc),a1
        move.w  d0,(a1)
        trap    #0                      ; supervisor mode
        ori.w   #$0700,sr               ; interrupts off
        lea     qdos_ssp(pc),a1
        move.l  sp,(a1)
        lea     polled_stack_top(pc),sp ; our own stack (QDOS's is small)
        move.b  pc_clear_f+1(pc),PC_INTR ; drop any stale frame flag
        ; The profiler and bench read the tick through tick_counter_ptr
        lea     clock(pc),a1
        lea     tick_counter_ptr(pc),a2
        move.l  a1,(a2)
        ; qsound_init synced prev_tick to QDOS's tick (time since boot); our
        ; clock starts at 0, so re-sync or the first wait lasts that long
        lea     prev_tick(pc),a2
        move.w  (a1),(a2)
        bsr     kb_sync                 ; keys already down are not "new"
        jmp     (a0)

; ----------------------------------------------------------------------------
; leave_polled_mode - from the TOP LEVEL only (exit_game).  Falls back to the
; caller in user mode with interrupts on.
; ----------------------------------------------------------------------------
leave_polled_mode:
        movea.l (sp)+,a0
        bsr     ipc_drain               ; keystrokes QDOS would otherwise find
        move.b  pc_clear_f+1(pc),PC_INTR
        movea.l qdos_ssp(pc),sp
        andi.w  #$D8FF,sr               ; user mode, interrupts on
        jmp     (a0)

; ----------------------------------------------------------------------------
; poll_tick - the frame flag was seen: count it.  Keeps all registers & CCR.
; ----------------------------------------------------------------------------
poll_tick:
        move.w  sr,-(sp)
        move.l  a0,-(sp)
        move.b  pc_clear_f+1(pc),PC_INTR
        lea     clock(pc),a0
        addq.w  #1,(a0)
        ; TICK HOOK: the 25 Hz audio step (music + SFX mix) on even ticks,
        ; so music keeps time whatever the game frame rate does
        ifnd MUSIC50
        btst    #0,1(a0)
        bne.s   .odd
        endif                           ; MUSIC50 (test): every tick, 50 Hz
        movea.l audio_tick_ptr(pc),a0   ; (all registers preserved)
        jsr     (a0)
.odd:
        move.l  (sp)+,a0
        move.w  (sp)+,sr
        rts

; ----------------------------------------------------------------------------
; wait_frame_polled - adaptive pacing on `clock` (same rules as the QDOS
; version: wait until FRAME_TICKS have passed since the last frame; after an
; overrun, don't wait).  PROFILE: counts idle spins.
; ----------------------------------------------------------------------------
wait_frame_polled:
        movem.l d0-d1/a0,-(sp)
        POLL
        move.w  clock(pc),d0
        sub.w   prev_tick(pc),d0
        ifd PROFILE
        bsr     prof_entry
        endif
        moveq   #0,d1
        cmpi.w  #FRAME_TICKS,d0
        bhs.s   .overrun                ; unsigned: a negative gap resyncs
        lea     frame_overrun(pc),a0
        clr.w   (a0)
.wait:
        addq.l  #1,d1
        POLL
        move.w  clock(pc),d0
        sub.w   prev_tick(pc),d0
        cmpi.w  #FRAME_TICKS,d0
        blo.s   .wait
        bra.s   .save
.overrun:
        lea     frame_overrun(pc),a0
        move.w  #1,(a0)
.save:
        ifd PROFILE
        bsr     prof_frame              ; d1 = idle spins
        endif
        add.w   prev_tick(pc),d0
        lea     prev_tick(pc),a0
        move.w  d0,(a0)
        movem.l (sp)+,d0-d1/a0
        rts

; ----------------------------------------------------------------------------
; KEYBOARD
; A KEYROW transaction costs ~1.57 ms (bit-by-bit handshake with the 8049), so
; rows are read only when they matter.  read_row keeps each row's last value
; in row_last; kb_cur is composed from row_last, so a row not read this scan
; keeps its old state and cannot produce a false "new" press.
;   kb_scan d0 = which rows: bit n = row n (KB_ROWS_*)
; kb_sync - read row 1 (KB_ROWS_ALL); the current state becomes "old" (kb_new = 0).
; ----------------------------------------------------------------------------
KB_ROWS_1       equ     %00000010
KB_ROWS_ALL     equ     KB_ROWS_1       ; the only row the game uses

kb_scan:
        movem.l d0-d3/a0,-(sp)
        bsr.s   kb_read_rows
        bsr.s   kb_compose              ; d2 = held game keys
        lea     kb_cur(pc),a0
        move.w  (a0),d3                 ; old
        move.w  d2,(a0)
        not.w   d3
        and.w   d2,d3                   ; went down now
        lea     kb_new(pc),a0
        move.w  d3,(a0)
        movem.l (sp)+,d0-d3/a0
        rts

kb_sync:
        movem.l d0-d3/a0,-(sp)
        moveq   #KB_ROWS_ALL,d0
        bsr.s   kb_read_rows
        bsr.s   kb_compose
        lea     kb_cur(pc),a0
        move.w  d2,(a0)
        lea     kb_new(pc),a0
        clr.w   (a0)
        movem.l (sp)+,d0-d3/a0
        rts

; kb_read_rows - d0.b = row mask.  Reads those rows into row_last.
kb_read_rows:
        movem.l d0-d2,-(sp)
        move.b  d0,d2
        moveq   #0,d0
.row:   btst    d0,d2
        beq.s   .next
        bsr     read_row
.next:  addq.w  #1,d0
        cmpi.w  #8,d0
        blo.s   .row
        movem.l (sp)+,d0-d2
        rts

; kb_compose - d2.w = game key bits from row_last.  Uses d1, a0.
kb_compose:
        moveq   #0,d2
        lea     row_last(pc),a0
        move.b  1(a0),d1                ; row 1
        cmpi.b  #$FF,d1
        beq.s   .done                   ; "every key" = nothing
        lsr.b   #1,d1                   ; bit 0 ENTER
        bcc.s   .r1a
        bset    #KB_ENTER,d2
.r1a:   lsr.b   #1,d1                   ; LEFT
        bcc.s   .r1b
        bset    #KB_LEFT,d2
.r1b:   lsr.b   #1,d1                   ; UP
        bcc.s   .r1c
        bset    #KB_UP,d2
.r1c:   lsr.b   #1,d1                   ; ESC
        bcc.s   .r1d
        bset    #KB_ESC,d2
.r1d:   lsr.b   #1,d1                   ; RIGHT
        bcc.s   .r1e
        bset    #KB_RIGHT,d2
.r1e:   lsr.b   #2,d1                   ; (\) then SPACE
        bcc.s   .r1f
        bset    #KB_SPACE,d2
.r1f:   lsr.b   #1,d1                   ; DOWN
        bcc.s   .done
        bset    #KB_DOWN,d2
.done:  rts

; kb_rows_for_play - d0 = rows to read this main_loop frame.
;   stopped: row 1 every frame; moving: every other frame (directions are
;   ignored while moving; ESC/ENTER/SPACE are seen within 80 ms).
kb_rows_for_play:
        move.l  a0,-(sp)
        lea     kb_phase(pc),a0
        addq.w  #1,(a0)
        moveq   #KB_ROWS_1,d0
        move.w  hero_dir(pc),d1
        beq.s   .out                    ; stopped
        btst    #0,1(a0)
        beq.s   .out
        moveq   #0,d0                   ; moving, odd frame: no read
.out:   move.l  (sp)+,a0
        rts

kb_phase:       dc.w    0

; read_row - d0 = row.  Returns d1.b, a bit set for each key down ($FF read
; as nothing).  A changed row is re-read (up to 4 more) until two reads agree
; or it is back to the old value.  Changes only d1 (d0 kept; others saved).
read_row:
        movem.l d2/d4/a0,-(sp)
        move.w  d0,-(sp)
        bsr.s   read_once
        move.w  (sp),d0
        lea     row_last(pc),a0
        cmp.b   0(a0,d0.w),d1
        beq.s   .same
        moveq   #3,d2
.again:
        move.b  d1,d4
        move.w  (sp),d0
        bsr.s   read_once
        move.w  (sp),d0
        cmp.b   d4,d1
        beq.s   .agree
        cmp.b   0(a0,d0.w),d1
        dbeq    d2,.again
.agree:
        move.b  d1,0(a0,d0.w)
.same:
        move.w  (sp)+,d0
        movem.l (sp)+,d2/d4/a0
        rts

; read_once - one KEYROW transaction: 8 bits out ($9r), 8 bits back.
; Tight bit loop: IPC registers in a1/a2, one btst/dbeq per wait spin
; (about half the CPU time of the ipc_bit version).
read_once:
        movem.l d0/d2-d4/a1-a2,-(sp)
        lea     PC_IPCWR,a1
        lea     PC_IPCRD,a2
        moveq   #9,d4
        lsl.w   #4,d4
        or.w    d0,d4                   ; $9r
        moveq   #7,d1
.send:  moveq   #%1100,d2
        btst    d1,d4
        beq.s   .s0
        addq.b  #2,d2                   ; %1110 = a 1
.s0:    move.b  d2,(a1)
        move.w  #IPC_WAIT,d3
.sw:    btst    #6,(a2)
        dbeq    d3,.sw
        dbra    d1,.send
        moveq   #0,d4
        moveq   #7,d1
.recv:  move.b  #%1110,(a1)
        move.w  #IPC_WAIT,d3
.rw:    btst    #6,(a2)
        dbeq    d3,.rw
        move.b  (a2),d0
        add.b   d0,d0
        addx.b  d4,d4
        dbra    d1,.recv
        move.b  pc_clear_i+1(pc),PC_INTR ; clear the IPC interrupt raised
        move.l  d4,d1
        movem.l (sp)+,d0/d2-d4/a1-a2
        rts

; ipc_bit - one bit each way.  d2.b = byte to write.  Returns the IPC's bit
; in bit 7 of d0.  Uses d0, d3.
ipc_bit:
        move.b  d2,PC_IPCWR
        move.w  #IPC_WAIT,d3
.wait:  btst    #6,PC_IPCRD
        beq.s   .ok
        dbra    d3,.wait
        moveq   #0,d0                   ; no answer: give up on this bit
        rts
.ok:    move.b  PC_IPCRD,d0
        rts

; ipc_send - d1.w bits of d4, top first.  Uses d0-d3.
ipc_send:
        subq.w  #1,d1
.bit:   moveq   #%1100,d2
        btst    d1,d4
        beq.s   .zero
        moveq   #%1110,d2
.zero:  bsr.s   ipc_bit
        dbra    d1,.bit
        rts

; ipc_recv - d1.w bits into d4, top first.  Uses d0-d3.
ipc_recv:
        moveq   #0,d4
        subq.w  #1,d1
.bit:   moveq   #%1110,d2
        bsr.s   ipc_bit
        add.b   d0,d0
        addx.l  d4,d4
        dbra    d1,.bit
        rts

; ipc_drain - empty the IPC's keystroke buffer before handing back to QDOS.
ipc_drain:
        movem.l d0-d5,-(sp)
        moveq   #1,d4                   ; status
        moveq   #4,d1
        bsr.s   ipc_send
        moveq   #8,d1
        bsr.s   ipc_recv
        btst    #0,d4
        beq.s   .empty
        moveq   #8,d4                   ; keystrokes: a nibble of count, then each
        moveq   #4,d1
        bsr.s   ipc_send
        moveq   #4,d1
        bsr.s   ipc_recv
        moveq   #7,d5
        and.w   d4,d5
        bra.s   .more
.key:   moveq   #12,d1
        bsr.s   ipc_recv
.more:  dbra    d5,.key
.empty:
        move.b  pc_clear_i+1(pc),PC_INTR
        movem.l (sp)+,d0-d5
        rts

; ----------------------------------------------------------------------------
; Game-side key handling on kb_cur / kb_new (replaces the IO.FBYTE versions)
; ----------------------------------------------------------------------------
; read_keyboard_polled - once per main_loop frame.  Same decisions as the
; console version, but a HELD direction starts a new move as soon as the hero
; stops (held key repeats).  SPACE, ENTER (reset) and ESC act on the press only.
read_keyboard_polled:
        movem.l d0-d2/a0,-(sp)
        bsr     kb_rows_for_play        ; d0 = rows worth reading now (d1 used)
        bsr     kb_scan
        move.w  kb_new(pc),d1
        btst    #KB_ESC,d1
        bne     .quit
        move.w  hero_exit_active(pc),d0 ; no input during the exit animation
        bne     .done
        btst    #KB_ENTER,d1
        bne     .reset_lvl
        btst    #KB_SPACE,d1
        bne     .swap_hero
        move.w  hero_dir(pc),d0
        bne     .done                   ; moving: directions wait
        move.w  kb_cur(pc),d1           ; held keys
        moveq   #DIR_UP,d0
        btst    #KB_UP,d1
        bne     .set_dir
        moveq   #DIR_DOWN,d0
        btst    #KB_DOWN,d1
        bne     .set_dir
        moveq   #DIR_LEFT,d0
        btst    #KB_LEFT,d1
        bne     .set_dir
        moveq   #DIR_RIGHT,d0
        btst    #KB_RIGHT,d1
        bne     .set_dir
        ifd AUTOPILOT
        bsr     prof_auto_key           ; d0.l = 0 & d1 = arrow code, or -1
        tst.l   d0
        bmi     .done
        moveq   #DIR_UP,d0
        cmpi.b  #208,d1
        beq     .set_dir
        moveq   #DIR_DOWN,d0
        cmpi.b  #216,d1
        beq     .set_dir
        moveq   #DIR_LEFT,d0
        cmpi.b  #192,d1
        beq     .set_dir
        moveq   #DIR_RIGHT,d0
        bra     .set_dir
        endif
        bra     .done
.set_dir:
        lea     hero_dir(pc),a0
        move.w  d0,(a0)
        lea     hero_last_dir(pc),a0
        move.w  d0,(a0)
        movea.l sound_to_play_ptr(pc),a0
        move.w  #SFX_FLY,(a0)
        bra     .done
.reset_lvl:
        lea     reset_level_flag(pc),a0
        move.w  #1,(a0)
        bra     .done
.swap_hero:
        move.w  hero_dir(pc),d0
        bne     .done
        bsr     switch_hero
        bra     .done
.quit:
        lea     quit_flag(pc),a0
        move.w  #1,(a0)
.done:
        movem.l (sp)+,d0-d2/a0
        rts

; check_title_key_polled - d0 = 1 if SPACE went down, 2 if ENTER (keys
; page), else 0; ESC sets quit.
check_title_key_polled:
        move.l  a0,-(sp)
        moveq   #KB_ROWS_1,d0
        bsr     kb_scan
        move.w  kb_new(pc),d0
        btst    #KB_ESC,d0
        beq.s   .no_esc
        lea     quit_flag(pc),a0
        move.w  #1,(a0)
.no_esc:
        btst    #KB_SPACE,d0
        bne.s   .fire
        btst    #KB_ENTER,d0
        beq.s   .none
        moveq   #2,d0
        bra.s   .out
.none:
        ifd AUTOPILOT
        bsr     prof_auto_firekey
        else
        moveq   #0,d0
        endif
        bra.s   .out
.fire:
        moveq   #1,d0
.out:
        move.l  (sp)+,a0
        rts

; check_space_key_polled - d0 = 1 if SPACE went down; ESC sets quit (d0 = 0).
check_space_key_polled:
        move.l  a0,-(sp)
        moveq   #KB_ROWS_1,d0
        bsr     kb_scan
        move.w  kb_new(pc),d0
        btst    #KB_ESC,d0
        beq.s   .no_esc
        lea     quit_flag(pc),a0
        move.w  #1,(a0)
        moveq   #0,d0
        bra.s   .out
.no_esc:
        btst    #KB_SPACE,d0
        bne.s   .space
        ifd AUTOPILOT
        bsr     prof_auto_firekey
        else
        moveq   #0,d0
        endif
        bra.s   .out
.space:
        moveq   #1,d0
.out:
        move.l  (sp)+,a0
        rts

; read_rtc - d0.l = RTC seconds (read until two reads agree)
read_rtc:
        move.l  d1,-(sp)
.again: move.l  RTC_SECS,d0
        move.l  RTC_SECS,d1
        cmp.l   d0,d1
        bne.s   .again
        move.l  (sp)+,d1
        rts

        even
polled_stack:   ds.b    POLLED_STACK
polled_stack_top:
