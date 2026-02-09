; ============================================================
; Old Tower - Music Edition (QDOS Executable)
; ============================================================
; QDOS executable version - run with EXEC_W or EX command.
; Full audio: QSound music + SFX, or IPC beeper fallback.
; Memory: ~110KB. Requires 128KB QL or expanded system.
; Music uses TBK compression, mixed with AFX sound effects.
; ============================================================
; Levels: 00 (title), 01-15 and 21-25 (21 levels total)
; Press SPACE to swap between heroes (or advance when level won)
; Press R to reset level, ESC to return to title (quit from title)
; ============================================================

; QDOS trap codes
MT_FRJOB        equ $05         ; Force remove job (terminate)
MT_DMODE        equ $10         ; Set/read display mode

        org     0

; Screen constants
SCREEN_BASE     equ $20000
SCREEN_STRIDE   equ 128
TILE_HEIGHT     equ 8
TILE_Y_BYTES    equ TILE_HEIGHT*SCREEN_STRIDE

; Playfield (screen)
PLAY_X          equ 10
PLAY_Y          equ 4
PLAY_W          equ 12
PLAY_H          equ 24
X_OFFSET_BYTES  equ PLAY_X*4
Y_OFFSET_BYTES  equ PLAY_Y*TILE_HEIGHT*SCREEN_STRIDE
PLAYFIELD_BASE  equ SCREEN_BASE+Y_OFFSET_BYTES+X_OFFSET_BYTES

; Side columns (drawn directly to screen, not buffered)
COL_LEFT_X      equ PLAY_X-1            ; Left column at tile 9
COL_RIGHT_X     equ PLAY_X+PLAY_W       ; Right column at tile 22
COL_LEFT_ADDR   equ SCREEN_BASE+Y_OFFSET_BYTES+(COL_LEFT_X*4)
COL_RIGHT_ADDR  equ SCREEN_BASE+Y_OFFSET_BYTES+(COL_RIGHT_X*4)
; Brick pattern colors
COL_BRICK       equ $00AA00AA           ; Red brick
COL_MORTAR      equ $00000000           ; Black mortar
COL_BRICK_HALF  equ $00AA0000           ; Half brick (left red, right black)

; World/Level
LEVEL_W         equ 12
LEVEL_H         equ 64
LEVEL_SIZE      equ LEVEL_W*LEVEL_H
SCROLL_MARGIN   equ 4
NUM_TILES       equ 32
NUM_LEVELS      equ 21

; Buffer-window constants
BUF_STRIDE      equ 48          ; 12 tiles × 4 bytes per scanline
BUF_HEIGHT      equ 512         ; 64 tiles × 8 pixels
BUF_SIZE        equ BUF_STRIDE*BUF_HEIGHT  ; = 24576 bytes
VIEW_HEIGHT_PX  equ PLAY_H*8    ; 192 pixels visible

; Camera constants (Spectrum-style)
CAM_ANCHOR_Y    equ 10          ; Hero anchor point (tiles from top)
CAM_ANCHOR_PX   equ CAM_ANCHOR_Y*8  ; = 80 pixels
MAX_WINDOW_Y    equ (LEVEL_H-PLAY_H)*8  ; = 320 pixels (40 tiles * 8)

; Tile types
TILE_EMPTY      equ 0
TILE_HIDDEN     equ 1           ; Crumbling block - passable, transforms on contact
TILE_SPIKE_UP   equ 2           ; Spike pointing up - kills from below
TILE_SPIKE_DN   equ 3           ; Spike pointing down - kills from above
TILE_SPIKE_R    equ 4           ; Spike pointing right - kills from left
TILE_SPIKE_L    equ 5           ; Spike pointing left - kills from right
TILE_COIN_SM    equ 6           ; Small coin (dot)
TILE_COIN_LG    equ 7           ; Large coin (circle)
TILE_BLACK      equ 8           ; Pure black tile for logo background
TILE_EXIT       equ 13          ; Exit tile - active when all coins collected
TILE_ONEWAY_DN  equ 14          ; One-way: passable UP, blocks DOWN
TILE_ONEWAY_UP  equ 15          ; One-way: passable DOWN, blocks UP
TILE_REFLECT1   equ 16          ; Reflector \ - redirects movement
TILE_REFLECT2   equ 17          ; Reflector / - redirects movement
TILE_HERO_DOWN  equ 18          ; Second hero facing down
TILE_HERO_UP    equ 19          ; Second hero facing up
TILE_HERO_LEFT  equ 20          ; Second hero facing left
TILE_HERO_RIGHT equ 21          ; Second hero facing right
TILE_BOUNCE     equ 26          ; Bounce tile - reverses vertical movement
TILE_CRACK      equ 27          ; Cracked block - solid until bumped, then removed
TILE_UNHIDDEN   equ 28          ; Solid block after transformation
TILE_SOLID_1    equ 29
TILE_SOLID_2    equ 30
TILE_HERO_START equ 31

; Directions
DIR_STOP        equ 0
DIR_UP          equ 1
DIR_DOWN        equ 2
DIR_LEFT        equ 3
DIR_RIGHT       equ 4

; Trail
NUM_TRAIL_SLOTS equ 24
TRAIL_SLOT_SIZE equ 10
TRAIL_IDX_END   equ $FF

; QSound / AY-3-8910 constants
LPSG_IO         equ $12000      ; QSound PIA base address
AY_NUM_REGS     equ 14          ; AY-3-8910 register count
AFX_NUM_CH      equ 3           ; AFX channels (A, B, C)
AFX_CH_SIZE     equ 8           ; Bytes per channel slot

; QSound detection modes
QSND_NONE       equ 0           ; No sound hardware
QSND_VECTOR     equ 1           ; QSound firmware API (SV.AYJMP)
QSND_BEEPER     equ 3           ; IPC beeper fallback

; IPC constants
MT_IPCOM        equ $11         ; trap #1 function code
IPC_CMD_SOUND   equ $0A         ; IPC sound command byte

; Sound effect IDs (matching Spectrum ot.asm)
SFX_CANNON      equ 0
SFX_FLY         equ 1           ; Hero movement
SFX_SWAP        equ 2           ; Hero switch / menu select
SFX_DEAD        equ 3           ; Player death
SFX_LAND        equ 4           ; Landing
SFX_EXIT        equ 5           ; Level exit
SFX_FIN         equ 6           ; Level complete
SFX_PUSH        equ 7           ; (unused in Spectrum)
SFX_GOLD        equ 8           ; Coin collect
SFX_NONE        equ 255         ; No effect queued

; Music track IDs
MUSIC_MENU      equ 0           ; Title screen
MUSIC_LEVEL1    equ 1           ; Levels 1-10
MUSIC_LEVEL2    equ 2           ; Levels 11-15
MUSIC_LEVEL3    equ 3           ; Levels 16-20 (21-25)
MUSIC_OUTRO     equ 4           ; Outro sequence
MUSIC_NONE      equ 255         ; No music / stop
NUM_TRACKS      equ 5

; Enemy constants
ENEMY_RIGHT     equ 32              ; Tile type for right-moving bat
ENEMY_LEFT      equ 33              ; Tile type for left-moving bat
MAX_ENEMIES     equ 4               ; Max enemies per level
ENEMY_SLOT_SIZE equ 12              ; Bytes per enemy slot
; Slot structure: +0=active, +2=tile_x, +4=tile_y, +6=dir, +8=frame, +10=delay
ENEMY_ANIM_DELAY equ 2              ; Ticks per animation frame
ENEMY_ANIM_FRAMES equ 4             ; 4 frames: 0,1,2,3

; Death animation constants (Spectrum-style kabum effect)
DEAD_DELAY       equ 32              ; Total death animation frames
DEAD_KABUM_START equ 25              ; Frame when kabum color cycling starts
DEAD_COLOR_COUNT equ 7               ; Number of colors in death sequence

; Lives HUD
MAX_LIVES        equ 5               ; Maximum displayable lives

; Coin animation (buffer-based approach)
COIN_ANIM_FRAMES equ 4               ; 4 animation frames (0-3)
COIN_ANIM_SKIP   equ 4               ; Update every N frames (original speed)
COIN_TILE_SIZE   equ 32              ; Bytes per expanded tile (8 rows × 4 bytes)
COIN_TILE_OFFSET equ TILE_COIN_LG*COIN_TILE_SIZE  ; Offset in expanded_tiles (7×32=224)
MAX_COINS        equ 32              ; Max large coins to cache per level

; Exit animation (color cycling when active)
EXIT_ANIM_FRAMES equ 4               ; 4 color frames for cycling
EXIT_ANIM_SKIP   equ 3               ; Update every N frames (faster than coins)
EXIT_TILE_OFFSET equ TILE_EXIT*COIN_TILE_SIZE  ; Offset in expanded_tiles (13×32=416)
MAX_EXITS        equ 4               ; Max exit tiles to cache per level

; Cannon/Bullet constants
TILE_CANNON_OPEN_R equ 22            ; Right-facing cannon open (firing)
TILE_CANNON_OPEN_L equ 23            ; Left-facing cannon open (firing)
TILE_CANNON_R    equ 24              ; Right-facing cannon tile (closed)
TILE_CANNON_L    equ 25              ; Left-facing cannon tile (closed)
MAX_CANNONS      equ 8               ; Maximum cannons per level
MAX_BULLETS      equ 2               ; Maximum active bullets

; Cannon data structure offsets (10 bytes per cannon)
CANNON_ACTIVE    equ 0               ; 1 = active (word)
CANNON_X         equ 2               ; Grid X position (word)
CANNON_Y         equ 4               ; Grid Y position (word)
CANNON_DIR       equ 6               ; Direction: TILE_CANNON_R or TILE_CANNON_L (word)
CANNON_TIMER     equ 8               ; Per-cannon timer 0-255 (word)
CANNON_SIZE      equ 10              ; Total bytes per cannon record

; Bullet data structure offsets (8 bytes per bullet)
BULLET_ACTIVE    equ 0               ; 1 = active, 0 = inactive (word)
BULLET_X         equ 2               ; Grid X position (word)
BULLET_Y         equ 4               ; Grid Y position (word)
BULLET_DIR       equ 6               ; Direction: DIR_LEFT or DIR_RIGHT (word)
BULLET_SIZE      equ 8               ; Total bytes per bullet record

; Hero slot structure offsets (18 bytes per hero)
HERO_SLOT_X      equ 0               ; Grid X position (word)
HERO_SLOT_Y      equ 2               ; Grid Y position (word)
HERO_SLOT_DIR    equ 4               ; Current direction (word)
HERO_SLOT_LASTD  equ 6               ; Last direction for sprite (word)
HERO_SLOT_FLY    equ 8               ; Flying flag (word)
HERO_SLOT_ANIM   equ 10              ; Animation frame (word)
HERO_SLOT_ACT    equ 12              ; Active flag (word)
HERO_SLOT_STARTX equ 14              ; Spawn X position (word)
HERO_SLOT_STARTY equ 16              ; Spawn Y position (word)
HERO_SLOT_SIZE   equ 18              ; Total bytes per hero slot
MAX_HEROES       equ 2               ; Maximum heroes per level

; Colors
COL4_BLACK      equ $0000
COL4_BLUE       equ $0055
COL4_RED        equ $00AA
COL4_MAGENTA    equ $00FF
COL4_GREEN      equ $AA00
COL4_CYAN       equ $AA55
COL4_YELLOW     equ $AAAA
COL4_WHITE      equ $AAFF

; QDOS
IO_OPEN         equ $01
IO_CLOSE        equ $02
IO_FBYTE        equ $01
IO_SSTRG        equ $07

; Game states
GS_GAMEPLAY     equ 0           ; Normal gameplay
GS_WIN          equ 1           ; Level won - waiting for key press
GS_TITLE        equ 2           ; Title screen - waiting for fire
GS_OUTRO        equ 3           ; Game complete outro screen

; Win state animation
WIN_FLASH_RATE  equ 8           ; Flash "PRESS SPACE" every N frames
TITLE_FLASH_RATE equ 10         ; Flash "PUSH FIRE TO START" rate

; ============================================================
; Entry - QDOS Job Entry Point
; ============================================================
start:
        ; No register save needed - job terminates with MT.FRJOB
        bsr     open_console
        tst.l   d0
        bmi     exit_fail

        ; Set MODE 8 using QDOS (compatible across emulators)
        moveq   #MT_DMODE,d0
        moveq   #8,d1           ; MODE 8
        moveq   #-1,d2          ; Clear screen
        trap    #1
        bsr     expand_tiles

        ; Draw side images once at program start - they persist forever
        bsr     clear_screen
        bsr     draw_side_images

        ; Set up SFX function pointers, init QSound, init diag buffer
        bsr     sfx_setup_ptrs

        ; Show title screen first
        bsr     init_title_screen
        bra     title_loop

; ============================================================
; start_game - Called after title screen, starts level 1
; ============================================================
start_game:
        ; Initialize to level 1 (absolute addressing for far variable)
        lea     start(pc),a0
        adda.l  #current_level,a0
        move.w  #1,(a0)

        ; Start level 1 music (absolute addressing for far variable)
        lea     start(pc),a0
        adda.l  #music_to_play,a0
        move.w  #MUSIC_LEVEL1,(a0)

        ; Load first level
        bsr     load_current_level
        bsr     cache_coin_positions        ; Cache coin positions for fast animation
        bsr     cache_exit_positions        ; Cache exit positions for animation

        bsr     clear_screen_preserve_sides ; Preserve side graphics
        bsr     find_hero_start
        bsr     init_enemies                ; Initialize enemies before rendering
        bsr     build_cannon_list           ; Build cannon list and clear bullets
        bsr     init_scroll

        ; Use absolute addressing for far variables
        lea     start(pc),a0
        adda.l  #hero_dir,a0
        clr.w   (a0)
        lea     start(pc),a0
        adda.l  #hero_last_dir,a0
        move.w  #DIR_DOWN,(a0)
        lea     start(pc),a0
        adda.l  #hero_fly,a0
        clr.w   (a0)
        lea     start(pc),a0
        adda.l  #anim_frame,a0
        clr.w   (a0)
        lea     start(pc),a0
        adda.l  #anim_counter,a0
        move.w  #4,(a0)
        lea     start(pc),a0
        adda.l  #quit_flag,a0
        clr.w   (a0)
        lea     start(pc),a0
        adda.l  #reset_level_flag,a0
        clr.w   (a0)
        lea     start(pc),a0
        adda.l  #active_trails,a0
        clr.w   (a0)
        lea     start(pc),a0
        adda.l  #hero_drawn_x,a0
        move.w  #-1,(a0)
        ; Initialize coin animation
        lea     coin_anim_frame(pc),a0
        clr.w   (a0)
        lea     coin_anim_ctr(pc),a0
        move.w  #1,(a0)                     ; Start with update on first frame

        ; Set game state to gameplay
        lea     game_state(pc),a0
        move.w  #GS_GAMEPLAY,(a0)

        bsr     clear_trails
        bsr     render_playfield_to_buffer  ; Render level to off-screen buffer
        bsr     copy_window_to_screen       ; Copy visible portion to screen
        bsr     draw_scrolling_columns      ; Draw side columns
        bsr     draw_hero_force
        ; Removed draw_level_num (level indicator removed)
        ; Force lives redraw (title screen set prev_lives, clear_screen wiped hearts)
        ; absolute addressing for far variable
        lea     start(pc),a0
        adda.l  #prev_lives,a0
        move.w  #-1,(a0)
        bsr     draw_lives                  ; Draw lives HUD

        ; Reset score for new game
        lea     score(pc),a0
        clr.l   (a0)
        lea     prev_score(pc),a0
        move.l  #-1,(a0)                    ; Force redraw
        bsr     draw_score

main_loop:
        ; Clear flags
        lea     hero_hit_spike(pc),a0
        clr.w   (a0)
        lea     hero_bounce_dir(pc),a0
        clr.w   (a0)
        bsr     wait_vsync
        movea.l sfx_update_ptr(pc),a6  ; update sound
        jsr     (a6)
        bsr     update_animation
        bsr     update_coin_animation       ; Animate large coins in buffer
        bsr     update_exit_animation       ; Animate exits when active
        ; update_hero_exit_anim merged into composite_hero_to_buffer
        bsr     read_keyboard
        ; Check for level reset request
        move.w  reset_level_flag(pc),d0
        bne     handle_reset_level
        ; First movement step (1 tile)
        bsr     update_hero_movement
        ; Check if hero hit a spike during first step
        move.w  hero_hit_spike(pc),d0
        bne     handle_death                ; Hit spike! Die
        ; Check if level complete after first step
        move.w  level_complete_flag(pc),d0
        bne     handle_level_complete       ; Reached exit on first step
        ; Second movement step REMOVED (1 tile per tick)
        bsr     update_enemies              ; Update enemy positions/animation
        bsr     do_bullets                  ; Bullet movement (before cannon fire!)
        bsr     do_cannons                  ; Cannon timing and firing
        bsr     check_collision             ; Check hero/enemy collision
        tst.w   d0
        bne     handle_death                ; Collision! Handle death
        bsr     check_bullet_collision      ; Check hero/bullet collision
        tst.w   d0
        bne     handle_death                ; Hit by bullet!
        move.w  level_complete_flag(pc),d0  ; Check flag (set by process_tile_effects)
        bne     handle_level_complete       ; Level complete!
        bsr     update_camera               ; Smooth camera tracking
        ; Composite all sprites into buffer before copy (no flicker)
        bsr     composite_trails_to_buffer  ; Draw trails into buffer (behind sprites)
        bsr     composite_enemies_to_buffer ; Draw enemies into buffer
        bsr     composite_hero2_to_buffer   ; Draw inactive hero (behind active)
        bsr     composite_hero_to_buffer    ; Draw active hero (on top)
        bsr     copy_window_to_screen       ; Copy buffer+sprites to screen
        ; Bullets direct to screen (fast, no save/restore needed)
        bsr     draw_bullets_to_screen      ; Bullets drawn after copy
        ; Restore buffer (reverse order of compositing)
        bsr     restore_buffer_under_hero   ; Restore active hero area
        bsr     restore_buffer_under_hero2  ; Restore inactive hero area
        bsr     restore_buffer_under_enemies ; Restore enemy areas
        bsr     restore_buffer_under_trails ; Restore trail areas in buffer
        bsr     draw_lives                  ; Draw lives HUD
        bsr     draw_score                  ; Draw score HUD

        ; ESC returns to title instead of quitting
        move.w  quit_flag(pc),d0
        bne.s   return_to_title
        bra     main_loop

; ============================================================
; Return to title screen (used when ESC pressed during game)
; ============================================================
return_to_title:
        bsr     init_title_screen
        bra     title_loop

; ============================================================
; Title Screen
; ============================================================

; ============================================================
; init_title_screen - Initialize and display title screen
; ============================================================
init_title_screen:
        ; Set game state to title
        lea     game_state(pc),a0
        move.w  #GS_TITLE,(a0)

        ; Start menu music (absolute addressing for far variable)
        lea     start(pc),a0
        adda.l  #music_to_play,a0
        move.w  #MUSIC_MENU,(a0)

        ; Initialize level 0 (title/menu level)
        lea     current_level(pc),a0
        clr.w   (a0)

        ; Load title level
        bsr     load_current_level
        bsr     cache_coin_positions
        bsr     cache_exit_positions

        bsr     clear_screen_preserve_sides ; Preserve side graphics
        bsr     find_hero_start
        bsr     init_enemies
        bsr     build_cannon_list
        bsr     init_scroll

        ; Override scroll position for title screen
        ; Hero at row 54, bricks at rows 45-48 behind logo
        ; window_y = 320 (MAX_WINDOW_Y) puts hero at screen row 14 (center)
        ; Brick blocks at screen rows 5-8 (pixels 40-64) behind logo
        lea     window_y(pc),a0
        move.w  #320,(a0)

        ; Initialize hero state
        lea     hero_dir(pc),a0
        clr.w   (a0)
        lea     hero_last_dir(pc),a0
        move.w  #DIR_DOWN,(a0)
        lea     hero_fly(pc),a0
        clr.w   (a0)
        lea     anim_frame(pc),a0
        clr.w   (a0)
        lea     anim_counter(pc),a0
        move.w  #4,(a0)
        lea     quit_flag(pc),a0
        clr.w   (a0)
        lea     active_trails(pc),a0
        clr.w   (a0)
        lea     hero_drawn_x(pc),a0
        move.w  #-1,(a0)
        lea     coin_anim_frame(pc),a0
        clr.w   (a0)
        lea     coin_anim_ctr(pc),a0
        move.w  #1,(a0)

        ; Initialize title flash counter
        lea     title_flash_ctr(pc),a0
        move.w  #TITLE_FLASH_RATE,(a0)

        ; Flush keyboard buffer to prevent immediate key detection
        bsr     flush_keyboard

        bsr     clear_trails
        bsr     render_playfield_to_buffer
        bsr     copy_window_to_screen
        bsr     draw_scrolling_columns

        ; Draw the "OLD TOWER" logo
        bsr     draw_title_logo

        ; Draw lives
        bsr     draw_lives
        bsr     draw_score                  ; Draw score on title

        rts

; ============================================================
; title_loop - Title screen loop, waiting for FIRE to start
; Fixed keyboard handling using QDOS traps
; Samples frame timing to auto-detect pacer mode
; ============================================================
title_loop:
        bsr     wait_vsync
        bsr     title_pacer_sample      ; sample frame timing
        movea.l sfx_update_ptr(pc),a6  ; update sound
        jsr     (a6)
        bsr     update_animation
        bsr     update_coin_animation
        bsr     update_exit_animation

        ; Composite and draw (trails into buffer for no flicker)
        bsr     composite_trails_to_buffer
        bsr     composite_enemies_to_buffer
        bsr     composite_hero_to_buffer

        ; Use title-specific copy that skips logo area (no flicker)
        bsr     copy_window_to_screen_title

        ; Columns are static - no redraw needed

        ; Restore buffer
        bsr     restore_buffer_under_hero
        bsr     restore_buffer_under_enemies
        bsr     restore_buffer_under_trails

        ; Update logo colors (cycling) and redraw
        bsr     cycle_logo_colors
        bsr     draw_title_logo

        ; Draw flashing "PUSH FIRE TO START"
        bsr     draw_push_fire

        bsr     draw_lives
        bsr     draw_score

        ; Check keyboard (FIRE to start, ESC to quit)
        bsr     check_title_key
        tst.w   d0
        bne.s   .title_start

        ; Check if ESC was pressed
        move.w  quit_flag(pc),d0
        bne     exit_game

        bra     title_loop

.title_start:
        ; Play swap sound on title start
        movea.l sound_to_play_ptr(pc),a0
        move.w  #SFX_SWAP,(a0)
        ; Clear title screen message area
        bsr     clear_title_message_area

        ; Start the actual game
        bra     start_game

; Outro routines moved near buffer code (see after copy_window_to_screen_title)

; Pacer sampling constants and variables (near title_loop for bsr range)
PACER_SKIP      equ 8                   ; Skip first N frames (warm-up)
PACER_SAMPLES   equ 12                  ; Sample N frames after skip

title_pacer_count:   dc.w 0             ; Frame counter for sampling
title_pacer_overrun: dc.w 0             ; 1 if any overrun detected

; ============================================================
; title_pacer_sample - Sample frame timing during title screen
; Uses frame_overrun flag instead of red pixel check
; Skips PACER_SKIP frames, samples PACER_SAMPLES frames.
; If all samples under budget, switches to forced 25fps mode.
; After sampling completes, becomes a no-op.
; ============================================================
title_pacer_sample:
        move.w  title_pacer_count(pc),d0
        cmpi.w  #PACER_SKIP+PACER_SAMPLES,d0
        bge.s   .tps_done               ; Sampling complete — no-op

        addq.w  #1,d0
        lea     title_pacer_count(pc),a0
        move.w  d0,(a0)

        cmpi.w  #PACER_SKIP,d0
        ble.s   .tps_done               ; Still in warm-up

        ; Check for overrun via frame_overrun flag
        move.w  frame_overrun(pc),d1
        beq.s   .tps_no_overrun
        lea     title_pacer_overrun(pc),a0
        move.w  #1,(a0)
.tps_no_overrun:

        cmpi.w  #PACER_SKIP+PACER_SAMPLES,d0
        bne.s   .tps_done

        ; Sampling complete — decide mode
        move.w  title_pacer_overrun(pc),d0
        bne.s   .tps_done               ; Overrun seen — stay adaptive

        ; All frames under budget — switch to forced 25fps
        lea     frame_pacer_mode(pc),a0
        move.w  #PACER_FORCED,(a0)

.tps_done:
        rts

; ============================================================
; draw_string - Draw $FF-terminated string at screen address
; Input: a0 = string data (byte array of char indices)
;        a1 = screen address
; Preserves: a1 is advanced past last character
; ============================================================
draw_string:
        movem.l d0/a0,-(sp)
.ds_loop:
        moveq   #0,d0
        move.b  (a0)+,d0
        cmpi.b  #$FF,d0
        beq.s   .ds_done
        bsr     draw_char_at
        addq.l  #4,a1                   ; Next character position
        bra.s   .ds_loop
.ds_done:
        movem.l (sp)+,d0/a0
        rts

; ============================================================
; draw_string_to_buf - Draw $FF-terminated string to buffer
; Input: a0 = string data (byte array of char indices)
;        a1 = buffer address
; ============================================================
draw_string_to_buf:
        movem.l d0/a0,-(sp)
.dsb_loop:
        moveq   #0,d0
        move.b  (a0)+,d0
        cmpi.b  #$FF,d0
        beq.s   .dsb_done
        bsr     draw_char_to_buf
        addq.l  #4,a1                   ; Next character position
        bra.s   .dsb_loop
.dsb_done:
        movem.l (sp)+,d0/a0
        rts

; ============================================================
; draw_title_logo - Draw "OLD TOWER" Spectrum graphic
; Uses nibble_to_mask for proper QL MODE 8 stipple expansion
; Uses Spectrum logoColors sequence for rainbow effect
; Position: screen row 72 (moved down 4 tiles from 40)
; ============================================================
draw_title_logo:
        movem.l d0-d5/a0-a4,-(sp)

        lea     gameName_1bpp(pc),a0    ; Source: 1bpp graphic (8 bytes/row x 32 rows)
        ; Logo at screen row 72 (down 4 tiles from original 40)
        ; Playfield X=40 bytes, logo=32 bytes wide, center offset = 8
        lea     SCREEN_BASE+(72*SCREEN_STRIDE)+48,a1
        lea     logo_colors(pc),a2      ; Color table (16 entries for 32 rows)
        lea     nibble_to_mask(pc),a3   ; Pixel expansion lookup

        moveq   #31,d5                  ; 32 rows

.row_loop:
        ; Get color for this row (2 rows per color entry)
        move.w  d5,d4
        lsr.w   #1,d4                   ; Divide by 2
        andi.w  #15,d4                  ; 16 colors in table
        add.w   d4,d4                   ; Word index
        move.w  (a2,d4.w),d2            ; d2 = color for this row pair

        ; Draw 8 source bytes (64 pixels = 32 QL bytes) per row
        moveq   #7,d4                   ; 8 source bytes

.byte_loop:
        move.b  (a0)+,d0                ; Get 1bpp byte (8 pixels)

        ; Expand high nibble (4 pixels) using nibble_to_mask
        move.b  d0,d1
        lsr.b   #4,d1                   ; High nibble (0-15)
        andi.w  #$0F,d1
        add.w   d1,d1                   ; Word index into table
        move.w  (a3,d1.w),d1            ; Get stipple mask
        and.w   d2,d1                   ; Apply color
        move.w  d1,(a1)+                ; Write to screen

        ; Expand low nibble (4 pixels) using nibble_to_mask
        moveq   #0,d1
        move.b  d0,d1
        andi.w  #$0F,d1                 ; Low nibble (0-15)
        add.w   d1,d1                   ; Word index into table
        move.w  (a3,d1.w),d1            ; Get stipple mask
        and.w   d2,d1                   ; Apply color
        move.w  d1,(a1)+                ; Write to screen

        dbra    d4,.byte_loop

        ; Move to next screen row (128 bytes per line, we wrote 32)
        lea     SCREEN_STRIDE-32(a1),a1

        dbra    d5,.row_loop

        movem.l (sp)+,d0-d5/a0-a4
        rts

; Spectrum logoColors converted to QL (16 colors for 32 rows, 2 rows each)
; Original: bright green, cyan, yellow, white, white, yellow, magenta, green,
;           white, cyan, green, magenta, green, cyan, yellow, magenta
logo_colors:
        dc.w    COL4_GREEN,COL4_CYAN,COL4_YELLOW,COL4_WHITE
        dc.w    COL4_WHITE,COL4_YELLOW,COL4_MAGENTA,COL4_GREEN
        dc.w    COL4_WHITE,COL4_CYAN,COL4_GREEN,COL4_MAGENTA
        dc.w    COL4_GREEN,COL4_CYAN,COL4_YELLOW,COL4_MAGENTA

; ============================================================
; draw_push_fire - Draw flashing "PUSH FIRE TO START" text
; ============================================================
draw_push_fire:
        movem.l d0-d1/a0-a1,-(sp)

        ; Update flash counter
        lea     title_flash_ctr(pc),a0
        move.w  (a0),d0
        subq.w  #1,d0
        bne.s   .store_ctr

        ; Toggle visibility
        lea     title_text_visible(pc),a1
        eori.w  #1,(a1)
        move.w  #TITLE_FLASH_RATE,d0

.store_ctr:
        move.w  d0,(a0)

        ; Check if visible
        move.w  title_text_visible(pc),d0
        beq     .clear_text

        ; Draw "PUSH FIRE TO START" (18 characters)
        ; Position: row 30 (below playfield), centered
        lea     SCREEN_BASE+(30*8*SCREEN_STRIDE)+28,a1  ; Row 30, centered
        moveq   #0,d0                   ; Start with 'P'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #10,d0                  ; 'U'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #3,d0                   ; 'S'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #11,d0                  ; 'H'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #6,d0                   ; space
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #7,d0                   ; 'F'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #8,d0                   ; 'I'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #1,d0                   ; 'R'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #2,d0                   ; 'E'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #6,d0                   ; space
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #12,d0                  ; 'T'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #13,d0                  ; 'O'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #6,d0                   ; space
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #3,d0                   ; 'S'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #12,d0                  ; 'T'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #4,d0                   ; 'A'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #1,d0                   ; 'R'
        bsr     draw_char_at
        lea     4(a1),a1
        moveq   #12,d0                  ; 'T'
        bsr     draw_char_at

        bra.s   .done

.clear_text:
        bsr     clear_title_message_area

.done:
        movem.l (sp)+,d0-d1/a0-a1
        rts

; ============================================================
; clear_title_message_area - Clear the "PUSH FIRE" area
; ============================================================
clear_title_message_area:
        movem.l d0-d1/a1,-(sp)

        lea     SCREEN_BASE+(30*8*SCREEN_STRIDE)+28,a1

        ; Clear 8 rows × 72 bytes (18 chars × 4 bytes)
        moveq   #0,d0
        moveq   #7,d1                   ; 8 rows

.ctma_row:
        move.l  d0,(a1)
        move.l  d0,4(a1)
        move.l  d0,8(a1)
        move.l  d0,12(a1)
        move.l  d0,16(a1)
        move.l  d0,20(a1)
        move.l  d0,24(a1)
        move.l  d0,28(a1)
        move.l  d0,32(a1)
        move.l  d0,36(a1)
        move.l  d0,40(a1)
        move.l  d0,44(a1)
        move.l  d0,48(a1)
        move.l  d0,52(a1)
        move.l  d0,56(a1)
        move.l  d0,60(a1)
        move.l  d0,64(a1)
        move.l  d0,68(a1)
        adda.w  #SCREEN_STRIDE,a1
        dbra    d1,.ctma_row

        movem.l (sp)+,d0-d1/a1
        rts

; ============================================================
; check_title_key - Check keyboard on title screen
; Returns: d0 = 1 if FIRE pressed, 0 otherwise
; Sets quit_flag if ESC pressed
; Uses QDOS TRAP #3 like other keyboard routines
; ============================================================
check_title_key:
        movem.l d1-d3/a0,-(sp)

        ; Use QDOS IO_FBYTE to read keyboard (non-blocking)
        move.l  con_id(pc),a0
        move.l  a0,d0
        beq.s   .no_key

        moveq   #IO_FBYTE,d0
        moveq   #0,d3                   ; Non-blocking (timeout=0)
        trap    #3
        tst.l   d0
        bmi.s   .no_key                 ; No key available

        ; Check if SPACE or ENTER was pressed (FIRE)
        cmpi.b  #' ',d1
        beq.s   .fire_pressed
        cmpi.b  #13,d1                  ; ENTER
        beq.s   .fire_pressed

        ; Check for ESC (quit)
        cmpi.b  #27,d1
        bne.s   .no_key
        ; ESC pressed - set quit flag
        lea     quit_flag(pc),a0
        move.w  #1,(a0)

.no_key:
        moveq   #0,d0                   ; Return 0 (no fire)
        bra.s   .check_done

.fire_pressed:
        moveq   #1,d0                   ; Return 1 (fire pressed)

.check_done:
        movem.l (sp)+,d1-d3/a0
        rts

; ============================================================
; flush_keyboard - Clear any pending keys from buffer
; ============================================================
flush_keyboard:
        movem.l d0-d3/a0,-(sp)
        move.l  con_id(pc),a0
        move.l  a0,d0
        beq.s   .flush_done
.flush_loop:
        moveq   #IO_FBYTE,d0
        moveq   #0,d3                   ; Non-blocking
        trap    #3
        tst.l   d0
        bpl.s   .flush_loop             ; Keep flushing while keys available
.flush_done:
        movem.l (sp)+,d0-d3/a0
        rts

; ============================================================
; handle_level_complete - Called when hero reaches active exit
; Enters win state (Spectrum-style exit animation)
; ============================================================
handle_level_complete:
        ; Enter win state
        lea     game_state(pc),a0
        move.w  #GS_WIN,(a0)

        ; Initialize flash counter
        lea     win_flash_ctr(pc),a0
        move.w  #WIN_FLASH_RATE,(a0)

        ; Fall through to win_loop

; ============================================================
; win_loop - Level won, waiting for SPACE to continue
; Continues animations but hero doesn't move
; ============================================================
win_loop:
        bsr     wait_vsync
        movea.l sfx_update_ptr(pc),a6  ; update sound
        jsr     (a6)

        ; Update animations (enemies, trails, exit tiles)
        bsr     update_enemies
        bsr     update_camera           ; Keep camera smooth if needed
        bsr     update_exit_animation   ; Keep exit animation going

        ; Composite graphics to buffer (trails + sprites, no flicker)
        bsr     composite_trails_to_buffer
        bsr     composite_enemies_to_buffer

        ; Check if second hero's exit animation is playing
        move.w  hero_exit_active(pc),d0
        beq.s   .win_no_exit_anim
        ; Exit animation active - process it (draws sprite + advances animation)
        bsr     composite_hero_to_buffer
        bra.s   .win_no_hero2           ; Skip hero2 draw - they're the one exiting
.win_no_exit_anim:
        ; No exit animation - don't draw active hero (they've exited)

        ; Check if inactive hero should be drawn (two-hero levels where one exited)
        move.w  level_has_hero2(pc),d0
        beq.s   .win_no_hero2
        ; Only draw hero2 if they haven't exited
        move.w  heroes_exited(pc),d0
        move.w  active_hero(pc),d1
        eori.w  #1,d1                   ; d1 = inactive hero index
        btst    d1,d0
        bne.s   .win_no_hero2           ; Inactive hero also exited
        bsr     composite_hero2_to_buffer
.win_no_hero2:

        ; Copy buffer to screen
        bsr     copy_window_to_screen
        ; Columns are static - no redraw needed
        bsr     draw_lives
        bsr     draw_score

        ; Restore buffer
        ; Restore under hero if exit animation was playing
        move.w  hero_exit_active(pc),d0
        beq.s   .win_no_hero_restore
        bsr     restore_buffer_under_hero
.win_no_hero_restore:
        bsr     restore_buffer_under_hero2
        bsr     restore_buffer_under_enemies
        bsr     restore_buffer_under_trails

        ; Draw flashing "PRESS SPACE" message
        bsr     draw_press_space

        ; Check for SPACE key press
        bsr     check_space_key
        tst.w   d0
        bne.s   .win_advance

        ; ESC returns to title instead of quitting
        move.w  quit_flag(pc),d0
        bne     return_to_title

        bra     win_loop

.win_advance:
        ; Check if this was the last level
        move.w  current_level(pc),d0
        cmpi.w  #NUM_LEVELS-1,d0        ; Level 20 = last playable
        beq     init_outro              ; Game complete!

        ; Reset game state for next level
        lea     game_state(pc),a0
        move.w  #GS_GAMEPLAY,(a0)

        ; Clear the "PRESS SPACE" message area
        bsr     clear_message_area

        ; Black flash on playfield+columns for 0.5s
        bsr     black_playfield
        moveq   #15-1,d7                ; 15 frames = 0.3s at 50fps
.black_wait:
        bsr     wait_vsync
        move.l  d7,-(sp)                ; save counter
        movea.l sfx_update_ptr(pc),a6   ; update audio during black flash
        jsr     (a6)
        move.l  (sp)+,d7                ; restore counter
        dbra    d7,.black_wait

        ; Advance to next level
        bsr     next_level
        bra     main_loop

; ============================================================
; check_space_key - Check if SPACE is pressed (non-blocking)
; Uses QDOS IO_FBYTE via console channel
; Returns: d0 = 1 if pressed, 0 if not
; ============================================================
check_space_key:
        movem.l d1-d3/a0,-(sp)

        ; Use QDOS IO_FBYTE to read keyboard (non-blocking)
        move.l  con_id(pc),a0
        move.l  a0,d0
        beq.s   .no_key

        moveq   #IO_FBYTE,d0
        moveq   #0,d3                   ; Non-blocking (timeout=0)
        trap    #3
        tst.l   d0
        bmi.s   .no_key                 ; No key available

        ; Check if SPACE was pressed
        cmpi.b  #' ',d1
        beq.s   .space_pressed

        ; Not SPACE - check for ESC (allow quit during win state)
        cmpi.b  #27,d1
        bne.s   .no_key
        ; ESC pressed - set quit flag
        lea     quit_flag(pc),a0
        move.w  #1,(a0)
        moveq   #0,d0                   ; Return 0 (don't advance)
        bra.s   .check_done

.space_pressed:
        moveq   #1,d0
        bra.s   .check_done

.no_key:
        moveq   #0,d0

.check_done:
        movem.l (sp)+,d1-d3/a0
        rts

; ============================================================
; draw_press_fire - Draw flashing "PRESS FIRE" at screen bottom
; Uses proper 8x8 character font rendering
; MODE 8: 4 bits/pixel, 1 byte = 2 pixels, 4 bytes = 8 pixels = 1 char
; ============================================================
draw_press_space:
        movem.l d0-d7/a0-a3,-(sp)

        ; Update flash counter
        lea     win_flash_ctr(pc),a0
        move.w  (a0),d0
        subq.w  #1,d0
        bpl.s   .dps_no_reset
        move.w  #WIN_FLASH_RATE*2,d0    ; Reset counter (on + off cycle)
.dps_no_reset:
        move.w  d0,(a0)

        ; Determine if showing or hidden (flash on/off)
        cmpi.w  #WIN_FLASH_RATE,d0
        blt.s   .dps_show_message

        ; Flash off - clear area
        bsr     clear_message_area
        bra     .dps_flash_done

.dps_show_message:
        ; Flash on - draw "PRESS FIRE"
        ; Position: row 29 (one row up from row 30)
        ; 10 chars × 4 bytes = 40 bytes, playfield starts at 40 bytes, width 48 bytes
        ; Center in playfield: 40 + (48-40)/2 = 40 + 4 = 44 bytes offset
        lea     SCREEN_BASE+(29*8*SCREEN_STRIDE)+44,a1

        ; Draw each character: P R E S S   F I R E
        lea     press_fire_str(pc),a2   ; String data (character indices)
        moveq   #10-1,d7                ; 10 characters

.dps_char_loop:
        move.b  (a2)+,d0                ; Get character index
        ext.w   d0
        bsr     draw_char_at            ; Draw character at a1
        addq.l  #4,a1                   ; Move to next char (4 bytes = 8 pixels)
        dbra    d7,.dps_char_loop

.dps_flash_done:
        movem.l (sp)+,d0-d7/a0-a3
        rts

; ============================================================
; draw_char_at - Draw single 8x8 character to screen
; Input: d0.w = character index, a1 = screen address
; Uses SCREEN_STRIDE between rows
; ============================================================
draw_char_at:
        move.w  #SCREEN_STRIDE,d4
        bra.s   draw_char_with_stride

; ============================================================
; draw_char_to_buf - Draw single 8x8 character to buffer
; Input: d0.w = character index, a1 = buffer address
; Uses BUF_STRIDE between rows
; ============================================================
draw_char_to_buf:
        move.w  #BUF_STRIDE,d4

; ============================================================
; draw_char_with_stride - Draw 8x8 character with variable stride
; Input: d0.w = character index, a1 = dest address, d4.w = stride
; ============================================================
draw_char_with_stride:
        movem.l d0-d4/a0-a1,-(sp)

        ; Get pointer to character bitmap (8 bytes per char)
        lea     msg_font(pc),a0
        lsl.w   #3,d0                   ; d0 = char_index * 8
        adda.w  d0,a0                   ; a0 = pointer to character bitmap

        ; Draw 8 rows
        moveq   #7,d3                   ; 8 rows (0-7)

.dcw_row:
        move.b  (a0)+,d0                ; Get bitmap row (8 pixels as bits)

        ; Expand 8 font bits to 2 words (8 pixels)
        moveq   #0,d1                   ; Word 0 (pixels 0-3)
        moveq   #0,d2                   ; Word 1 (pixels 4-7)

        ; Pixels 0-3 into word 0
        btst    #7,d0
        beq.s   .dcw_n7
        ori.w   #$80C0,d1
.dcw_n7:
        btst    #6,d0
        beq.s   .dcw_n6
        ori.w   #$2030,d1
.dcw_n6:
        btst    #5,d0
        beq.s   .dcw_n5
        ori.w   #$080C,d1
.dcw_n5:
        btst    #4,d0
        beq.s   .dcw_n4
        ori.w   #$0203,d1
.dcw_n4:
        ; Pixels 4-7 into word 1
        btst    #3,d0
        beq.s   .dcw_n3
        ori.w   #$80C0,d2
.dcw_n3:
        btst    #2,d0
        beq.s   .dcw_n2
        ori.w   #$2030,d2
.dcw_n2:
        btst    #1,d0
        beq.s   .dcw_n1
        ori.w   #$080C,d2
.dcw_n1:
        btst    #0,d0
        beq.s   .dcw_n0
        ori.w   #$0203,d2
.dcw_n0:
        move.w  d1,(a1)                 ; Write pixels 0-3
        move.w  d2,2(a1)                ; Write pixels 4-7

        ; Move to next row using stride
        adda.w  d4,a1
        dbra    d3,.dcw_row

        movem.l (sp)+,d0-d4/a0-a1
        rts

; ============================================================
; clear_message_area - Clear the "PRESS FIRE" area (8 rows)
; ============================================================
clear_message_area:
        movem.l d0-d1/a1,-(sp)

        lea     SCREEN_BASE+(29*8*SCREEN_STRIDE)+44,a1

        ; Clear 8 rows × 40 bytes (10 chars × 4 bytes)
        moveq   #0,d0
        moveq   #7,d1                   ; 8 rows

.cma_row:
        move.l  d0,(a1)
        move.l  d0,4(a1)
        move.l  d0,8(a1)
        move.l  d0,12(a1)
        move.l  d0,16(a1)
        move.l  d0,20(a1)
        move.l  d0,24(a1)
        move.l  d0,28(a1)
        move.l  d0,32(a1)
        move.l  d0,36(a1)
        adda.w  #SCREEN_STRIDE,a1
        dbra    d1,.cma_row

        movem.l (sp)+,d0-d1/a1
        rts

; ============================================================
; Message font data - 8x8 characters from ZX Spectrum font
; Index: 0=P, 1=R, 2=E, 3=S, 4=A, 5=C, 6=space, 7=F, 8=I
;        9=unused, 10=U, 11=H, 12=T, 13=O, 14=L, 15=D, 16=W
; Extracted from original Spectrum res/font.fnt
; Added U, H, T, O, L, D, W for title screen
; ============================================================
msg_font:
        ; P (index 0) - from Spectrum font offset $180
        dc.b    $00,$7C,$66,$66,$7C,$60,$60,$00
        ; R (index 1) - from Spectrum font offset $190
        dc.b    $00,$7C,$66,$66,$7C,$66,$06,$00
        ; E (index 2) - from Spectrum font offset $128
        dc.b    $00,$7E,$60,$78,$60,$7E,$00,$00
        ; S (index 3) - from Spectrum font offset $198
        dc.b    $00,$3C,$60,$3C,$06,$7C,$00,$00
        ; A (index 4) - from Spectrum font ASCII 65
        dc.b    $00,$3C,$66,$7E,$66,$66,$06,$00
        ; C (index 5) - from Spectrum font ASCII 67
        dc.b    $00,$3C,$66,$60,$66,$3C,$00,$00
        ; (space) (index 6) - from Spectrum font offset $000
        dc.b    $00,$00,$00,$00,$00,$00,$00,$00
        ; F (index 7) - from Spectrum font offset $130
        dc.b    $00,$7E,$60,$7C,$60,$60,$60,$00
        ; I (index 8) - from Spectrum font offset $148
        dc.b    $00,$7E,$18,$18,$18,$7E,$00,$00
        ; (unused) (index 9)
        dc.b    $00,$00,$00,$00,$00,$00,$00,$00
        ; U (index 10) - from Spectrum font offset $1A8
        dc.b    $00,$66,$66,$66,$66,$3C,$00,$00
        ; H (index 11) - from Spectrum font offset $140
        dc.b    $00,$66,$66,$7E,$66,$66,$00,$00
        ; T (index 12) - from Spectrum font offset $1A0
        dc.b    $00,$7E,$18,$18,$18,$18,$00,$00
        ; O (index 13) - from Spectrum font offset $178
        dc.b    $00,$3C,$66,$66,$66,$3C,$00,$00
        ; L (index 14) - from Spectrum font offset $160
        dc.b    $00,$60,$60,$60,$60,$7E,$00,$00
        ; D (index 15) - from Spectrum font offset $120
        dc.b    $00,$78,$64,$66,$64,$78,$00,$00
        ; W (index 16) - from Spectrum font offset $1B8
        dc.b    $00,$66,$66,$66,$7E,$24,$00,$00
        ; New characters for outro screen
        ; N (index 17) - from Spectrum font ASCII 78
        dc.b    $00,$7C,$66,$66,$66,$66,$06,$00
        ; K (index 18) - from Spectrum font ASCII 75
        dc.b    $00,$66,$66,$7C,$66,$66,$06,$00
        ; Y (index 19) - from Spectrum font ASCII 89
        dc.b    $00,$66,$66,$66,$18,$18,$00,$00
        ; G (index 20) - from Spectrum font ASCII 71
        dc.b    $00,$3C,$66,$60,$66,$3E,$00,$00
        ; M (index 21) - from Spectrum font ASCII 77
        dc.b    $00,$7E,$6B,$6B,$63,$63,$03,$00
        ; X (index 22) - from Spectrum font ASCII 88
        dc.b    $00,$66,$66,$18,$66,$66,$00,$00
        ; Z (index 23) - from Spectrum font ASCII 90
        dc.b    $00,$7E,$06,$18,$60,$7E,$00,$00
        ; V (index 24)
        dc.b    $00,$66,$66,$66,$3C,$18,$00,$00
        ; New characters for updated credits
        ; Q (index 25) - from Spectrum font ASCII 81
        dc.b    $00,$3C,$66,$66,$6E,$38,$04,$00
        ; J (index 26) - from Spectrum font ASCII 74
        dc.b    $00,$06,$06,$66,$66,$3C,$00,$00
        ; ! (index 27) - from Spectrum font ASCII 33
        dc.b    $00,$18,$18,$18,$00,$18,$00,$00
        ; : (index 28) - from Spectrum font ASCII 58
        dc.b    $00,$00,$10,$00,$10,$00,$00,$00
        even

; String data: "PRESS FIRE" as character indices
; P=0, R=1, E=2, S=3, S=3, space=6, F=7, I=8, R=1, E=2
press_fire_str:
        dc.b    0,1,2,3,3,6,7,8,1,2
        even

; Outro screen string data (character indices, $FF terminated)
; Char indices: P=0,R=1,E=2,S=3,A=4,C=5,_=6,F=7,I=8,U=10,H=11,T=12,
;   O=13,L=14,D=15,W=16,N=17,K=18,Y=19,G=20,M=21,X=22,Z=23,V=24,Q=25,J=26,!=27,:=28
outro_str_welldone:
        dc.b    16,2,14,14,6,6,15,13,17,2,$FF    ; "WELL  DONE"
outro_str_thanks1:
        dc.b    12,11,4,17,18,3,6,7,13,1,$FF     ; "THANKS FOR"
outro_str_thanks2:
        dc.b    0,14,4,19,8,17,20,$FF             ; "PLAYING"
outro_str_kudos:
        dc.b    18,10,15,13,3,$FF                 ; "KUDOS"
outro_str_gmaster:
        dc.b    20,4,21,2,21,4,3,12,2,1,27,$FF   ; "GAMEMASTER!"
outro_str_qlport:
        dc.b    25,14,6,0,13,1,12,6,28,$FF        ; "QL PORT :"
outro_str_jmckay:
        dc.b    26,6,21,5,18,4,19,$FF             ; "J MCKAY"
outro_str_zxgame:
        dc.b    23,22,6,20,4,21,2,6,28,$FF        ; "ZX GAME :"
outro_str_coder:
        dc.b    15,6,20,1,4,5,11,2,24,$FF        ; "D GRACHEV"
outro_str_musician:
        dc.b    13,6,17,8,18,8,12,8,17,$FF       ; "O NIKITIN"
outro_str_artist:
        dc.b    8,6,3,2,14,2,23,17,2,24,$FF      ; "I SELEZNEV"
outro_str_pushfire:
        dc.b    0,10,3,11,6,7,8,1,2,$FF          ; "PUSH FIRE"
        even

; ============================================================
; handle_death - Called when collision detected
; Runs death animation, decrements lives, restarts level or ends game
; ============================================================
handle_death:
        ; Play death sound
        movea.l sound_to_play_ptr(pc),a0
        move.w  #SFX_DEAD,(a0)
        ; Initialize death animation counter
        lea     death_anim_count(pc),a0
        move.w  #DEAD_DELAY,(a0)

        ; Compute hero screen address once
        move.w  hero_y(pc),d0
        lsl.w   #3,d0                   ; d0 = hero_y * 8 (pixel Y)
        sub.w   window_y(pc),d0         ; d0 = screen pixel Y
        move.w  d0,d1
        lsl.w   #7,d1                   ; d1 = pixel_y * 128 (SCREEN_STRIDE)
        lea     PLAYFIELD_BASE,a3
        adda.w  d1,a3
        move.w  hero_x(pc),d0
        lsl.w   #2,d0                   ; d0 = hero_x * 4 bytes
        adda.w  d0,a3
        lea     death_screen_ptr(pc),a0
        move.l  a3,(a0)                 ; Save for animation loop

.death_loop:
        ; Update audio during death animation
        bsr     wait_vsync
        movea.l sfx_update_ptr(pc),a6
        jsr     (a6)

        ; Draw background first
        bsr     copy_window_to_screen
        ; Columns are static - no redraw needed
        bsr     draw_lives                  ; Keep lives HUD visible
        bsr     draw_score                  ; Keep score visible

        ; Get saved screen pointer
        move.l  death_screen_ptr(pc),a3

        ; Determine color based on animation phase
        move.w  death_anim_count(pc),d0
        cmpi.w  #DEAD_KABUM_START,d0
        bgt.s   .initial_phase

        ; Kabum phase - cycle colors (fast: every 2 frames)
        move.w  #DEAD_KABUM_START,d1
        sub.w   d0,d1                   ; d1 = frames since kabum started
        lsr.w   #1,d1                   ; d1 = color index (change every 2 frames)
        cmpi.w  #DEAD_COLOR_COUNT-1,d1
        ble.s   .get_color
        move.w  #DEAD_COLOR_COUNT-1,d1  ; Clamp to last color
        bra.s   .get_color

.initial_phase:
        ; Initial phase - just red
        moveq   #0,d1                   ; Color index 0 = red

.get_color:
        ; Get color from table
        lea     death_colors(pc),a0
        add.w   d1,d1                   ; Word offset
        move.w  0(a0,d1.w),d4           ; d4 = color

        ; Draw hero with death color
        bsr     draw_hero_death_color

        ; Decrement animation counter
        lea     death_anim_count(pc),a0
        subq.w  #1,(a0)
        bne.s   .death_loop             ; Continue animation

        ; Animation complete - decrement lives
        lea     lives(pc),a0
        move.w  (a0),d0
        subq.w  #1,d0
        move.w  d0,(a0)
        beq     game_over               ; No lives left, game over

        ; Lives remaining - full level restart (restores coins etc.)
        bsr     full_restart_level
        bsr     draw_score                  ; Redraw score after restart
        bra     main_loop

; ============================================================
; handle_reset_level - Player pressed R to reset level
; Fully reloads level (coins, hidden tiles, enemies restored)
; Costs 1 life. If no lives left, game over.
; ============================================================
handle_reset_level:
        ; Clear the flag
        lea     reset_level_flag(pc),a0
        clr.w   (a0)

        ; Decrement lives
        lea     lives(pc),a0
        move.w  (a0),d0
        subq.w  #1,d0
        move.w  d0,(a0)
        beq     game_over               ; No lives left

        ; Use shared full restart subroutine
        bsr     full_restart_level
        bsr     draw_score                  ; Redraw score after restart
        bra     main_loop

; ============================================================
; full_restart_level - Full level reload subroutine
; Restores all coins, hidden tiles, enemies. Resets hero state.
; Called by handle_death and handle_reset_level.
; ============================================================
full_restart_level:
        bsr     load_current_level
        bsr     cache_coin_positions
        bsr     cache_exit_positions
        bsr     find_hero_start
        bsr     init_enemies
        bsr     build_cannon_list
        bsr     init_scroll
        bsr     clear_trails

        ; Reset hero state
        lea     hero_dir(pc),a0
        clr.w   (a0)
        lea     hero_last_dir(pc),a0
        move.w  #DIR_DOWN,(a0)
        lea     hero_fly(pc),a0
        clr.w   (a0)
        lea     anim_frame(pc),a0
        clr.w   (a0)
        lea     hero_drawn_x(pc),a0
        move.w  #-1,(a0)
        lea     coin_count(pc),a0
        clr.w   (a0)

        ; Re-render level
        bsr     render_playfield_to_buffer
        bsr     copy_window_to_screen
        bsr     draw_scrolling_columns
        bsr     draw_hero_force
        ; Removed draw_level_num
        bsr     draw_lives
        rts

; ============================================================
; game_over - No lives left, return to title screen
; ============================================================
game_over:
        ; Reset lives for next game
        lea     lives(pc),a0
        move.w  #5,(a0)

        ; Return to title screen
        bsr     init_title_screen
        bra     title_loop

; ============================================================
; draw_hero_death_color - Draw hero with specified color
; Input: d4.w = color to use, a3 = screen pointer
; ============================================================
draw_hero_death_color:
        movem.l d0-d3/d5/a3-a5,-(sp)
        lea     hero_death_sprite(pc),a4
        lea     nibble_to_mask(pc),a5
        moveq   #7,d5                   ; 8 rows
.death_row:
        move.b  (a4)+,d0                ; Get sprite byte
        ; High nibble -> first word
        move.b  d0,d1
        lsr.b   #4,d1
        and.w   #$0F,d1
        add.w   d1,d1
        move.w  0(a5,d1.w),d2
        and.w   d4,d2
        move.w  d2,(a3)
        ; Low nibble -> second word
        move.b  d0,d1
        and.w   #$0F,d1
        add.w   d1,d1
        move.w  0(a5,d1.w),d2
        and.w   d4,d2
        move.w  d2,2(a3)
        adda.w  #SCREEN_STRIDE,a3
        dbra    d5,.death_row
        movem.l (sp)+,d0-d3/d5/a3-a5
        rts

; ============================================================
; draw_lives - Draw lives HUD at top-left of screen
; ============================================================
draw_lives:
        ; OPT: Check if lives changed - skip redraw if unchanged
        move.w  lives(pc),d0
        cmp.w   prev_lives(pc),d0
        beq.s   .lives_unchanged        ; No change, skip redraw

        ; Lives changed - update cache and redraw
        lea     prev_lives(pc),a0
        move.w  d0,(a0)

        movem.l d0-d6/a0-a5,-(sp)

        ; Screen address for lives display (Y=3, X=4 pixels)
        lea     SCREEN_BASE,a0
        adda.w  #3*SCREEN_STRIDE+2,a0

        ; Get current lives count
        move.w  lives(pc),d3

        ; Draw MAX_LIVES life slots
        moveq   #MAX_LIVES-1,d4
        lea     nibble_to_mask(pc),a5

.draw_life_slot:
        move.w  #MAX_LIVES-1,d0
        sub.w   d4,d0
        cmp.w   d3,d0
        bge.s   .draw_empty_life

        ; Draw filled life icon (red)
        lea     life_icon(pc),a4
        move.w  #COL4_RED,d5
        bra.s   .draw_life_icon

.draw_empty_life:
        ; Draw empty life icon (blue outline)
        lea     life_empty(pc),a4
        move.w  #COL4_BLUE,d5

.draw_life_icon:
        move.l  a0,a1
        moveq   #7,d2

.life_row:
        move.b  (a4)+,d0
        move.b  d0,d1
        lsr.b   #4,d1
        and.w   #$0F,d1
        add.w   d1,d1
        move.w  0(a5,d1.w),d6
        and.w   d5,d6
        move.w  d6,(a1)
        move.b  d0,d1
        and.w   #$0F,d1
        add.w   d1,d1
        move.w  0(a5,d1.w),d6
        and.w   d5,d6
        move.w  d6,2(a1)
        adda.w  #SCREEN_STRIDE,a1
        dbra    d2,.life_row

        adda.w  #4,a0
        dbra    d4,.draw_life_slot

        movem.l (sp)+,d0-d6/a0-a5
.lives_unchanged:
        rts

exit_game:
        movea.l ay_silence_ptr(pc),a6   ; Silence QSound before exit
        jsr     (a6)
        bsr     close_console
        ; Restore MODE 4 using QDOS (compatible across emulators)
        moveq   #MT_DMODE,d0
        moveq   #4,d1           ; MODE 4
        moveq   #0,d2           ; Don't clear screen
        trap    #1
        ; Terminate as QDOS job (don't RTS)
        moveq   #MT_FRJOB,d0    ; Force remove job
        moveq   #-1,d1          ; This job
        moveq   #0,d3           ; No error
        trap    #1              ; Never returns

exit_fail:
        ; Terminate with error
        moveq   #MT_FRJOB,d0    ; Force remove job
        moveq   #-1,d1          ; This job
        moveq   #-1,d3          ; Error code
        trap    #1              ; Never returns

; ============================================================
; sfx_setup_ptrs - Compute absolute addresses of SFX routines
; Must be called once at startup before any SFX functions are used.
; Uses 'start' label (org 0) as base to compute runtime addresses.
; ============================================================
sfx_setup_ptrs:
        movem.l d0/a0-a1,-(sp)
        lea     start(pc),a0           ; a0 = runtime base address

        ; Compute and store sfx_update address
        lea     sfx_update_ptr(pc),a1
        move.l  a0,(a1)
        addi.l  #sfx_update,(a1)

        ; Compute and store qsound_init address
        lea     qsound_init_ptr(pc),a1
        move.l  a0,(a1)
        addi.l  #qsound_init,(a1)

        ; Compute and store ay_silence address
        lea     ay_silence_ptr(pc),a1
        move.l  a0,(a1)
        addi.l  #ay_silence,(a1)

        ; Compute and store sound_to_play address
        lea     sound_to_play_ptr(pc),a1
        move.l  a0,(a1)
        addi.l  #sound_to_play,(a1)

        ; Store runtime base address for music track pointers
        lea     runtime_base_ptr(pc),a1
        move.l  a0,(a1)

        ; Call qsound_init (too far for bsr from main init)
        lea     qsound_init_ptr(pc),a1
        movea.l (a1),a1
        jsr     (a1)

        movem.l (sp)+,d0/a0-a1
        rts

; ============================================================
; Level remap table - maps display level to source data index
; ============================================================
; Indexed by current_level (0-20), returns source level index
; Remapping: L01↔L02, L05-10 rotated, L12-15/L21-25 shuffled
; ============================================================
level_remap:
        dc.w    0               ; Index 0 (L00 title): unchanged
        dc.w    2               ; Index 1 (L01): load from L02
        dc.w    1               ; Index 2 (L02): load from L01
        dc.w    3               ; Index 3 (L03): unchanged
        dc.w    4               ; Index 4 (L04): unchanged
        dc.w    6               ; Index 5 (L05): load from L06
        dc.w    8               ; Index 6 (L06): load from L08
        dc.w    9               ; Index 7 (L07): load from L09
        dc.w    7               ; Index 8 (L08): load from L07
        dc.w    10              ; Index 9 (L09): load from L10
        dc.w    5               ; Index 10 (L10): load from L05
        dc.w    11              ; Index 11 (L11): unchanged
        dc.w    19              ; Index 12 (L12): load from L24
        dc.w    20              ; Index 13 (L13): load from L25
        dc.w    17              ; Index 14 (L14): load from L22
        dc.w    12              ; Index 15 (L15): load from L12
        dc.w    15              ; Index 16 (L21): load from L15
        dc.w    16              ; Index 17 (L22): load from L21
        dc.w    14              ; Index 18 (L23): load from L14
        dc.w    13              ; Index 19 (L24): load from L13
        dc.w    18              ; Index 20 (L25): load from L23

; ============================================================
; load_current_level - Decompress level from RLE compressed data
; ============================================================
; Uses RLE compressed level data for ~9KB savings.
; Uses level_remap table for difficulty progression.
; ============================================================
load_current_level:
        movem.l d0-d2/a0-a2,-(sp)

        ; Remap current_level through lookup table
        move.w  current_level(pc),d0
        add.w   d0,d0                   ; word index
        lea     level_remap(pc),a0
        move.w  (a0,d0.w),d0            ; d0 = remapped source level index

        ; Get compressed data offset from table
        add.w   d0,d0                   ; word index for offsets
        lea     level_offsets(pc),a0
        move.w  (a0,d0.w),d0            ; d0 = offset into compressed data
        lea     levels_compressed(pc),a0
        adda.w  d0,a0                   ; a0 = compressed source

        ; Get destination (two-step lea for level_working)
        lea     .lw_ref(pc),a1
        adda.l  #level_working-.lw_ref,a1
.lw_ref:
        ; a0 = source (compressed)
        ; a1 = destination (level_working)
        ; d2 = output size
        move.w  #LEVEL_SIZE,d2
        bsr     rle_decompress

        ; Store working buffer pointer for renderer
        ; a1 is preserved by decompressor, still points to level_working
        lea     level_data_ptr(pc),a0
        move.l  a1,(a0)

        ; Set world-specific block tiles based on level number
        bsr     set_world_tiles

        movem.l (sp)+,d0-d2/a0-a2
        rts

; ============================================================
; rle_decompress - RLE decompressor
; ============================================================
; Input:  a0 = source (compressed data)
;         a1 = destination buffer
;         d2.w = output size (bytes to decompress)
; Output: a1 preserved (still points to destination start)
; Encoding:
;   Byte < $80: literal byte
;   Byte >= $80: (count | $80), value - repeat 'value' 'count' times
; ============================================================
rle_decompress:
        movem.l d0-d3/a0-a1,-(sp)
        moveq   #0,d0
        moveq   #0,d1
.rd_loop:
        tst.w   d2
        beq.s   .rd_done                ; d2 = 0, finished
        move.b  (a0)+,d0                ; Read control byte
        tst.b   d0
        bpl.s   .rd_literal             ; Bit 7 clear = literal (0-127)
        ; It's a run: extract count, get value
        andi.w  #$007F,d0               ; d0.w = count (1-127)
        move.b  (a0)+,d1                ; d1.b = value to repeat
        sub.w   d0,d2                   ; Subtract full count from output remaining
        move.w  d0,d3                   ; d3 = count for loop
.rd_run:
        move.b  d1,(a1)+                ; Write value
        subq.w  #1,d3                   ; Decrement run counter
        bne.s   .rd_run                 ; More to write?
        bra.s   .rd_loop
.rd_literal:
        move.b  d0,(a1)+                ; Write literal byte
        subq.w  #1,d2                   ; Decrement output counter
        bra.s   .rd_loop
.rd_done:
        movem.l (sp)+,d0-d3/a0-a1
        rts

; ============================================================
; set_world_tiles - Copy appropriate block tiles for current world
; ============================================================
; Like original ZX Spectrum game:
;   Level 0 (title): blocks1
;   Levels 1-10: blocks1 (brick wall with offset rows)
;   Levels 11-15: blocks3 (different brick pattern)
;   Levels 16+: blocks2 (diagonal pattern)
; Copies tiles 29-30 to expanded_tiles buffer
; ============================================================
set_world_tiles:
        movem.l d0-d2/a0-a3,-(sp)

        ; Get current level
        move.w  current_level(pc),d0

        ; Determine which world (tile set + column colors)
        cmpi.w  #11,d0
        blt.s   .use_world1             ; Levels 0-10: world1
        cmpi.w  #16,d0
        blt.s   .use_world3             ; Levels 11-15: world3
        bra.s   .use_world2             ; Levels 16+: world2

.use_world1:
        ; World 1: RED columns, blocks1 tiles
        lea     blocks1_tiles(pc),a0
        lea     col_brick_pattern(pc),a1
        lea     col_brick_pattern_mirror(pc),a2
        bra.s   .apply_world

.use_world2:
        ; World 2: MAGENTA columns, blocks2 tiles
        lea     blocks2_tiles(pc),a0
        lea     col_pattern_world2(pc),a1
        lea     col_pattern_world2_mirror(pc),a2
        bra.s   .apply_world

.use_world3:
        ; World 3: CYAN columns, blocks3 tiles
        lea     blocks3_tiles(pc),a0
        lea     col_pattern_world3(pc),a1
        lea     col_pattern_world3_mirror(pc),a2

.apply_world:
        ; Save tile source pointer
        move.l  a0,a3

        ; Set column pattern pointers
        lea     col_pattern_ptr(pc),a0
        move.l  a1,(a0)+                ; col_pattern_ptr = left pattern
        move.l  a2,(a0)                 ; col_pattern_mirror_ptr = right pattern

        ; Copy block tiles from saved pointer
        move.l  a3,a0

.copy_tiles:
        ; Copy 64 bytes (2 tiles x 32 bytes) to expanded_tiles + (29*32)
        lea     expanded_tiles(pc),a1
        adda.w  #29*32,a1               ; Offset to tile 29

        ; Copy 64 bytes (16 longwords)
        moveq   #15,d0
.copy_loop:
        move.l  (a0)+,(a1)+
        dbra    d0,.copy_loop

        movem.l (sp)+,d0-d2/a0-a3
        rts

; ============================================================
; cache_coin_positions - Build list of large coin positions + count total coins
; Called at level start for fast animation refresh
; Also counts ALL coins (small + large) for exit activation
; ============================================================
cache_coin_positions:
        movem.l d0-d4/a0-a2,-(sp)

        ; Setup pointers
        lea     num_cached_coins(pc),a2
        clr.w   (a2)                    ; Reset large coin count
        lea     coin_cache(pc),a1       ; a1 = cache write pointer
        move.l  level_data_ptr(pc),a0   ; a0 = level data read pointer

        ; Initialize total coin counter
        moveq   #0,d4                   ; d4 = total coins (small + large)

        ; Scan all tiles
        moveq   #0,d1                   ; d1 = tile index (0-767)
        move.w  #LEVEL_SIZE-1,d3        ; d3 = loop counter

.scan:
        move.b  (a0)+,d0                ; Read tile type, advance pointer

        ; Check for any coin type (6 or 7)
        cmpi.b  #TILE_COIN_SM,d0
        beq.s   .found_coin
        cmpi.b  #TILE_COIN_LG,d0
        bne.s   .next_tile

        ; Found large coin - cache its position
        ; Calculate x,y from index: y = index / 12, x = index mod 12
        moveq   #0,d2                   ; CRITICAL: Clear high word before DIVU
        move.w  d1,d2                   ; d2.L = tile index (0-767)
        divu    #LEVEL_W,d2             ; d2.w = y (quotient), d2 high = x (remainder)
        move.b  d2,(a1)+                ; Store y
        swap    d2
        move.b  d2,(a1)+                ; Store x

        ; Increment large coin cache count and check max
        addq.w  #1,(a2)
        cmpi.w  #MAX_COINS,(a2)
        bge.s   .cache_full             ; Cache full, but keep counting total

.found_coin:
        ; Count this coin toward total
        addq.w  #1,d4

.next_tile:
        addq.w  #1,d1                   ; Next tile index
        dbra    d3,.scan
        bra.s   .done

.cache_full:
        ; Cache is full, but continue counting total coins
        addq.w  #1,d4                   ; Count this coin
.cache_full_loop:
        addq.w  #1,d1
        dbra    d3,.count_only
        bra.s   .done

.count_only:
        move.b  (a0)+,d0
        cmpi.b  #TILE_COIN_SM,d0
        beq.s   .count_it
        cmpi.b  #TILE_COIN_LG,d0
        bne.s   .cache_full_loop
.count_it:
        addq.w  #1,d4
        bra.s   .cache_full_loop

.done:
        ; Store total coin count
        lea     coins_total(pc),a0
        move.w  d4,(a0)

        ; Clear level complete flag for new level
        lea     level_complete_flag(pc),a0
        clr.w   (a0)

        ; Clear heroes exited mask for new level
        lea     heroes_exited(pc),a0
        clr.w   (a0)

        ; Reset game state for new level
        lea     game_state(pc),a0
        move.w  #GS_GAMEPLAY,(a0)

        movem.l (sp)+,d0-d4/a0-a2
        rts

; ============================================================
; cache_exit_positions - Build list of exit tile positions
; Called at level start for exit animation
; ============================================================
cache_exit_positions:
        movem.l d0-d3/a0-a2,-(sp)

        ; Setup pointers
        lea     num_cached_exits(pc),a2
        clr.w   (a2)                    ; Reset exit count
        lea     exit_cache(pc),a1       ; a1 = cache write pointer
        move.l  level_data_ptr(pc),a0   ; a0 = level data read pointer

        ; Scan all tiles
        moveq   #0,d1                   ; d1 = tile index (0-767)
        move.w  #LEVEL_SIZE-1,d3        ; d3 = loop counter

.exit_scan:
        move.b  (a0)+,d0                ; Read tile type
        cmpi.b  #TILE_EXIT,d0
        bne.s   .exit_next

        ; Found exit tile - cache its position
        ; Calculate x,y from index: y = index / 12, x = index mod 12
        moveq   #0,d2
        move.w  d1,d2
        divu    #LEVEL_W,d2             ; d2.w = y, d2 high = x
        move.b  d2,(a1)+                ; Store y
        swap    d2
        move.b  d2,(a1)+                ; Store x

        ; Increment count and check max
        addq.w  #1,(a2)
        cmpi.w  #MAX_EXITS,(a2)
        bge.s   .exit_done              ; Cache full

.exit_next:
        addq.w  #1,d1
        dbra    d3,.exit_scan

.exit_done:
        ; Reset exit animation state
        lea     exit_anim_frame(pc),a0
        clr.w   (a0)
        lea     exit_anim_ctr(pc),a0
        move.w  #1,(a0)

        movem.l (sp)+,d0-d3/a0-a2
        rts

; ============================================================
; next_level - Advance to next level
; ============================================================
next_level:
        movem.l d0/a0,-(sp)

        lea     current_level(pc),a0
        move.w  (a0),d0
        addq.w  #1,d0
        cmpi.w  #NUM_LEVELS,d0
        blt.s   .set_level
        moveq   #1,d0                   ; Wrap to level 1 (skip level 00)
.set_level:
        move.w  d0,(a0)

        ; Select music track based on level number
        ; Levels 1-10: MUSIC_LEVEL1, 11-15: MUSIC_LEVEL2, 16-20: MUSIC_LEVEL3
        move.w  d0,d1                   ; d1 = level number
        lea     start(pc),a0
        adda.l  #music_to_play,a0
        cmpi.w  #11,d1
        blt.s   .music1
        cmpi.w  #16,d1
        blt.s   .music2
        move.w  #MUSIC_LEVEL3,(a0)
        bra.s   .music_done
.music2:
        move.w  #MUSIC_LEVEL2,(a0)
        bra.s   .music_done
.music1:
        move.w  #MUSIC_LEVEL1,(a0)
.music_done:
        lea     current_level(pc),a0    ; Restore a0 for load_current_level

        bsr     load_current_level
        bsr     cache_coin_positions        ; Cache coin positions for fast animation
        bsr     cache_exit_positions        ; Cache exit positions for animation
        bsr     find_hero_start
        bsr     init_enemies                ; Scan for enemies before rendering
        bsr     build_cannon_list           ; Build cannon list and clear bullets
        bsr     init_scroll
        bsr     clear_trails
        bsr     render_playfield_to_buffer  ; Render new level to buffer
        bsr     copy_window_to_screen       ; Copy visible portion to screen
        bsr     draw_scrolling_columns      ; Draw animated side columns

        ; Reset hero state (optimized - only essential resets)
        lea     hero_dir(pc),a0
        clr.w   (a0)
        lea     hero_last_dir(pc),a0
        move.w  #DIR_DOWN,(a0)          ; Reset sprite orientation to upright
        lea     hero_fly(pc),a0
        clr.w   (a0)
        lea     anim_frame(pc),a0
        clr.w   (a0)
        lea     hero_drawn_x(pc),a0
        move.w  #-1,(a0)
        lea     coin_count(pc),a0
        clr.w   (a0)

        bsr     draw_hero_force
        ; Removed draw_level_num
        bsr     draw_lives                  ; Draw lives HUD
        bsr     draw_score                  ; Draw score on new level

        movem.l (sp)+,d0/a0
        rts

; ============================================================
; draw_level_num - Draw current level number in top-left
; No longer called, but keeping routine for reference
; ============================================================
; Uses lookup table to avoid DIVU issues
; Level indices 1-15 display as "01"-"15"
; Level indices 16-20 display as "21"-"25"
; ============================================================
draw_level_num:
        movem.l d0-d2/a0-a2,-(sp)

        ; Draw at top-left of screen (above playfield)
        lea     SCREEN_BASE+SCREEN_STRIDE*2+4,a0

        ; Draw "L" prefix using white without flash
        move.l  #$80800000,(a0)
        move.l  #$80800000,SCREEN_STRIDE(a0)
        move.l  #$80800000,SCREEN_STRIDE*2(a0)
        move.l  #$80800000,SCREEN_STRIDE*3(a0)
        move.l  #$80800000,SCREEN_STRIDE*4(a0)
        move.l  #$80800000,SCREEN_STRIDE*5(a0)
        move.l  #$A8A80000,SCREEN_STRIDE*6(a0)
        move.l  #$A8A80000,SCREEN_STRIDE*7(a0)

        ; Get level index and look up display digits
        move.w  current_level(pc),d0
        andi.w  #$1F,d0                 ; Safety clamp to 0-31
        add.w   d0,d0                   ; d0 = index * 2 (word offset)
        lea     level_display_table(pc),a2
        move.w  (a2,d0.w),d2            ; d2 = packed digits (tens:units)

        ; Draw tens digit at offset 4
        lea     4(a0),a1
        move.w  d2,d1
        lsr.w   #8,d1                   ; d1 = tens digit
        bsr.s   draw_digit

        ; Draw units digit at offset 8
        lea     8(a0),a1
        move.w  d2,d1
        andi.w  #$FF,d1                 ; d1 = units digit
        bsr.s   draw_digit

        movem.l (sp)+,d0-d2/a0-a2
        rts

; Level display lookup table: packed tens:units for each level index
; Index 0-15 -> display 00-15, Index 16-20 -> display 21-25
level_display_table:
        dc.w    $0000           ; Index 0: "00" (unused)
        dc.w    $0001           ; Index 1: "01"
        dc.w    $0002           ; Index 2: "02"
        dc.w    $0003           ; Index 3: "03"
        dc.w    $0004           ; Index 4: "04"
        dc.w    $0005           ; Index 5: "05"
        dc.w    $0006           ; Index 6: "06"
        dc.w    $0007           ; Index 7: "07"
        dc.w    $0008           ; Index 8: "08"
        dc.w    $0009           ; Index 9: "09"
        dc.w    $0100           ; Index 10: "10"
        dc.w    $0101           ; Index 11: "11"
        dc.w    $0102           ; Index 12: "12"
        dc.w    $0103           ; Index 13: "13"
        dc.w    $0104           ; Index 14: "14"
        dc.w    $0105           ; Index 15: "15"
        dc.w    $0201           ; Index 16: "21"
        dc.w    $0202           ; Index 17: "22"
        dc.w    $0203           ; Index 18: "23"
        dc.w    $0204           ; Index 19: "24"
        dc.w    $0205           ; Index 20: "25"

; ============================================================
; draw_digit - Draw a single digit (0-9) at a1
; Input: d1 = digit (0-9), a1 = screen address
; ============================================================
; MODE 8 white pixel patterns (no flash):
; Pixel 0: $8080, Pixel 1: $2020, Pixel 2: $0808, Pixel 3: $0202
; ============================================================
draw_digit:
        movem.l d0-d2/a0-a2,-(sp)

        lea     digit_patterns(pc),a0
        move.w  d1,d0
        lsl.w   #3,d0           ; d0 = digit * 8
        adda.w  d0,a0           ; a0 = pattern for this digit

        moveq   #7,d2
.row:
        move.b  (a0)+,d0
        ; Expand 1bpp to MODE 8 white (no flash)
        ; Each bit maps to white pixel pattern
        moveq   #0,d1
        btst    #7,d0
        beq.s   .b7
        ori.w   #$8080,d1       ; Pixel 0 white
.b7:    btst    #6,d0
        beq.s   .b6
        ori.w   #$2020,d1       ; Pixel 1 white
.b6:    btst    #5,d0
        beq.s   .b5
        ori.w   #$0808,d1       ; Pixel 2 white
.b5:    btst    #4,d0
        beq.s   .b4
        ori.w   #$0202,d1       ; Pixel 3 white
.b4:
        move.w  d1,(a1)
        ; Second half (pixels 4-7)
        moveq   #0,d1
        btst    #3,d0
        beq.s   .b3
        ori.w   #$8080,d1       ; Pixel 4 white
.b3:    btst    #2,d0
        beq.s   .b2
        ori.w   #$2020,d1       ; Pixel 5 white
.b2:    btst    #1,d0
        beq.s   .b1
        ori.w   #$0808,d1       ; Pixel 6 white
.b1:    btst    #0,d0
        beq.s   .b0
        ori.w   #$0202,d1       ; Pixel 7 white
.b0:
        move.w  d1,2(a1)
        adda.w  #SCREEN_STRIDE,a1
        dbra    d2,.row

        movem.l (sp)+,d0-d2/a0-a2
        rts

; Simple 8x8 digit patterns (1bpp)
digit_patterns:
        dc.b    $3C,$66,$6E,$76,$66,$66,$3C,$00  ; 0
        dc.b    $18,$38,$18,$18,$18,$18,$7E,$00  ; 1
        dc.b    $3C,$66,$06,$1C,$30,$60,$7E,$00  ; 2
        dc.b    $3C,$66,$06,$1C,$06,$66,$3C,$00  ; 3
        dc.b    $0C,$1C,$3C,$6C,$7E,$0C,$0C,$00  ; 4
        dc.b    $7E,$60,$7C,$06,$06,$66,$3C,$00  ; 5
        dc.b    $1C,$30,$60,$7C,$66,$66,$3C,$00  ; 6
        dc.b    $7E,$06,$0C,$18,$30,$30,$30,$00  ; 7
        dc.b    $3C,$66,$66,$3C,$66,$66,$3C,$00  ; 8
        dc.b    $3C,$66,$66,$3E,$06,$0C,$38,$00  ; 9
        even

; ============================================================
; Score variables (placed near draw_score for PC-relative range)
; ============================================================
score:           dc.l 0             ; Accumulated score (32-bit, persists across deaths)
prev_score:      dc.l -1            ; Previous score for change detection

; ============================================================
; Score display using 5-row Spectrum font
; ============================================================

; 5-row digit font data (rows 1-5 from Spectrum font.fnt)
; 10 digits × 5 bytes each
score_font_5row:
        dc.b    $3c,$66,$6e,$76,$3c         ; 0
        dc.b    $38,$18,$18,$18,$3c         ; 1
        dc.b    $3c,$46,$1c,$60,$7e         ; 2
        dc.b    $3c,$46,$0c,$46,$3c         ; 3
        dc.b    $0c,$1c,$2c,$7c,$0c         ; 4
        dc.b    $7e,$60,$7c,$06,$7c         ; 5
        dc.b    $3c,$60,$7c,$66,$3c         ; 6
        dc.b    $7e,$06,$06,$0c,$18         ; 7
        dc.b    $3c,$66,$3c,$66,$3c         ; 8
        dc.b    $3c,$66,$3e,$06,$3c         ; 9
        even

; Division table for score-to-decimal conversion
score_divisors:
        dc.l    100000,10000,1000,100,10,1

; ============================================================
; draw_score - Draw 6-digit score at top-right of screen
; Uses change detection (prev_score) for efficiency
; ============================================================
draw_score:
        ; Check if score changed
        move.l  score(pc),d0
        cmp.l   prev_score(pc),d0
        beq     .score_done                 ; No change, skip redraw

        ; Score changed - update cache
        lea     prev_score(pc),a0
        move.l  d0,(a0)

        movem.l d0-d7/a0-a4,-(sp)

        ; Convert score (d0.l) to 6 decimal digits
        ; Use repeated subtraction with divisor table
        lea     score_divisors(pc),a2
        ; Score position indented to match lives (2 bytes from edge)
        ; 6 digits × 4 bytes = 24; screen width = 128 bytes; 128-24-2 = 102
        lea     SCREEN_BASE+SCREEN_STRIDE*5+102,a3

        moveq   #5,d7                       ; 6 digits (0-5)
.next_digit:
        move.l  (a2)+,d1                    ; d1 = divisor
        moveq   #0,d2                       ; d2 = digit value
.sub_loop:
        cmp.l   d1,d0
        blt.s   .sub_done
        sub.l   d1,d0
        addq.l  #1,d2
        bra.s   .sub_loop
.sub_done:
        ; d2 = digit (0-9), draw it at a3
        ; Look up font pattern: digit * 5 bytes
        move.l  a3,a4                       ; a4 = screen pos for this digit
        lea     score_font_5row(pc),a1
        move.w  d2,d3
        mulu    #5,d3                       ; d3 = offset into font
        adda.w  d3,a1                       ; a1 = font data for this digit

        ; Draw 5 rows, expand 1bpp → MODE 8 white
        moveq   #4,d4                       ; 5 rows (0-4)
.score_row:
        move.b  (a1)+,d3                    ; Get font byte
        ; Expand high nibble (pixels 0-3) → first word
        moveq   #0,d5
        btst    #7,d3
        beq.s   .sr7
        ori.w   #$8080,d5
.sr7:   btst    #6,d3
        beq.s   .sr6
        ori.w   #$2020,d5
.sr6:   btst    #5,d3
        beq.s   .sr5
        ori.w   #$0808,d5
.sr5:   btst    #4,d3
        beq.s   .sr4
        ori.w   #$0202,d5
.sr4:
        move.w  d5,(a4)
        ; Expand low nibble (pixels 4-7) → second word
        moveq   #0,d5
        btst    #3,d3
        beq.s   .sr3
        ori.w   #$8080,d5
.sr3:   btst    #2,d3
        beq.s   .sr2
        ori.w   #$2020,d5
.sr2:   btst    #1,d3
        beq.s   .sr1
        ori.w   #$0808,d5
.sr1:   btst    #0,d3
        beq.s   .sr0
        ori.w   #$0202,d5
.sr0:
        move.w  d5,2(a4)
        adda.w  #SCREEN_STRIDE,a4           ; Next row
        dbra    d4,.score_row

        addq.l  #4,a3                       ; Advance to next digit position (4 bytes = 8 pixels)
        dbra    d7,.next_digit

        movem.l (sp)+,d0-d7/a0-a4
.score_done:
        rts

; ============================================================
; wait_vsync with 25fps frame pacing (debug/timing code removed)
; Two modes - adaptive (default) or forced 25fps
; Waits until 2 ticks have elapsed since previous frame end.
; ============================================================
FRAME_TICKS     equ 2                   ; Target: 2 ticks = 40ms = 25fps

; Frame pacer mode constants
PACER_ADAPTIVE  equ 0                   ; Adaptive timing (default)
PACER_FORCED    equ 1                   ; Forced 25fps

wait_vsync:
        ; Quick mode check - branch to forced if non-zero
        move.w  frame_pacer_mode(pc),d0
        bne.s   wait_vsync_forced
        ; Fall through to adaptive mode

; --- Adaptive mode: wait until 2 ticks elapsed ---
wait_vsync_adaptive:
        movem.l d0/a0,-(sp)
        move.w  $2802E,d0
        sub.w   prev_tick(pc),d0
        cmpi.w  #FRAME_TICKS,d0
        bge.s   .a_overrun
        ; Clear overrun flag (for pacer sampling)
        lea     frame_overrun(pc),a0
        clr.w   (a0)
.a_wait:
        move.w  $2802E,d0
        sub.w   prev_tick(pc),d0
        cmpi.w  #FRAME_TICKS,d0
        blt.s   .a_wait
        bra.s   .a_save

.a_overrun:
        ; Set overrun flag (for pacer sampling)
        lea     frame_overrun(pc),a0
        move.w  #1,(a0)

.a_save:
        add.w   prev_tick(pc),d0
        lea     prev_tick(pc),a0
        move.w  d0,(a0)
        movem.l (sp)+,d0/a0
        rts

; --- Forced 25fps mode: wait for 2 tick boundaries ---
wait_vsync_forced:
        movem.l d0/a0,-(sp)
        move.w  $2802E,d0
        sub.w   prev_tick(pc),d0
        cmpi.w  #FRAME_TICKS,d0
        bge.s   .f_overrun
        lea     frame_overrun(pc),a0
        clr.w   (a0)
        bra.s   .f_wait1
.f_overrun:
        lea     frame_overrun(pc),a0
        move.w  #1,(a0)
.f_wait1:
        move.w  $2802E,d0
.f_spin1:
        cmp.w   $2802E,d0
        beq.s   .f_spin1
        move.w  $2802E,d0
.f_spin2:
        cmp.w   $2802E,d0
        beq.s   .f_spin2

        move.w  $2802E,d0
        lea     prev_tick(pc),a0
        move.w  d0,(a0)
        movem.l (sp)+,d0/a0
        rts

; ============================================================
; activate_hidden_tile - If tile at (x,y) is TILE_HIDDEN, make solid
; Input: d0 = x (level coord 0-11)
;        d1 = y (level coord 0-63)
; ============================================================
activate_hidden_tile:
        movem.l d0-d3/a0,-(sp)

        ; Bounds check
        tst.w   d0
        bmi     .done
        cmpi.w  #LEVEL_W,d0
        bge     .done
        tst.w   d1
        bmi     .done
        cmpi.w  #LEVEL_H,d1
        bge     .done

        ; Save coordinates
        move.w  d0,d2           ; d2 = x (saved)
        move.w  d1,d3           ; d3 = y (saved)

        ; Calculate offset: y * 12 + x using shift-add
        add.w   d1,d1           ; d1 = y*2
        add.w   d3,d1           ; d1 = y*3 (using saved y)
        lsl.w   #2,d1           ; d1 = y*12
        add.w   d2,d1           ; d1 = y*12 + x

        ; Get level_data base from stored pointer
        move.l  level_data_ptr(pc),a0

        ; Check tile type - is it TILE_HIDDEN (1)?
        cmpi.b  #TILE_HIDDEN,(a0,d1.w)
        bne.s   .done

        ; It's a hidden tile - change to TILE_UNHIDDEN (28)
        move.b  #TILE_UNHIDDEN,(a0,d1.w)

        ; Update buffer with new tile (d2=x, d3=y)
        move.w  d2,d0           ; d0 = tile_x
        move.w  d3,d1           ; d1 = tile_y
        moveq   #TILE_UNHIDDEN,d2  ; d2 = new tile type
        bsr     render_tile_to_buffer

.done:
        movem.l (sp)+,d0-d3/a0
        rts

; ============================================================
; check_crack_tile - Remove cracked tile if hero bumped into one
; Called at start of movement to check/remove cracked block
; Uses hero_land_dir to know which direction hero last bumped
; ============================================================
check_crack_tile:
        ; Check if we have a landing direction (non-zero means hero bumped something)
        move.w  hero_land_dir(pc),d0
        beq.s   .cct_done                   ; No landing direction, nothing to check

        movem.l d0-d3/a0,-(sp)

        ; Get hero position
        move.w  hero_x(pc),d2               ; d2 = hero x
        move.w  hero_y(pc),d3               ; d3 = hero y

        ; Calculate adjacent tile position based on landing direction
        move.w  hero_land_dir(pc),d0
        cmpi.w  #DIR_UP,d0
        beq.s   .cct_up
        cmpi.w  #DIR_DOWN,d0
        beq.s   .cct_down
        cmpi.w  #DIR_LEFT,d0
        beq.s   .cct_left
        cmpi.w  #DIR_RIGHT,d0
        beq.s   .cct_right
        bra.s   .cct_clear                  ; Unknown direction, just clear

.cct_up:
        subq.w  #1,d3                       ; y - 1
        bmi.s   .cct_clear                  ; Off edge
        bra.s   .cct_check

.cct_down:
        addq.w  #1,d3                       ; y + 1
        cmpi.w  #LEVEL_H,d3
        bge.s   .cct_clear                  ; Off edge
        bra.s   .cct_check

.cct_left:
        subq.w  #1,d2                       ; x - 1
        bmi.s   .cct_clear                  ; Off edge
        bra.s   .cct_check

.cct_right:
        addq.w  #1,d2                       ; x + 1
        cmpi.w  #LEVEL_W,d2
        bge.s   .cct_clear                  ; Off edge

.cct_check:
        ; Calculate tile offset: y*12 + x
        move.w  d3,d1
        add.w   d1,d1                       ; d1 = y*2
        add.w   d3,d1                       ; d1 = y*3
        lsl.w   #2,d1                       ; d1 = y*12
        add.w   d2,d1                       ; d1 = y*12 + x

        ; Check if it's a cracked tile
        move.l  level_data_ptr(pc),a0
        cmpi.b  #TILE_CRACK,(a0,d1.w)
        bne.s   .cct_clear                  ; Not cracked, just clear landing dir

        ; It's a cracked tile - change to empty
        move.b  #TILE_EMPTY,(a0,d1.w)

        ; Update buffer with empty tile
        move.w  d2,d0                       ; d0 = tile_x
        move.w  d3,d1                       ; d1 = tile_y
        moveq   #TILE_EMPTY,d2              ; d2 = new tile type
        bsr     render_tile_to_buffer

.cct_clear:
        ; Clear landing direction
        lea     hero_land_dir(pc),a0
        clr.w   (a0)
        movem.l (sp)+,d0-d3/a0

.cct_done:
        rts

; ============================================================
; mark_coin_collected - Mark large coin as collected in cache
; Input: d5 = x, d6 = y
; ============================================================
mark_coin_collected:
        movem.l d0-d1/a0,-(sp)

        move.w  num_cached_coins(pc),d0
        beq.s   .done
        subq.w  #1,d0
        lea     coin_cache(pc),a0

.search:
        move.b  (a0),d1                 ; Get cached y
        cmp.b   d6,d1                   ; Compare with hero y
        bne.s   .next
        move.b  1(a0),d1                ; Get cached x
        cmp.b   d5,d1                   ; Compare with hero x
        bne.s   .next

        ; Found it - mark as collected
        move.b  #$FF,(a0)               ; Mark y as $FF
        move.b  #$FF,1(a0)              ; Mark x as $FF
        bra.s   .done

.next:
        addq.l  #2,a0
        dbra    d0,.search

.done:
        movem.l (sp)+,d0-d1/a0
        rts

; ============================================================
; is_solid_tile - Check if tile at (d0,d1) blocks movement
; Input: d0 = x, d1 = y
; Output: d0 = 1 if solid, 0 if passable
; ============================================================
is_solid_tile:
        ; Bounds check
        tst.w   d0
        bmi.s   .solid
        cmpi.w  #LEVEL_W,d0
        bge.s   .solid
        tst.w   d1
        bmi.s   .passable
        cmpi.w  #LEVEL_H,d1
        bge.s   .solid

        movem.l d1-d3/a0,-(sp)

        ; Save x, calculate offset using shift-add (y*12)
        move.w  d0,d2           ; d2 = x
        move.w  d1,d3           ; d3 = y
        add.w   d3,d3           ; d3 = y*2
        add.w   d1,d3           ; d3 = y*3
        lsl.w   #2,d3           ; d3 = y*12
        add.w   d2,d3           ; d3 = y*12 + x

        ; Get tile type
        move.l  level_data_ptr(pc),a0
        moveq   #0,d0
        move.b  (a0,d3.w),d0

        ; Check cannon tiles (22-25) - all block hero
        cmpi.b  #TILE_CANNON_OPEN_R,d0
        blt.s   .not_cannon
        cmpi.b  #TILE_CANNON_L,d0
        ble.s   .is_solid               ; Cannon tile - blocks hero

.not_cannon:
        ; Check solid tiles: >= 28 means solid
        cmpi.b  #TILE_UNHIDDEN,d0
        bge.s   .is_solid

        movem.l (sp)+,d1-d3/a0
.passable:
        moveq   #0,d0
        rts

.is_solid:
        movem.l (sp)+,d1-d3/a0
.solid:
        moveq   #1,d0
        rts

; ============================================================
; is_solid_for_hero - Direction-aware tile collision check
; Input: d0 = x, d1 = y, d2 = move direction (DIR_UP/DOWN/LEFT/RIGHT)
; Output: d0 = 1 if solid, 0 if passable
; Handles special cases:
;   - Inactive hero: blocks active hero (allows using as platform)
;   - One-way tiles: allow passage in specific direction only
;   - Spike tiles: kill if approaching from face, block from sides
;   - Bounce tiles (26): sets hero_bounce_dir for vertical movement
;   - Cracked tiles (27): always solid until removed by check_crack_tile
; ============================================================
is_solid_for_hero:
        ; Bounds check (same as is_solid_tile)
        tst.w   d0
        bmi     .sfh_solid
        cmpi.w  #LEVEL_W,d0
        bge     .sfh_solid
        tst.w   d1
        bmi     .sfh_passable
        cmpi.w  #LEVEL_H,d1
        bge     .sfh_solid

        ; === Check if inactive hero blocks this position ===
        ; Only check if level has two heroes
        move.w  level_has_hero2(pc),d3
        beq.s   .sfh_no_hero2_block

        ; Get inactive hero index
        move.w  active_hero(pc),d3
        eori.w  #1,d3                   ; d3 = inactive hero index (0->1, 1->0)

        ; Check if inactive hero has exited (exited heroes don't block)
        move.w  heroes_exited(pc),d4
        btst    d3,d4
        bne.s   .sfh_no_hero2_block     ; Inactive hero exited, doesn't block
        ; Multiply by 18: d3 = d3*16 + d3*2 = (d3<<4) + (d3<<1)
        move.w  d3,d4
        lsl.w   #4,d3                   ; d3 = index * 16
        add.w   d4,d4                   ; d4 = index * 2
        add.w   d4,d3                   ; d3 = index * 18

        ; Get inactive hero's position
        lea     hero_slots(pc),a0
        cmp.w   HERO_SLOT_X(a0,d3.w),d0 ; Compare x
        bne.s   .sfh_no_hero2_block
        cmp.w   HERO_SLOT_Y(a0,d3.w),d1 ; Compare y
        bne.s   .sfh_no_hero2_block
        ; Position matches inactive hero - block!
        bra.s   .sfh_solid

.sfh_no_hero2_block:
        movem.l d1-d4/a0,-(sp)

        ; Calculate level offset: y*12 + x
        move.w  d0,d3           ; d3 = x
        move.w  d1,d4           ; d4 = y
        add.w   d4,d4           ; d4 = y*2
        add.w   d1,d4           ; d4 = y*3
        lsl.w   #2,d4           ; d4 = y*12
        add.w   d3,d4           ; d4 = y*12 + x

        ; Get tile type
        move.l  level_data_ptr(pc),a0
        moveq   #0,d0
        move.b  (a0,d4.w),d0

        ; === FAST PATH: Empty tile (most common) ===
        beq.s   .sfh_pass_now           ; Tile 0 = empty, quick exit

        ; === FAST PATH: Solid tiles >= 28 (second most common) ===
        cmpi.b  #TILE_UNHIDDEN,d0
        bge.s   .sfh_is_solid

        ; === SPECIAL TILES (less common) ===
        ; Check spike tiles (2-5) using range check
        cmpi.b  #TILE_SPIKE_UP,d0       ; tile >= 2?
        blt.s   .sfh_pass_now           ; Tile 1 (hidden) = passable
        cmpi.b  #TILE_SPIKE_L,d0        ; tile <= 5?
        ble.s   .sfh_check_spike        ; It's a spike (2-5)

        ; Check one-way tiles (14-15)
        cmpi.b  #TILE_ONEWAY_DN,d0
        beq.s   .sfh_oneway_down
        cmpi.b  #TILE_ONEWAY_UP,d0
        beq.s   .sfh_oneway_up

        ; Check cannon tiles (22-25) - range check
        cmpi.b  #TILE_CANNON_OPEN_R,d0
        blt.s   .sfh_not_cannon
        cmpi.b  #TILE_CANNON_L,d0
        ble.s   .sfh_is_solid           ; Cannon tile - blocks hero

.sfh_not_cannon:
        ; Check bounce tile (26) - reverses vertical movement
        cmpi.b  #TILE_BOUNCE,d0
        beq.s   .sfh_bounce

        ; Check cracked tile (27) - always solid until removed
        cmpi.b  #TILE_CRACK,d0
        beq.s   .sfh_is_solid

        ; All other tiles (6-13, 16-21) are passable
        ; (coins, exit, reflectors, hero statues)
.sfh_pass_now:
        movem.l (sp)+,d1-d4/a0
.sfh_passable:
        moveq   #0,d0
        rts

.sfh_is_solid:
        movem.l (sp)+,d1-d4/a0
.sfh_solid:
        moveq   #1,d0
        rts

.sfh_check_spike:
        ; It's a spike tile (2-5) - check direction using table
        subi.b  #TILE_SPIKE_UP,d0       ; d0 = 0-3 (spike index)
        lea     spike_deadly_dir(pc),a0
        move.b  (a0,d0.w),d0            ; Get deadly direction for this spike
        cmp.b   d2,d0                   ; Compare with hero's move direction
        beq.s   .sfh_spike_kill
        bra.s   .sfh_is_solid           ; Block from other directions

.sfh_oneway_down:
        ; TILE_ONEWAY_DN (14): passable UP, blocks DOWN
        cmpi.w  #DIR_UP,d2
        beq.s   .sfh_ow_pass
        bra.s   .sfh_is_solid

.sfh_oneway_up:
        ; TILE_ONEWAY_UP (15): passable DOWN, blocks UP
        cmpi.w  #DIR_DOWN,d2
        beq.s   .sfh_ow_pass
        bra.s   .sfh_is_solid

.sfh_ow_pass:
        movem.l (sp)+,d1-d4/a0
        moveq   #0,d0
        rts

.sfh_bounce:
        ; Bounce tile (26) - reverse vertical movement, block horizontal
        ; d2 = movement direction
        cmpi.w  #DIR_UP,d2
        beq.s   .sfh_bounce_down
        cmpi.w  #DIR_DOWN,d2
        beq.s   .sfh_bounce_up
        ; Horizontal movement - just block
        bra.s   .sfh_is_solid

.sfh_bounce_down:
        ; Moving UP into bounce -> bounce DOWN
        lea     hero_bounce_dir(pc),a0
        move.w  #DIR_DOWN,(a0)
        bra.s   .sfh_is_solid

.sfh_bounce_up:
        ; Moving DOWN into bounce -> bounce UP
        lea     hero_bounce_dir(pc),a0
        move.w  #DIR_UP,(a0)
        bra.s   .sfh_is_solid

.sfh_spike_kill:
        ; Hero hit spike from deadly direction - set flag and allow movement
        lea     hero_hit_spike(pc),a0
        move.w  #1,(a0)
        movem.l (sp)+,d1-d4/a0
        moveq   #0,d0                   ; Return passable so hero moves onto spike
        rts

; ============================================================
; expand_tiles
; ============================================================
; expand_tiles - Copy pre-expanded 4bpp tiles to buffer
; Tiles are already expanded with colors baked in
; Copies 1024 bytes (32 tiles x 32 bytes)
; ============================================================
expand_tiles:
        movem.l d0-d7/a0-a1,-(sp)

        lea     tiles_4bpp(pc),a0
        lea     expanded_tiles(pc),a1

        ; Copy 1024 bytes using movem.l (32 bytes per iteration = 32 iterations)
        moveq   #31,d0
.copy_loop:
        movem.l (a0)+,d1-d7/a2     ; Read 32 bytes (8 longwords)
        movem.l d1-d7/a2,(a1)      ; Write 32 bytes
        lea     32(a1),a1          ; Advance dest pointer
        dbra    d0,.copy_loop

        movem.l (sp)+,d0-d7/a0-a1
        rts

; ============================================================
; update_coin_animation - Update coin animation frame
; Called every frame, but only updates every COIN_ANIM_SKIP frames
; Updates expanded_tiles entry for TILE_COIN_LG with current frame
; ============================================================
update_coin_animation:
        ; Check skip counter
        lea     coin_anim_ctr(pc),a0
        subq.w  #1,(a0)
        bne.s   .no_update

        ; Reset counter
        move.w  #COIN_ANIM_SKIP,(a0)

        ; Advance frame (0->1->2->3->0...)
        lea     coin_anim_frame(pc),a0
        move.w  (a0),d0
        addq.w  #1,d0
        andi.w  #COIN_ANIM_FRAMES-1,d0  ; Wrap at 4
        move.w  d0,(a0)

        ; Copy current frame to expanded_tiles at TILE_COIN_LG position
        ; Source: coin_exp_frames + frame * 32
        lsl.w   #5,d0                   ; d0 = frame * 32
        lea     coin_exp_frames(pc),a0
        adda.w  d0,a0                   ; a0 = source frame

        ; Destination: expanded_tiles + TILE_COIN_LG * 32
        lea     expanded_tiles(pc),a1
        adda.w  #COIN_TILE_OFFSET,a1    ; a1 = destination

        ; Copy 32 bytes (8 longwords)
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+

        ; Now refresh visible coin tiles in buffer
        bsr.s   refresh_coin_tiles

.no_update:
        rts

; ============================================================
; refresh_coin_tiles - Re-render visible TILE_COIN_LG tiles to buffer
; OPTIMIZED: No per-coin stack operations
;   - d5 used for loop counter (not clobbered by render_tile_to_buffer)
;   - Inlined tile copy, pre-computed tile address in a2
;   - a1 used as buffer dest, a2 as tile source (indexed, not incremented)
; ============================================================
refresh_coin_tiles:
        movem.l d0-d5/a0-a2,-(sp)

        ; Calculate visible tile range based on window_y
        move.w  window_y(pc),d3
        lsr.w   #3,d3                   ; d3 = first visible tile row
        move.w  d3,d4
        addi.w  #PLAY_H,d4              ; d4 = last visible tile row (exclusive)

        ; Pre-compute expanded tile address (constant for all coins)
        lea     expanded_tiles(pc),a2
        adda.w  #TILE_COIN_LG*32,a2     ; a2 = expanded TILE_COIN_LG source

        ; Iterate through cached coin positions
        move.w  num_cached_coins(pc),d5
        beq.s   .done                   ; No coins cached
        subq.w  #1,d5                   ; Adjust for dbra
        lea     coin_cache(pc),a0

.coin_loop:
        ; Load y,x from cache (stored as y,x bytes)
        move.b  (a0)+,d1                ; d1 = tile_y
        move.b  (a0)+,d0                ; d0 = tile_x

        ; Check if collected ($FF marker)
        cmpi.b  #$FF,d1
        beq.s   .next_coin

        ; Check if visible (d3 <= y < d4)
        ext.w   d1                      ; Extend to word
        cmp.w   d3,d1
        blt.s   .next_coin              ; Below visible area
        cmp.w   d4,d1
        bge.s   .next_coin              ; Above visible area

        ; Inline tile copy (eliminates bsr/rts + movem overhead)
        ; Calculate buffer address: buf + tile_y * 384 + tile_x * 4
        ext.w   d0                      ; Extend x to word
        move.w  d1,d2
        lsl.w   #8,d2                   ; d2 = tile_y * 256
        lsl.w   #7,d1                   ; d1 = tile_y * 128
        add.w   d1,d2                   ; d2 = tile_y * 384
        lsl.w   #2,d0                   ; d0 = tile_x * 4
        add.w   d0,d2                   ; d2 = buffer offset
        lea     playfield_buf(pc),a1
        adda.w  d2,a1                   ; a1 = buffer destination

        ; Copy 8 rows using indexed addressing (a2 = tile base, constant)
        move.l  (a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  4(a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  8(a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  12(a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  16(a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  20(a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  24(a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  28(a2),(a1)

.next_coin:
        dbra    d5,.coin_loop

.done:
        movem.l (sp)+,d0-d5/a0-a2
        rts

; ============================================================
; update_exit_animation - Animate exit tiles when all coins collected
; Called every frame, only updates when coins_total = 0
; Cycles through colors: WHITE -> YELLOW -> GREEN -> CYAN
; ============================================================
update_exit_animation:
        ; Only animate if all coins collected
        move.w  coins_total(pc),d0
        bne.s   .exit_no_update         ; Coins remain - no animation

        ; Check skip counter
        lea     exit_anim_ctr(pc),a0
        subq.w  #1,(a0)
        bne.s   .exit_no_update

        ; Reset counter
        move.w  #EXIT_ANIM_SKIP,(a0)

        ; Advance frame (0->1->2->3->0...)
        lea     exit_anim_frame(pc),a0
        move.w  (a0),d0
        addq.w  #1,d0
        andi.w  #EXIT_ANIM_FRAMES-1,d0  ; Wrap at 4
        move.w  d0,(a0)

        ; Copy current frame to expanded_tiles at TILE_EXIT position
        ; Source: exit_exp_frames + frame * 32
        lsl.w   #5,d0                   ; d0 = frame * 32
        lea     exit_exp_frames(pc),a0
        adda.w  d0,a0                   ; a0 = source frame

        ; Destination: expanded_tiles + TILE_EXIT * 32
        lea     expanded_tiles(pc),a1
        adda.w  #EXIT_TILE_OFFSET,a1    ; a1 = destination

        ; Copy 32 bytes (8 longwords)
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+
        move.l  (a0)+,(a1)+

        ; Refresh visible exit tiles in buffer
        bsr.s   refresh_exit_tiles

.exit_no_update:
        rts

; ============================================================
; refresh_exit_tiles - Re-render visible TILE_EXIT tiles to buffer
; Inlined tile copy, pre-computed tile address in a2
; ============================================================
refresh_exit_tiles:
        movem.l d0-d5/a0-a2,-(sp)

        ; Calculate visible tile range based on window_y
        move.w  window_y(pc),d3
        lsr.w   #3,d3                   ; d3 = first visible tile row
        move.w  d3,d4
        addi.w  #PLAY_H,d4              ; d4 = last visible tile row (exclusive)

        ; Pre-compute expanded tile address (constant for all exits)
        lea     expanded_tiles(pc),a2
        adda.w  #TILE_EXIT*32,a2        ; a2 = expanded TILE_EXIT source

        ; Iterate through cached exit positions
        move.w  num_cached_exits(pc),d5
        beq.s   .exit_done              ; No exits cached
        subq.w  #1,d5                   ; Adjust for dbra
        lea     exit_cache(pc),a0

.exit_loop:
        ; Load y,x from cache
        move.b  (a0)+,d1                ; d1 = tile_y
        move.b  (a0)+,d0                ; d0 = tile_x

        ; Check if visible (d3 <= y < d4)
        ext.w   d1                      ; Extend to word
        cmp.w   d3,d1
        blt.s   .exit_next              ; Below visible area
        cmp.w   d4,d1
        bge.s   .exit_next              ; Above visible area

        ; Inline tile copy (eliminates bsr/rts + movem overhead)
        ; Calculate buffer address: buf + tile_y * 384 + tile_x * 4
        ext.w   d0                      ; Extend x to word
        move.w  d1,d2
        lsl.w   #8,d2                   ; d2 = tile_y * 256
        lsl.w   #7,d1                   ; d1 = tile_y * 128
        add.w   d1,d2                   ; d2 = tile_y * 384
        lsl.w   #2,d0                   ; d0 = tile_x * 4
        add.w   d0,d2                   ; d2 = buffer offset
        lea     playfield_buf(pc),a1
        adda.w  d2,a1                   ; a1 = buffer destination

        ; Copy 8 rows using indexed addressing (a2 = tile base, constant)
        move.l  (a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  4(a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  8(a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  12(a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  16(a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  20(a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  24(a2),(a1)
        adda.w  #BUF_STRIDE,a1
        move.l  28(a2),(a1)

.exit_next:
        dbra    d5,.exit_loop

.exit_done:
        movem.l (sp)+,d0-d5/a0-a2
        rts

; ============================================================
; find_hero_start (init_heroes) - Find all heroes in level
; Scans for TILE_HERO_START (31) and TILE_HERO_DOWN/UP/LEFT/RIGHT (18-21)
; Initializes hero_slots array and sets active hero
; ============================================================
find_hero_start:
        movem.l d0-d5/a0-a3,-(sp)

        ; Clear hero slots array
        lea     hero_slots(pc),a2
        moveq   #(MAX_HEROES*HERO_SLOT_SIZE/2)-1,d0
.clear_slots:
        clr.w   (a2)+
        dbra    d0,.clear_slots

        ; Reset hero count and active hero
        lea     num_heroes(pc),a2
        clr.w   (a2)
        lea     active_hero(pc),a2
        clr.w   (a2)

        ; Scan level for hero tiles
        move.l  level_data_ptr(pc),a0
        move.l  a0,a1                   ; a1 = level base for offset calc
        lea     hero_slots(pc),a2       ; a2 = current hero slot
        moveq   #0,d3                   ; d3 = hero count
        move.w  #LEVEL_W*LEVEL_H-1,d4   ; d4 = loop counter

.scan_loop:
        move.b  (a0),d0

        ; Check for TILE_HERO_START (31) - primary hero
        cmpi.b  #TILE_HERO_START,d0
        beq.s   .found_hero_start

        ; Check for TILE_HERO_DOWN (18)
        cmpi.b  #TILE_HERO_DOWN,d0
        beq.s   .found_hero_down

        ; Check for TILE_HERO_UP (19)
        cmpi.b  #TILE_HERO_UP,d0
        beq.s   .found_hero_up

        ; Check for TILE_HERO_LEFT (20)
        cmpi.b  #TILE_HERO_LEFT,d0
        beq.s   .found_hero_left

        ; Check for TILE_HERO_RIGHT (21)
        cmpi.b  #TILE_HERO_RIGHT,d0
        beq.s   .found_hero_right

.next_tile:
        addq.l  #1,a0
        dbra    d4,.scan_loop
        bra.s   .scan_done

.found_hero_start:
        moveq   #DIR_DOWN,d5
        bra.s   .add_hero
.found_hero_down:
        moveq   #DIR_DOWN,d5
        bra.s   .add_hero
.found_hero_up:
        moveq   #DIR_UP,d5
        bra.s   .add_hero
.found_hero_left:
        moveq   #DIR_LEFT,d5
        bra.s   .add_hero
.found_hero_right:
        moveq   #DIR_RIGHT,d5

.add_hero:
        ; Check if we have room for another hero
        cmpi.w  #MAX_HEROES,d3
        bge.s   .skip_hero

        ; Calculate x,y from offset
        move.l  a0,d0
        sub.l   a1,d0
        divu    #LEVEL_W,d0
        move.w  d0,d2           ; d2 = y (quotient)
        swap    d0
        move.w  d0,d1           ; d1 = x (remainder)

        ; Clear hero tile from level
        move.b  #TILE_EMPTY,(a0)

        ; Store in hero slot
        move.w  d1,HERO_SLOT_X(a2)      ; x
        move.w  d2,HERO_SLOT_Y(a2)      ; y
        clr.w   HERO_SLOT_DIR(a2)       ; dir = STOP
        move.w  d5,HERO_SLOT_LASTD(a2)  ; last_dir = initial direction
        clr.w   HERO_SLOT_FLY(a2)       ; fly = 0
        clr.w   HERO_SLOT_ANIM(a2)      ; anim = 0
        move.w  #1,HERO_SLOT_ACT(a2)    ; active = 1
        move.w  d1,HERO_SLOT_STARTX(a2) ; spawn x (for respawn)
        move.w  d2,HERO_SLOT_STARTY(a2) ; spawn y (for respawn)

        ; Advance to next slot
        lea     HERO_SLOT_SIZE(a2),a2
        addq.w  #1,d3

.skip_hero:
        bra.s   .next_tile

.scan_done:
        ; Store hero count
        lea     num_heroes(pc),a2
        move.w  d3,(a2)

        ; OPT: Set level_has_hero2 flag for fast runtime checks
        lea     level_has_hero2(pc),a2
        clr.w   (a2)                    ; Default to 0
        cmpi.w  #2,d3
        blt.s   .set_hero2_flag_done
        move.w  #1,(a2)                 ; Set flag if 2+ heroes
.set_hero2_flag_done:

        ; If no heroes found, create default
        tst.w   d3
        bne.s   .has_heroes
        lea     hero_slots(pc),a2
        move.w  #5,HERO_SLOT_X(a2)
        move.w  #60,HERO_SLOT_Y(a2)
        move.w  #DIR_DOWN,HERO_SLOT_LASTD(a2)
        move.w  #1,HERO_SLOT_ACT(a2)
        move.w  #5,HERO_SLOT_STARTX(a2)   ; spawn x
        move.w  #60,HERO_SLOT_STARTY(a2)  ; spawn y
        lea     num_heroes(pc),a2
        move.w  #1,(a2)

.has_heroes:
        ; Copy first hero to working variables
        lea     hero_slots(pc),a2
        move.w  HERO_SLOT_X(a2),d1
        move.w  HERO_SLOT_Y(a2),d2

        lea     hero_x(pc),a0
        move.w  d1,(a0)
        lea     hero_y(pc),a0
        move.w  d2,(a0)

        movem.l (sp)+,d0-d5/a0-a3
        rts

; ============================================================
; switch_hero - Swap control to next hero (called on SPACE key)
; Saves current hero state, switches to next hero, loads new state
; ============================================================
switch_hero:
        movem.l d0-d2/a0-a2,-(sp)

        ; Check if level has second hero (optimized flag check)
        move.w  level_has_hero2(pc),d0
        beq     .switch_done            ; Single hero level, can't switch

        ; Check if other hero has exited (can't swap to exited hero)
        move.w  active_hero(pc),d0
        eori.w  #1,d0                   ; d0 = other hero (0->1, 1->0)
        move.w  heroes_exited(pc),d1
        btst    d0,d1                   ; Test if other hero's bit is set
        bne     .switch_done            ; Other hero exited, can't switch

        ; Save current hero state to current slot
        ; OPT: d0*18 = d0*16 + d0*2 = (d0<<4) + (d0<<1)
        move.w  active_hero(pc),d0      ; d0 = 0 or 1
        move.w  d0,d1                   ; d1 = 0 or 1
        lsl.w   #4,d0                   ; d0 = 0 or 16
        add.w   d1,d1                   ; d1 = 0 or 2
        add.w   d1,d0                   ; d0 = 0 or 18
        lea     hero_slots(pc),a0
        add.w   d0,a0                   ; a0 = current slot

        move.w  hero_x(pc),HERO_SLOT_X(a0)
        move.w  hero_y(pc),HERO_SLOT_Y(a0)
        move.w  hero_dir(pc),HERO_SLOT_DIR(a0)
        move.w  hero_last_dir(pc),HERO_SLOT_LASTD(a0)
        move.w  hero_fly(pc),HERO_SLOT_FLY(a0)
        move.w  anim_frame(pc),HERO_SLOT_ANIM(a0)

        ; Play swap sound
        movea.l sound_to_play_ptr(pc),a0
        move.w  #SFX_SWAP,(a0)
        ; Switch to next hero (toggle between 0 and 1)
        move.w  active_hero(pc),d0
        eori.w  #1,d0                   ; Toggle 0<->1
        lea     active_hero(pc),a1
        move.w  d0,(a1)

        ; Load new hero state from new slot
        ; OPT: d0*18 = d0*16 + d0*2 = (d0<<4) + (d0<<1)
        move.w  d0,d1                   ; d1 = 0 or 1
        lsl.w   #4,d0                   ; d0 = 0 or 16
        add.w   d1,d1                   ; d1 = 0 or 2
        add.w   d1,d0                   ; d0 = 0 or 18
        lea     hero_slots(pc),a0
        add.w   d0,a0                   ; a0 = new slot

        move.w  HERO_SLOT_X(a0),d1
        move.w  HERO_SLOT_Y(a0),d2
        lea     hero_x(pc),a1
        move.w  d1,(a1)
        lea     hero_y(pc),a1
        move.w  d2,(a1)
        lea     hero_dir(pc),a1
        move.w  HERO_SLOT_DIR(a0),(a1)
        lea     hero_last_dir(pc),a1
        move.w  HERO_SLOT_LASTD(a0),(a1)
        lea     hero_fly(pc),a1
        move.w  HERO_SLOT_FLY(a0),(a1)
        lea     anim_frame(pc),a1
        move.w  HERO_SLOT_ANIM(a0),(a1)

        ; Stop current movement (hero starts stationary after swap)
        lea     hero_dir(pc),a1
        clr.w   (a1)
        lea     hero_fly(pc),a1
        clr.w   (a1)

        ; Force hero redraw at new position
        lea     hero_drawn_x(pc),a1
        move.w  #-1,(a1)

.switch_done:
        movem.l (sp)+,d0-d2/a0-a2
        rts

; ============================================================
; init_scroll - Initialize pixel-based camera system
; Sets cam_focus_y and window_y based on hero position
; ============================================================
init_scroll:
        movem.l d0-d1/a0,-(sp)

        ; Initialize hero_last_y for camera tracking
        move.w  hero_y(pc),d0
        lea     hero_last_y(pc),a0
        move.w  d0,(a0)

        ; cam_focus_y = hero_y * 8 + 4 (center of hero tile)
        lsl.w   #3,d0               ; d0 = hero_y * 8
        addq.w  #4,d0               ; d0 = hero_y * 8 + 4
        lea     cam_focus_y(pc),a0
        move.w  d0,(a0)

        ; window_y = cam_focus_y - CAM_ANCHOR_PX (clamped)
        subi.w  #CAM_ANCHOR_PX,d0   ; d0 = window_y (unclamped)

        ; Clamp to valid range [0, MAX_WINDOW_Y]
        bpl.s   .check_max
        clr.w   d0                  ; Clamp to 0
        bra.s   .set_window
.check_max:
        cmpi.w  #MAX_WINDOW_Y,d0
        ble.s   .set_window
        move.w  #MAX_WINDOW_Y,d0    ; Clamp to max
.set_window:
        lea     window_y(pc),a0
        move.w  d0,(a0)

        movem.l (sp)+,d0-d1/a0
        rts

; ============================================================
; init_enemies - Scan level for enemy tiles and populate slots
; ============================================================
init_enemies:
        movem.l d0-d4/a0-a3,-(sp)

        ; Clear all enemy slots
        lea     enemy_slots(pc),a0
        moveq   #MAX_ENEMIES-1,d0
.clear_loop:
        clr.l   (a0)+               ; Clear active + x
        clr.l   (a0)+               ; Clear y + dir
        clr.l   (a0)+               ; Clear frame + delay
        dbra    d0,.clear_loop

        ; Clear enemy count and composite addresses
        lea     num_enemies(pc),a0
        clr.w   (a0)
        lea     enemy_buf_addrs(pc),a0
        clr.l   (a0)+
        clr.l   (a0)+
        clr.l   (a0)+
        clr.l   (a0)

        ; Scan level for enemy tiles
        move.l  level_data_ptr(pc),a1   ; a1 = level data
        lea     enemy_slots(pc),a2      ; a2 = next free slot
        moveq   #0,d3                   ; d3 = enemy count
        moveq   #0,d1                   ; d1 = y coordinate

.scan_rows:
        moveq   #0,d0                   ; d0 = x coordinate
.scan_cols:
        ; FIX: Clear d2 before byte read to ensure clean word value
        moveq   #0,d2
        move.b  (a1),d2                 ; d2 = tile type (now full word is clean)

        ; Check for ENEMY_RIGHT (32)
        cmpi.b  #ENEMY_RIGHT,d2
        beq.s   .found_enemy
        ; Check for ENEMY_LEFT (33)
        cmpi.b  #ENEMY_LEFT,d2
        bne.s   .next_tile

.found_enemy:
        ; Check if we have room for more enemies
        cmpi.w  #MAX_ENEMIES,d3
        bge.s   .next_tile              ; Skip if full

        ; Clear tile from level (enemy is now a sprite)
        move.b  #TILE_EMPTY,(a1)

        ; Populate enemy slot
        move.w  #1,(a2)                 ; +0: active = 1
        move.w  d0,2(a2)                ; +2: x = tile X
        move.w  d1,4(a2)                ; +4: y = tile Y
        move.w  d2,6(a2)                ; +6: dir = tile type (32 or 33)

        ; Stagger animation frame based on enemy index (like original Spectrum)
        ; Each enemy starts at a different frame (0,1,2,3) so they don't
        ; move in lockstep - creates visual offset between enemies
        move.w  d3,d4
        andi.w  #(ENEMY_ANIM_FRAMES-1),d4  ; d4 = enemy_index mod 4
        move.w  d4,8(a2)                ; +8: frame = staggered start

        move.w  #ENEMY_ANIM_DELAY,10(a2) ; +10: delay = ENEMY_ANIM_DELAY

        ; Advance to next slot
        adda.w  #ENEMY_SLOT_SIZE,a2
        addq.w  #1,d3

.next_tile:
        addq.l  #1,a1                   ; Next level byte
        addq.w  #1,d0                   ; Next X
        cmpi.w  #LEVEL_W,d0
        blt.s   .scan_cols

        ; Next row
        addq.w  #1,d1
        cmpi.w  #LEVEL_H,d1
        blt.s   .scan_rows

        ; Store enemy count
        lea     num_enemies(pc),a0
        move.w  d3,(a0)

        ; Store enemy start data for restart
        lea     num_enemies_start(pc),a0
        move.w  d3,(a0)
        tst.w   d3
        beq.s   .no_store_enemies

        ; Copy enemy positions to start data
        lea     enemy_slots(pc),a0
        lea     enemy_start_data(pc),a1
        move.w  d3,d0
        subq.w  #1,d0
.store_loop:
        move.w  2(a0),(a1)+             ; Copy x
        move.w  4(a0),(a1)+             ; Copy y
        move.w  6(a0),(a1)+             ; Copy dir
        adda.w  #ENEMY_SLOT_SIZE,a0
        dbra    d0,.store_loop

.no_store_enemies:
        movem.l (sp)+,d0-d4/a0-a3
        rts

; ============================================================
; build_cannon_list - Scan level for cannon tiles and initialize
; Called at level load. Populates cannon_list with cannon positions.
; Each cannon gets staggered timer (N*32+16) so they don't all fire together.
; ============================================================
build_cannon_list:
        movem.l d0-d5/a0-a2,-(sp)

        ; Clear cannon count
        lea     cannon_count(pc),a0
        clr.w   (a0)

        ; Clear bullet count
        lea     bullet_count(pc),a0
        clr.w   (a0)

        ; Clear all bullet slots
        lea     bullet_list(pc),a0
        moveq   #(MAX_BULLETS*BULLET_SIZE/2)-1,d0
.clear_bullets:
        clr.w   (a0)+
        dbra    d0,.clear_bullets

        ; Clear bullet composite addresses
        lea     bullet_buf_addrs(pc),a0
        clr.l   (a0)+
        clr.l   (a0)

        ; Get pointer to cannon list
        lea     cannon_list(pc),a1

        ; Scan entire level for cannon tiles
        move.l  level_data_ptr(pc),a0
        moveq   #0,d1                   ; d1 = tile index (0-767)
        moveq   #0,d3                   ; d3 = cannon count
        move.w  #LEVEL_SIZE-1,d4        ; d4 = loop counter

.cannon_scan_loop:
        move.b  (a0)+,d0                ; Get tile type
        cmpi.b  #TILE_CANNON_R,d0
        beq.s   .found_cannon_right
        cmpi.b  #TILE_CANNON_L,d0
        beq.s   .found_cannon_left
        bra.s   .cannon_next

.found_cannon_right:
        move.w  #TILE_CANNON_R,d5       ; d5 = direction
        bra.s   .add_cannon

.found_cannon_left:
        move.w  #TILE_CANNON_L,d5       ; d5 = direction

.add_cannon:
        ; Check if we have room for more cannons
        cmpi.w  #MAX_CANNONS,d3
        bge.s   .cannon_next

        ; Calculate x,y from index: y = index / 12, x = index mod 12
        moveq   #0,d2                   ; Clear high word before DIVU
        move.w  d1,d2                   ; d2 = tile index
        divu    #LEVEL_W,d2             ; d2.w = y, high word = x

        ; Fill cannon record at a1
        move.w  #1,CANNON_ACTIVE(a1)    ; Active
        swap    d2
        move.w  d2,CANNON_X(a1)         ; X (remainder)
        swap    d2
        move.w  d2,CANNON_Y(a1)         ; Y (quotient)
        move.w  d5,CANNON_DIR(a1)       ; Direction

        ; Calculate staggered timer = cannon_count * 32 + 16
        move.w  d3,d2
        lsl.w   #5,d2                   ; d2 = cannon_count * 32
        addi.w  #16,d2                  ; d2 = cannon_count * 32 + 16
        move.w  d2,CANNON_TIMER(a1)     ; Per-cannon timer

        addq.w  #1,d3                   ; Increment cannon count

        ; Advance to next cannon slot
        lea     CANNON_SIZE(a1),a1

.cannon_next:
        addq.w  #1,d1                   ; Next tile index
        dbra    d4,.cannon_scan_loop

        ; Store cannon count
        lea     cannon_count(pc),a0
        move.w  d3,(a0)

        movem.l (sp)+,d0-d5/a0-a2
        rts

; ============================================================
; do_cannons - Handle per-cannon timing and firing
; Each cannon has its own timer that increments every frame.
; Timer wraps at 256. Fire at timer 0, 1, 2 (3-bullet burst).
; ============================================================
do_cannons:
        movem.l d0-d5/a0-a1,-(sp)

        ; Check if there are any cannons
        move.w  cannon_count(pc),d0
        beq     .cannon_done

        ; Iterate through all cannons
        lea     cannon_list(pc),a1
        move.w  cannon_count(pc),d3
        subq.w  #1,d3
        blt     .cannon_done

.cannon_loop:
        ; Check if cannon is active
        tst.w   CANNON_ACTIVE(a1)
        beq     .next_cannon

        ; Increment this cannon's timer
        move.w  CANNON_TIMER(a1),d0
        addq.w  #1,d0
        andi.w  #$FF,d0                 ; Wrap at 256 (B10-matched timing)
        move.w  d0,CANNON_TIMER(a1)

        ; Check animation states
        cmpi.w  #$FF,d0
        beq.s   .open_cannon            ; Timer=255: Open mouth
        cmpi.w  #5,d0
        beq.s   .close_cannon           ; Timer=5: Close mouth

        ; Fire at timer < 3 (three bullets per cycle)
        cmpi.w  #3,d0
        blt.s   .fire_cannon            ; Timer=0,1,2: Fire bullet (3-bullet burst)

        bra     .next_cannon            ; No action this tick

.open_cannon:
        ; Draw open mouth sprite (tile - 2)
        ; TILE_CANNON_R (24) -> TILE_CANNON_OPEN_R (22)
        ; TILE_CANNON_L (25) -> TILE_CANNON_OPEN_L (23)
        move.w  CANNON_DIR(a1),d2       ; Get tile type (24 or 25)
        subq.w  #2,d2                   ; Open tile = closed tile - 2
        move.w  CANNON_X(a1),d0         ; X position
        move.w  CANNON_Y(a1),d1         ; Y position
        bsr     render_tile_to_buffer
        bra     .next_cannon

.close_cannon:
        ; Draw closed mouth sprite (normal tile)
        move.w  CANNON_DIR(a1),d2       ; Get tile type (24 or 25)
        move.w  CANNON_X(a1),d0         ; X position
        move.w  CANNON_Y(a1),d1         ; Y position
        bsr     render_tile_to_buffer
        bra     .next_cannon

.fire_cannon:
        ; Play cannon sound
        movea.l sound_to_play_ptr(pc),a0
        move.w  #SFX_CANNON,(a0)
        ; Spawn a bullet for this cannon
        move.w  CANNON_X(a1),d1         ; Bullet X (starts at cannon position)
        move.w  CANNON_Y(a1),d2         ; Bullet Y

        ; Determine delta directly (-1 or +1) instead of direction constant
        move.w  CANNON_DIR(a1),d4
        cmpi.w  #TILE_CANNON_R,d4
        bne.s   .fire_left
        addq.w  #1,d1                   ; Right cannon: bullet starts +1
        moveq   #1,d4                   ; delta = +1 (right)
        bra.s   .do_spawn

.fire_left:
        subq.w  #1,d1                   ; Left cannon: bullet starts -1
        moveq   #-1,d4                  ; delta = -1 (left)

.do_spawn:
        ; Check if spawn position is valid
        tst.w   d1
        blt.s   .next_cannon            ; Off left edge
        cmpi.w  #LEVEL_W,d1
        bge.s   .next_cannon            ; Off right edge

        bsr     spawn_bullet

.next_cannon:
        lea     CANNON_SIZE(a1),a1
        dbra    d3,.cannon_loop

.cannon_done:
        movem.l (sp)+,d0-d5/a0-a1
        rts

; ============================================================
; spawn_bullet - Add a bullet to the bullet list
; Input: d1 = X, d2 = Y, d4 = delta (-1 for left, +1 for right)
; Now stores delta directly for faster movement calculation
; ============================================================
spawn_bullet:
        movem.l d0/a0-a1,-(sp)

        ; Find an inactive bullet slot
        lea     bullet_list(pc),a1
        moveq   #MAX_BULLETS-1,d0

.find_slot:
        tst.w   BULLET_ACTIVE(a1)
        beq.s   .found_slot
        lea     BULLET_SIZE(a1),a1
        dbra    d0,.find_slot

        ; No free slots - bullet lost
        bra.s   .spawn_done

.found_slot:
        ; Initialize bullet
        move.w  #1,BULLET_ACTIVE(a1)
        move.w  d1,BULLET_X(a1)
        move.w  d2,BULLET_Y(a1)
        move.w  d4,BULLET_DIR(a1)

        ; Increment active bullet count
        lea     bullet_count(pc),a0
        addq.w  #1,(a0)

.spawn_done:
        movem.l (sp)+,d0/a0-a1
        rts

; ============================================================
; do_bullets - Move bullets every frame (50Hz)
; Bullets pass through cannons but stop at solid tiles
; ============================================================
do_bullets:
        movem.l d0-d4/a0-a1,-(sp)

        ; Check if there are any active bullets
        move.w  bullet_count(pc),d0
        beq     .bullet_done

        ; Move bullets every frame (50Hz)
        lea     bullet_list(pc),a1
        moveq   #MAX_BULLETS-1,d3

.move_bullet_loop:
        ; Check if bullet is active
        tst.w   BULLET_ACTIVE(a1)
        beq.s   .next_bullet

        ; Get current position
        move.w  BULLET_X(a1),d1
        move.w  BULLET_Y(a1),d2

        ; Move bullet using stored delta directly (no branch)
        add.w   BULLET_DIR(a1),d1       ; d1 += delta (-1 or +1)

        ; Check bounds:
        ; Check if bullet hit screen edge
        tst.w   d1
        blt.s   .deactivate_bullet
        cmpi.w  #LEVEL_W,d1
        bge.s   .deactivate_bullet

        ; Check if bullet hit a solid tile
        move.w  d1,d0
        bsr     is_solid_for_bullet
        tst.w   d0
        bne.s   .deactivate_bullet      ; Hit solid tile

.bullet_ok:
        ; Update bullet position
        move.w  d1,BULLET_X(a1)
        bra.s   .next_bullet

.deactivate_bullet:
        clr.w   BULLET_ACTIVE(a1)
        lea     bullet_count(pc),a0
        subq.w  #1,(a0)

.next_bullet:
        lea     BULLET_SIZE(a1),a1
        dbra    d3,.move_bullet_loop

.bullet_done:
        movem.l (sp)+,d0-d4/a0-a1
        rts

; ============================================================
; is_solid_for_bullet - Check if tile blocks bullet
; Input: d0 = x, d2 = y
; Output: d0 = 1 if solid (except cannons), 0 if passable
; ============================================================
is_solid_for_bullet:
        movem.l d1-d3/a0,-(sp)

        move.w  d0,d3                   ; d3 = x

        ; Calculate offset: y*12 + x using shift-add
        move.w  d2,d0                   ; d0 = y
        add.w   d0,d0                   ; d0 = y*2
        add.w   d2,d0                   ; d0 = y*3
        lsl.w   #2,d0                   ; d0 = y*12
        add.w   d3,d0                   ; d0 = y*12 + x

        ; Get tile type
        move.l  level_data_ptr(pc),a0
        moveq   #0,d1
        move.b  (a0,d0.w),d1

        ; Cannons are passable for bullets
        cmpi.b  #TILE_CANNON_R,d1
        beq.s   .passable
        cmpi.b  #TILE_CANNON_L,d1
        beq.s   .passable

        ; Check solid tiles: >= 28 means solid
        cmpi.b  #TILE_UNHIDDEN,d1
        bge.s   .solid

.passable:
        movem.l (sp)+,d1-d3/a0
        moveq   #0,d0
        rts

.solid:
        movem.l (sp)+,d1-d3/a0
        moveq   #1,d0
        rts

; ============================================================
; check_bullet_collision - Check if hero touches any bullet
; Output: d0 = 1 if collision, 0 if no collision
; ============================================================
check_bullet_collision:
        movem.l d1-d3/a0-a1,-(sp)

        ; Get hero position
        move.w  hero_x(pc),d1
        move.w  hero_y(pc),d2

        ; Check if there are any active bullets
        move.w  bullet_count(pc),d0
        beq.s   .no_collision

        ; Iterate through all bullet slots
        lea     bullet_list(pc),a1
        moveq   #MAX_BULLETS-1,d3

.check_loop:
        ; Check if bullet is active
        tst.w   BULLET_ACTIVE(a1)
        beq.s   .next_check

        ; Check X match
        cmp.w   BULLET_X(a1),d1
        bne.s   .next_check

        ; Check Y match
        cmp.w   BULLET_Y(a1),d2
        bne.s   .next_check

        ; Hero hit by bullet!
        ; Deactivate the bullet
        clr.w   BULLET_ACTIVE(a1)
        lea     bullet_count(pc),a0
        subq.w  #1,(a0)

        movem.l (sp)+,d1-d3/a0-a1
        moveq   #1,d0                   ; Return collision
        rts

.next_check:
        lea     BULLET_SIZE(a1),a1
        dbra    d3,.check_loop

.no_collision:
        movem.l (sp)+,d1-d3/a0-a1
        moveq   #0,d0                   ; No collision
        rts

; ============================================================
; process_tile_effects - Unified tile effect handler (X16)
; Input: d5 = hero_x, d6 = hero_y
; Returns: d0 = 1 if level complete (on active exit), 0 otherwise
; ============================================================
; OPTIMIZATIONS:
;   - Single tile lookup handles all tile types
;   - Sets level_complete_flag (main loop checks flag, no re-lookup)
;   - Common coin code factored to reduce code size
;   - Saves ~140 cycles per step vs X15 approach
; ============================================================
process_tile_effects:
        ; Calculate offset ONCE: y*12 + x
        move.w  d6,d0           ; d0 = y
        add.w   d0,d0           ; d0 = y*2
        add.w   d6,d0           ; d0 = y*3
        lsl.w   #2,d0           ; d0 = y*12
        add.w   d5,d0           ; d0 = y*12 + x

        ; Read tile ONCE
        move.l  level_data_ptr(pc),a0
        move.b  (a0,d0.w),d1

        ; Dispatch based on tile type (most common first)
        cmpi.b  #TILE_COIN_SM,d1
        beq.s   .coin_sm
        cmpi.b  #TILE_COIN_LG,d1
        beq.s   .coin_lg
        cmpi.b  #TILE_EXIT,d1
        beq.s   .exit

        ; Not a special tile (most common path)
        moveq   #0,d0
        rts

.coin_sm:
        ; Small coin audio DISABLED for performance test
        ; (was SFX_GOLD trigger here)
        ; Clear tile in level data (a0 still valid, d0 = offset)
        move.b  #TILE_EMPTY,(a0,d0.w)
        ; Small coin = +1 score
        lea     score(pc),a0
        addq.l  #1,(a0)
        bra.s   .coin_common

.coin_lg:
        ; Play exit sound for large coin
        move.l  a0,-(sp)
        movea.l sound_to_play_ptr(pc),a0
        move.w  #SFX_EXIT,(a0)
        move.l  (sp)+,a0
        ; Save offset and mark in cache
        move.w  d0,-(sp)
        bsr     mark_coin_collected
        move.w  (sp)+,d0
        move.l  level_data_ptr(pc),a0
        move.b  #TILE_EMPTY,(a0,d0.w)
        ; Large coin = +5 score
        lea     score(pc),a0
        addq.l  #5,(a0)
        ; Fall through to common coin code

.coin_common:
        ; Increment coin count
        lea     coin_count(pc),a0
        addq.w  #1,(a0)

        ; Decrement coins_total (for exit activation)
        lea     coins_total(pc),a0
        subq.w  #1,(a0)

        ; Update buffer with empty tile
        move.w  d5,d0
        move.w  d6,d1
        moveq   #TILE_EMPTY,d2
        bsr     render_tile_to_buffer

        moveq   #0,d0           ; Not on exit
        rts

.exit:
        ; Check if all coins collected (exit is only active then)
        move.w  coins_total(pc),d0
        bne.s   .exit_inactive

        ; Check if exit animation already playing
        move.w  hero_exit_active(pc),d0
        bne.s   .exit_anim_running

        ; Play level complete sound on exit
        movea.l sound_to_play_ptr(pc),a0
        move.w  #SFX_FIN,(a0)
        ; Start hero exit animation
        ; Store hero position for animation
        move.w  hero_x(pc),d0
        lea     hero_exit_x(pc),a0
        move.w  d0,(a0)
        move.w  hero_y(pc),d0
        lea     hero_exit_y(pc),a0
        move.w  d0,(a0)

        ; Store which hero is exiting
        move.w  active_hero(pc),d0
        lea     hero_exit_hero_id(pc),a0
        move.w  d0,(a0)

        ; Initialize animation
        lea     hero_exit_frame(pc),a0
        clr.w   (a0)
        lea     hero_exit_delay(pc),a0
        move.w  #HERO_EXIT_ANIM_SPEED,(a0)
        lea     hero_exit_active(pc),a0
        move.w  #1,(a0)

        ; Clear hero movement state to prevent trail creation
        lea     hero_dir(pc),a0
        clr.w   (a0)
        lea     hero_fly(pc),a0
        clr.w   (a0)

        ; Stop hero movement while animating
        moveq   #1,d0                   ; Return 1 (hero reached exit, stops movement)
        rts

.exit_anim_running:
        ; Animation still playing - hero stays at exit
        moveq   #1,d0
        rts

.exit_inactive:
        moveq   #0,d0           ; Exit not active yet
        rts

; ============================================================
; composite_bullets_to_buffer - Draw bullets into buffer
; Saves background first, then draws bullet sprite.
; Called after composite_enemies, before composite_hero.
; ============================================================
composite_bullets_to_buffer:
        movem.l d0-d5/a0-a3,-(sp)

        ; Check if there are any active bullets
        move.w  bullet_count(pc),d0
        beq     .comp_done

        ; Load window_y once - use d5 for scratch to preserve d4
        move.w  window_y(pc),d4         ; d4 = window_y (pixels) - preserved

        ; Pointers for save data
        lea     bullet_buf_addrs(pc),a2
        lea     bullet_buf_saves(pc),a3

        ; Iterate through all bullet slots
        lea     bullet_list(pc),a1
        moveq   #MAX_BULLETS-1,d3

.comp_loop:
        ; Check if bullet is active
        tst.w   BULLET_ACTIVE(a1)
        beq.s   .next_comp

        ; Get bullet position
        move.w  BULLET_X(a1),d0         ; Grid X
        move.w  BULLET_Y(a1),d1         ; Grid Y

        ; Convert to buffer pixel position
        ; buffer_pixel_y = bullet_y * 8
        move.w  d1,d2
        lsl.w   #3,d2                   ; d2 = bullet_y * 8 (pixels in buffer)

        ; Check visibility: is bullet_y*8 within window_y to window_y+VIEW_HEIGHT_PX?
        move.w  d2,d1
        sub.w   d4,d1                   ; d1 = screen_pixel_y
        bmi.s   .next_comp              ; Above visible area
        cmpi.w  #VIEW_HEIGHT_PX-7,d1
        bgt.s   .next_comp              ; Below visible area

        ; Calculate buffer address using d5 as scratch (preserves d4)
        ; buf_addr = playfield_buf + bullet_y * 8 * BUF_STRIDE + bullet_x * 4
        ; = playfield_buf + bullet_y * 384 + bullet_x * 4
        move.w  d2,d1                   ; d1 = bullet_y * 8
        lsl.w   #4,d1                   ; d1 = bullet_y * 128
        move.w  d2,d5
        lsl.w   #5,d5                   ; d5 = bullet_y * 256
        add.w   d5,d1                   ; d1 = bullet_y * 384
        move.w  d0,d5
        lsl.w   #2,d5                   ; d5 = bullet_x * 4
        add.w   d5,d1                   ; d1 = buffer offset

        lea     playfield_buf(pc),a0
        adda.w  d1,a0                   ; a0 = buffer address for bullet

        ; Save buffer address for restore
        move.l  a0,(a2)

        ; Offset to center rows (rows 3-4)
        lea     BUF_STRIDE*3(a0),a0

        ; Save background (2 rows × 4 bytes = 8 bytes for 1-tile width)
        move.l  (a0),(a3)+              ; Row 3
        move.l  BUF_STRIDE(a0),(a3)+    ; Row 4

        ; Draw bullet sprite (8 pixels wide = 1 tile, white)
        move.l  #$AAAAAAAA,(a0)         ; Row 3 (full tile width white)
        move.l  #$AAAAAAAA,BUF_STRIDE(a0) ; Row 4

        bra.s   .advance_comp

.next_comp:
        ; Don't clear buf_addr here - let restore handle it
        addq.l  #8,a3                   ; Skip save space (8 bytes)

.advance_comp:
        addq.l  #4,a2                   ; Next address slot
        lea     BULLET_SIZE(a1),a1
        dbra    d3,.comp_loop

.comp_done:
        movem.l (sp)+,d0-d5/a0-a3
        rts

; ============================================================
; restore_buffer_under_bullets - Restore buffer after screen copy
; Called after restore_buffer_under_hero, before restore_buffer_under_enemies.
; Unrolled for MAX_BULLETS=2 (eliminates dbra overhead)
; ============================================================
restore_buffer_under_bullets:
        movem.l d0/a0-a2,-(sp)

        ; Must check ALL slots for non-zero buf_addr from bullets
        ; that were drawn last frame but have since deactivated

        ; Pointers for save data
        lea     bullet_buf_addrs(pc),a1
        lea     bullet_buf_saves(pc),a2

        ; --- Slot 0 (unrolled) ---
        move.l  (a1)+,a0
        move.l  a0,d0
        beq.s   .slot0_skip
        clr.l   -4(a1)                  ; Clear buf_addr
        lea     BUF_STRIDE*3(a0),a0     ; Offset to center rows
        move.l  (a2)+,(a0)              ; Restore row 3
        move.l  (a2)+,BUF_STRIDE(a0)    ; Restore row 4
        bra.s   .slot1
.slot0_skip:
        addq.l  #8,a2                   ; Skip save data

        ; --- Slot 1 (unrolled) ---
.slot1:
        move.l  (a1)+,a0
        move.l  a0,d0
        beq.s   .rest_done
        clr.l   -4(a1)                  ; Clear buf_addr
        lea     BUF_STRIDE*3(a0),a0     ; Offset to center rows
        move.l  (a2)+,(a0)              ; Restore row 3
        move.l  (a2)+,BUF_STRIDE(a0)    ; Restore row 4

.rest_done:
        movem.l (sp)+,d0/a0-a2
        rts

; ============================================================
; Console I/O
; ============================================================
open_console:
        movem.l d1-d3/a0-a1,-(sp)
        lea     con_name(pc),a0
        moveq   #IO_OPEN,d0
        moveq   #-1,d1
        moveq   #0,d3
        trap    #2
        tst.l   d0
        bmi.s   .fail
        lea     con_id(pc),a1
        move.l  a0,(a1)
        moveq   #0,d0
        bra.s   .done
.fail:
        lea     con_id(pc),a1
        clr.l   (a1)
.done:
        movem.l (sp)+,d1-d3/a0-a1
        rts

close_console:
        movem.l d0-d3/a0,-(sp)
        move.l  con_id(pc),a0
        move.l  a0,d0
        beq.s   .done
        moveq   #IO_CLOSE,d0
        trap    #2
        lea     con_id(pc),a0
        clr.l   (a0)
.done:
        movem.l (sp)+,d0-d3/a0
        rts

con_name:
        dc.w    4
        dc.b    "con_"
        even
con_id: dc.l    0

; ============================================================
; clear_screen - Full 32KB screen clear (used once at program start)
; ============================================================
clear_screen:
        movem.l d0/a0,-(sp)
        lea     SCREEN_BASE,a0
        move.w  #(32768/4)-1,d0
.clear:
        clr.l   (a0)+
        dbra    d0,.clear
        movem.l (sp)+,d0/a0
        rts

; ============================================================
; clear_screen_preserve_sides - Clear screen but keep side images
; Side images occupy rows 32-223 (playfield area), left/right 30 bytes
; Clears: rows 0-31 (full), rows 32-223 (middle 68 bytes), rows 224-255 (full)
; ============================================================
BG_END_ROW      equ BG_START_ROW+VIEW_HEIGHT_PX  ; 224 (first row after images)
BG_MID_CLEAR    equ SCREEN_STRIDE-BG_BYTES_PER_ROW-BG_BYTES_PER_ROW  ; 68 bytes

clear_screen_preserve_sides:
        movem.l d0-d1/a0,-(sp)
        moveq   #0,d0

        ; Part 1: Clear rows 0 to BG_START_ROW-1 (full width)
        lea     SCREEN_BASE,a0
        move.w  #(BG_START_ROW*SCREEN_STRIDE/4)-1,d1   ; 32*128/4 - 1 = 1023
.clr_top:
        move.l  d0,(a0)+
        dbra    d1,.clr_top

        ; Part 2: Clear middle of rows BG_START_ROW to BG_END_ROW-1
        ; Skip left 30 bytes, clear 68 bytes, skip right 30 bytes
        lea     SCREEN_BASE+(BG_START_ROW*SCREEN_STRIDE)+BG_BYTES_PER_ROW,a0
        move.w  #VIEW_HEIGHT_PX-1,d1                    ; 191
.clr_mid_row:
        ; Clear 68 bytes = 17 longwords
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        ; 17 * 4 = 68 bytes
        ; Skip right image (30 bytes) + left image of next row (30 bytes) = 60 bytes
        adda.w  #BG_BYTES_PER_ROW+BG_BYTES_PER_ROW,a0  ; Skip to next row middle
        dbra    d1,.clr_mid_row

        ; Part 3: Clear rows BG_END_ROW to 255 (full width)
        lea     SCREEN_BASE+(BG_END_ROW*SCREEN_STRIDE),a0
        move.w  #((256-BG_END_ROW)*SCREEN_STRIDE/4)-1,d1  ; 32*128/4 - 1 = 1023
.clr_bot:
        move.l  d0,(a0)+
        dbra    d1,.clr_bot

        movem.l (sp)+,d0-d1/a0
        rts

; ============================================================
; black_playfield - Clear playfield + columns to black
; Clears 56 bytes/row (left col + playfield + right col) x 192 rows
; Used for level transition flash
; ============================================================
PLAY_CLEAR_ADDR equ COL_LEFT_ADDR      ; Start at left column

black_playfield:
        movem.l d0-d1/a0,-(sp)
        lea     PLAY_CLEAR_ADDR,a0
        moveq   #0,d0
        move.w  #VIEW_HEIGHT_PX-1,d1    ; 191
.bp_row:
        ; Clear 56 bytes = 14 longwords (left col + playfield + right col)
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        move.l  d0,(a0)+
        ; Advance to next row: stride (128) - 56 bytes written = 72
        adda.w  #SCREEN_STRIDE-(14*4),a0
        dbra    d1,.bp_row
        movem.l (sp)+,d0-d1/a0
        rts

; ============================================================
; draw_border function removed

; ============================================================
; render_tile_to_buffer - Render single tile to off-screen buffer
; Input: d0 = tile_x (0-11), d1 = tile_y (0-63), d2 = tile_type
; ============================================================
render_tile_to_buffer:
        movem.l d0-d3/a0-a1,-(sp)

        ; Calculate buffer address: buf + tile_y * 384 + tile_x * 4
        ; tile_y * 384 = tile_y * 256 + tile_y * 128
        move.w  d1,d3
        lsl.w   #8,d3           ; d3 = tile_y * 256
        lsl.w   #7,d1           ; d1 = tile_y * 128
        add.w   d1,d3           ; d3 = tile_y * 384
        lsl.w   #2,d0           ; d0 = tile_x * 4
        add.w   d0,d3           ; d3 = buffer offset

        lea     playfield_buf(pc),a0
        adda.w  d3,a0           ; a0 = buffer destination

        ; Get expanded tile address
        andi.w  #$1F,d2         ; Clamp to 0-31
        lsl.w   #5,d2           ; d2 = tile_type * 32
        lea     expanded_tiles(pc),a1
        adda.w  d2,a1           ; a1 = expanded tile source

        ; Copy 8 rows to buffer (BUF_STRIDE = 48 bytes between rows)
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)

        movem.l (sp)+,d0-d3/a0-a1
        rts

; ============================================================
; render_playfield_to_buffer - Render entire level to buffer
; Called once when level loads
; ============================================================
render_playfield_to_buffer:
        movem.l d0-d5/a0-a3,-(sp)

        move.l  level_data_ptr(pc),a2   ; a2 = level data
        lea     expanded_tiles(pc),a3   ; a3 = expanded tiles base
        lea     playfield_buf(pc),a0    ; a0 = buffer start

        moveq   #0,d4                   ; d4 = tile_y counter

.row_loop:
        moveq   #LEVEL_W-1,d5           ; d5 = tile_x counter
        move.l  a0,a1                   ; a1 = row start in buffer

.col_loop:
        ; Get tile type from level data
        moveq   #0,d0
        move.b  (a2)+,d0

        ; Clamp to valid tile range
        cmpi.w  #NUM_TILES,d0
        blo.s   .tile_ok
        moveq   #0,d0
.tile_ok:
        ; Get expanded tile address
        move.w  d0,d1
        lsl.w   #5,d1           ; d1 = tile_type * 32
        lea     (a3),a1
        adda.w  d1,a1           ; a1 = expanded tile source

        ; Get buffer destination for this tile
        move.l  a0,-(sp)        ; Save buffer row ptr

        ; Copy 8 rows of tile to buffer
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #BUF_STRIDE,a0
        move.l  (a1)+,(a0)

        move.l  (sp)+,a0        ; Restore buffer row ptr
        addq.l  #4,a0           ; Next tile column in buffer

        dbra    d5,.col_loop

        ; Move to next tile row in buffer
        ; Already at correct position since we moved by 12*4=48 bytes
        ; But we need to skip 7 more scanlines (already did row 0)
        ; Total per tile row = 8 * 48 = 384 bytes
        ; We've moved 48 bytes, need 384-48 = 336 more
        adda.w  #BUF_STRIDE*7,a0

        addq.w  #1,d4
        cmpi.w  #LEVEL_H,d4
        blt     .row_loop

        movem.l (sp)+,d0-d5/a0-a3
        rts

; ============================================================
; copy_window_to_screen - Copy visible slice from buffer to screen
; Uses window_y (pixels) to determine which part to copy
; Copies 192 scanlines (VIEW_HEIGHT_PX) from buffer to screen
; 11 regs (d0-d6/a2-a5) = 44 bytes + move.l 4 bytes = 48 bytes
; A6 preserved for QDOS system variables (required by IPC beeper)
; ============================================================
copy_window_to_screen:
        movem.l d0-d7/a0-a5,-(sp)       ; A6 not used in blit

        ; Get window_y and clamp to valid range
        move.w  window_y(pc),d0
        bpl.s   .cam_not_neg
        clr.w   d0                  ; Clamp to 0 if negative
.cam_not_neg:
        cmpi.w  #MAX_WINDOW_Y,d0
        ble.s   .cam_ok
        move.w  #MAX_WINDOW_Y,d0    ; Clamp to max
.cam_ok:
        ; Calculate source address: buf + window_y * BUF_STRIDE
        ; d0 * 48 = d0 * 32 + d0 * 16 (faster than mulu)
        move.w  d0,d1
        lsl.w   #5,d0               ; d0 = window_y * 32
        lsl.w   #4,d1               ; d1 = window_y * 16
        add.w   d1,d0               ; d0 = window_y * 48
        lea     playfield_buf(pc),a0
        adda.w  d0,a0               ; a0 = source in buffer

        ; Destination: screen playfield area
        lea     PLAYFIELD_BASE,a1

        ; 8x unrolled loop (192/8 = 24 iterations)
        ; 11 regs (d0-d6/a2-a5) = 44 bytes + move.l 4 bytes = 48 bytes/line
        moveq   #23,d7              ; 24 iterations of 8 lines each

.copy_8lines:
        ; Line 0 (48 bytes via 11-reg movem + move.l)
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        ; Line 1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        ; Line 2
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        ; Line 3
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        ; Line 4
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        ; Line 5
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        ; Line 6
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        ; Line 7
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1

        dbra    d7,.copy_8lines

        movem.l (sp)+,d0-d7/a0-a5       ; Restore (A6 untouched)
        rts

; ============================================================
; copy_window_to_screen_title - Title screen version
; Skips playfield rows 40-71 (logo area at screen rows 72-103)
; Main game uses copy_window_to_screen (no overhead)
; 11-reg blit (A6 preserved for QDOS)
; ============================================================
copy_window_to_screen_title:
        movem.l d0-d7/a0-a5,-(sp)       ; A6 not used in blit

        ; Get window_y and clamp
        move.w  window_y(pc),d0
        bpl.s   .tcam_not_neg
        clr.w   d0
.tcam_not_neg:
        cmpi.w  #MAX_WINDOW_Y,d0
        ble.s   .tcam_ok
        move.w  #MAX_WINDOW_Y,d0
.tcam_ok:
        ; Calculate source: buf + window_y * 48
        move.w  d0,d1
        lsl.w   #5,d0
        lsl.w   #4,d1
        add.w   d1,d0
        lea     playfield_buf(pc),a0
        adda.w  d0,a0

        lea     PLAYFIELD_BASE,a1

        ; --- Part 1: Copy playfield rows 0-39 (5 iterations of 8 lines) ---
        ; These appear at screen rows 32-71 (above logo)
        moveq   #4,d7
.copy_part1:
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        dbra    d7,.copy_part1

        ; --- Skip logo area: advance pointers by 32 rows ---
        ; Source: 32 rows * 48 bytes = 1536 bytes
        ; Dest: 32 rows * 128 bytes = 4096 bytes
        adda.w  #32*BUF_STRIDE,a0
        adda.w  #32*SCREEN_STRIDE,a1

        ; --- Part 2: Copy playfield rows 72-191 (15 iterations of 8 lines) ---
        ; These appear at screen rows 104-223 (below logo)
        moveq   #14,d7
.copy_part2:
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        dbra    d7,.copy_part2

        movem.l (sp)+,d0-d7/a0-a5       ; Restore (A6 untouched)
        rts

; ============================================================
; cycle_logo_colors - Rotate logo color table for rainbow effect
; Called each frame during title screen only
; Rotates the 16-entry color table by 1 position
; ============================================================
cycle_logo_colors:
        movem.l d0-d1/a0,-(sp)

        lea     logo_colors(pc),a0

        ; Save first color
        move.w  (a0),d0

        ; Shift all colors up by one position (15 moves)
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+
        move.w  2(a0),(a0)+

        ; Put saved color at end
        move.w  d0,(a0)

        movem.l (sp)+,d0-d1/a0
        rts

; ============================================================
; Outro Screen (game complete) - within playfield
; Text drawn to buffer, vertical bounce, scrolling columns kept
; ============================================================

; ============================================================
; init_outro - Prepare outro screen in playfield buffer
; Called after completing level 20
; ============================================================
init_outro:
        ; Set game state
        lea     game_state(pc),a0
        move.w  #GS_OUTRO,(a0)

        ; Start outro music
        lea     start(pc),a0
        adda.l  #music_to_play,a0
        move.w  #MUSIC_OUTRO,(a0)

        ; Clear entire playfield buffer
        lea     playfield_buf(pc),a0
        move.l  a0,a2                   ; a2 = buffer base (preserved for text)
        move.w  #(BUF_SIZE/4)-1,d0
        moveq   #0,d1
.clr_buf:
        move.l  d1,(a0)+
        dbra    d0,.clr_buf

        ; Draw credits text into playfield buffer (bounces)
        ; a2 = playfield_buf base, all text left-aligned at offset 4
        ; (1 character space from left column)

        ; Row 16: "KUDOS"
        lea     outro_str_kudos(pc),a0
        lea     16*8*BUF_STRIDE+4(a2),a1
        bsr     draw_string_to_buf

        ; Row 17: "GAMEMASTER!"
        lea     outro_str_gmaster(pc),a0
        lea     17*8*BUF_STRIDE+4(a2),a1
        bsr     draw_string_to_buf

        ; Row 24: "QL PORT :"
        lea     outro_str_qlport(pc),a0
        lea     24*8*BUF_STRIDE+4(a2),a1
        bsr     draw_string_to_buf

        ; Row 25: "J MCKAY"
        lea     outro_str_jmckay(pc),a0
        lea     25*8*BUF_STRIDE+4(a2),a1
        bsr     draw_string_to_buf

        ; Row 28: "ZX GAME :"
        lea     outro_str_zxgame(pc),a0
        lea     28*8*BUF_STRIDE+4(a2),a1
        bsr     draw_string_to_buf

        ; Row 29: "D GRACHEV"
        lea     outro_str_coder(pc),a0
        lea     29*8*BUF_STRIDE+4(a2),a1
        bsr     draw_string_to_buf

        ; Row 31: "O NIKITIN"
        lea     outro_str_musician(pc),a0
        lea     31*8*BUF_STRIDE+4(a2),a1
        bsr     draw_string_to_buf

        ; Row 33: "I SELEZNEV"
        lea     outro_str_artist(pc),a0
        lea     33*8*BUF_STRIDE+4(a2),a1
        bsr     draw_string_to_buf

        ; Initialize bounce animation
        lea     outro_bounce_idx(pc),a0
        clr.w   (a0)
        lea     outro_bounce_frame(pc),a0
        clr.w   (a0)

        ; Set initial window_y from bounce table
        lea     outro_bounce_table(pc),a0
        move.w  (a0),d0
        lea     window_y(pc),a0
        move.w  d0,(a0)

        ; Initial screen update (playfield + columns)
        bsr     copy_window_to_screen
        bsr     draw_scrolling_columns

        ; Preserve lives and score HUD - don't clear top status area
        ; Draw "WELL  DONE" centered, aligned with lives row (row 3)
        lea     outro_str_welldone(pc),a0
        lea     SCREEN_BASE+(3*SCREEN_STRIDE)+44,a1
        bsr     draw_string

        ; Convert WELL DONE from white to yellow
        ; AND $FFAA strips blue channel bits: white ($AAFF) -> yellow ($AAAA)
        lea     SCREEN_BASE+(3*SCREEN_STRIDE)+44,a1
        move.l  #$FFAAFFAA,d0
        moveq   #7,d1                   ; 8 rows
.yellow_row:
        and.l   d0,(a1)
        and.l   d0,4(a1)
        and.l   d0,8(a1)
        and.l   d0,12(a1)
        and.l   d0,16(a1)
        and.l   d0,20(a1)
        and.l   d0,24(a1)
        and.l   d0,28(a1)
        and.l   d0,32(a1)
        and.l   d0,36(a1)
        adda.w  #SCREEN_STRIDE,a1
        dbra    d1,.yellow_row

        ; Clear bottom status area (row 29) - flash routine will draw text
        lea     SCREEN_BASE+(29*8*SCREEN_STRIDE),a1
        moveq   #0,d0
        move.w  #(128*8/4)-1,d1         ; 256 longwords
.clr_bot:
        move.l  d0,(a1)+
        dbra    d1,.clr_bot

        ; Side images persist - no redraw needed

        ; Initialize flash counter for "THANKS FOR PLAYING"
        lea     title_flash_ctr(pc),a0
        move.w  #TITLE_FLASH_RATE,(a0)
        lea     title_text_visible(pc),a0
        move.w  #1,(a0)

        ; Initialize outro delay counter (match Spectrum: ~255 frames)
        lea     outro_count(pc),a0
        move.w  #255,(a0)

        bsr     flush_keyboard
        ; Fall through to outro_loop

; ============================================================
; outro_loop - Outro animation loop with bounce and flash
; ============================================================
outro_loop:
        bsr     wait_vsync
        movea.l sfx_update_ptr(pc),a6  ; update sound
        jsr     (a6)

        ; Update bounce animation
        bsr     update_outro_bounce

        ; Draw thanks text before playfield copy to push the heavy
        ; copy later, giving the CRT beam more head start
        ; Columns are static (drawn once in init_outro), not redrawn
        bsr     draw_outro_thanks

        ; Copy buffer to screen (reduced: skips blank top/bottom rows)
        bsr     copy_outro_to_screen

        ; Decrement outro delay counter
        lea     outro_count(pc),a0
        move.w  (a0),d0
        beq.s   .outro_check_key
        subq.w  #1,d0
        move.w  d0,(a0)
        bra     outro_loop

.outro_check_key:
        ; Check keyboard (SPACE/ENTER -> title, ESC -> title)
        bsr     check_title_key
        tst.w   d0
        bne.s   .outro_done

        ; ESC also returns to title (same as SPACE)
        move.w  quit_flag(pc),d0
        bne.s   .outro_done

        bra     outro_loop

.outro_done:
        ; Return to title screen
        bsr     init_title_screen
        bra     title_loop

; ============================================================
; update_outro_bounce - Update window_y from bounce table
; 8-entry table, advances every frame (8 frames per full cycle)
; ============================================================
update_outro_bounce:
        movem.l d0-d1/a0,-(sp)

        ; Advance bounce index every frame
        lea     outro_bounce_idx(pc),a0
        move.w  (a0),d1
        addq.w  #1,d1
        andi.w  #7,d1                   ; Wrap 0-7
        move.w  d1,(a0)

        ; Get new window_y from table
        lea     outro_bounce_table(pc),a0
        add.w   d1,d1                   ; Word offset
        move.w  (a0,d1.w),d1
        lea     window_y(pc),a0
        move.w  d1,(a0)

        movem.l (sp)+,d0-d1/a0
        rts

; Outro bounce table (8 entries, 3-pixel oscillation)
; Credits at buffer rows 16-33, centered at window_y ~104
outro_bounce_table:
        dc.w    105,104,103,102,102,103,104,105

; ============================================================
; copy_outro_to_screen - Reduced copy for outro (skip blank edges)
; Copies 160 lines (rows 16-175 of playfield) instead of all 192.
; Top 16 and bottom 16 lines are always blank during outro and
; were cleared in init_outro, so they never need updating.
; This reduces screen writes by ~17%, helping reduce CRT tearing.
; ============================================================
OUTRO_SKIP_LINES equ 16
copy_outro_to_screen:
        movem.l d0-d7/a0-a5,-(sp)

        ; Get window_y and clamp
        move.w  window_y(pc),d0
        bpl.s   .cam_not_neg
        clr.w   d0
.cam_not_neg:
        cmpi.w  #MAX_WINDOW_Y,d0
        ble.s   .cam_ok
        move.w  #MAX_WINDOW_Y,d0
.cam_ok:
        ; Source: buf + (window_y + OUTRO_SKIP_LINES) * BUF_STRIDE
        add.w   #OUTRO_SKIP_LINES,d0
        move.w  d0,d1
        lsl.w   #5,d0               ; d0 = offset * 32
        lsl.w   #4,d1               ; d1 = offset * 16
        add.w   d1,d0               ; d0 = offset * 48
        lea     playfield_buf(pc),a0
        adda.w  d0,a0               ; a0 = source in buffer

        ; Dest: playfield + skip lines
        lea     PLAYFIELD_BASE+(OUTRO_SKIP_LINES*SCREEN_STRIDE),a1

        ; Copy 160 lines (20 groups of 8)
        moveq   #19,d7              ; 20 iterations

.copy_8lines:
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1
        movem.l (a0)+,d0-d6/a2-a5
        movem.l d0-d6/a2-a5,(a1)
        move.l  (a0)+,44(a1)
        adda.w  #SCREEN_STRIDE,a1

        dbra    d7,.copy_8lines

        movem.l (sp)+,d0-d7/a0-a5
        rts

; ============================================================
; draw_outro_thanks - Flash "THANKS FOR PLAYING" at bottom of screen
; Same mechanism as title screen PUSH FIRE flash
; ============================================================
draw_outro_thanks:
        movem.l d0-d1/a0-a1,-(sp)

        ; Update flash counter
        lea     title_flash_ctr(pc),a0
        move.w  (a0),d0
        subq.w  #1,d0
        bne.s   .otf_store

        ; Toggle visibility
        lea     title_text_visible(pc),a1
        eori.w  #1,(a1)
        move.w  #TITLE_FLASH_RATE,d0

.otf_store:
        move.w  d0,(a0)

        ; Check if visible
        move.w  title_text_visible(pc),d0
        beq.s   .otf_clear

        ; Draw "THANKS FOR PLAYING" centered at screen row 29
        ; 18 chars = 72 bytes, centered in 128: offset 28
        lea     outro_str_thanks1(pc),a0
        lea     SCREEN_BASE+(29*8*SCREEN_STRIDE)+28,a1
        bsr     draw_string
        addq.l  #4,a1                   ; Space between FOR and PLAYING
        lea     outro_str_thanks2(pc),a0
        bsr     draw_string
        bra.s   .otf_done

.otf_clear:
        ; Clear 18 chars × 8 rows (72 bytes per row)
        lea     SCREEN_BASE+(29*8*SCREEN_STRIDE)+28,a1
        moveq   #0,d0
        moveq   #7,d1
.otf_clr_row:
        move.l  d0,(a1)
        move.l  d0,4(a1)
        move.l  d0,8(a1)
        move.l  d0,12(a1)
        move.l  d0,16(a1)
        move.l  d0,20(a1)
        move.l  d0,24(a1)
        move.l  d0,28(a1)
        move.l  d0,32(a1)
        move.l  d0,36(a1)
        move.l  d0,40(a1)
        move.l  d0,44(a1)
        move.l  d0,48(a1)
        move.l  d0,52(a1)
        move.l  d0,56(a1)
        move.l  d0,60(a1)
        move.l  d0,64(a1)
        move.l  d0,68(a1)
        adda.w  #SCREEN_STRIDE,a1
        dbra    d1,.otf_clr_row

.otf_done:
        movem.l (sp)+,d0-d1/a0-a1
        rts

; ============================================================
; draw_bullets_to_screen - Draw bullets directly to screen
; Called AFTER copy_window_to_screen. No save/restore needed since
; buffer is never modified - fresh copy each frame overwrites old bullets.
; Much simpler than composite_bullets_to_buffer: just calc screen addr and draw.
; ============================================================
draw_bullets_to_screen:
        move.w  bullet_count(pc),d0
        beq     .done                   ; No bullets, exit early

        movem.l d0-d4/a0-a1,-(sp)

        move.w  window_y(pc),d4         ; d4 = window_y (preserved)
        lea     bullet_list(pc),a0

        ; Unrolled for MAX_BULLETS=2
        ; --- Slot 0 ---
        tst.w   BULLET_ACTIVE(a0)
        beq.s   .slot1

        ; Get position and check visibility
        move.w  BULLET_Y(a0),d1         ; d1 = tile Y
        lsl.w   #3,d1                   ; d1 = pixel Y in buffer
        move.w  d1,d2
        sub.w   d4,d2                   ; d2 = screen_pixel_y
        bmi.s   .slot1                  ; Above screen
        cmpi.w  #VIEW_HEIGHT_PX-7,d2
        bgt.s   .slot1                  ; Below screen

        ; Calculate screen address directly
        ; screen_addr = PLAYFIELD_BASE + screen_y * SCREEN_STRIDE + bullet_x * 4
        move.w  d2,d0
        lsl.w   #7,d0                   ; d0 = screen_y * 128
        move.w  BULLET_X(a0),d1
        lsl.w   #2,d1                   ; d1 = bullet_x * 4
        add.w   d1,d0
        lea     PLAYFIELD_BASE,a1
        adda.w  d0,a1

        ; Draw bullet at center rows (offset by 3 scanlines)
        lea     SCREEN_STRIDE*3(a1),a1
        move.l  #$AAAAAAAA,(a1)         ; Row 3 (white)
        move.l  #$AAAAAAAA,SCREEN_STRIDE(a1) ; Row 4

.slot1:
        ; --- Slot 1 ---
        lea     BULLET_SIZE(a0),a0
        tst.w   BULLET_ACTIVE(a0)
        beq.s   .done_pop

        move.w  BULLET_Y(a0),d1
        lsl.w   #3,d1
        move.w  d1,d2
        sub.w   d4,d2
        bmi.s   .done_pop
        cmpi.w  #VIEW_HEIGHT_PX-7,d2
        bgt.s   .done_pop

        move.w  d2,d0
        lsl.w   #7,d0
        move.w  BULLET_X(a0),d1
        lsl.w   #2,d1
        add.w   d1,d0
        lea     PLAYFIELD_BASE,a1
        adda.w  d0,a1

        lea     SCREEN_STRIDE*3(a1),a1
        move.l  #$AAAAAAAA,(a1)
        move.l  #$AAAAAAAA,SCREEN_STRIDE(a1)

.done_pop:
        movem.l (sp)+,d0-d4/a0-a1
.done:
        rts

; ============================================================
; draw_enemies_to_screen - Draw all enemies directly to screen
; No buffer save/restore - clean buffer copy each frame erases old positions
; ============================================================
draw_enemies_to_screen:
        move.w  num_enemies(pc),d0
        beq     .ene_done

        movem.l d0-d7/a0-a2,-(sp)

        move.w  window_y(pc),d6         ; d6 = window_y (preserved)
        lea     enemy_slots(pc),a1
        moveq   #MAX_ENEMIES-1,d5

.ene_loop:
        tst.w   (a1)                    ; Check active
        beq     .ene_next

        ; Get position
        move.w  2(a1),d0                ; d0 = tile X
        move.w  4(a1),d1                ; d1 = tile Y

        ; Check visibility
        move.w  d1,d2
        lsl.w   #3,d2                   ; d2 = tile_y * 8
        sub.w   d6,d2                   ; d2 = screen_pixel_y
        bmi     .ene_next               ; Above visible
        cmpi.w  #VIEW_HEIGHT_PX-7,d2
        bgt     .ene_next               ; Below visible

        ; Calculate screen address
        ; screen_addr = PLAYFIELD_BASE + screen_y * 128 + tile_x * 4
        move.w  d2,d3
        lsl.w   #7,d3                   ; d3 = screen_y * 128
        move.w  d0,d4
        lsl.w   #2,d4                   ; d4 = tile_x * 4
        add.w   d4,d3
        lea     PLAYFIELD_BASE,a0
        adda.w  d3,a0                   ; a0 = screen address

        ; Get sprite address
        bsr     get_enemy_sprite        ; Returns a4 = sprite address

        ; Draw enemy (8 rows × 8 bytes = 2 tiles wide)
        ; Use SCREEN_STRIDE (128) between rows
        movem.l (a4)+,d0-d1             ; 8 bytes
        move.l  d0,(a0)
        move.l  d1,4(a0)
        movem.l (a4)+,d0-d1
        move.l  d0,SCREEN_STRIDE(a0)
        move.l  d1,SCREEN_STRIDE+4(a0)
        movem.l (a4)+,d0-d1
        move.l  d0,SCREEN_STRIDE*2(a0)
        move.l  d1,SCREEN_STRIDE*2+4(a0)
        movem.l (a4)+,d0-d1
        move.l  d0,SCREEN_STRIDE*3(a0)
        move.l  d1,SCREEN_STRIDE*3+4(a0)
        movem.l (a4)+,d0-d1
        move.l  d0,SCREEN_STRIDE*4(a0)
        move.l  d1,SCREEN_STRIDE*4+4(a0)
        movem.l (a4)+,d0-d1
        move.l  d0,SCREEN_STRIDE*5(a0)
        move.l  d1,SCREEN_STRIDE*5+4(a0)
        movem.l (a4)+,d0-d1
        move.l  d0,SCREEN_STRIDE*6(a0)
        move.l  d1,SCREEN_STRIDE*6+4(a0)
        movem.l (a4)+,d0-d1
        move.l  d0,SCREEN_STRIDE*7(a0)
        move.l  d1,SCREEN_STRIDE*7+4(a0)

.ene_next:
        adda.w  #ENEMY_SLOT_SIZE,a1
        dbra    d5,.ene_loop

        movem.l (sp)+,d0-d7/a0-a2
.ene_done:
        rts

; ============================================================
; draw_hero2_to_screen - Draw inactive hero directly to screen
; Uses green mask to distinguish from active hero
; ============================================================
draw_hero2_to_screen:
        move.w  level_has_hero2(pc),d0
        beq     .h2s_done               ; Single hero level

        ; Check if inactive hero has exited
        move.w  active_hero(pc),d0
        eori.w  #1,d0                   ; d0 = inactive hero index
        move.w  heroes_exited(pc),d1
        btst    d0,d1
        bne     .h2s_done               ; Inactive hero exited

        movem.l d0-d3/a0-a2,-(sp)

        ; Get inactive hero slot
        move.w  d0,d1
        lsl.w   #4,d0                   ; d0 = 0 or 16
        add.w   d1,d1                   ; d1 = 0 or 2
        add.w   d1,d0                   ; d0 = 0 or 18
        lea     hero_slots(pc),a1
        add.w   d0,a1

        ; Check if active
        tst.w   HERO_SLOT_ACT(a1)
        beq     .h2s_exit

        ; Get position and check visibility
        move.w  HERO_SLOT_Y(a1),d0
        lsl.w   #3,d0                   ; d0 = y * 8
        sub.w   window_y(pc),d0         ; d0 = screen_y
        bmi     .h2s_exit
        cmpi.w  #VIEW_HEIGHT_PX-7,d0
        bgt     .h2s_exit

        ; Calculate screen address
        move.w  d0,d2                   ; d2 = screen_y
        lsl.w   #7,d2                   ; d2 = screen_y * 128
        move.w  HERO_SLOT_X(a1),d1
        lsl.w   #2,d1                   ; d1 = x * 4
        add.w   d1,d2
        lea     PLAYFIELD_BASE,a0
        adda.w  d2,a0

        ; Get sprite
        move.w  HERO_SLOT_LASTD(a1),d0
        move.w  HERO_SLOT_ANIM(a1),d1
        move.w  HERO_SLOT_FLY(a1),d2
        bsr     get_hero_sprite_for_dir ; a2 = sprite

        ; Draw with green mask ($FF00FF00)
        move.l  #$FF00FF00,d3
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,SCREEN_STRIDE(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,SCREEN_STRIDE*2(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,SCREEN_STRIDE*3(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,SCREEN_STRIDE*4(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,SCREEN_STRIDE*5(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,SCREEN_STRIDE*6(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,SCREEN_STRIDE*7(a0)

.h2s_exit:
        movem.l (sp)+,d0-d3/a0-a2
.h2s_done:
        rts

; ============================================================
; draw_hero_to_screen - Draw active hero directly to screen
; ============================================================
draw_hero_to_screen:
        movem.l d0-d2/a0-a2,-(sp)

        ; Check visibility
        move.w  hero_y(pc),d0
        lsl.w   #3,d0                   ; d0 = hero_y * 8
        sub.w   window_y(pc),d0         ; d0 = screen_y
        bmi     .hs_done
        cmpi.w  #VIEW_HEIGHT_PX-7,d0
        bgt     .hs_done

        ; Calculate screen address
        move.w  d0,d1                   ; d1 = screen_y
        lsl.w   #7,d1                   ; d1 = screen_y * 128
        move.w  hero_x(pc),d2
        lsl.w   #2,d2                   ; d2 = x * 4
        add.w   d2,d1
        lea     PLAYFIELD_BASE,a0
        adda.w  d1,a0

        ; Get sprite
        bsr     get_hero_sprite         ; a2 = sprite

        ; Draw 8 rows
        move.l  (a2)+,(a0)
        move.l  (a2)+,SCREEN_STRIDE(a0)
        move.l  (a2)+,SCREEN_STRIDE*2(a0)
        move.l  (a2)+,SCREEN_STRIDE*3(a0)
        move.l  (a2)+,SCREEN_STRIDE*4(a0)
        move.l  (a2)+,SCREEN_STRIDE*5(a0)
        move.l  (a2)+,SCREEN_STRIDE*6(a0)
        move.l  (a2)+,SCREEN_STRIDE*7(a0)

.hs_done:
        movem.l (sp)+,d0-d2/a0-a2
        rts

; ============================================================
; draw_side_images - Draw static border graphics from pl1.png
; Left image at screen left edge, right side mirrored at runtime
; 60x133 pixels = 30 bytes/row, tiled vertically across 192-row playfield
; First tile: 133 rows, second tile: 59 rows (cut at playfield bottom)
; Mirror: reverse word order per row, reverse 4 pixels within each word
; ============================================================
BG_BYTES_PER_ROW equ 30
BG_WORDS_PER_ROW equ 15
BG_HEIGHT        equ 133
BG_TILE2_ROWS    equ VIEW_HEIGHT_PX-BG_HEIGHT  ; 192-133 = 59
BG_RIGHT_OFFSET  equ SCREEN_STRIDE-BG_BYTES_PER_ROW  ; 98
BG_START_ROW     equ PLAY_Y*TILE_HEIGHT              ; 32

draw_side_images:
        movem.l d0-d7/a0-a5,-(sp)

        ; Image data is beyond PC-relative range (after 24KB playfield_buf).
        ; Use PC trick: get our own address, then add 32-bit offset.
        pea     .pc_ref(pc)
        move.l  (sp)+,a2                ; a2 = runtime address of .pc_ref
.pc_ref:

        ; === LEFT SIDE ===
        ; First tile: full 133 rows at playfield top
        move.l  a2,a0
        adda.l  #bg1_left-.pc_ref,a0
        move.l  a0,a3                   ; a3 = source start (for second tile)
        lea     SCREEN_BASE+(BG_START_ROW*SCREEN_STRIDE),a1
        move.w  #BG_HEIGHT-1,d0
.left1:
        movem.l (a0)+,d1-d7        ; 28 bytes (7 longwords)
        movem.l d1-d7,(a1)
        move.w  (a0)+,28(a1)       ; last 2 bytes
        adda.w  #SCREEN_STRIDE,a1
        dbra    d0,.left1

        ; Second tile: 59 rows from image start
        move.l  a3,a0                   ; Reset source to start of image
        move.w  #BG_TILE2_ROWS-1,d0
.left2:
        movem.l (a0)+,d1-d7
        movem.l d1-d7,(a1)
        move.w  (a0)+,28(a1)
        adda.w  #SCREEN_STRIDE,a1
        dbra    d0,.left2

        ; === RIGHT SIDE (mirrored from left at runtime) ===
        ; a4 = mirror lookup table
        move.l  a2,a4
        adda.l  #mirror_lut-.pc_ref,a4

        ; a0 = start of bg1_left (source), a3 already = source start
        move.l  a3,a0
        lea     SCREEN_BASE+(BG_START_ROW*SCREEN_STRIDE)+BG_RIGHT_OFFSET,a1
        move.w  #BG_HEIGHT-1,d0
.right1:
        bsr.s   .mirror_row
        dbra    d0,.right1

        ; Second tile: 59 rows from image start
        move.l  a3,a0
        move.w  #BG_TILE2_ROWS-1,d0
.right2:
        bsr.s   .mirror_row
        dbra    d0,.right2

        movem.l (sp)+,d0-d7/a0-a5
        rts

; .mirror_row - Mirror one 30-byte row from (a0) to (a1)
; Reads 15 words from end of source row backwards, reverses pixels
; within each word via lookup table, writes forwards to dest.
; Advances a0 past source row, advances a1 by SCREEN_STRIDE.
; Uses: d1-d3, a0, a1, a4 (mirror_lut), a5 (temp source ptr)
.mirror_row:
        lea     BG_BYTES_PER_ROW-2(a0),a5  ; a5 = last word of source row
        moveq   #BG_WORDS_PER_ROW-1,d1
.mr_word:
        moveq   #0,d2
        moveq   #0,d3
        move.w  (a5),d2             ; read source word
        ; Mirror low byte (byte1: R/B bits)
        move.b  d2,d3               ; d3.w = original low byte (0-255)
        move.b  0(a4,d3.w),d2       ; replace low byte with mirrored
        ; Mirror high byte (byte0: G/F bits)
        rol.w   #8,d2               ; swap: mirrored-low now in high, orig-high in low
        move.b  d2,d3               ; d3.w = original high byte (0-255)
        move.b  0(a4,d3.w),d2       ; replace with mirrored high byte (now in low pos)
        rol.w   #8,d2               ; swap back: mirrored-high in high, mirrored-low in low
        move.w  d2,(a1)+            ; write mirrored word to dest
        subq.l  #2,a5               ; move source backwards
        dbra    d1,.mr_word

        ; Advance a0 past this row to start of next row
        lea     BG_BYTES_PER_ROW(a0),a0
        ; Advance a1 to next screen row (a1 already advanced by 30 from writes)
        lea     SCREEN_STRIDE-BG_BYTES_PER_ROW(a1),a1
        rts

; ============================================================
; draw_scrolling_columns - Draw brick-textured columns to screen
; Called only at init/level-load (static columns)
; Uses 8-row brick pattern based on current window_y
; Left column uses normal pattern, right column uses mirrored pattern
; ============================================================
draw_scrolling_columns:
        movem.l d0-d3/a0-a3,-(sp)

        ; Setup column screen addresses
        lea     COL_LEFT_ADDR,a0        ; a0 = left column screen address
        lea     COL_RIGHT_ADDR,a1       ; a1 = right column screen address

        ; Get pattern bases from pointers (set by set_world_tiles)
        move.l  col_pattern_ptr(pc),a2
        move.l  col_pattern_mirror_ptr(pc),a3
        move.w  window_y(pc),d1
        andi.w  #7,d1                   ; d1 = starting pattern row (0-7)
        lsl.w   #2,d1                   ; d1 = byte offset (row * 4)

        ; Draw 192 scanlines using pattern lookup
        move.w  #VIEW_HEIGHT_PX-1,d3    ; d3 = line counter

.draw_line:
        ; Get pattern values for this row
        move.l  (a2,d1.w),d0            ; d0 = left pattern[row]
        move.l  d0,(a0)                 ; Left column
        move.l  (a3,d1.w),d0            ; d0 = right pattern[row] (mirrored)
        move.l  d0,(a1)                 ; Right column

        ; Advance screen pointers
        adda.w  #SCREEN_STRIDE,a0
        adda.w  #SCREEN_STRIDE,a1

        ; Advance pattern row (wrapping 0-7)
        addq.w  #4,d1                   ; Next row offset
        andi.w  #$1C,d1                 ; Wrap at 32 (8 rows × 4 bytes)

        dbra    d3,.draw_line

        movem.l (sp)+,d0-d3/a0-a3
        rts

; ============================================================
; composite_hero_to_buffer - Draw hero into buffer for flicker-free copy
; Saves the background first so it can be restored after copy
; Uses pixel-based window_y for visibility check
; Draws exit animation sprite when exit animation is active
; Animation update merged here to reduce normal loop overhead
; ============================================================
composite_hero_to_buffer:
        movem.l d0-d2/a0-a2,-(sp)

        ; Check if exit animation is playing for this hero
        move.w  hero_exit_active(pc),d0
        beq.s   .draw_normal_hero

        ; Exit animation active - check if it's the active hero
        move.w  hero_exit_hero_id(pc),d0
        cmp.w   active_hero(pc),d0
        bne.s   .draw_normal_hero   ; Different hero - draw normal

        ; Update animation (merged from update_hero_exit_anim)
        lea     hero_exit_delay(pc),a0
        subq.w  #1,(a0)
        bne.s   .exit_draw          ; Not time to advance yet
        move.w  #HERO_EXIT_ANIM_SPEED,(a0)  ; Reset delay
        lea     hero_exit_frame(pc),a0
        addq.w  #1,(a0)
        cmpi.w  #HERO_EXIT_FRAMES,(a0)
        blt.s   .exit_draw
        ; Animation complete - finalize exit
        bsr     complete_hero_exit
        bra     .done               ; Don't draw - hero has exited

.exit_draw:
        ; Draw exit animation sprite
        bsr     composite_exit_anim_to_buffer
        bra     .done

.draw_normal_hero:
        ; Check if hero is within visible window (pixel-based)
        ; screen_pixel_y = hero_y * 8 - window_y
        move.w  hero_y(pc),d0
        lsl.w   #3,d0               ; d0 = hero_y * 8 (hero pixel position)
        sub.w   window_y(pc),d0     ; d0 = screen_pixel_y
        bmi     .done               ; Hero above visible area
        cmpi.w  #VIEW_HEIGHT_PX-7,d0
        bgt     .done               ; Hero below visible area (8px sprite)

        ; Calculate buffer address for hero position
        ; buf_addr = playfield_buf + hero_y * 384 + hero_x * 4
        move.w  hero_y(pc),d0
        move.w  d0,d1
        lsl.w   #8,d1               ; d1 = hero_y * 256
        lsl.w   #7,d0               ; d0 = hero_y * 128
        add.w   d1,d0               ; d0 = hero_y * 384

        move.w  hero_x(pc),d1
        lsl.w   #2,d1               ; d1 = hero_x * 4
        add.w   d1,d0               ; d0 = buffer offset

        lea     playfield_buf(pc),a0
        adda.l  d0,a0               ; a0 = buffer address for hero

        ; Save background (8 longwords, BUF_STRIDE apart)
        lea     hero_buf_save(pc),a1
        move.l  (a0),(a1)+
        move.l  BUF_STRIDE(a0),(a1)+
        move.l  BUF_STRIDE*2(a0),(a1)+
        move.l  BUF_STRIDE*3(a0),(a1)+
        move.l  BUF_STRIDE*4(a0),(a1)+
        move.l  BUF_STRIDE*5(a0),(a1)+
        move.l  BUF_STRIDE*6(a0),(a1)+
        move.l  BUF_STRIDE*7(a0),(a1)+

        ; Store buffer address for restore
        lea     hero_buf_addr(pc),a1
        move.l  a0,(a1)

        ; Get hero sprite address
        bsr     get_hero_sprite     ; Returns a2 = sprite address

        ; Draw hero sprite into buffer
        move.l  (a2)+,(a0)
        move.l  (a2)+,BUF_STRIDE(a0)
        move.l  (a2)+,BUF_STRIDE*2(a0)
        move.l  (a2)+,BUF_STRIDE*3(a0)
        move.l  (a2)+,BUF_STRIDE*4(a0)
        move.l  (a2)+,BUF_STRIDE*5(a0)
        move.l  (a2)+,BUF_STRIDE*6(a0)
        move.l  (a2)+,BUF_STRIDE*7(a0)

.done:
        movem.l (sp)+,d0-d2/a0-a2
        rts

; ============================================================
; composite_exit_anim_to_buffer - Draw exit animation sprite
; Called when hero exit animation is playing
; ============================================================
composite_exit_anim_to_buffer:
        ; Check if animation position is within visible window
        move.w  hero_exit_y(pc),d0
        lsl.w   #3,d0               ; d0 = exit_y * 8 (pixel position)
        sub.w   window_y(pc),d0     ; d0 = screen_pixel_y
        bmi     .exit_done          ; Above visible area
        cmpi.w  #VIEW_HEIGHT_PX-7,d0
        bgt     .exit_done          ; Below visible area

        ; Calculate buffer address for exit animation position
        move.w  hero_exit_y(pc),d0
        move.w  d0,d1
        lsl.w   #8,d1               ; d1 = exit_y * 256
        lsl.w   #7,d0               ; d0 = exit_y * 128
        add.w   d1,d0               ; d0 = exit_y * 384

        move.w  hero_exit_x(pc),d1
        lsl.w   #2,d1               ; d1 = exit_x * 4
        add.w   d1,d0               ; d0 = buffer offset

        lea     playfield_buf(pc),a0
        adda.l  d0,a0               ; a0 = buffer address

        ; Save background
        lea     hero_buf_save(pc),a1
        move.l  (a0),(a1)+
        move.l  BUF_STRIDE(a0),(a1)+
        move.l  BUF_STRIDE*2(a0),(a1)+
        move.l  BUF_STRIDE*3(a0),(a1)+
        move.l  BUF_STRIDE*4(a0),(a1)+
        move.l  BUF_STRIDE*5(a0),(a1)+
        move.l  BUF_STRIDE*6(a0),(a1)+
        move.l  BUF_STRIDE*7(a0),(a1)+

        ; Store buffer address for restore
        lea     hero_buf_addr(pc),a1
        move.l  a0,(a1)

        ; Get exit animation sprite address
        ; a2 = exp_hero_exit_sprites + frame * 32
        move.w  hero_exit_frame(pc),d0
        lsl.w   #5,d0               ; d0 = frame * 32
        lea     exp_hero_exit_sprites(pc),a2
        adda.w  d0,a2               ; a2 = sprite address

        ; Draw exit animation sprite into buffer
        move.l  (a2)+,(a0)
        move.l  (a2)+,BUF_STRIDE(a0)
        move.l  (a2)+,BUF_STRIDE*2(a0)
        move.l  (a2)+,BUF_STRIDE*3(a0)
        move.l  (a2)+,BUF_STRIDE*4(a0)
        move.l  (a2)+,BUF_STRIDE*5(a0)
        move.l  (a2)+,BUF_STRIDE*6(a0)
        move.l  (a2)+,BUF_STRIDE*7(a0)

.exit_done:
        rts

; ============================================================
; restore_buffer_under_hero - Restore buffer background after copy
; ============================================================
restore_buffer_under_hero:
        movem.l d0/a0-a1,-(sp)

        ; Get saved buffer address
        move.l  hero_buf_addr(pc),a0
        move.l  a0,d0
        beq.s   .done               ; No hero was composited

        ; Restore background from saved data
        lea     hero_buf_save(pc),a1
        move.l  (a1)+,(a0)
        move.l  (a1)+,BUF_STRIDE(a0)
        move.l  (a1)+,BUF_STRIDE*2(a0)
        move.l  (a1)+,BUF_STRIDE*3(a0)
        move.l  (a1)+,BUF_STRIDE*4(a0)
        move.l  (a1)+,BUF_STRIDE*5(a0)
        move.l  (a1)+,BUF_STRIDE*6(a0)
        move.l  (a1)+,BUF_STRIDE*7(a0)

        ; Clear saved address
        lea     hero_buf_addr(pc),a0
        clr.l   (a0)

.done:
        movem.l (sp)+,d0/a0-a1
        rts

; ============================================================
; composite_hero2_to_buffer - Draw inactive hero into buffer
; Only draws if level has 2 heroes and the other hero is visible
; Uses green-tinted sprite to distinguish from active hero
; OPT: Uses level_has_hero2 flag and shift/sub instead of MULU
; ============================================================
composite_hero2_to_buffer:
        ; OPT: Fast flag check instead of num_heroes comparison
        move.w  level_has_hero2(pc),d0
        beq     .h2_done                ; Single hero level - skip entirely

        ; Check if inactive hero has exited (don't draw exited heroes)
        move.w  active_hero(pc),d0
        eori.w  #1,d0                   ; d0 = inactive hero index (0->1, 1->0)
        move.w  heroes_exited(pc),d1
        btst    d0,d1                   ; Test if inactive hero's bit is set
        bne     .h2_done                ; Inactive hero exited - don't draw

        ; Check if exit animation is playing for inactive hero
        move.w  hero_exit_active(pc),d1
        beq.s   .h2_no_exit_anim        ; No exit animation
        cmp.w   hero_exit_hero_id(pc),d0
        beq     .h2_done                ; Exit animation for this hero - don't draw normal

.h2_no_exit_anim:
        ; Visibility check BEFORE movem.l save (saves register overhead)
        ; Get inactive hero slot offset using scratch registers
        ; d0*18 = d0*16 + d0*2 = (d0<<4) + (d0<<1)
        move.w  d0,d1                   ; d1 = 0 or 1
        lsl.w   #4,d0                   ; d0 = 0 or 16
        add.w   d1,d1                   ; d1 = 0 or 2
        add.w   d1,d0                   ; d0 = 0 or 18
        lea     hero_slots(pc),a0       ; a0 = slot base (scratch)
        adda.w  d0,a0                   ; a0 = inactive hero slot

        ; Check if inactive hero is active (not dead)
        tst.w   HERO_SLOT_ACT(a0)
        beq     .h2_done                ; Not active - skip entirely

        ; Visibility check before committing to register save
        move.w  HERO_SLOT_Y(a0),d0      ; d0 = hero2_y
        lsl.w   #3,d0                   ; d0 = y * 8
        sub.w   window_y(pc),d0         ; d0 = screen_pixel_y
        bmi     .h2_done                ; Above visible area - skip entirely
        cmpi.w  #VIEW_HEIGHT_PX-7,d0
        bgt     .h2_done                ; Below visible area - skip entirely

        ; Hero2 is visible - NOW save registers and do the work
        movem.l d0-d3/a0-a2,-(sp)

        ; a0 was clobbered by movem, recalculate slot address
        move.w  active_hero(pc),d0
        eori.w  #1,d0                   ; d0 = inactive hero index
        move.w  d0,d1
        lsl.w   #4,d0
        add.w   d1,d1
        add.w   d1,d0
        lea     hero_slots(pc),a1
        add.w   d0,a1                   ; a1 = inactive hero slot

        ; Calculate buffer address
        move.w  HERO_SLOT_Y(a1),d0
        move.w  d0,d1
        lsl.w   #8,d1                   ; d1 = y * 256
        lsl.w   #7,d0                   ; d0 = y * 128
        add.w   d1,d0                   ; d0 = y * 384

        move.w  HERO_SLOT_X(a1),d1
        lsl.w   #2,d1                   ; d1 = x * 4
        add.w   d1,d0                   ; d0 = buffer offset

        lea     playfield_buf(pc),a0
        adda.l  d0,a0                   ; a0 = buffer address

        ; Save background
        lea     hero2_buf_save(pc),a2
        move.l  (a0),(a2)+
        move.l  BUF_STRIDE(a0),(a2)+
        move.l  BUF_STRIDE*2(a0),(a2)+
        move.l  BUF_STRIDE*3(a0),(a2)+
        move.l  BUF_STRIDE*4(a0),(a2)+
        move.l  BUF_STRIDE*5(a0),(a2)+
        move.l  BUF_STRIDE*6(a0),(a2)+
        move.l  BUF_STRIDE*7(a0),(a2)+

        ; Store buffer address
        lea     hero2_buf_addr(pc),a2
        move.l  a0,(a2)

        ; Get sprite based on inactive hero's last_dir
        move.w  HERO_SLOT_LASTD(a1),d0  ; d0 = direction
        move.w  HERO_SLOT_ANIM(a1),d1   ; d1 = anim frame
        move.w  HERO_SLOT_FLY(a1),d2    ; d2 = fly flag
        bsr     get_hero_sprite_for_dir ; a2 = sprite address

        ; Draw sprite with GREEN color mask (strips red bits)
        ; $FF00FF00 keeps green plane, removes red plane from each word
        move.l  #$FF00FF00,d3           ; d3 = green mask (preserved in movem)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,BUF_STRIDE(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,BUF_STRIDE*2(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,BUF_STRIDE*3(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,BUF_STRIDE*4(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,BUF_STRIDE*5(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,BUF_STRIDE*6(a0)
        move.l  (a2)+,d0
        and.l   d3,d0
        move.l  d0,BUF_STRIDE*7(a0)

.h2_exit:
        movem.l (sp)+,d0-d3/a0-a2
.h2_done:
        rts

; ============================================================
; restore_buffer_under_hero2 - Restore buffer under inactive hero
; ============================================================
restore_buffer_under_hero2:
        move.l  hero2_buf_addr(pc),a0
        move.l  a0,d0
        beq.s   .rh2_done               ; No hero2 was composited

        movem.l a0-a1,-(sp)

        lea     hero2_buf_save(pc),a1
        move.l  (a1)+,(a0)
        move.l  (a1)+,BUF_STRIDE(a0)
        move.l  (a1)+,BUF_STRIDE*2(a0)
        move.l  (a1)+,BUF_STRIDE*3(a0)
        move.l  (a1)+,BUF_STRIDE*4(a0)
        move.l  (a1)+,BUF_STRIDE*5(a0)
        move.l  (a1)+,BUF_STRIDE*6(a0)
        move.l  (a1)+,BUF_STRIDE*7(a0)

        lea     hero2_buf_addr(pc),a0
        clr.l   (a0)

        movem.l (sp)+,a0-a1
.rh2_done:
        rts

; ============================================================
; get_hero_sprite_for_dir - Get sprite for given direction/anim
; Input: d0 = direction, d1 = anim frame, d2 = fly flag
; Output: a2 = sprite address
; OPT: Offset table lookup (PC-relative safe, replaces branches)
; ============================================================
get_hero_sprite_for_dir:
        tst.w   d2
        bne.s   .ghs_flying
        ; Walking: index = (direction * 2 + anim) * 2 (word offsets)
        add.w   d0,d0                   ; d0 = direction * 2
        add.w   d1,d0                   ; d0 = direction * 2 + anim
        add.w   d0,d0                   ; d0 = (direction * 2 + anim) * 2
        lea     hero_walk_offsets(pc),a2
        move.w  0(a2,d0.w),d0           ; d0 = sprite offset from base
        lea     exp_hero_left_0(pc),a2  ; a2 = sprite base address
        adda.w  d0,a2                   ; a2 = base + offset
        rts
.ghs_flying:
        ; Flying: index = anim * 2 (word offsets)
        add.w   d1,d1                   ; d1 = anim * 2
        lea     hero_fly_offsets(pc),a2
        move.w  0(a2,d1.w),d1           ; d1 = sprite offset from base
        lea     exp_hero_left_0(pc),a2  ; a2 = sprite base address
        adda.w  d1,a2                   ; a2 = base + offset
        rts

; ============================================================
; composite_enemies_to_buffer - Draw all enemies into buffer
; ============================================================
composite_enemies_to_buffer:
        move.w  num_enemies(pc),d0
        beq     .exit

        movem.l d0-d7/a0-a5,-(sp)        ; FIX: Added d7, skip d5 in data ops

        lea     enemy_slots(pc),a1
        lea     enemy_buf_addrs(pc),a2
        lea     enemy_buf_saves(pc),a3
        moveq   #MAX_ENEMIES-1,d5

.comp_loop:
        tst.w   (a1)                    ; Check active
        beq     .next_comp

        ; Get enemy position from tile coordinates
        move.w  2(a1),d0                ; d0 = tile X
        move.w  4(a1),d1                ; d1 = tile Y

        ; Check if enemy is visible
        ; screen_pixel_y = enemy_y * 8 - window_y
        move.w  d1,d2
        lsl.w   #3,d2                   ; d2 = enemy_y * 8
        sub.w   window_y(pc),d2         ; d2 = screen_pixel_y
        bmi     .next_comp              ; Above visible area
        cmpi.w  #VIEW_HEIGHT_PX-7,d2
        bgt     .next_comp              ; Below visible area

        ; Calculate buffer address using tile position
        ; Buffer Y offset = tile_y * 384
        move.w  d1,d3
        ; d3 * 48 = d3 * 32 + d3 * 16 (no mulu for speed)
        move.w  d3,d4
        lsl.w   #5,d3                   ; d3 = y * 32
        lsl.w   #4,d4                   ; d4 = y * 16
        add.w   d4,d3
        lsl.w   #3,d3                   ; d3 = y * 48 * 8 = y * 384

        ; X offset from tile position: tile_x * 4 (bytes)
        move.w  d0,d4
        lsl.w   #2,d4                   ; d4 = tile_x * 4
        add.w   d4,d3                   ; d3 = buffer offset

        lea     playfield_buf(pc),a0
        adda.w  d3,a0                   ; a0 = buffer address

        ; Save buffer address for restore
        move.l  a0,(a2)

        ; FIX: Save background - avoid d5 (loop counter)
        ; Use d0-d4,d6-d7,a4 for 8 longwords
        ; Load rows 0-3 from buffer, store to save area
        move.l  (a0),d0
        move.l  4(a0),d1
        move.l  BUF_STRIDE(a0),d2
        move.l  BUF_STRIDE+4(a0),d3
        move.l  BUF_STRIDE*2(a0),d4
        move.l  BUF_STRIDE*2+4(a0),d6       ; Skip d5!
        move.l  BUF_STRIDE*3(a0),d7
        move.l  BUF_STRIDE*3+4(a0),a4
        movem.l d0-d4/d6-d7/a4,(a3)
        lea     32(a3),a3
        ; Load rows 4-7
        move.l  BUF_STRIDE*4(a0),d0
        move.l  BUF_STRIDE*4+4(a0),d1
        move.l  BUF_STRIDE*5(a0),d2
        move.l  BUF_STRIDE*5+4(a0),d3
        move.l  BUF_STRIDE*6(a0),d4
        move.l  BUF_STRIDE*6+4(a0),d6       ; Skip d5!
        move.l  BUF_STRIDE*7(a0),d7
        move.l  BUF_STRIDE*7+4(a0),a4
        movem.l d0-d4/d6-d7/a4,(a3)
        lea     32(a3),a3

        ; Get sprite address based on direction and frame
        bsr     get_enemy_sprite        ; Returns a4 = sprite address

        ; FIX: Draw sprite - avoid d5 (loop counter)
        ; Use d0-d4,d6-d7,a5 for 8 longwords
        movem.l (a4)+,d0-d4/d6-d7/a5        ; Skip d5!
        move.l  d0,(a0)
        move.l  d1,4(a0)
        move.l  d2,BUF_STRIDE(a0)
        move.l  d3,BUF_STRIDE+4(a0)
        move.l  d4,BUF_STRIDE*2(a0)
        move.l  d6,BUF_STRIDE*2+4(a0)       ; d6 not d5
        move.l  d7,BUF_STRIDE*3(a0)
        move.l  a5,BUF_STRIDE*3+4(a0)
        ; Load rows 4-7 from sprite
        movem.l (a4)+,d0-d4/d6-d7/a5        ; Skip d5!
        move.l  d0,BUF_STRIDE*4(a0)
        move.l  d1,BUF_STRIDE*4+4(a0)
        move.l  d2,BUF_STRIDE*5(a0)
        move.l  d3,BUF_STRIDE*5+4(a0)
        move.l  d4,BUF_STRIDE*6(a0)
        move.l  d6,BUF_STRIDE*6+4(a0)       ; d6 not d5
        move.l  d7,BUF_STRIDE*7(a0)
        move.l  a5,BUF_STRIDE*7+4(a0)
        bra.s   .next_comp2

.next_comp:
        ; No enemy composited - clear buffer addr, advance save ptr
        clr.l   (a2)
        adda.w  #64,a3                  ; Skip save area
.next_comp2:
        addq.l  #4,a2                   ; Next buffer addr slot
        adda.w  #ENEMY_SLOT_SIZE,a1     ; Next enemy slot
        dbra    d5,.comp_loop

        movem.l (sp)+,d0-d7/a0-a5       ; FIX: Added d7
.exit:
        rts

; ============================================================
; restore_buffer_under_enemies - Restore buffer after copy
; ============================================================
restore_buffer_under_enemies:
        move.w  num_enemies(pc),d0
        beq     .exit

        movem.l d0-d7/a0-a3,-(sp)       ; OPT: More regs for movem.l

        lea     enemy_buf_addrs(pc),a1
        lea     enemy_buf_saves(pc),a2
        moveq   #MAX_ENEMIES-1,d1

.rest_loop:
        move.l  (a1)+,a0                ; Get saved buffer address
        move.l  a0,d0
        beq.s   .skip_restore           ; No enemy was composited here

        ; OPT: Restore background using movem.l for contiguous reads
        ; Load rows 0-3 from save area (contiguous)
        movem.l (a2)+,d2-d7/a3/a4       ; 8 longwords
        move.l  d2,(a0)
        move.l  d3,4(a0)
        move.l  d4,BUF_STRIDE(a0)
        move.l  d5,BUF_STRIDE+4(a0)
        move.l  d6,BUF_STRIDE*2(a0)
        move.l  d7,BUF_STRIDE*2+4(a0)
        move.l  a3,BUF_STRIDE*3(a0)
        move.l  a4,BUF_STRIDE*3+4(a0)
        ; Load rows 4-7 from save area
        movem.l (a2)+,d2-d7/a3/a4
        move.l  d2,BUF_STRIDE*4(a0)
        move.l  d3,BUF_STRIDE*4+4(a0)
        move.l  d4,BUF_STRIDE*5(a0)
        move.l  d5,BUF_STRIDE*5+4(a0)
        move.l  d6,BUF_STRIDE*6(a0)
        move.l  d7,BUF_STRIDE*6+4(a0)
        move.l  a3,BUF_STRIDE*7(a0)
        move.l  a4,BUF_STRIDE*7+4(a0)
        bra.s   .next_rest

.skip_restore:
        adda.w  #64,a2                  ; Skip save area

.next_rest:
        dbra    d1,.rest_loop

        ; Clear all buffer addresses
        lea     enemy_buf_addrs(pc),a0
        clr.l   (a0)+
        clr.l   (a0)+
        clr.l   (a0)+
        clr.l   (a0)

        movem.l (sp)+,d0-d7/a0-a3       ; OPT: Restore more regs
.exit:
        rts

; ============================================================
; get_enemy_sprite - Get current enemy sprite address
; Input: a1 = enemy slot pointer
; Output: a4 = sprite address
; OPT: Table lookup replaces compare chain (no branches)
; ============================================================
get_enemy_sprite:
        move.w  8(a1),d4                ; d4 = frame (0-3)
        move.w  6(a1),d6                ; d6 = direction (32=right, 33=left)
        andi.w  #1,d6                   ; d6 = 0 (right) or 1 (left)
        lsl.w   #2,d6                   ; d6 = 0 or 4
        add.w   d6,d4                   ; d4 = sprite index (0-7)
        lsl.w   #6,d4                   ; d4 = index * 64 (byte offset)
        lea     exp_bat_sprites(pc),a4  ; Base of all bat sprites
        adda.w  d4,a4                   ; a4 = correct sprite address
        rts

; ============================================================
; get_hero_sprite - Get current hero sprite address
; Output: a2 = sprite address
; OPT: Uses table lookup (replaces branchy selection)
; ============================================================
get_hero_sprite:
        move.w  hero_fly(pc),d2
        move.w  hero_last_dir(pc),d0
        move.w  anim_frame(pc),d1
        bra     get_hero_sprite_for_dir  ; Reuse table lookup function

; ============================================================
; update_animation
; ============================================================
update_animation:
        lea     anim_counter(pc),a0
        subq.w  #1,(a0)
        bne.s   .done
        move.w  #4,(a0)
        lea     anim_frame(pc),a0
        eori.w  #1,(a0)
.done:
        rts

; ============================================================
; update_hero_exit_anim - REMOVED
; Logic merged into composite_hero_to_buffer to reduce game loop overhead
; ============================================================

; ============================================================
; complete_hero_exit - Called when exit animation finishes
; Handles hero switching and level completion.
; ============================================================
complete_hero_exit:
        ; Clear animation state
        lea     hero_exit_active(pc),a0
        clr.w   (a0)

        ; Check if single hero level
        move.w  level_has_hero2(pc),d0
        beq     .single_hero_exit       ; Long branch due to added code

        ; === TWO HERO LEVEL ===
        ; Mark current hero as exited
        move.w  hero_exit_hero_id(pc),d0   ; d0 = 0 or 1
        lea     heroes_exited(pc),a0
        move.w  (a0),d1
        bset    d0,d1                   ; Set bit for this hero
        move.w  d1,(a0)

        ; Check if both heroes have exited (bits 0 and 1 set = value 3)
        cmpi.w  #3,d1
        beq.s   .both_done

        ; Only one hero exited - swap to other hero
        bsr     switch_hero

        ; Check if newly active hero is on an exit tile
        ; This handles the case where hero waits on exit for other to collect keys
        ; After switch_hero, hero_x/hero_y contain the new active hero's position

        ; Look up tile at new hero's position: level_working + y * 12 + x
        move.w  hero_y(pc),d3           ; d3 = y
        move.w  d3,d4                   ; d4 = y
        lsl.w   #3,d3                   ; d3 = y * 8
        lsl.w   #2,d4                   ; d4 = y * 4
        add.w   d4,d3                   ; d3 = y * 12
        add.w   hero_x(pc),d3           ; d3 = y * 12 + x = tile offset

        lea     .lw_ref2(pc),a1
        adda.l  #level_working-.lw_ref2,a1
.lw_ref2:
        move.b  (a1,d3.w),d4            ; d4 = tile at new hero position
        cmpi.b  #TILE_EXIT,d4
        bne.s   .other_not_on_exit

        ; New active hero is on exit tile - start their exit animation
        ; Play exit sound
        movea.l sound_to_play_ptr(pc),a0
        move.w  #SFX_FIN,(a0)

        ; Store hero position for animation
        move.w  hero_x(pc),d0
        lea     hero_exit_x(pc),a0
        move.w  d0,(a0)
        move.w  hero_y(pc),d0
        lea     hero_exit_y(pc),a0
        move.w  d0,(a0)

        ; Store which hero is exiting
        move.w  active_hero(pc),d0
        lea     hero_exit_hero_id(pc),a0
        move.w  d0,(a0)

        ; Initialize animation
        lea     hero_exit_frame(pc),a0
        clr.w   (a0)
        lea     hero_exit_delay(pc),a0
        move.w  #HERO_EXIT_ANIM_SPEED,(a0)
        lea     hero_exit_active(pc),a0
        move.w  #1,(a0)

        ; Clear hero movement state
        lea     hero_dir(pc),a0
        clr.w   (a0)
        lea     hero_fly(pc),a0
        clr.w   (a0)

.other_not_on_exit:
        rts

.both_done:
        ; Both heroes exited - level complete!
        lea     level_complete_flag(pc),a0
        move.w  #1,(a0)
        rts

.single_hero_exit:
        ; Single hero - complete level
        lea     level_complete_flag(pc),a0
        move.w  #1,(a0)
        rts

; ============================================================
; update_enemies - Update enemy positions and animation
; B10-style: per-enemy delay, linear animation, move on frame wrap
; ============================================================
update_enemies:
        move.w  num_enemies(pc),d0
        beq     .exit                   ; No enemies

        movem.l d0-d7/a0-a2,-(sp)       ; FIX: Added d7 for collision check

        ; Track processed count for early exit
        move.w  num_enemies(pc),a2      ; a2 = num to process (as counter)
        ; Process each enemy slot
        lea     enemy_slots(pc),a1
        moveq   #MAX_ENEMIES-1,d5

.enemy_loop:
        tst.w   (a1)                    ; Check active
        beq.s   .next_enemy

        ; Decrement per-enemy delay counter
        move.w  10(a1),d0               ; d0 = delay counter
        subq.w  #1,d0
        bgt.s   .store_delay            ; Delay not expired, just store

        ; Delay expired - advance animation frame and reset delay
        move.w  #ENEMY_ANIM_DELAY,d0    ; Reset delay
        move.w  8(a1),d1                ; d1 = current frame
        addq.w  #1,d1
        andi.w  #(ENEMY_ANIM_FRAMES-1),d1  ; Cycle 0-3
        move.w  d1,8(a1)                ; Store new frame

        ; Check if frame wrapped to 0 - time to move
        tst.w   d1
        bne.s   .store_delay            ; Not frame 0, don't move

        ; Frame wrapped to 0 - move enemy
        move.w  2(a1),d2                ; d2 = tile X
        move.w  4(a1),d3                ; d3 = tile Y
        move.w  6(a1),d4                ; d4 = direction

        cmpi.w  #ENEMY_RIGHT,d4
        bne.s   .move_left

        ; Moving right
        cmpi.w  #LEVEL_W-2,d2           ; Check right edge (bat is 2 tiles wide)
        bge.s   .reverse_to_left        ; At edge, reverse
        addq.w  #1,d2                   ; Try new X

        ; Check tile to the right
        ; FIX: Use d7 instead of d5 (d5 is loop counter!)
        move.w  d2,d7
        addq.w  #1,d7                   ; Check right edge of bat (X+1)
        bsr     .check_tile_solid
        tst.w   d6
        bne.s   .reverse_to_left        ; Solid, reverse

        ; Move right
        move.w  d2,2(a1)                ; Store new X
        bra.s   .store_delay

.reverse_to_left:
        move.w  #ENEMY_LEFT,6(a1)       ; Change direction
        bra.s   .store_delay

.move_left:
        tst.w   d2                      ; Check left edge
        beq.s   .reverse_to_right       ; At edge (X=0), reverse
        subq.w  #1,d2                   ; Try new X

        ; Check tile to the left
        ; FIX: Use d7 instead of d5 (d5 is loop counter!)
        move.w  d2,d7
        bsr     .check_tile_solid
        tst.w   d6
        bne.s   .reverse_to_right       ; Solid, reverse

        ; Move left
        move.w  d2,2(a1)                ; Store new X
        bra.s   .store_delay

.reverse_to_right:
        move.w  #ENEMY_RIGHT,6(a1)      ; Change direction

.store_delay:
        move.w  d0,10(a1)               ; Store delay counter
        ; Check if all enemies processed (early exit)
        subq.w  #1,a2                   ; Decrement remaining count
        move.l  a2,d0
        beq.s   .early_exit             ; All enemies processed

.next_enemy:
        adda.w  #ENEMY_SLOT_SIZE,a1
        dbra    d5,.enemy_loop

.early_exit:
        movem.l (sp)+,d0-d7/a0-a2       ; FIX: Added d7
.exit:
        rts

; Check if tile at (d7,d3) is solid
; FIX: Changed from d5 to d7 (d5 is loop counter)
; Returns d6 = 1 if solid, 0 if passable
; OPT: mulu #12 -> shifts (y*3*4 = y*12)
.check_tile_solid:
        move.l  level_data_ptr(pc),a2
        move.w  d3,d6
        add.w   d6,d6                   ; d6 = y * 2
        add.w   d3,d6                   ; d6 = y * 3
        lsl.w   #2,d6                   ; d6 = y * 12
        add.w   d7,d6                   ; d6 = y * 12 + x (FIX: d7 not d5)
        move.b  (a2,d6.w),d6
        ; Check if solid (tiles 28-30 are solid)
        cmpi.b  #TILE_UNHIDDEN,d6
        blt.s   .not_solid
        moveq   #1,d6
        rts
.not_solid:
        moveq   #0,d6
        rts

; ============================================================
; check_collision - Hero/enemy collision using actual movement range
; Uses [hero_y, hero_last_y] range for UP movement
; Uses [hero_last_y, hero_y] range for DOWN movement
; This ensures collision only checked through tiles hero passed through
; Prevents false collisions through solid walls
; Returns: d0 = 1 if collision, 0 if no collision
; ============================================================
check_collision:
        ; OPT: Early exit if no enemies
        move.w  num_enemies(pc),d0
        beq     .no_coll                ; No enemies, no collision possible

        ; Get hero position and direction
        move.w  hero_x(pc),d0
        move.w  hero_y(pc),d1           ; d1 = current hero_y
        move.w  hero_dir(pc),d4         ; d4 = movement direction
        move.w  hero_last_y(pc),d6      ; d6 = previous hero_y

        ; Loop through enemy slots
        lea     enemy_slots(pc),a0
        moveq   #MAX_ENEMIES-1,d2

.loop:
        tst.w   (a0)                    ; Active? (+0)
        beq     .next

        ; Get enemy Y
        move.w  4(a0),d3                ; d3 = enemy_y (+4)

        ; Check direction for Y matching strategy
        cmpi.w  #DIR_UP,d4
        beq.s   .check_up_path
        cmpi.w  #DIR_DOWN,d4
        beq.s   .check_down_path

        ; Horizontal or stopped: exact Y match
        cmp.w   d3,d1                   ; hero_y == enemy_y?
        bne     .next
        bra.s   .check_x

.check_up_path:
        ; Moving UP: check if enemy_y is in actual path [hero_y, hero_last_y]
        ; enemy_y must be >= hero_y (current) AND <= hero_last_y (previous)
        cmp.w   d1,d3                   ; enemy_y >= hero_y?
        blt     .next                   ; No, enemy above where hero is now
        cmp.w   d6,d3                   ; enemy_y <= hero_last_y?
        bgt     .next                   ; No, enemy below where hero was
        bra.s   .check_x

.check_down_path:
        ; Moving DOWN: check if enemy_y is in actual path [hero_last_y, hero_y]
        ; enemy_y must be >= hero_last_y (previous) AND <= hero_y (current)
        cmp.w   d6,d3                   ; enemy_y >= hero_last_y?
        blt     .next                   ; No, enemy above where hero was
        cmp.w   d1,d3                   ; enemy_y <= hero_y?
        bgt     .next                   ; No, enemy below where hero is now

.check_x:
        ; Check X overlap (bat is 2 tiles wide: enemy_x and enemy_x+1)
        move.w  2(a0),d3                ; d3 = enemy_x (+2)
        cmp.w   d3,d0                   ; hero_x >= enemy_x?
        blt.s   .next
        addq.w  #1,d3
        cmp.w   d3,d0                   ; hero_x <= enemy_x+1?
        bgt.s   .next

        ; Collision!
        moveq   #1,d0
        rts

.next:
        lea     ENEMY_SLOT_SIZE(a0),a0
        dbra    d2,.loop

        ; No enemy collision - now check bullets
        ; d0 = hero_x, d1 = hero_y, d4 = hero_dir, d6 = hero_last_y (all preserved)
        ; Reload hero position (may have been clobbered)
        move.w  hero_x(pc),d0
        move.w  hero_y(pc),d1

        lea     bullet_list(pc),a0
        moveq   #MAX_BULLETS-1,d2

.bullet_loop:
        tst.w   BULLET_ACTIVE(a0)       ; Active?
        beq.s   .next_bullet

        ; Get bullet Y
        move.w  BULLET_Y(a0),d3         ; d3 = bullet_y

        ; Check direction for Y matching strategy
        cmpi.w  #DIR_UP,d4
        beq.s   .bullet_check_up_path
        cmpi.w  #DIR_DOWN,d4
        beq.s   .bullet_check_down_path

        ; Horizontal or stopped: exact Y match
        cmp.w   d3,d1                   ; hero_y == bullet_y?
        bne.s   .next_bullet
        bra.s   .bullet_check_x

.bullet_check_up_path:
        ; Moving UP: check if bullet_y is in actual path [hero_y, hero_last_y]
        cmp.w   d1,d3                   ; bullet_y >= hero_y?
        blt.s   .next_bullet
        cmp.w   d6,d3                   ; bullet_y <= hero_last_y?
        bgt.s   .next_bullet
        bra.s   .bullet_check_x

.bullet_check_down_path:
        ; Moving DOWN: check if bullet_y is in path [hero_last_y, hero_y]
        cmp.w   d6,d3                   ; bullet_y >= hero_last_y?
        blt.s   .next_bullet
        cmp.w   d1,d3                   ; bullet_y <= hero_y?
        bgt.s   .next_bullet

.bullet_check_x:
        ; Check X overlap based on bullet direction
        ; Bullet is 2 tiles wide, position depends on direction:
        ;   Right-moving at X: occupies X-1 and X
        ;   Left-moving at X: occupies X and X+1
        move.w  BULLET_X(a0),d3         ; d3 = bullet_x
        move.w  BULLET_DIR(a0),d5       ; d5 = bullet delta (-1 or +1)

        ; Use sign test instead of compare (delta is -1 or +1)
        tst.w   d5
        bmi.s   .bullet_left_x          ; negative delta = left-moving

        ; Right-moving: check hero_x in [bullet_x-1, bullet_x]
        move.w  d3,d5
        subq.w  #1,d5                   ; d5 = bullet_x - 1
        cmp.w   d5,d0                   ; hero_x >= bullet_x-1?
        blt.s   .next_bullet
        cmp.w   d3,d0                   ; hero_x <= bullet_x?
        bgt.s   .next_bullet
        bra.s   .bullet_hit

.bullet_left_x:
        ; Left-moving: check hero_x in [bullet_x, bullet_x+1]
        cmp.w   d3,d0                   ; hero_x >= bullet_x?
        blt.s   .next_bullet
        addq.w  #1,d3
        cmp.w   d3,d0                   ; hero_x <= bullet_x+1?
        bgt.s   .next_bullet

.bullet_hit:
        ; Collision with bullet!
        moveq   #1,d0
        rts

.next_bullet:
        lea     BULLET_SIZE(a0),a0
        dbra    d2,.bullet_loop

.no_coll:
        moveq   #0,d0
        rts

; ============================================================
; SCREEN Y ADDRESS TABLE
; ============================================================
y_addr_table:
        dc.l    PLAYFIELD_BASE+0*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+1*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+2*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+3*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+4*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+5*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+6*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+7*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+8*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+9*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+10*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+11*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+12*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+13*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+14*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+15*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+16*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+17*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+18*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+19*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+20*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+21*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+22*TILE_Y_BYTES
        dc.l    PLAYFIELD_BASE+23*TILE_Y_BYTES

; ============================================================
; get_tile_addr - Get screen address for tile at (x, screen_y)
; Input: d0 = x (0-11), d1 = screen_y (0-23)
; Output: a0 = screen address
; Trashes: d0, d1
; ============================================================
get_tile_addr:
        lsl.w   #2,d1
        lea     y_addr_table(pc),a0
        adda.w  d1,a0
        move.l  (a0),a0
        lsl.w   #2,d0
        adda.w  d0,a0
        rts

; ============================================================
; draw_hero_smart
; ============================================================
draw_hero_smart:
        move.w  hero_x(pc),d0
        cmp.w   hero_drawn_x(pc),d0
        bne.s   draw_hero_force
        move.w  hero_y(pc),d0
        cmp.w   hero_drawn_y(pc),d0
        bne.s   draw_hero_force
        move.w  anim_frame(pc),d0
        cmp.w   hero_drawn_anim(pc),d0
        bne.s   draw_hero_force
        move.w  hero_fly(pc),d0
        cmp.w   hero_drawn_fly(pc),d0
        bne.s   draw_hero_force
        move.w  window_y(pc),d0
        cmp.w   hero_drawn_scroll(pc),d0
        bne.s   draw_hero_force
        rts

draw_hero_force:
        movem.l d0-d2/a0-a1,-(sp)

        move.w  hero_x(pc),d0
        lea     hero_drawn_x(pc),a0
        move.w  d0,(a0)
        move.w  hero_y(pc),d0
        lea     hero_drawn_y(pc),a0
        move.w  d0,(a0)
        move.w  anim_frame(pc),d0
        lea     hero_drawn_anim(pc),a0
        move.w  d0,(a0)
        move.w  hero_fly(pc),d0
        lea     hero_drawn_fly(pc),a0
        move.w  d0,(a0)
        move.w  window_y(pc),d0
        lea     hero_drawn_scroll(pc),a0
        move.w  d0,(a0)

        ; Calculate screen position using pixel-based window_y
        ; screen_pixel_y = hero_y * 8 - window_y
        ; screen_tile_y = screen_pixel_y / 8
        move.w  hero_x(pc),d0
        move.w  hero_y(pc),d1
        lsl.w   #3,d1               ; d1 = hero_y * 8
        sub.w   window_y(pc),d1     ; d1 = screen_pixel_y
        bmi     .done               ; Above visible area
        cmpi.w  #VIEW_HEIGHT_PX-7,d1
        bgt     .done               ; Below visible area
        lsr.w   #3,d1               ; d1 = screen_tile_y

        bsr     get_tile_addr

        ; OPT: Use table lookup for sprite selection
        move.w  hero_fly(pc),d2
        move.w  hero_last_dir(pc),d0
        move.w  anim_frame(pc),d1
        bsr     get_hero_sprite_for_dir ; a2 = sprite address
        move.l  a2,a1                   ; a1 = sprite for draw loop

.draw:
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)

.done:
        movem.l (sp)+,d0-d2/a0-a1
        rts

; ============================================================
; redraw_tile_at - Redraw tile at level position (x,y)
; Input: d0 = x (level coord 0-11)
;        d1 = y (level coord 0-63)
; ============================================================
redraw_tile_at:
        movem.l d0-d5/a0-a2,-(sp)

        ; Bounds check
        tst.w   d0
        bmi     .done
        cmpi.w  #LEVEL_W,d0
        bge     .done
        tst.w   d1
        bmi     .done
        cmpi.w  #LEVEL_H,d1
        bge     .done

        ; Save level coordinates
        move.w  d0,d3           ; d3 = level_x
        move.w  d1,d4           ; d4 = level_y

        ; Check if visible on screen (pixel-based)
        ; screen_pixel_y = level_y * 8 - window_y
        move.w  d4,d2
        lsl.w   #3,d2           ; d2 = level_y * 8
        sub.w   window_y(pc),d2 ; d2 = screen_pixel_y
        bmi     .done           ; Above visible area
        cmpi.w  #VIEW_HEIGHT_PX-7,d2
        bgt     .done           ; Below visible area
        lsr.w   #3,d2           ; d2 = screen_tile_y

        ; Calculate offset: y * 12 + x using shift-add
        move.w  d4,d0           ; d0 = y
        add.w   d0,d0           ; d0 = y*2
        add.w   d4,d0           ; d0 = y*3
        lsl.w   #2,d0           ; d0 = y*12
        add.w   d3,d0           ; d0 = y*12 + x

        ; Get tile type from level_data
        move.l  level_data_ptr(pc),a0
        moveq   #0,d5
        move.b  (a0,d0.w),d5    ; d5 = tile type

        ; Get expanded tile data
        lsl.w   #5,d5
        lea     expanded_tiles(pc),a1
        adda.w  d5,a1           ; a1 = expanded tile

        ; Get screen address
        move.w  d3,d0           ; d0 = level_x (= screen_x)
        move.w  d2,d1           ; d1 = screen_y
        bsr     get_tile_addr   ; a0 = screen address

        ; Draw tile
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)
        adda.w  #SCREEN_STRIDE,a0
        move.l  (a1)+,(a0)

.done:
        movem.l (sp)+,d0-d5/a0-a2
        rts

; ============================================================
; update_camera - Spectrum-style smooth camera tracking
; cam_focus_y steps toward hero position in pixels
; window_y = cam_focus_y - CAM_ANCHOR_PX, clamped to valid range
; ============================================================
update_camera:
        movem.l d0-d4/a0,-(sp)

        ; Step 1: Compute heroYpix (target for cam_focus_y)
        ; heroYpix = hero_y * 8 + 4 (center of hero tile)
        move.w  hero_y(pc),d1
        lsl.w   #3,d1               ; d1 = hero_y * 8
        addq.w  #4,d1               ; d1 = heroYpix

        ; Update hero_last_y for next frame
        move.w  hero_y(pc),d0
        lea     hero_last_y(pc),a0
        move.w  d0,(a0)

        ; Step 2: Calculate diff = heroYpix - cam_focus_y
        move.w  cam_focus_y(pc),d0  ; d0 = current focus
        move.w  d1,d2
        sub.w   d0,d2               ; d2 = diff = heroYpix - cam_focus_y
        beq.s   .derive_window      ; Focus already at target

        ; Calculate |diff| in d3
        move.w  d2,d3
        bpl.s   .abs_ok
        neg.w   d3                  ; d3 = |diff|
.abs_ok:

        ; Coarse/fast scroll with overshoot fix
        ; if |diff| >= 256: step = 16 (was 8)
        ; else: step = (|diff| >> 3) + 2  ; gives 2..34 (was 1..16)
        cmpi.w  #256,d3
        bge.s   .use_speed_16

        move.w  d3,d4
        lsr.w   #3,d4               ; d4 = |diff| / 8 (was /16)
        addq.w  #1,d4               ; step (1..33) - 1 pixel min scroll
        bra.s   .clamp_step

.use_speed_16:
        moveq   #16,d4              ; step = 16 for large diff (was 8)

.clamp_step:
        ; Clamp step to |diff| to prevent overshoot/oscillation
        cmp.w   d3,d4               ; Compare step with |diff|
        ble.s   .apply_step         ; Step <= |diff|, no clamp needed
        move.w  d3,d4               ; Clamp step to |diff|

.apply_step:
        ; Apply sign of diff to step
        tst.w   d2
        bpl.s   .step_positive
        neg.w   d4                  ; Negative step for camera moving up
.step_positive:

        ; Apply step to cam_focus_y
        add.w   d4,d0
        lea     cam_focus_y(pc),a0
        move.w  d0,(a0)

.derive_window:
        ; Derive window_y from cam_focus_y
        ; window_y = cam_focus_y - CAM_ANCHOR_PX (clamped)
        move.w  cam_focus_y(pc),d0
        subi.w  #CAM_ANCHOR_PX,d0   ; d0 = window start position

        ; Clamp to valid range [0, MAX_WINDOW_Y]
        bpl.s   .win_check_max
        clr.w   d0                  ; Clamp to 0
.win_check_max:
        cmpi.w  #MAX_WINDOW_Y,d0
        ble.s   .win_ok
        move.w  #MAX_WINDOW_Y,d0    ; Clamp to max
.win_ok:
        lea     window_y(pc),a0
        move.w  d0,(a0)

        movem.l (sp)+,d0-d4/a0
        rts

; ============================================================
; update_hero_movement
; Removed hero_exit_active check - hero_dir is cleared
;      when exit animation starts, so existing check suffices
; ============================================================
update_hero_movement:
        movem.l d0-d6/a0,-(sp)

        move.w  hero_dir(pc),d0
        beq     .done

        ; Check and remove cracked tile if hero bumped into one last move
        bsr     check_crack_tile

        lea     hero_fly(pc),a0
        move.w  #1,(a0)

        ; Store old position in d5/d6
        move.w  hero_x(pc),d5
        move.w  hero_y(pc),d6

        ; ==================== REFLECTOR CHECK (OPTIMIZED) ====================
        ; Check tile at hero's current position for reflectors
        ; Uses range check + factored common code for efficiency
        move.w  d6,d0           ; d0 = y
        add.w   d0,d0           ; d0 = y*2
        add.w   d6,d0           ; d0 = y*3
        lsl.w   #2,d0           ; d0 = y*12
        add.w   d5,d0           ; d0 = y*12 + x (tile offset)
        move.l  level_data_ptr(pc),a0
        move.b  (a0,d0.w),d1    ; d1 = tile type at hero position

        ; Range check: is tile 16 or 17? (REFLECT1 or REFLECT2)
        subi.b  #TILE_REFLECT1,d1    ; d1 = tile - 16
        cmpi.b  #2,d1
        bhs.s   .reflect_done        ; Not a reflector (d1 >= 2 unsigned)

        ; d1 = 0 (REFLECT1 \) or 1 (REFLECT2 /)
        tst.b   d1
        beq.s   .is_reflect1
        lea     reflect2_table(pc),a0
        bra.s   .apply_reflect
.is_reflect1:
        lea     reflect1_table(pc),a0

.apply_reflect:
        ; Common direction update code (factored out)
        move.w  hero_dir(pc),d0
        add.w   d0,d0           ; word index
        move.w  (a0,d0.w),d0    ; d0 = new direction
        lea     hero_dir(pc),a0
        move.w  d0,(a0)
        lea     hero_last_dir(pc),a0
        move.w  d0,(a0)

.reflect_done:
        ; ==================== END REFLECTOR CHECK ====================

        ; No need to erase hero - copy_window_to_screen restores background
        lea     hero_drawn_x(pc),a0
        move.w  #-1,(a0)

.do_move:
        ; Direction dispatch point (also used for bounce restart)
        move.w  hero_dir(pc),d0

        ; ==================== LEFT (1-tile) ====================
        cmpi.w  #DIR_LEFT,d0
        bne     .not_left

        move.w  d5,d0
        subq.w  #1,d0
        bmi     .stop                   ; Off left edge
        move.w  d6,d1
        moveq   #DIR_LEFT,d2            ; Direction for one-way check
        bsr     is_solid_for_hero
        tst.w   d0
        bne     .stop

        ; Activate old position
        move.w  d5,d0
        move.w  d6,d1
        bsr     activate_hidden_tile

        ; Trail at old position
        move.w  hero_dir(pc),d0
        move.w  d5,d1
        move.w  d6,d2
        bsr     start_trail

        ; Move
        subq.w  #1,d5
        lea     hero_x(pc),a0
        move.w  d5,(a0)

        ; Process tile effects (coin collection + exit check)
        bsr     process_tile_effects

.left_done:
        bra     .done

        ; ==================== RIGHT (1-tile) ====================
.not_left:
        cmpi.w  #DIR_RIGHT,d0
        bne     .not_right

        move.w  d5,d0
        addq.w  #1,d0
        cmpi.w  #LEVEL_W,d0
        bge     .stop                   ; Off right edge
        move.w  d6,d1
        moveq   #DIR_RIGHT,d2           ; Direction for one-way check
        bsr     is_solid_for_hero
        tst.w   d0
        bne     .stop

        ; Activate old position
        move.w  d5,d0
        move.w  d6,d1
        bsr     activate_hidden_tile

        ; Trail at old position
        move.w  hero_dir(pc),d0
        move.w  d5,d1
        move.w  d6,d2
        bsr     start_trail

        ; Move
        addq.w  #1,d5
        lea     hero_x(pc),a0
        move.w  d5,(a0)

        ; Process tile effects (coin collection + exit check)
        bsr     process_tile_effects

.right_done:
        bra     .done

        ; ==================== UP (1-tile) ====================
.not_right:
        cmpi.w  #DIR_UP,d0
        bne     .not_up

        move.w  d5,d0
        move.w  d6,d1
        subq.w  #1,d1
        bmi     .stop
        moveq   #DIR_UP,d2              ; Direction for one-way check
        bsr     is_solid_for_hero
        tst.w   d0
        bne     .stop

        ; Activate old position
        move.w  d5,d0
        move.w  d6,d1
        bsr     activate_hidden_tile

        ; Trail
        move.w  hero_dir(pc),d0
        move.w  d5,d1
        move.w  d6,d2
        bsr     start_trail

        ; Move
        subq.w  #1,d6
        lea     hero_y(pc),a0
        move.w  d6,(a0)

        ; Process tile effects (coin collection + exit check)
        bsr     process_tile_effects

.up_done:
        bra     .done

        ; ==================== DOWN (1-tile) ====================
.not_up:
        move.w  d5,d0
        move.w  d6,d1
        addq.w  #1,d1
        cmpi.w  #LEVEL_H,d1
        bge     .stop
        moveq   #DIR_DOWN,d2            ; Direction for one-way check
        bsr     is_solid_for_hero
        tst.w   d0
        bne     .stop

        ; Activate old position
        move.w  d5,d0
        move.w  d6,d1
        bsr     activate_hidden_tile

        ; Trail
        move.w  hero_dir(pc),d0
        move.w  d5,d1
        move.w  d6,d2
        bsr     start_trail

        ; Move
        addq.w  #1,d6
        lea     hero_y(pc),a0
        move.w  d6,(a0)

        ; Process tile effects (coin collection + exit check)
        bsr     process_tile_effects

.down_done:
        bra.s   .done

.stop:
        ; Check if we should bounce instead of stop
        move.w  hero_bounce_dir(pc),d0
        beq.s   .real_stop              ; No bounce, really stop

        ; Bounce! Set new direction and continue moving
        lea     hero_dir(pc),a0
        move.w  d0,(a0)                 ; Set direction to bounce direction
        lea     hero_bounce_dir(pc),a0
        clr.w   (a0)                    ; Clear bounce flag
        bra     .do_move                ; Restart movement with new direction

.real_stop:
        ; Save landing direction before clearing (for cracked block check)
        move.w  hero_dir(pc),d0
        lea     hero_land_dir(pc),a0
        move.w  d0,(a0)
        lea     hero_dir(pc),a0
        clr.w   (a0)
        lea     hero_fly(pc),a0
        clr.w   (a0)
        ; SFX_FLY removed - now plays at movement START

.done:
        movem.l (sp)+,d0-d6/a0
        rts

; ============================================================
; read_keyboard
; ============================================================
read_keyboard:
        movem.l d0-d3/a0,-(sp)

        move.l  con_id(pc),a0
        move.l  a0,d0
        beq     .done

        moveq   #IO_FBYTE,d0
        moveq   #0,d3
        trap    #3
        tst.l   d0
        bmi     .done

        cmpi.b  #27,d1
        beq     .quit

        ; Block all input during exit animation
        move.w  hero_exit_active(pc),d0
        bne     .done

        ; Level skip ("=") removed for release

        ; Check for "R" key to reset level
        cmpi.b  #'r',d1
        beq     .reset_lvl
        cmpi.b  #'R',d1
        beq     .reset_lvl

        ; Check for SPACE key to swap heroes
        cmpi.b  #' ',d1
        beq     .swap_hero

        move.w  hero_dir(pc),d0
        bne     .done

        ; Arrow keys
        cmpi.b  #208,d1
        beq.s   .set_up
        cmpi.b  #216,d1
        beq.s   .set_down
        cmpi.b  #192,d1
        beq.s   .set_left
        cmpi.b  #200,d1
        beq.s   .set_right
        ; WASD keys
        cmpi.b  #'w',d1
        beq.s   .set_up
        cmpi.b  #'W',d1
        beq.s   .set_up
        cmpi.b  #'s',d1
        beq.s   .set_down
        cmpi.b  #'S',d1
        beq.s   .set_down
        cmpi.b  #'a',d1
        beq.s   .set_left
        cmpi.b  #'A',d1
        beq.s   .set_left
        cmpi.b  #'d',d1
        beq.s   .set_right
        cmpi.b  #'D',d1
        beq.s   .set_right
        bra.s   .done

.set_up:
        moveq   #DIR_UP,d0
        bra.s   .set_dir
.set_down:
        moveq   #DIR_DOWN,d0
        bra.s   .set_dir
.set_left:
        moveq   #DIR_LEFT,d0
        bra.s   .set_dir
.set_right:
        moveq   #DIR_RIGHT,d0

.set_dir:
        lea     hero_dir(pc),a0
        move.w  d0,(a0)
        lea     hero_last_dir(pc),a0
        move.w  d0,(a0)
        ; Play fly sound on movement START (fixes coin sound overwrite)
        movea.l sound_to_play_ptr(pc),a0
        move.w  #SFX_FLY,(a0)
        bra.s   .done

.reset_lvl:
        ; Set reset flag - handled in main loop
        lea     reset_level_flag(pc),a0
        move.w  #1,(a0)
        bra.s   .done

.swap_hero:
        ; Prevent swap while moving (same guard as direction keys)
        move.w  hero_dir(pc),d0
        bne.s   .done
        bsr     switch_hero
        bra.s   .done

.quit:
        lea     quit_flag(pc),a0
        move.w  #1,(a0)

.done:
        movem.l (sp)+,d0-d3/a0
        rts

; ============================================================
; Trail routines
; ============================================================
clear_trails:
        lea     trail_slots(pc),a0
        moveq   #NUM_TRAIL_SLOTS-1,d0
.clear:
        clr.w   (a0)
        adda.w  #TRAIL_SLOT_SIZE,a0
        dbra    d0,.clear
        lea     active_trails(pc),a0
        clr.w   (a0)
        ; Clear trail buffer save addresses
        lea     trail_buf_addrs(pc),a0
        moveq   #NUM_TRAIL_SLOTS-1,d0
.clear_addrs:
        clr.l   (a0)+
        dbra    d0,.clear_addrs
        rts

start_trail:
        movem.l d0-d3/a0-a1,-(sp)
        move.w  d0,d3

        lea     trail_slots(pc),a0
        moveq   #NUM_TRAIL_SLOTS-1,d0
.find:
        tst.w   (a0)
        beq.s   .found
        adda.w  #TRAIL_SLOT_SIZE,a0
        dbra    d0,.find
        bra.s   .done

.found:
        move.w  #1,(a0)
        move.w  d1,2(a0)
        move.w  d2,4(a0)

        lea     active_trails(pc),a1
        addq.w  #1,(a1)

        lea     trail_anim_down(pc),a1
        cmpi.w  #DIR_UP,d3
        bne.s   .not_up
        lea     trail_anim_up(pc),a1
        bra.s   .set
.not_up:
        cmpi.w  #DIR_LEFT,d3
        bne.s   .not_left
        lea     trail_anim_left(pc),a1
        bra.s   .set
.not_left:
        cmpi.w  #DIR_RIGHT,d3
        bne.s   .set
        lea     trail_anim_right(pc),a1
.set:
        move.l  a1,6(a0)

.done:
        movem.l (sp)+,d0-d3/a0-a1
        rts

; ============================================================
; composite_trails_to_buffer
; Draws trail sprites into the playfield buffer (like hero/enemies)
; so they are included in copy_window_to_screen without flicker.
; Background is saved for later restore.
; ============================================================
composite_trails_to_buffer:
        move.w  active_trails(pc),d0
        beq     .exit

        movem.l d0-d5/a0-a5,-(sp)

        lea     trail_slots(pc),a3
        lea     exp_trail_sprites(pc),a5
        lea     trail_buf_addrs(pc),a4  ; a4 = save address array
        lea     trail_buf_saves(pc),a2  ; a2 = save data array
        moveq   #NUM_TRAIL_SLOTS-1,d5

.loop:
        tst.w   (a3)
        beq.s   .inactive

        ; Advance animation frame
        move.l  6(a3),a1
        moveq   #0,d0
        move.b  (a1)+,d0
        cmpi.b  #TRAIL_IDX_END,d0
        beq.s   .slot_done

        move.l  a1,6(a3)

        ; Get trail sprite address
        lsl.w   #5,d0               ; d0 = sprite_index * 32
        lea     (a5),a1
        adda.w  d0,a1               ; a1 = trail sprite data

        ; Calculate buffer address
        ; buf_addr = playfield_buf + slot_y * (BUF_STRIDE*8) + slot_x * 4
        ;          = playfield_buf + slot_y * 384 + slot_x * 4
        move.w  4(a3),d0            ; d0 = slot_y (tiles)
        move.w  d0,d1
        lsl.w   #8,d1               ; d1 = slot_y * 256
        lsl.w   #7,d0               ; d0 = slot_y * 128
        add.w   d1,d0               ; d0 = slot_y * 384

        move.w  2(a3),d1            ; d1 = slot_x
        lsl.w   #2,d1               ; d1 = slot_x * 4
        add.w   d1,d0               ; d0 = buffer offset

        lea     playfield_buf(pc),a0
        adda.l  d0,a0               ; a0 = buffer address for trail

        ; Store buffer address for restore
        move.l  a0,(a4)

        ; Save background (8 longwords, BUF_STRIDE apart)
        move.l  (a0),(a2)+
        move.l  BUF_STRIDE(a0),(a2)+
        move.l  BUF_STRIDE*2(a0),(a2)+
        move.l  BUF_STRIDE*3(a0),(a2)+
        move.l  BUF_STRIDE*4(a0),(a2)+
        move.l  BUF_STRIDE*5(a0),(a2)+
        move.l  BUF_STRIDE*6(a0),(a2)+
        move.l  BUF_STRIDE*7(a0),(a2)+

        ; Draw trail sprite into buffer
        move.l  (a1)+,(a0)
        move.l  (a1)+,BUF_STRIDE(a0)
        move.l  (a1)+,BUF_STRIDE*2(a0)
        move.l  (a1)+,BUF_STRIDE*3(a0)
        move.l  (a1)+,BUF_STRIDE*4(a0)
        move.l  (a1)+,BUF_STRIDE*5(a0)
        move.l  (a1)+,BUF_STRIDE*6(a0)
        move.l  (a1)+,BUF_STRIDE*7(a0)
        bra.s   .next

.slot_done:
        clr.w   (a3)
        lea     active_trails(pc),a0
        subq.w  #1,(a0)
        ; Clear buf addr so restore skips this slot
        clr.l   (a4)
        ; Fall through to .inactive to advance a2

.inactive:
        ; Advance save data pointer to keep aligned with slot index
        adda.w  #32,a2

.next:
        addq.l  #4,a4               ; Next save address slot
        adda.w  #TRAIL_SLOT_SIZE,a3
        dbra    d5,.loop

        movem.l (sp)+,d0-d5/a0-a5
.exit:
        rts

; ============================================================
; restore_buffer_under_trails
; Restores buffer background under all composited trails.
; Iterates in REVERSE order (slot 23->0) to correctly handle
; overlapping trails. When two trails share the same buffer position,
; the later-composited trail's save captured the earlier trail's sprite.
; Restoring in reverse undoes composites in LIFO order, ensuring the
; original clean background is restored last.
; ============================================================
restore_buffer_under_trails:
        move.w  active_trails(pc),d0
        beq     .exit

        movem.l d0-d1/a0-a2,-(sp)

        ; Start from the LAST slot and work backwards
        lea     trail_buf_addrs(pc),a1
        adda.w  #(NUM_TRAIL_SLOTS-1)*4,a1
        lea     trail_buf_saves(pc),a2
        adda.w  #(NUM_TRAIL_SLOTS-1)*32,a2
        moveq   #NUM_TRAIL_SLOTS-1,d1

.loop:
        move.l  (a1),a0             ; a0 = saved buffer address
        move.l  a0,d0
        beq.s   .skip               ; No sprite was composited here

        ; Restore background using explicit offsets (a2 = start of save block)
        move.l  (a2),(a0)
        move.l  4(a2),BUF_STRIDE(a0)
        move.l  8(a2),BUF_STRIDE*2(a0)
        move.l  12(a2),BUF_STRIDE*3(a0)
        move.l  16(a2),BUF_STRIDE*4(a0)
        move.l  20(a2),BUF_STRIDE*5(a0)
        move.l  24(a2),BUF_STRIDE*6(a0)
        move.l  28(a2),BUF_STRIDE*7(a0)

        ; Clear address (one-shot restore)
        clr.l   (a1)

.skip:
        suba.w  #4,a1               ; Previous buf_addr slot
        suba.w  #32,a2              ; Previous save block
        dbra    d1,.loop

        movem.l (sp)+,d0-d1/a0-a2
.exit:
        rts

; ============================================================
; DATA TABLES
; ============================================================

nibble_to_mask:
        dc.w    $0000,$0303,$0C0C,$0F0F
        dc.w    $3030,$3333,$3C3C,$3F3F
        dc.w    $C0C0,$C3C3,$CCCC,$CFCF
        dc.w    $F0F0,$F3F3,$FCFC,$FFFF

; Tile colors - NO LONGER USED (colors baked into tiles_4bpp)
; tile_colors:
;         dc.w    COL4_BLUE,COL4_BLUE,COL4_CYAN,COL4_CYAN     ; Tiles 0-1 blue, 2-3 cyan (spikes)
;         dc.w    COL4_CYAN,COL4_CYAN,COL4_YELLOW,COL4_YELLOW
;         dc.w    COL4_BLACK,COL4_GREEN,COL4_BLUE,COL4_GREEN  ; Tile 8 = black for logo bg
;         dc.w    COL4_GREEN,COL4_WHITE,COL4_RED,COL4_RED
;         dc.w    COL4_CYAN,COL4_CYAN,COL4_RED,COL4_GREEN
;         dc.w    COL4_GREEN,COL4_GREEN,COL4_GREEN,COL4_GREEN
;         dc.w    COL4_CYAN,COL4_CYAN,COL4_RED,COL4_CYAN
;         dc.w    COL4_MAGENTA,COL4_RED,COL4_RED,COL4_BLACK

; Death animation color table (Spectrum kabum-style)
death_colors:
        dc.w    COL4_RED         ; 0: Initial death - red
        dc.w    COL4_YELLOW      ; 1: Explosion flash - yellow
        dc.w    COL4_WHITE       ; 2: Bright flash - white
        dc.w    COL4_MAGENTA     ; 3: Fade - magenta
        dc.w    COL4_CYAN        ; 4: Fade - cyan
        dc.w    COL4_BLUE        ; 5: Fade - blue
        dc.w    COL4_BLACK       ; 6: Final - black (disappear)

; Reflector direction lookup tables (indexed by current direction)
; TILE_REFLECT1 (\): UP→LEFT, DOWN→RIGHT, LEFT→UP, RIGHT→DOWN
reflect1_table:
        dc.w    DIR_STOP         ; 0: STOP → STOP
        dc.w    DIR_LEFT         ; 1: UP → LEFT
        dc.w    DIR_RIGHT        ; 2: DOWN → RIGHT
        dc.w    DIR_UP           ; 3: LEFT → UP
        dc.w    DIR_DOWN         ; 4: RIGHT → DOWN

; TILE_REFLECT2 (/): UP→RIGHT, DOWN→LEFT, LEFT→DOWN, RIGHT→UP
reflect2_table:
        dc.w    DIR_STOP         ; 0: STOP → STOP
        dc.w    DIR_RIGHT        ; 1: UP → RIGHT
        dc.w    DIR_LEFT         ; 2: DOWN → LEFT
        dc.w    DIR_DOWN         ; 3: LEFT → DOWN
        dc.w    DIR_UP           ; 4: RIGHT → UP

; Spike deadly direction table - indexed by (spike_tile - 2)
; Maps spike type to the direction that kills the hero
spike_deadly_dir:
        dc.b    DIR_DOWN         ; Spike UP (2) - kills hero moving DOWN
        dc.b    DIR_UP           ; Spike DN (3) - kills hero moving UP
        dc.b    DIR_LEFT         ; Spike R (4) - kills hero moving LEFT
        dc.b    DIR_RIGHT        ; Spike L (5) - kills hero moving RIGHT

; Compressed hero death sprite (1bpp, 8 bytes - solid block)
hero_death_sprite:
        dc.b    $00,$7E,$FF,$FF,$FF,$FF,$7E,$00

; Life icon sprites for HUD (8x8 pixels, 1bpp)
life_icon:
        dc.b    $00,$66,$FF,$FF,$FF,$7E,$3C,$18
life_empty:
        dc.b    $00,$66,$99,$81,$81,$42,$24,$18

; ============================================================
; HERO SPRITE OFFSET TABLES (PC-relative safe)
; Offsets from exp_hero_left_0 base (each sprite = 32 bytes)
; Index: (direction * 2 + anim) * 2 for walking (word offsets)
;        anim * 2 for flying
; ============================================================
hero_walk_offsets:
        ; DIR_STOP (0) - uses down sprites (offset 192, 224)
        dc.w    192,224
        ; DIR_UP (1) - offset 128, 160
        dc.w    128,160
        ; DIR_DOWN (2) - offset 192, 224
        dc.w    192,224
        ; DIR_LEFT (3) - offset 0, 32
        dc.w    0,32
        ; DIR_RIGHT (4) - offset 64, 96
        dc.w    64,96

hero_fly_offsets:
        ; fly_0: offset 256, fly_1: offset 288
        dc.w    256,288

; ============================================================
; HERO SPRITES
; ============================================================
exp_hero_left_0:
        dc.l    $283C0000,$2A3F0203,$00002233,$A0F0AAFF
        dc.l    $A2F32233,$22332A3F,$A2F32233,$A2F3AAFF
exp_hero_left_1:
        dc.l    $A0F00000,$A8FC0203,$000088CC,$A2F3A8FC
        dc.l    $88CC88CC,$080CA8FC,$88CC88CC,$8ACFA8FC
exp_hero_right_0:
        dc.l    $0000283C,$80C0A8FC,$88CC0000,$AAFF0A0F
        dc.l    $88CC8ACF,$A8FC88CC,$88CC8ACF,$AAFF8ACF
exp_hero_right_1:
        dc.l    $00000A0F,$80C02A3F,$22330000,$2A3F8ACF
        dc.l    $22332233,$2A3F2030,$22332233,$2A3FA2F3
exp_hero_up_0:
        dc.l    $02038ACF,$A2F3AAFF,$A0F00000,$2030AAFF
        dc.l    $02030203,$0A0FAAFF,$02032233,$2A3FAAFF
exp_hero_up_1:
        dc.l    $A2F38ACF,$A2F30000,$2030AAFF,$02030203
        dc.l    $0A0FAAFF,$02032233,$0A0FAAFF,$20300000
exp_hero_down_0:
        dc.l    $2A3FAAFF,$02032233,$0A0FAAFF,$02030203
        dc.l    $2030AAFF,$A0F00000,$A2F3AAFF,$02038ACF
exp_hero_down_1:
        dc.l    $20300000,$0A0FAAFF,$02032233,$0A0FAAFF
        dc.l    $02030203,$2030AAFF,$A2F30000,$A2F38ACF
exp_hero_fly_0:
        dc.l    $00000000,$2A3FA8FC,$AAFFAAFF,$AAFFAAFF
        dc.l    $AAFFAAFF,$AAFFAAFF,$2A3FA8FC,$00000000
exp_hero_fly_1:
        dc.l    $0A0FA0F0,$2A3FA8FC,$2A3FA8FC,$2A3FA8FC
        dc.l    $2A3FA8FC,$2A3FA8FC,$2A3FA8FC,$0A0FA0F0

; Hero exit animation sprites - dissolve effect
; Based on Spectrum frames 16-17 blob patterns
; 7 frames: full blob -> smaller -> dots -> nothing
exp_hero_exit_sprites:
; Frame 0: Full blob ($7E pattern = 6 pixels wide, 6 rows)
exp_hero_exit_0:
        dc.l    $00000000,$2A3FA8FC,$AAFFAAFF,$AAFFAAFF
        dc.l    $AAFFAAFF,$AAFFAAFF,$2A3FA8FC,$00000000
; Frame 1: Slightly smaller blob
exp_hero_exit_1:
        dc.l    $00000000,$0A0FA0F0,$2A3FA8FC,$AAFFAAFF
        dc.l    $AAFFAAFF,$2A3FA8FC,$0A0FA0F0,$00000000
; Frame 2: Medium blob (4 pixels wide, 4 rows)
exp_hero_exit_2:
        dc.l    $00000000,$00000000,$0A0FA0F0,$2A3FA8FC
        dc.l    $2A3FA8FC,$0A0FA0F0,$00000000,$00000000
; Frame 3: Small blob (centered)
exp_hero_exit_3:
        dc.l    $00000000,$00000000,$00000000,$0A0FA0F0
        dc.l    $0A0FA0F0,$00000000,$00000000,$00000000
; Frame 4: Tiny dots (2 pixels)
exp_hero_exit_4:
        dc.l    $00000000,$00000000,$00000000,$000380C0
        dc.l    $000380C0,$00000000,$00000000,$00000000
; Frame 5: Single dot
exp_hero_exit_5:
        dc.l    $00000000,$00000000,$00000000,$00000000
        dc.l    $000380C0,$00000000,$00000000,$00000000
; Frame 6: Empty (animation complete)
exp_hero_exit_6:
        dc.l    $00000000,$00000000,$00000000,$00000000
        dc.l    $00000000,$00000000,$00000000,$00000000
HERO_EXIT_FRAMES equ 7

; Trail sprites - Accurate Spectrum reproduction
; Spectrum analysis:
;   Vertical FULL (tile 24): $3C = 4px wide, 8 rows
;   Vertical FADE (tiles 20,19,18): $18 = 2px wide, 7/5/2 rows
;   Horizontal FULL (tile 31): 4 middle rows, full width
;   Horizontal FADE (tiles 27,26,25): 2 middle rows, shrinking width
; QL patterns:
;   WIDE vertical: $0203F0F0 (~4 pixels)
;   THIN vertical: $000380C0 (~2 pixels, centered)
;   WIDE horiz: 4 rows (2-5), full width
;   THIN horiz: 2 rows (3-4), partial width
exp_trail_sprites:
; Sprite 0 (DOWN fade): THIN, 2 bottom rows (like tile 18)
        dc.l    $00000000,$00000000,$00000000,$00000000
        dc.l    $00000000,$00000000,$000380C0,$000380C0
; Sprite 1 (DOWN mid): THIN, 5 bottom rows (like tile 19)
        dc.l    $00000000,$00000000,$00000000,$000380C0
        dc.l    $000380C0,$000380C0,$000380C0,$000380C0
; Sprite 2 (DOWN full): WIDE, 8 rows (like tile 24)
        dc.l    $0203F0F0,$0203F0F0,$0203F0F0,$0203F0F0
        dc.l    $0203F0F0,$0203F0F0,$0203F0F0,$0203F0F0
; Sprite 3 (UP fade): THIN, 2 top rows (like tile 21)
        dc.l    $000380C0,$000380C0,$00000000,$00000000
        dc.l    $00000000,$00000000,$00000000,$00000000
; Sprite 4 (UP mid): THIN, 5 top rows (like tile 22)
        dc.l    $000380C0,$000380C0,$000380C0,$000380C0
        dc.l    $000380C0,$00000000,$00000000,$00000000
; Sprite 5 (UP full): WIDE, 8 rows (like tile 24)
        dc.l    $0203F0F0,$0203F0F0,$0203F0F0,$0203F0F0
        dc.l    $0203F0F0,$0203F0F0,$0203F0F0,$0203F0F0
; Sprite 6 (transition): WIDE full column
        dc.l    $0203F0F0,$0203F0F0,$0203F0F0,$0203F0F0
        dc.l    $0203F0F0,$0203F0F0,$0203F0F0,$0203F0F0
; Sprite 7 (LEFT fade): 2 middle rows, short bar (like tile 25: $C0)
        dc.l    $00000000,$00000000,$00000000,$80C00000
        dc.l    $80C00000,$00000000,$00000000,$00000000
; Sprite 8 (LEFT mid): 2 middle rows, medium bar (like tile 26: $F8)
        dc.l    $00000000,$00000000,$00000000,$AAF80000
        dc.l    $AAF80000,$00000000,$00000000,$00000000
; Sprite 9 (LEFT full): 4 middle rows, full width bar (all 8 pixels)
        dc.l    $00000000,$00000000,$AAFFAAFF,$AAFFAAFF
        dc.l    $AAFFAAFF,$AAFFAAFF,$00000000,$00000000
; Sprite 10 (RIGHT fade): 2 middle rows, short bar (like tile 28: $03)
        dc.l    $00000000,$00000000,$00000000,$00000203
        dc.l    $00000203,$00000000,$00000000,$00000000
; Sprite 11 (RIGHT mid): 2 middle rows, medium bar (like tile 29: $1F)
        dc.l    $00000000,$00000000,$00000000,$00002AFF
        dc.l    $00002AFF,$00000000,$00000000,$00000000
; Sprite 12 (RIGHT full): 4 middle rows, full width bar (all 8 pixels)
        dc.l    $00000000,$00000000,$AAFFAAFF,$AAFFAAFF
        dc.l    $AAFFAAFF,$AAFFAAFF,$00000000,$00000000
; Sprite 13 (extra): centered block
        dc.l    $00000000,$00000000,$AAFFAAFF,$AAFFAAFF
        dc.l    $AAFFAAFF,$AAFFAAFF,$00000000,$00000000

; ============================================================
; Bat enemy sprites (8 frames: 4 right, 4 left)
; Each sprite is 16 pixels wide x 8 rows = 64 bytes
; Frames have built-in X offsets (0,2,4,6 pixels) for smooth animation
; OPT: Contiguous layout for table lookup (index * 64)
; ============================================================
exp_bat_sprites:                     ; Base for table lookup
exp_bat_right_0:                     ; Index 0
        dc.l    $82C3080C,$20300000  ; Frame 0: leftmost position
        dc.l    $82C3A8FC,$20300000
        dc.l    $2A3F2233,$80C00000
        dc.l    $2A3F2233,$80C00000
        dc.l    $0A0FAAFF,$00000000
        dc.l    $0A0FAAFF,$00000000
        dc.l    $0203080C,$00000000
        dc.l    $00000000,$00000000
exp_bat_right_1:                     ; Index 1
        dc.l    $00002030,$80C00000  ; Frame 1: +2 pixels
        dc.l    $02032A3F,$88CC0000
        dc.l    $0A0FAAFF,$AAFF0000
        dc.l    $0203A2F3,$283C0000
        dc.l    $0000AAFF,$A0F00000
        dc.l    $0000AAFF,$A0F00000
        dc.l    $00002030,$80C00000
        dc.l    $00000000,$00000000
exp_bat_right_2:                     ; Index 2
        dc.l    $00000000,$00000000  ; Frame 2: +4 pixels
        dc.l    $00000203,$080C0000
        dc.l    $00000203,$A8FC0000
        dc.l    $00002A3F,$AAFF80C0
        dc.l    $0000AAFF,$2233A0F0
        dc.l    $00000A0F,$AAFF0000
        dc.l    $00000A0F,$AAFF0000
        dc.l    $00000203,$A8FC0000
exp_bat_right_3:                     ; Index 3
        dc.l    $00000000,$00000000  ; Frame 3: +6 pixels
        dc.l    $00000000,$203080C0
        dc.l    $00000000,$2A3F80C0
        dc.l    $00000000,$AAFFA0F0
        dc.l    $00000203,$A2F3283C
        dc.l    $00000203,$AAFFA8FC
        dc.l    $00000A0F,$AAFFAAFF
        dc.l    $0000080C,$8ACF2233
exp_bat_left_0:                      ; Index 4
        dc.l    $0000080C,$203082C3  ; Frame 0: rightmost position
        dc.l    $0000080C,$2A3F82C3
        dc.l    $00000203,$88CCA8FC
        dc.l    $00000203,$88CCA8FC
        dc.l    $00000000,$AAFFA0F0
        dc.l    $00000000,$AAFFA0F0
        dc.l    $00000000,$203080C0
        dc.l    $00000000,$00000000
exp_bat_left_1:                      ; Index 5
        dc.l    $00000203,$080C0000  ; Frame 1: -2 pixels
        dc.l    $00002233,$A8FC80C0
        dc.l    $0000A8FC,$8ACFA0F0
        dc.l    $0000283C,$8ACF80C0
        dc.l    $00000A0F,$AAFF0000
        dc.l    $00000A0F,$AAFF0000
        dc.l    $00000203,$080C0000
        dc.l    $00000000,$00000000
exp_bat_left_2:                      ; Index 6
        dc.l    $00000000,$00000000  ; Frame 2: -4 pixels
        dc.l    $00002030,$80C00000
        dc.l    $00002A3F,$80C00000
        dc.l    $0203AAFF,$A8FC0000
        dc.l    $0A0F88CC,$AAFF0000
        dc.l    $0000AAFF,$A0F00000
        dc.l    $0000AAFF,$A0F00000
        dc.l    $00002A3F,$80C00000
exp_bat_left_3:                      ; Index 7
        dc.l    $00000000,$00000000  ; Frame 3: -6 pixels (leftmost)
        dc.l    $0203080C,$00000000
        dc.l    $0203A8FC,$00000000
        dc.l    $0A0FAAFF,$00000000
        dc.l    $283C8ACF,$80C00000
        dc.l    $2A3FAAFF,$80C00000
        dc.l    $AAFFAAFF,$A0F00000
        dc.l    $88CCA2F3,$20300000

; Trail animations: 7 frames (Spectrum-accurate: 4 hold + 3 fade)
trail_anim_down:
        dc.b    2,2,2,2,1,1,0,TRAIL_IDX_END
trail_anim_up:
        dc.b    5,5,5,5,4,4,3,TRAIL_IDX_END
trail_anim_left:
        dc.b    9,9,9,9,8,8,7,TRAIL_IDX_END
trail_anim_right:
        dc.b    12,12,12,12,11,11,10,TRAIL_IDX_END

        even

; ============================================================
; COLUMN BRICK PATTERNS (8 rows × 4 bytes = 32 bytes each)
; Left column: dither on left, brick on right
; Right column: Y-axis mirrored (brick on left, dither on right)
; MODE 8 encoding: word low byte = 4 pixels × 2 bits each
; ============================================================
col_brick_pattern:                      ; LEFT COLUMN
        dc.l    $00000000               ; Row 0: BBBBBBBB - black mortar
        dc.l    $00CC00AA               ; Row 1: MBMBRRRR - magenta dither + red brick
        dc.l    $003C00AA               ; Row 2: BMMBRRRR - alt dither + red brick
        dc.l    $00CC00AA               ; Row 3: MBMBRRRR - magenta dither + red brick
        dc.l    $00000000               ; Row 4: BBBBBBBB - black mortar
        dc.l    $0033002A               ; Row 5: BMBMBRRR - offset dither + red brick
        dc.l    $00CF002A               ; Row 6: MBMMBRRR - alt dither + red brick
        dc.l    $0033002A               ; Row 7: BMBMBRRR - offset dither + red brick

col_brick_pattern_mirror:               ; RIGHT COLUMN (Y-axis mirrored)
        dc.l    $00000000               ; Row 0: BBBBBBBB - black mortar
        dc.l    $00AA0033               ; Row 1: RRRRBMBM - red brick + magenta dither
        dc.l    $00AA003C               ; Row 2: RRRRBMMB - red brick + alt dither
        dc.l    $00AA0033               ; Row 3: RRRRBMBM - red brick + magenta dither
        dc.l    $00000000               ; Row 4: BBBBBBBB - black mortar
        dc.l    $00A800CC               ; Row 5: RRRBMBMB - red brick + offset dither
        dc.l    $00A800F3               ; Row 6: RRRBMMBM - red brick + alt dither
        dc.l    $00A800CC               ; Row 7: RRRBMBMB - red brick + offset dither

; World 2 (levels 16+): MAGENTA columns with blue dither
col_pattern_world2:                     ; LEFT COLUMN
        dc.l    $00000000               ; Row 0: black mortar
        dc.l    $004400FF               ; Row 1: blue dither + magenta brick
        dc.l    $001400FF               ; Row 2: blue dither + magenta brick
        dc.l    $004400FF               ; Row 3: blue dither + magenta brick
        dc.l    $00000000               ; Row 4: black mortar
        dc.l    $0011003F               ; Row 5: blue dither + partial magenta
        dc.l    $0045003F               ; Row 6: blue dither + partial magenta
        dc.l    $0011003F               ; Row 7: blue dither + partial magenta

col_pattern_world2_mirror:              ; RIGHT COLUMN
        dc.l    $00000000               ; Row 0: black mortar
        dc.l    $00FF0011               ; Row 1: magenta brick + blue dither
        dc.l    $00FF0014               ; Row 2: magenta brick + blue dither
        dc.l    $00FF0011               ; Row 3: magenta brick + blue dither
        dc.l    $00000000               ; Row 4: black mortar
        dc.l    $00FC0044               ; Row 5: partial magenta + blue dither
        dc.l    $00FC0051               ; Row 6: partial magenta + blue dither
        dc.l    $00FC0044               ; Row 7: partial magenta + blue dither

; World 3 (levels 11-15): CYAN columns with green dither
col_pattern_world3:                     ; LEFT COLUMN
        dc.l    $00000000               ; Row 0: black mortar
        dc.l    $8800AA55               ; Row 1: green dither + cyan brick
        dc.l    $2800AA55               ; Row 2: green dither + cyan brick
        dc.l    $8800AA55               ; Row 3: green dither + cyan brick
        dc.l    $00000000               ; Row 4: black mortar
        dc.l    $22002A15               ; Row 5: green dither + partial cyan
        dc.l    $8A002A15               ; Row 6: green dither + partial cyan
        dc.l    $22002A15               ; Row 7: green dither + partial cyan

col_pattern_world3_mirror:              ; RIGHT COLUMN
        dc.l    $00000000               ; Row 0: black mortar
        dc.l    $AA552200               ; Row 1: cyan brick + green dither
        dc.l    $AA552800               ; Row 2: cyan brick + green dither
        dc.l    $AA552200               ; Row 3: cyan brick + green dither
        dc.l    $00000000               ; Row 4: black mortar
        dc.l    $A8548800               ; Row 5: partial cyan + green dither
        dc.l    $A854A200               ; Row 6: partial cyan + green dither
        dc.l    $A8548800               ; Row 7: partial cyan + green dither

; ============================================================
; GAME NAME LOGO (from Spectrum gameName.bin)
; 64 pixels wide x 32 rows, 1bpp format
; ============================================================
gameName_1bpp:
        dc.b    $00,$00,$0e,$c3,$01,$b8,$00,$00  ; Row 0
        dc.b    $00,$00,$1f,$e7,$03,$fc,$00,$00  ; Row 1
        dc.b    $00,$00,$3f,$ef,$03,$fc,$00,$00  ; Row 2
        dc.b    $00,$00,$79,$ef,$03,$ce,$00,$00  ; Row 3
        dc.b    $00,$00,$79,$cf,$01,$cf,$00,$00  ; Row 4
        dc.b    $00,$00,$79,$ef,$03,$cf,$00,$00  ; Row 5
        dc.b    $00,$00,$f1,$ef,$03,$cf,$00,$00  ; Row 6
        dc.b    $00,$00,$79,$ef,$83,$cf,$00,$00  ; Row 7
        dc.b    $00,$00,$f9,$ef,$03,$cf,$00,$00  ; Row 8
        dc.b    $00,$00,$79,$ef,$03,$cf,$00,$00  ; Row 9
        dc.b    $00,$00,$39,$ef,$03,$cf,$00,$00  ; Row 10
        dc.b    $00,$00,$79,$ef,$03,$cf,$08,$00  ; Row 11
        dc.b    $00,$00,$7f,$cf,$fb,$fe,$00,$00  ; Row 12
        dc.b    $00,$00,$7f,$8f,$f9,$fc,$08,$00  ; Row 13
        dc.b    $08,$00,$3f,$0f,$ea,$f0,$0c,$00  ; Row 14
        dc.b    $3f,$70,$80,$20,$00,$07,$6f,$e0  ; Row 15
        dc.b    $3f,$f1,$fe,$f3,$c7,$7f,$ef,$f8  ; Row 16
        dc.b    $3f,$f3,$fe,$f7,$cf,$7f,$ef,$fc  ; Row 17
        dc.b    $37,$87,$9e,$73,$cf,$7a,$0f,$3c  ; Row 18
        dc.b    $27,$87,$8e,$f3,$cf,$78,$0f,$3c  ; Row 19
        dc.b    $07,$8f,$9e,$f3,$8f,$78,$0f,$3c  ; Row 20
        dc.b    $27,$87,$9e,$f3,$cf,$7e,$0f,$fc  ; Row 21
        dc.b    $0f,$87,$9e,$f3,$cf,$7c,$0f,$fc  ; Row 22
        dc.b    $07,$87,$9e,$f3,$ce,$7e,$0f,$f0  ; Row 23
        dc.b    $07,$87,$1e,$f3,$ff,$78,$0f,$78  ; Row 24
        dc.b    $03,$87,$9e,$e3,$ff,$70,$0f,$3c  ; Row 25
        dc.b    $07,$87,$9e,$f3,$ff,$78,$0f,$3c  ; Row 26
        dc.b    $07,$87,$fc,$ff,$88,$7f,$cf,$3c  ; Row 27
        dc.b    $07,$87,$f8,$ff,$00,$7f,$af,$3c  ; Row 28
        dc.b    $07,$87,$b0,$fe,$00,$3f,$6f,$3c  ; Row 29
        dc.b    $07,$06,$00,$c0,$00,$20,$0c,$3c  ; Row 30
        dc.b    $06,$84,$00,$80,$00,$00,$08,$3c  ; Row 31

; ============================================================
; PRE-EXPANDED 4BPP TILES (QL MODE 8 format)
; Each tile is 32 bytes (8 rows x 4 bytes)
; Generated from tiles_1bpp + tile_colors
; ============================================================
tiles_4bpp:
; Tile 0 - background with dots (BLUE)
        dc.l    $00000000,$00100000,$00000000,$00000000
        dc.l    $00000000,$00000000,$00000004,$00000000
; Tile 1 - HIDDEN/crumbling (BLUE)
        dc.l    $88888888,$00440044
        dc.l    $80800808,$00400004
        dc.l    $80800808,$00400004
        dc.l    $88888888,$00440044
; Tile 2 - SPIKE_UP (CYAN)
        dc.l    $00000000,$00000000,$00000000,$00000000
        dc.l    $08042010,$08042010,$2814A050,$00140050
; Tile 3 - SPIKE_DN (CYAN)
        dc.l    $283CA0F0,$2814A050,$08042010,$08042010
        dc.l    $08042010,$00000000,$00000000,$00000000
; Tile 4 - SPIKE_R (CYAN)
        dc.l    $00000000,$20100000,$2A150000,$00150000
        dc.l    $20100000,$2A150000,$00150000,$00000000
; Tile 5 - SPIKE_L (CYAN)
        dc.l    $00000000,$00000804,$0000A854,$00000054
        dc.l    $00000804,$0000A854,$00000054,$0000000
; Tile 6 - small coin (YELLOW)
        dc.l    $00000000,$00000000,$00000000,$02028080
        dc.l    $02028080,$00010040,$00000000,$00000000
; Tile 7 - large coin (YELLOW)
        dc.l    $00000000,$0A0AA0B0,$2020080C,$222288C8
        dc.l    $22228888,$20200808,$0A0AA0A0,$00000000
; Tile 8 - TILE_BLACK (pure black)
        dc.l    $00000000,$00000000,$00000000,$00000000
        dc.l    $00000000,$00000000,$00000000,$00000000
; Tile 9 (GREEN)
        dc.l    $00000000,$00000000,$00000000,$00000000
        dc.l    $00000000,$02000000,$80000800,$8A002A00
; Tile 10 (BLUE)
        dc.l    $00440044,$00000000,$00010000,$00000000
        dc.l    $00110011,$00000000,$00000004,$00000000
; Tile 11 - ladder left (GREEN)
        dc.l    $00000200,$00000A00,$00000200,$00000000
        dc.l    $00000000,$00000200,$00002200,$00000000
; Tile 12 - ladder right (GREEN)
        dc.l    $80000000,$A0000000,$80000000,$00000000
        dc.l    $00000000,$80000000,$88000000,$00000000
; Tile 13 - exit (BLUE)
        dc.l    $00550055,$00400001,$00400001,$00400001
        dc.l    $00400001,$00400001,$00400001,$00550055
; Tile 14 - one-way down (RED)
        dc.l    $00550055,$00000080,$000200A0,$000A00A8
        dc.l    $002A00AA,$00000000,$000300F0,$000300F0
; Tile 15 - one-way up (RED)
        dc.l    $00000000,$000300F0,$000300F0,$00000000
        dc.l    $002A00AA,$000A00A8,$000200A0,$00550095
; Tile 16 - reflector \ (CYAN)
        dc.l    $A0F00000,$88CC0000,$2A150000,$0A058040
        dc.l    $0201A050,$0000A854,$00002233,$00000A0F
; Tile 17 - reflector / (CYAN)
        dc.l    $00000A0F,$00002233,$0000A854,$0201A050
        dc.l    $0A058040,$2A150000,$88CC0000,$A0F00000
; Tile 18 - hero down (RED)
        dc.l    $002A00AA,$00020028,$002200AA,$00020002
        dc.l    $002000AA,$00A00000,$00A200AA,$000A008A
; Tile 19 - hero up (GREEN)
        dc.l    $02008A00,$A200AA00,$A0000000,$2000AA00
        dc.l    $02000200,$2200AA00,$02002800,$2A00AA00
; Tile 20 - hero left (GREEN)
        dc.l    $28000000,$2A000200,$00002200,$A000AA00
        dc.l    $A2002200,$22002A00,$A2002200,$A200AA00
; Tile 21 - hero right (GREEN)
        dc.l    $00002800,$8000A800,$88000000,$AA000A00
        dc.l    $88008A00,$A8008800,$88008A00,$AA008A00
; Tile 22 - cannon right closed (GREEN)
        dc.l    $A2F3AAFF,$826902A9,$A2592289,$82410201
        dc.l    $A251AA55,$82410000,$A2000000,$82002A00
; Tile 23 - cannon left closed (GREEN)
        dc.l    $AAFF8ACF,$806A8269,$88628A65,$80408241
        dc.l    $AA558A45,$00008241,$00008A00,$A8008200
; Tile 24 - cannon right open (CYAN)
        dc.l    $A2F3AAFF,$826902A9
        dc.l    $A2592299,$82410201
        dc.l    $A251AA55,$82410000
        dc.l    $A2002A00,$80000000
; Tile 25 - cannon left open (CYAN)
        dc.l    $AAFF8ACF,$806A8269
        dc.l    $88668A65,$80408241
        dc.l    $AA558A45,$00008241
        dc.l    $A8008A00,$00000200
; Tile 26 - bounce (RED)
        dc.l    $00000080,$005600A5
        dc.l    $005F00FD,$00550055
        dc.l    $00550055,$005F00FD
        dc.l    $005600A5,$00000080
; Tile 27 - crack (CYAN)
        dc.l    $88998899,$00550055
        dc.l    $80D5085D,$00550055
        dc.l    $80D5085D,$00550055
        dc.l    $88558855,$00000000
; Tile 28 - UNHIDDEN/solid (MAGENTA)
        dc.l    $00FF00FC,$00CF00CC
        dc.l    $00FF00FC,$00FF00FC
        dc.l    $00FF00FC,$008A0088
        dc.l    $00AA00A8,$00550054
; Tile 29 - SOLID_1 (RED) - blocks1 brick pattern for levels 1-10
; 1bpp: $00,$F7,$F7,$F7,$00,$BF,$BF,$00
; Tile 29 - SOLID_1
        dc.l    $00000000,$00AA002A,$00AA80AA,$00AA002A
        dc.l    $00000000,$009A00AA,$008A00AA,$00550055
; Tile 30 - SOLID_2 (RED) - blocks1 brick pattern for levels 1-10
; 1bpp: $00,$F7,$F7,$F7,$00,$BF,$BF,$BF
; Tile 30 - SOLID_2
        dc.l    $00000000,$00AA002A
        dc.l    $00AA80AA,$00AA002A
        dc.l    $00000000,$008A00AA
        dc.l    $20AA00AA,$008A00AA
; Tile 31 - HERO_START (BLACK)
        dc.l    $00000000,$00000000,$00000000,$00000000
        dc.l    $00000000,$00000000,$00000000,$00000000

; ============================================================
; WORLD-SPECIFIC BLOCK TILES (pre-expanded 4bpp)
; These are copied to expanded_tiles at tiles 29-30 based on level
; ============================================================

; blocks1_tiles - Levels 1-10: Brick wall with offset rows
; 1bpp Tile 29: $00,$F7,$F7,$F7,$00,$BF,$BF,$00
; 1bpp Tile 30: $00,$F7,$F7,$F7,$00,$BF,$BF,$BF
blocks1_tiles:
        ; Tile 29 - blocks1
        dc.l    $00000000,$00AA002A,$00AA80AA,$00AA002A
        dc.l    $00000000,$009A00AA,$008A00AA,$00550055
        ; Tile 30 - blocks1
        dc.l    $00000000,$00AA002A
        dc.l    $00AA80AA,$00AA002A
        dc.l    $00000000,$008A00AA
        dc.l    $20AA00AA,$008A00AA

; blocks2_tiles - Levels 16+: Diagonal pattern
; 1bpp Tile 29: $00,$7E,$7C,$7A,$00,$3C,$38,$34
; 1bpp Tile 30: $00,$70,$F7,$77,$F7,$67,$D6,$05
blocks2_tiles:
        ; Tile 29 - blocks2
        dc.l    $00000000,$003F00FC
        dc.l    $003F00F0,$003F00CC
        dc.l    $00550055,$000F00F0
        dc.l    $000A0080,$000A0020
        ; Tile 30 - blocks2
        dc.l    $00000000,$002A0000
        dc.l    $00AA002A,$003F003F
        dc.l    $00FF003F,$003C003F
        dc.l    $00F7007D,$00000033
; blocks3_tiles - Levels 11-15: Different brick pattern
; 1bpp Tile 29: $0E,$EA,$E0,$EE,$EA,$0E,$E0,$00
; 1bpp Tile 30: $FA,$EC,$7E,$BA,$7C,$BE,$56,$00
blocks3_tiles:
        ; Tile 29 - blocks3
        dc.l    $0000A8FC,$A8548844
        dc.l    $A8FC0000,$A855A855
        dc.l    $A8558855,$0000A854
        dc.l    $A8FC0000,$00000000
        ; Tile 30 - blocks3
        dc.l    $AAFF88DD,$A8FDA0F5
        dc.l    $2A7FA8FD,$8ADF88DD
        dc.l    $2A7FA0F5,$8ADFA8FD
        dc.l    $22FF28FF,$00000000

; ============================================================
; ALL LEVEL DATA
; Levels stored contiguously so we can calculate addresses:
;   level_addr = level00 + (level_index * LEVEL_SIZE)
; ============================================================
        include "levels_compressed.inc"

        even

; ============================================================
; VARIABLES
; ============================================================
level_data_ptr:  dc.l 0         ; Stored base address for writes
current_level:   dc.w 0         ; Current level index (0-20)
coin_count:      dc.w 0         ; Collected coins this level
coins_total:     dc.w 0         ; Total coins in level (for exit activation)
level_complete_flag: dc.w 0    ; Set by process_tile_effects when on active exit
heroes_exited:   dc.w 0         ; Bitmask: bit 0 = hero 0 exited, bit 1 = hero 1 exited

; Hero exit animation
hero_exit_active: dc.w 0        ; Flag: exit animation is playing
hero_exit_frame:  dc.w 0        ; Current animation frame (0-6)
hero_exit_delay:  dc.w 0        ; Delay counter between frames
hero_exit_x:      dc.w 0        ; X position of exiting hero (grid)
hero_exit_y:      dc.w 0        ; Y position of exiting hero (grid)
hero_exit_hero_id: dc.w 0       ; Which hero is exiting (0 or 1)
HERO_EXIT_ANIM_SPEED equ 4      ; Frames between animation updates

game_state:      dc.w GS_GAMEPLAY  ; Current game state
win_flash_ctr:   dc.w 0         ; Counter for "PRESS SPACE" flash
; Title screen variables
title_flash_ctr:   dc.w 0       ; Counter for "PUSH FIRE" flash
title_text_visible: dc.w 1      ; 1 = text visible, 0 = hidden
; Outro bounce animation variables
outro_bounce_idx:   dc.w 0      ; Current index into bounce table (0-7)
outro_bounce_frame: dc.w 0      ; Frame counter for bounce speed
outro_count:        dc.w 0      ; Delay counter before accepting input
coin_anim_frame: dc.w 0         ; Current coin animation frame (0-3)
coin_anim_ctr:   dc.w 1         ; Frames until next update (1=update now)
; Coin position cache (for fast animation refresh)
num_cached_coins: dc.w 0        ; Number of large coins in cache
coin_cache:      ds.b MAX_COINS*2  ; x,y pairs (1 byte each) - $FF,$FF = collected

; Exit animation
exit_anim_frame: dc.w 0         ; Current exit color frame (0-3)
exit_anim_ctr:   dc.w 1         ; Frames until next update
num_cached_exits: dc.w 0        ; Number of exit tiles in cache
exit_cache:      ds.b MAX_EXITS*2  ; y,x pairs (1 byte each)
hero_x:          dc.w 5
hero_y:          dc.w 60
hero_dir:        dc.w DIR_STOP
hero_hit_spike:  dc.w 0               ; Set by is_solid_for_hero when deadly spike hit
hero_last_dir:   dc.w DIR_DOWN
hero_fly:        dc.w 0
hero_land_dir:   dc.w 0               ; Direction hero was moving when stopped (for crack check)
hero_bounce_dir: dc.w 0               ; Direction to bounce (set by is_solid_for_hero)
anim_frame:      dc.w 0
anim_counter:    dc.w 4
quit_flag:       dc.w 0
reset_level_flag: dc.w 0              ; R key level reset flag
active_trails:   dc.w 0
lives:           dc.w 5             ; Player lives (start with 5)
prev_lives:      dc.w -1            ; Previous lives value for caching (-1 = force redraw)
death_anim_count: dc.w 0            ; Death animation frame counter
death_screen_ptr: dc.l 0            ; Screen address for death sprite

; Frame drop detection
prev_tick:       dc.w 0             ; Previous frame's tick counter value

; Frame pacer mode (0=adaptive, 1=forced 25fps)
frame_pacer_mode: dc.w 0

; Frame overrun flag (for pacer sampling without red pixel)
frame_overrun:   dc.w 0

; QSound SFX function pointers (set by sfx_setup_ptrs at startup)
sfx_update_ptr:    dc.l 0           ; Absolute address of sfx_update
qsound_init_ptr:   dc.l 0           ; Absolute address of qsound_init
ay_silence_ptr:    dc.l 0           ; Absolute address of ay_silence
sound_to_play_ptr: dc.l 0           ; Absolute address of sound_to_play
runtime_base_ptr:  dc.l 0           ; Runtime base address (start of binary)

; Multi-hero system variables
num_heroes:      dc.w 1             ; Number of heroes in current level
level_has_hero2: dc.w 0             ; Flag: 1 if level has 2+ heroes (optimization)
active_hero:     dc.w 0             ; Index of currently controlled hero (0 or 1)
hero_slots:                         ; Hero slot array (18 bytes per hero)
        ds.b    MAX_HEROES*HERO_SLOT_SIZE
hero2_buf_addr:  dc.l 0             ; Buffer address where hero 2 was drawn
hero2_buf_save:  ds.b 32            ; Saved background for hero 2

; Camera variables (pixel-based smooth scrolling)
cam_focus_y:     dc.w 0             ; Camera focus position in pixels
window_y:        dc.w 0             ; Visible window offset in pixels
hero_last_y:     dc.w 0             ; Hero Y from previous frame (for camera lag)
col_pattern_ptr:        dc.l 0     ; Pointer to current world's left column pattern
col_pattern_mirror_ptr: dc.l 0     ; Pointer to current world's right column pattern

hero_drawn_x:    dc.w -1
hero_drawn_y:    dc.w 0
hero_drawn_anim: dc.w 0
hero_drawn_fly:  dc.w 0
hero_drawn_scroll: dc.w 0

; Compositing variables for flicker-free hero
hero_buf_addr:   dc.l 0             ; Buffer address where hero was drawn
hero_buf_save:   ds.b 32            ; Saved background (8 longwords)

; Enemy variables
num_enemies:     dc.w 0             ; Active enemy count
; Enemy slot structure (12 bytes each):
;   +0: active (word) - 0=inactive
;   +2: x (word) - tile X coordinate
;   +4: y (word) - tile Y coordinate
;   +6: dir (word) - ENEMY_LEFT or ENEMY_RIGHT
;   +8: frame (word) - animation frame 0-3
;   +10: delay (word) - per-enemy animation delay counter
enemy_slots:
        ds.b    MAX_ENEMIES*ENEMY_SLOT_SIZE

; Compositing data for enemies (64 bytes save area per enemy)
enemy_buf_addrs: ds.l MAX_ENEMIES   ; Buffer addresses where enemies drawn
enemy_buf_saves: ds.b MAX_ENEMIES*64 ; Saved backgrounds (8 bytes x 8 rows each)

; Enemy starting positions (for restart after death)
; Structure: x (word), y (word), dir (word) = 6 bytes each
enemy_start_data:
        ds.b    MAX_ENEMIES*6
num_enemies_start: dc.w 0           ; Enemy count at level start

; Cannon variables
cannon_count:    dc.w 0              ; Number of cannons on level
cannon_list:
        ds.b    MAX_CANNONS*CANNON_SIZE  ; 8 * 10 = 80 bytes

; Bullet variables
bullet_count:    dc.w 0              ; Number of active bullets
bullet_list:
        ds.b    MAX_BULLETS*BULLET_SIZE  ; 2 * 8 = 16 bytes

; Bullet compositing data (for buffer save/restore)
bullet_buf_addrs: ds.l MAX_BULLETS   ; Buffer addresses where bullets drawn
bullet_buf_saves: ds.b MAX_BULLETS*8 ; Saved backgrounds (2 rows × 4 bytes each)

trail_slots:
        ds.b    NUM_TRAIL_SLOTS*TRAIL_SLOT_SIZE

; Trail compositing save data (for buffer save/restore)
trail_buf_addrs: ds.l NUM_TRAIL_SLOTS   ; Buffer addresses where trails drawn
trail_buf_saves: ds.b NUM_TRAIL_SLOTS*32 ; Saved backgrounds (8 longwords each)

; ============================================================
; Pre-expanded coin animation frames (MODE 8 format)
; 4 frames × 32 bytes each = 128 bytes
; Each frame: 8 rows × 4 bytes (2 words per row, ANDed with COL4_YELLOW)
; ============================================================
coin_exp_frames:
; Frame 0 - Full coin (from B10: $00,$18,$24,$2C,$2C,$24,$18,$00)
        dc.l    $00000000       ; Row 0: $00
        dc.l    $02028080       ; Row 1: $18
        dc.l    $08082020       ; Row 2: $24
        dc.l    $0808A0A0       ; Row 3: $2C
        dc.l    $0808A0A0       ; Row 4: $2C
        dc.l    $08082020       ; Row 5: $24
        dc.l    $02028080       ; Row 6: $18
        dc.l    $00000000       ; Row 7: $00
; Frame 1 - Thin/edge-on (from B10: $00,$18,$18,$18,$18,$18,$18,$00)
        dc.l    $00000000       ; Row 0: $00
        dc.l    $02028080       ; Row 1: $18
        dc.l    $02028080       ; Row 2: $18
        dc.l    $02028080       ; Row 3: $18
        dc.l    $02028080       ; Row 4: $18
        dc.l    $02028080       ; Row 5: $18
        dc.l    $02028080       ; Row 6: $18
        dc.l    $00000000       ; Row 7: $00
; Frame 2 - Full coin alt (from B10: $00,$18,$24,$34,$34,$24,$18,$00)
        dc.l    $00000000       ; Row 0: $00
        dc.l    $02028080       ; Row 1: $18
        dc.l    $08082020       ; Row 2: $24
        dc.l    $0A0A2020       ; Row 3: $34 (nibble 3=$0A0A, nibble 4=$2020)
        dc.l    $0A0A2020       ; Row 4: $34
        dc.l    $08082020       ; Row 5: $24
        dc.l    $02028080       ; Row 6: $18
        dc.l    $00000000       ; Row 7: $00
; Frame 3 - Larger coin (from B10: $00,$3C,$42,$5A,$5A,$42,$3C,$00)
        dc.l    $00000000       ; Row 0: $00
        dc.l    $0A0AA0A0       ; Row 1: $3C (nibble 3=$0A0A, nibble C=$A0A0)
        dc.l    $20200808       ; Row 2: $42
        dc.l    $22228888       ; Row 3: $5A
        dc.l    $22228888       ; Row 4: $5A
        dc.l    $20200808       ; Row 5: $42
        dc.l    $0A0AA0A0       ; Row 6: $3C
        dc.l    $00000000       ; Row 7: $00

; Exit animation frames (color cycling when exits active)
; Exit tile shape: $FF,$81,$81,$81,$81,$81,$81,$FF (hollow square)
; Each frame: 8 rows × 4 bytes, pre-expanded with different colors
; ============================================================
exit_exp_frames:
; Frame 0 - WHITE ($AAFF)
        dc.l    $AAFFAAFF       ; Row 0: $FF
        dc.l    $80C00203       ; Row 1: $81
        dc.l    $80C00203       ; Row 2: $81
        dc.l    $80C00203       ; Row 3: $81
        dc.l    $80C00203       ; Row 4: $81
        dc.l    $80C00203       ; Row 5: $81
        dc.l    $80C00203       ; Row 6: $81
        dc.l    $AAFFAAFF       ; Row 7: $FF
; Frame 1 - YELLOW ($AAAA)
        dc.l    $AAAAAAAA       ; Row 0: $FF
        dc.l    $80800202       ; Row 1: $81
        dc.l    $80800202       ; Row 2: $81
        dc.l    $80800202       ; Row 3: $81
        dc.l    $80800202       ; Row 4: $81
        dc.l    $80800202       ; Row 5: $81
        dc.l    $80800202       ; Row 6: $81
        dc.l    $AAAAAAAA       ; Row 7: $FF
; Frame 2 - GREEN ($AA00)
        dc.l    $AA00AA00       ; Row 0: $FF
        dc.l    $80000200       ; Row 1: $81
        dc.l    $80000200       ; Row 2: $81
        dc.l    $80000200       ; Row 3: $81
        dc.l    $80000200       ; Row 4: $81
        dc.l    $80000200       ; Row 5: $81
        dc.l    $80000200       ; Row 6: $81
        dc.l    $AA00AA00       ; Row 7: $FF
; Frame 3 - CYAN ($AA55)
        dc.l    $AA55AA55       ; Row 0: $FF
        dc.l    $80400201       ; Row 1: $81
        dc.l    $80400201       ; Row 2: $81
        dc.l    $80400201       ; Row 3: $81
        dc.l    $80400201       ; Row 4: $81
        dc.l    $80400201       ; Row 5: $81
        dc.l    $80400201       ; Row 6: $81
        dc.l    $AA55AA55       ; Row 7: $FF

expanded_tiles:
        ds.b    NUM_TILES*32

; Working buffer for current level (runtime modifications)
level_working:
        ds.b    LEVEL_SIZE

; Off-screen playfield buffer (24KB)
; Full level pre-rendered: 12 tiles × 64 tiles × 8 pixels
; 48 bytes per scanline × 512 scanlines = 24576 bytes
playfield_buf:
        ds.b    BUF_SIZE

; bg1_left and mirror_lut moved to end of binary for memory overlay
; See "Reclaimable Memory" section at end of file

; ============================================================
; QSound SFX Engine (AY-3-8910 via QSound ROM vector)
; ============================================================
; Ported from Spectrum 128K AFX engine (Z80) to 68008 assembly.
; Plays sound effects through QSound ROM/QPC2 emulation using
; the AY.JMP dispatch vector at SV_BASE+$164.
; Placed at end of binary; called via function pointers to
; avoid PC-relative displacement issues in the 65KB binary.
; ============================================================

; --- SFX engine data (near code for PC-relative) ---
qsound_mode:  dc.w 0          ; 0=none, 1=QSound vector, 3=IPC beeper
sound_to_play:     dc.w SFX_NONE   ; Queued effect ID (255=none)
ay_regs:           dc.b 0,0,0,0,0,0,0,$3F,0,0,0,0,0,0
                   even

; --- Music player data ---
music_regs:        dc.b 0,0,0,0,0,0,0,$3F,0,0,0,0,0,0   ; Music-only AY register output
                   even
music_to_play:     dc.w MUSIC_NONE ; Queued track ID (255=no change)
music_playing:     dc.w 0          ; 1 = music active, 0 = silent
current_music_id:  dc.w 255        ; Currently loaded track ID
                   even

; TBK decompression state
tbk_buffer:        ds.b 16         ; Unpacked register frame (16 bytes)
tbk_stream:        dc.l 0          ; Current position in packed data stream
tbk_prev:          dc.l 0          ; Saved return position (for replay commands)
tbk_loop_addr:     dc.l 0          ; Start of packed data (for track looping)
tbk_pausing:       dc.w 0          ; Pause frames remaining (0=not pausing)

; AFX channel data (3 channels x 8 bytes = 24 bytes)
afx_ch_data:       ds.b AFX_NUM_CH*AFX_CH_SIZE
afx_noise_period:  dc.b 0
                   even

; Sound bank pointer (set during init)
afx_bank_ptr:      dc.l 0

; Cached AY.JMP dispatch vector (set during qsound_init)
ay_jmp_vector:     dc.l 0

; --- Sound bank data (513 bytes, 9 effects) ---
sound_bank:
        incbin  "tomba.afb"
        even

; ============================================================
; qsound_init - Detect QSound or fall back to IPC beeper
; Two-tier detection:
;   1. Check SV.AYJMP ($164) for QSound ROM/emulation vector
;   2. If absent, fall back to IPC beeper (universally available)
; ============================================================
qsound_init:
        movem.l d0-d2/a0-a2,-(sp)

        ; Get system variables base via MT.INF
        moveq   #0,d0
        trap    #1                      ; MT.INF: a0 = sys vars base

        ; Check if QSound vector is installed at SV.AYJMP ($164)
        move.l  $164(a0),d0
        beq.s   .no_vector

        ; QSound vector mode
        lea     ay_jmp_vector(pc),a1
        move.l  d0,(a1)
        lea     qsound_mode(pc),a1
        move.w  #QSND_VECTOR,(a1)
        bra.s   .init_done

.no_vector:
        ; IPC beeper fallback — cache sys vars for fast MT.IPCOM later
        lea     qsound_mode(pc),a1
        move.w  #QSND_BEEPER,(a1)
        lea     beeper_sysvars(pc),a1
        move.l  a0,(a1)                 ; a0 = sys vars from MT.INF above

.init_done:
        ; Initialize AFX player (even if no hardware — just sets up data)
        bsr     afx_init

        ; Only silence AY if in vector mode
        move.w  qsound_mode(pc),d0
        cmpi.w  #QSND_VECTOR,d0
        bne.s   .skip_silence
        bsr     ay_silence
.skip_silence:

        movem.l (sp)+,d0-d2/a0-a2
        rts

; ============================================================
; afx_init - Initialize AFX sound bank and channel data
; ============================================================
afx_init:
        movem.l d0/a0-a1,-(sp)
        ; Set bank pointer (skip first byte = effect count)
        lea     sound_bank(pc),a0
        addq.l  #1,a0                   ; Point past effect count byte
        lea     afx_bank_ptr(pc),a1
        move.l  a0,(a1)

        ; Init channel data: 32-bit addr=0 (inactive), ampl=0, mixer=$FF, tone=0
        ; (No time counter needed — Z80 uses it for LRU, we always use ch B)
        lea     afx_ch_data(pc),a0
        moveq   #AFX_NUM_CH-1,d0
.clr:   clr.l   (a0)+              ; +0..+3: address = 0 (inactive)
        clr.b   (a0)+              ; +4: amplitude = 0
        move.b  #$FF,(a0)+         ; +5: mixer bits = $FF (all disabled)
        clr.b   (a0)+              ; +6: tone low = 0
        clr.b   (a0)+              ; +7: tone high = 0
        dbra    d0,.clr

        ; Clear noise period
        lea     afx_noise_period(pc),a0
        clr.b   (a0)

        movem.l (sp)+,d0/a0-a1
        rts

; ============================================================
; sfx_play - Trigger a sound effect on channel B
; Input: D0.w = effect ID (0-8)
; ============================================================
sfx_play:
        movem.l d0-d2/a0-a2,-(sp)
        move.w  qsound_mode(pc),d1 ; Use d1, not d0 (d0=effect ID)
        cmpi.w  #QSND_VECTOR,d1    ; Only process AFX in vector mode
        bne.s   .done

        ; Look up effect address from bank offset table
        ; AFB format: offsets are little-endian (Z80), relative to
        ; the position of the high byte of the table entry
        move.l  afx_bank_ptr(pc),a0     ; Offset table base
        andi.w  #$FF,d0
        add.w   d0,d0                   ; d0 = effect_id * 2
        lea     (a0,d0.w),a1           ; a1 = &table[effect_id]
        moveq   #0,d1
        moveq   #0,d2
        move.b  (a1)+,d1               ; d1 = offset low byte
        move.b  (a1),d2                ; d2 = offset high byte; a1 at high byte pos
        lsl.w   #8,d2
        or.w    d2,d1                  ; d1 = 16-bit LE offset
        lea     (a1,d1.w),a1          ; effect addr = high_byte_pos + offset

        ; Store in channel B (channel 1, offset AFX_CH_SIZE)
        lea     afx_ch_data+AFX_CH_SIZE(pc),a2
        move.l  a1,(a2)                ; +0: data pointer
        clr.b   4(a2)                  ; +4: amplitude = 0
        clr.b   5(a2)                  ; +5: mixer bits = 0
        clr.w   6(a2)                  ; +6: tone = 0

.done:  movem.l (sp)+,d0-d2/a0-a2
        rts

; ============================================================
; sfx_update - Per-frame sound update (Music + SFX)
; Full audio with TBK music and AFX effects via amplitude mixing
; ============================================================
sfx_update:
        move.w  qsound_mode(pc),d0
        beq     .done                   ; QSND_NONE
        cmpi.w  #QSND_BEEPER,d0
        beq     .beeper_path

        ; --- QSound path (QSND_VECTOR) with Music ---

        ; Music track switching (once per game frame)
        lea     music_to_play(pc),a0
        move.w  (a0),d0
        cmpi.w  #MUSIC_NONE,d0
        beq.s   .no_track_change
        cmp.w   current_music_id(pc),d0
        beq.s   .clear_music_queue      ; Already playing this track
        bsr     psg_init                ; D0 = track ID
.clear_music_queue:
        lea     music_to_play(pc),a0
        move.w  #MUSIC_NONE,(a0)
.no_track_change:

        ; SFX queue (once per game frame)
        lea     sound_to_play(pc),a0
        move.w  (a0),d0
        cmpi.w  #SFX_NONE,d0
        beq.s   .no_new_sfx
        bsr     sfx_play
        move.w  #SFX_NONE,(a0)
.no_new_sfx:

        ; === Audio Frame 1 ===
        ; Music frame
        move.w  music_playing(pc),d0
        beq.s   .no_music_f1
        bsr     psg_frame
.no_music_f1:
        ; Copy music_regs to ay_regs (base layer)
        lea     music_regs(pc),a0
        lea     ay_regs(pc),a1
        move.l  (a0)+,(a1)+             ; regs 0-3
        move.l  (a0)+,(a1)+             ; regs 4-7
        move.l  (a0)+,(a1)+             ; regs 8-11
        move.w  (a0)+,(a1)+             ; regs 12-13
        ; SFX overlay (amplitude priority mixing)
        bsr     sfx_frame_overlay
        ; Output to hardware
        bsr     ay_write_all

        ; === Audio Frame 2 (25fps mode only) ===
        ; In forced 25fps mode, music was composed for 50fps so we need
        ; to advance and output a second audio frame per game tick
        move.w  frame_pacer_mode(pc),d0
        beq.s   .audio_done             ; 0 = adaptive 50fps, skip 2nd frame
        ; Music frame 2
        move.w  music_playing(pc),d0
        beq.s   .no_music_f2
        bsr     psg_frame
.no_music_f2:
        ; Copy music_regs to ay_regs (base layer)
        lea     music_regs(pc),a0
        lea     ay_regs(pc),a1
        move.l  (a0)+,(a1)+             ; regs 0-3
        move.l  (a0)+,(a1)+             ; regs 4-7
        move.l  (a0)+,(a1)+             ; regs 8-11
        move.w  (a0)+,(a1)+             ; regs 12-13
        ; SFX overlay (amplitude priority mixing)
        bsr     sfx_frame_overlay
        ; Output to hardware
        bsr     ay_write_all
.audio_done:
        rts

        ; --- IPC beeper path (no music support) ---
.beeper_path:
        lea     sound_to_play(pc),a0
        move.w  (a0),d0
        cmpi.w  #SFX_NONE,d0
        beq.s   .done
        move.w  #SFX_NONE,(a0)          ; Clear before call
        bsr     beeper_play_sfx
.done:  rts

; ============================================================
; sfx_frame_overlay - Process AFX channels, overlay on music
; Amplitude-priority mixing - SFX overrides music when louder
; Music values already in ay_regs from psg_frame; only override
; when SFX amplitude >= music amplitude for each channel.
; ============================================================
sfx_frame_overlay:
        movem.l d0-d5/a0-a3,-(sp)

        ; Process all 3 channels into afx_ch_data (advance effect data)
        ; Then overlay onto ay_regs using amplitude priority

        ; Start with SFX mixer = all off ($3F = all tone+noise disabled)
        moveq   #$3F,d4
        ; d5 = accumulated SFX noise period
        moveq   #0,d5
        lea     ay_regs(pc),a3

        ; --- Process Channel A ---
        lea     afx_ch_data(pc),a0
        bsr     .process_channel
        ; Channel A mixer bits: info bit4→mixer bit0 (tone), bit7→bit3 (noise)
        move.b  5(a0),d0
        lsr.b   #4,d0                  ; bit4→bit0, bit7→bit3
        andi.b  #$09,d0                ; keep bits 0 and 3 only
        andi.b  #$F6,d4                ; clear chA bits in mixer
        or.b    d0,d4                  ; merge
        ; Amplitude priority: compare SFX vs music
        move.b  4(a0),d0               ; SFX amplitude
        andi.b  #$0F,d0                ; mask to 4 bits
        move.b  8(a3),d1               ; Music amplitude (already in ay_regs)
        andi.b  #$0F,d1
        cmp.b   d1,d0
        bcs.s   .skip_a                ; SFX < music → skip
        ; SFX wins: override ay_regs
        move.b  4(a0),8(a3)            ; AmplA
        move.b  6(a0),0(a3)            ; TonA_lo
        move.b  7(a0),1(a3)            ; TonA_hi
        ; Override mixer bits for channel A
        move.b  7(a3),d1               ; current ay_regs mixer
        andi.b  #$F6,d1                ; clear chA bits
        move.b  5(a0),d0
        lsr.b   #4,d0
        andi.b  #$09,d0
        or.b    d0,d1
        move.b  d1,7(a3)
        ; Check if SFX has noise update
        btst    #7,5(a0)               ; noise enable bit in SFX info
        beq.s   .skip_a
        lea     afx_noise_period(pc),a2
        move.b  (a2),d5                ; capture noise period
.skip_a:

        ; --- Process Channel B ---
        lea     afx_ch_data+AFX_CH_SIZE(pc),a0
        bsr     .process_channel
        ; Channel B mixer bits: info bit4→mixer bit1, bit7→bit4
        move.b  5(a0),d0
        lsr.b   #3,d0
        andi.b  #$12,d0
        andi.b  #$ED,d4
        or.b    d0,d4
        ; Amplitude priority
        move.b  4(a0),d0
        andi.b  #$0F,d0
        move.b  9(a3),d1
        andi.b  #$0F,d1
        cmp.b   d1,d0
        bcs.s   .skip_b
        move.b  4(a0),9(a3)            ; AmplB
        move.b  6(a0),2(a3)            ; TonB_lo
        move.b  7(a0),3(a3)            ; TonB_hi
        move.b  7(a3),d1
        andi.b  #$ED,d1
        move.b  5(a0),d0
        lsr.b   #3,d0
        andi.b  #$12,d0
        or.b    d0,d1
        move.b  d1,7(a3)
        btst    #7,5(a0)
        beq.s   .skip_b
        lea     afx_noise_period(pc),a2
        move.b  (a2),d5
.skip_b:

        ; --- Process Channel C ---
        lea     afx_ch_data+AFX_CH_SIZE*2(pc),a0
        bsr     .process_channel
        ; Channel C mixer bits: info bit4→mixer bit2, bit7→bit5
        move.b  5(a0),d0
        lsr.b   #2,d0
        andi.b  #$24,d0
        andi.b  #$DB,d4
        or.b    d0,d4
        ; Amplitude priority
        move.b  4(a0),d0
        andi.b  #$0F,d0
        move.b  10(a3),d1
        andi.b  #$0F,d1
        cmp.b   d1,d0
        bcs.s   .skip_c
        move.b  4(a0),10(a3)           ; AmplC
        move.b  6(a0),4(a3)            ; TonC_lo
        move.b  7(a0),5(a3)            ; TonC_hi
        move.b  7(a3),d1
        andi.b  #$DB,d1
        move.b  5(a0),d0
        lsr.b   #2,d0
        andi.b  #$24,d0
        or.b    d0,d1
        move.b  d1,7(a3)
        btst    #7,5(a0)
        beq.s   .skip_c
        lea     afx_noise_period(pc),a2
        move.b  (a2),d5
.skip_c:

        ; If any SFX channel had noise, override noise period
        tst.b   d5
        beq.s   .no_sfx_noise
        move.b  d5,6(a3)               ; Override noise period
.no_sfx_noise:

        movem.l (sp)+,d0-d5/a0-a3
        rts

; --- Process single channel ---
.process_channel:
        move.l  (a0),d0
        beq.s   .ch_inactive

        move.l  d0,a1
        move.b  (a1)+,d0
        move.b  d0,5(a0)

        move.b  d0,d1
        andi.b  #$0F,d1
        move.b  d1,4(a0)

        btst    #5,d0
        beq.s   .no_tone
        move.b  (a1)+,d1
        move.b  (a1)+,d2
        move.b  d1,6(a0)
        move.b  d2,7(a0)
.no_tone:

        btst    #6,d0
        beq.s   .no_noise
        move.b  (a1),d1
        cmpi.b  #$20,d1
        bcs.s   .valid_noise
        clr.l   (a0)
        clr.b   4(a0)
        rts
.valid_noise:
        addq.l  #1,a1
        lea     afx_noise_period(pc),a2
        move.b  d1,(a2)
.no_noise:
        move.l  a1,(a0)
        rts

.ch_inactive:
        clr.b   4(a0)
        clr.b   5(a0)
        rts

; ============================================================
; ay_write_all - Write 14 AY registers via QSound ROM vector
; Calls AY.WRALL (function 3) through SV.AYJMP dispatch.
; Works on both real QSound hardware and QPC2 emulation.
; ============================================================
ay_write_all:
        movem.l d0-d2/a0-a2/a5,-(sp)
        move.w  qsound_mode(pc),d0
        cmpi.w  #QSND_VECTOR,d0
        bne.s   .done
        move.l  ay_jmp_vector(pc),a0   ; Cached SV.AYJMP dispatch
        lea     ay_regs(pc),a1         ; 14-byte register buffer
        moveq   #3,d0                  ; Function 3 = AY.WRALL
        moveq   #0,d2                  ; Chip ID = 0
        jsr     (a0)                   ; Call QSound dispatch
.done:  movem.l (sp)+,d0-d2/a0-a2/a5
        rts

; ============================================================
; ay_silence - Zero all AY registers (init + shutdown)
; ============================================================
ay_silence:
        movem.l d0/a0,-(sp)
        lea     ay_regs(pc),a0
        moveq   #AY_NUM_REGS-1,d0
.clr:   clr.b   (a0)+
        dbra    d0,.clr
        lea     ay_regs+7(pc),a0
        move.b  #$3F,(a0)
        bsr     ay_write_all
        movem.l (sp)+,d0/a0
        rts

; ============================================================
; End of QSound SFX Engine
; ============================================================

; ============================================================
; IPC Beeper Sound Engine
; Fallback sound output using the QL's native IPC beeper.
; Uses MT.IPCOM (trap #1, d0=$11) with pre-built command blocks.
; Sys vars pointer cached during init to avoid per-call MT.INF.
; No per-frame overhead — only sends IPC command on landing trigger.
; ============================================================

; --- Cached sys vars pointer (set during qsound_init) ---
beeper_sysvars:  dc.l 0

; --- IPC SOUND command block for FLY (whoosh + shhh) ---
; QDOS MT.IPCOM format: cmd, n_params, 4-byte BitsPParm mask, params, reply.
; Mask $0000AAAA = all 8 params sent as full bytes (2 nibbles each = 16 nibbles).
; 16-bit fields (interval, duration) are BIG-ENDIAN (high byte first in block).
; AFX-matched whoosh: descending sweep high→mid with breathy noise (~0.36s).
; AFX FLY: tone period 2→103, noise throughout, vol 15→1 fade.
; IPC approximation: pitch 5→110 descent, fuzzy+random for noise texture.
beep_fly:
        dc.b    IPC_CMD_SOUND   ; $0A — offset 0: command
        dc.b    8               ; offset 1: 8 parameter bytes
        dc.l    $0000AAAA       ; offset 2-5: BitsPParm mask (all bytes)
        dc.b    5               ; offset 6: pitch1 — very high (AFX period ~2)
        dc.b    110             ; offset 7: pitch2 — mid-low (AFX period ~103)
        dc.w    2               ; offset 8-9: interval (BE) — moderate sweep speed
        dc.w    13              ; offset 10-11: duration (BE) — ~0.09s
        dc.b    $20             ; offset 12: grady=2, wrap=0 (single descent)
        dc.b    $88             ; offset 13: random=8, fuzzy=8 (breathy noise)
        dc.b    1               ; offset 14: 1 reply byte expected
        even

; --- IPC SOUND command block for EXIT (warble) ---
; Short warble: pitch bounces rapidly between two tones.
beep_exit:
        dc.b    IPC_CMD_SOUND   ; $0A — offset 0: command
        dc.b    8               ; offset 1: 8 parameter bytes
        dc.l    $0000AAAA       ; offset 2-5: BitsPParm mask (all bytes)
        dc.b    10              ; offset 6: pitch1 — high tone
        dc.b    30              ; offset 7: pitch2 — lower tone
        dc.w    3               ; offset 8-9: interval (BE) — fast oscillation
        dc.w    18              ; offset 10-11: duration (BE) — short
        dc.b    $4F             ; offset 12: grady=4, wrap=15 (rapid bounce)
        dc.b    $00             ; offset 13: random=0, fuzzy=0 (clean tone)
        dc.b    1               ; offset 14: 1 reply byte expected
        even

; --- IPC SOUND command block for SWAP (echo beep) ---
; Double-echo beep: tone bounces twice between pitches, fuzz adds decay feel.
beep_swap:
        dc.b    IPC_CMD_SOUND   ; $0A — offset 0: command
        dc.b    8               ; offset 1: 8 parameter bytes
        dc.l    $0000AAAA       ; offset 2-5: BitsPParm mask (all bytes)
        dc.b    10              ; offset 6: pitch1 — high beep
        dc.b    40              ; offset 7: pitch2 — noticeably lower
        dc.w    6               ; offset 8-9: interval (BE) — spaced steps
        dc.w    20              ; offset 10-11: duration (BE) — short
        dc.b    $32             ; offset 12: grady=3, wrap=2 (bounce twice)
        dc.b    $05             ; offset 13: random=0, fuzzy=5 (light decay)
        dc.b    1               ; offset 14: 1 reply byte expected
        even

; --- IPC SOUND command block for DEAD (low buzz) ---
; Low-pitched buzz: deep tone with fuzz for gritty death sound.
beep_dead:
        dc.b    IPC_CMD_SOUND   ; $0A — offset 0: command
        dc.b    8               ; offset 1: 8 parameter bytes
        dc.l    $0000AAAA       ; offset 2-5: BitsPParm mask (all bytes)
        dc.b    200             ; offset 6: pitch1 — very low
        dc.b    220             ; offset 7: pitch2 — slightly lower still
        dc.w    2               ; offset 8-9: interval (BE) — slow drift
        dc.w    25              ; offset 10-11: duration (BE) — short buzz
        dc.b    $10             ; offset 12: grady=1, wrap=0 (slow descent)
        dc.b    $0A             ; offset 13: random=0, fuzzy=10 (buzzy)
        dc.b    1               ; offset 14: 1 reply byte expected
        even

; --- IPC SOUND command block for CANNON (laser pew) ---
; Fast descending sweep from high to mid, clean tone, very short.
beep_cannon:
        dc.b    IPC_CMD_SOUND   ; $0A — offset 0: command
        dc.b    8               ; offset 1: 8 parameter bytes
        dc.l    $0000AAAA       ; offset 2-5: BitsPParm mask (all bytes)
        dc.b    3               ; offset 6: pitch1 — very high (laser start)
        dc.b    60              ; offset 7: pitch2 — mid (pew tail)
        dc.w    1               ; offset 8-9: interval (BE) — fastest sweep
        dc.w    12              ; offset 10-11: duration (BE) — short zap
        dc.b    $30             ; offset 12: grady=3, wrap=0 (fast single descent)
        dc.b    $00             ; offset 13: random=0, fuzzy=0 (clean laser tone)
        dc.b    1               ; offset 14: 1 reply byte expected
        even

; --- IPC SOUND command block for GOLD (coin collect ping) ---
; High-pitched short ping for coin collection feedback.
beep_gold:
        dc.b    IPC_CMD_SOUND   ; $0A — offset 0: command
        dc.b    8               ; offset 1: 8 parameter bytes
        dc.l    $0000AAAA       ; offset 2-5: BitsPParm mask (all bytes)
        dc.b    2               ; offset 6: pitch1 — very high ping
        dc.b    8               ; offset 7: pitch2 — slightly lower
        dc.w    2               ; offset 8-9: interval (BE) — quick
        dc.w    8               ; offset 10-11: duration (BE) — short ping
        dc.b    $20             ; offset 12: grady=2, wrap=0 (slight descent)
        dc.b    $00             ; offset 13: random=0, fuzzy=0 (clean tone)
        dc.b    1               ; offset 14: 1 reply byte expected
        even

; ============================================================
; beeper_play_sfx - IPC beeper dispatcher
; Input: D0.w = effect ID (0-8)
; Handles all game SFX triggers including GOLD and EXIT.
; ============================================================
beeper_play_sfx:
        cmpi.w  #SFX_CANNON,d0
        bne.s   .not_cannon
        lea     beep_cannon(pc),a3
        bra.s   beeper_play_cmd
.not_cannon:
        cmpi.w  #SFX_FLY,d0
        bne.s   .not_fly
        lea     beep_fly(pc),a3
        bra.s   beeper_play_cmd
.not_fly:
        cmpi.w  #SFX_SWAP,d0
        bne.s   .not_swap
        lea     beep_swap(pc),a3
        bra.s   beeper_play_cmd
.not_swap:
        cmpi.w  #SFX_DEAD,d0
        bne.s   .not_dead
        lea     beep_dead(pc),a3
        bra.s   beeper_play_cmd
.not_dead:
        cmpi.w  #SFX_EXIT,d0
        bne.s   .not_exit
        lea     beep_exit(pc),a3        ; Exit tile touch - warble
        bra.s   beeper_play_cmd
.not_exit:
        cmpi.w  #SFX_FIN,d0
        bne.s   .not_fin
        lea     beep_exit(pc),a3        ; Level complete - same warble
        bra.s   beeper_play_cmd
.not_fin:
        cmpi.w  #SFX_GOLD,d0
        bne.s   .done
        lea     beep_gold(pc),a3        ; Coin collect - high ping
        bra.s   beeper_play_cmd
.done:  rts

; ============================================================
; beeper_play_cmd - Send IPC command block via MT.IPCOM
; Input: A3 = pointer to IPC command block
; Uses cached sys vars pointer (no MT.INF call needed).
; Single trap #1 call — minimal frame budget impact.
; ============================================================
beeper_play_cmd:
        move.l  a6,-(sp)
        move.l  beeper_sysvars(pc),a6   ; cached sys vars
        moveq   #MT_IPCOM,d0
        trap    #1                      ; Send IPC sound command
        move.l  (sp)+,a6
        rts

; ============================================================
; PSG Music Player (TBK decompression)
; ============================================================

; ============================================================
; psg_init - Initialize TBK player for a track
; Input: D0.w = track ID (0-4)
; Uses embedded track data, no disk loading
; ============================================================
psg_init:
        movem.l d0-d3/a0-a3,-(sp)

        ; Bounds check
        cmpi.w  #NUM_TRACKS,d0
        bcc     .bad_track

        move.w  d0,d2                   ; save track ID

        ; Get track pointer from embedded table (longword offsets from org 0)
        ; Compute runtime address: cached_base + stored_offset
        lea     music_track_ptrs(pc),a0
        add.w   d0,d0
        add.w   d0,d0                   ; d0 = track_id * 4 (longword index)
        move.l  (a0,d0.w),d1            ; d1 = offset from org 0
        move.l  runtime_base_ptr(pc),a2 ; a2 = cached runtime base address
        adda.l  d1,a2                   ; a2 = actual track address

        ; Set stream pointers to embedded track data
        lea     tbk_stream(pc),a1
        move.l  a2,(a1)
        lea     tbk_loop_addr(pc),a1
        move.l  a2,(a1)

        ; Clear TBK buffer
        lea     tbk_buffer(pc),a0
        clr.l   (a0)+                   ; bytes 0-3
        clr.l   (a0)+                   ; bytes 4-7
        clr.l   (a0)+                   ; bytes 8-11
        clr.l   (a0)+                   ; bytes 12-15
        lea     tbk_buffer+7(pc),a0
        move.b  #$3F,(a0)               ; mixer = all disabled (matches music_regs)
        lea     tbk_buffer+13(pc),a0
        move.b  #$FF,(a0)               ; reg13 flag = no update

        ; Clear saved return pointer and pause
        lea     tbk_prev(pc),a0
        clr.l   (a0)
        lea     tbk_pausing(pc),a0
        clr.w   (a0)

        ; Clear music_regs to silence
        lea     music_regs(pc),a0
        moveq   #13,d0
.clr_regs:
        clr.b   (a0)+
        dbra    d0,.clr_regs
        lea     music_regs+7(pc),a0
        move.b  #$3F,(a0)               ; mixer = all disabled

        ; Set state
        lea     music_playing(pc),a1
        move.w  #1,(a1)
        lea     current_music_id(pc),a1
        move.w  d2,(a1)
        bra.s   .init_done

.bad_track:
        ; Stop music on failure
        lea     music_playing(pc),a0
        clr.w   (a0)
.init_done:
        movem.l (sp)+,d0-d3/a0-a3
        rts

; ============================================================
; psg_frame - Unpack one TBK frame, update music_regs
; Called once per game frame when music is playing
; TBK decompression ported from ZX Spectrum
; ============================================================
psg_frame:
        movem.l d0-d5/a0-a4,-(sp)

        move.w  music_playing(pc),d0
        tst.w   d0
        beq     .pf_done

        ; Check if pausing
        move.w  tbk_pausing(pc),d0
        beq.s   .do_unpack
        subq.w  #1,d0
        lea     tbk_pausing(pc),a0
        move.w  d0,(a0)
        bra     .pf_done               ; buffer unchanged during pause

.do_unpack:
        ; Reset reg13 flag for this frame
        lea     tbk_buffer+13(pc),a0
        move.b  #$FF,(a0)

        move.l  tbk_stream(pc),a0       ; a0 = stream read position
        lea     tbk_buffer(pc),a1       ; a1 = output buffer base

        ; ======== Top-level command dispatch ========
.tbk_dispatch:
        moveq   #0,d0
        move.b  (a0),d0                 ; d0 = command byte

        ; Test bit 7 for command type
        btst    #7,d0
        bne     .cmd_1x                 ; bit7=1: replay command

        ; Command 0X (bit7=0)
        btst    #6,d0
        bne     .cmd_01                 ; bit6=1: PSG2 bulk update

        ; ======== Command 00: PSG1 / Pause / Stop ========
        move.w  d0,d1
        andi.w  #$3F,d1                 ; 6-bit field (bits 5-0)
        cmpi.b  #30,d1
        blt     .cmd_psg1              ; 0-29: register write(s)
        beq.s   .cmd_empty             ; 30: empty frame (no register changes)
        cmpi.b  #63,d1
        beq.s   .cmd_stop              ; 63: stop (loop to start)

        ; Pause: duration = field - 30
        ; Subtract 31 (not 30) because this frame itself counts as one
        subi.w  #31,d1
        lea     tbk_pausing(pc),a2
        move.w  d1,(a2)
        addq.l  #1,a0                  ; advance past command byte
        bra     .tbk_frame_done

.cmd_empty:
        addq.l  #1,a0                  ; advance past command byte
        bra     .tbk_frame_done

.cmd_stop:
        ; Loop: reinitialize from start of track
        move.l  tbk_loop_addr(pc),a0
        ; Clear buffer for fresh loop
        clr.l   (a1)
        clr.l   4(a1)
        clr.l   8(a1)
        clr.l   12(a1)
        move.b  #$3F,7(a1)             ; mixer = all disabled
        move.b  #$FF,13(a1)            ; reg13 flag = no update
        bra     .tbk_dispatch           ; unpack first frame of loop

        ; ======== Command 00 - PSG1: 1 or 2 register writes ========
.cmd_psg1:
        ; d0 = command byte, low nibble = first register number
        move.w  d0,d1
        andi.w  #$0F,d1                ; d1 = register number

        ; Write first register value
        cmpi.b  #13,d1
        bne.s   .psg1_wr1
        ; Register 13: set flag + write value to slot 14
        move.b  d1,13(a1)              ; flag = 13 (non-$FF)
        move.b  1(a0),14(a1)           ; value to buffer[14]
        bra.s   .psg1_check2
.psg1_wr1:
        move.b  1(a0),(a1,d1.w)        ; buffer[reg] = value

.psg1_check2:
        ; Check if 2-register record: byte == low nibble means high nibble is 0
        cmp.b   d0,d1
        bne.s   .psg1_single           ; not equal: 1 register only

        ; Second register write
        moveq   #0,d2
        move.b  2(a0),d2               ; second indicator byte
        andi.w  #$0F,d2                ; d2 = second register number
        cmpi.b  #13,d2
        bne.s   .psg1_wr2
        move.b  d2,13(a1)              ; reg13 flag
        move.b  3(a0),14(a1)           ; reg13 value
        bra.s   .psg1_two_done
.psg1_wr2:
        move.b  3(a0),(a1,d2.w)        ; buffer[reg2] = value2
.psg1_two_done:
        addq.l  #4,a0                  ; advance past 4 bytes
        bra     .tbk_frame_done

.psg1_single:
        addq.l  #2,a0                  ; advance past 2 bytes
        bra     .tbk_frame_done

        ; ======== Command 01 - PSG2: bulk register update ========
.cmd_01:
        ; Build 14-bit register presence mask
        ; Bits 5-0 of command = registers 0-5 (bit5=reg0, bit0=reg5)
        ; Next byte bits 7-0 = registers 6-13 (bit7=reg6, bit0=reg13)
        move.w  d0,d3
        andi.w  #$3F,d3                ; command bits 5-0
        lsl.w   #8,d3                  ; shift to bits 13-8
        moveq   #0,d4
        move.b  1(a0),d4               ; second mask byte
        or.w    d4,d3                  ; d3 = 14-bit mask
        lsl.w   #2,d3                  ; align to bits 15-2 for shifting

        lea     2(a0),a2               ; a2 = source (value bytes in stream)
        moveq   #0,d2                  ; d2 = register counter (0-13)

.cmd01_loop:
        add.w   d3,d3                  ; shift left, MSB to carry
        bcc.s   .cmd01_skip

        ; Register d2 is present — read value
        cmpi.b  #13,d2
        bne.s   .cmd01_normal
        ; Register 13 special handling
        move.b  #0,13(a1)             ; flag = 0 (non-$FF, means "update")
        move.b  (a2)+,14(a1)          ; value to slot 14
        bra.s   .cmd01_next
.cmd01_normal:
        move.b  (a2)+,(a1,d2.w)       ; buffer[reg] = value
.cmd01_skip:
.cmd01_next:
        addq.w  #1,d2
        cmpi.w  #14,d2
        blt.s   .cmd01_loop

        move.l  a2,a0                  ; update stream pointer past all values
        bra.s   .tbk_frame_done

        ; ======== Command 1X - Replay (back-reference) ========
.cmd_1x:
        ; Read 14-bit offset: command bits 5-0 = high, next byte = low
        moveq   #0,d1
        move.b  (a0),d1
        andi.w  #$3F,d1                ; 6-bit high offset
        lsl.w   #8,d1
        moveq   #0,d2
        move.b  1(a0),d2               ; low byte of offset
        or.w    d2,d1                  ; d1 = 14-bit offset

        ; Check bit 6 for Command 10 vs Command 11
        btst    #6,d0
        bne.s   .cmd_11

        ; Command 10: single frame replay
        lea     2(a0),a2               ; return address = after 2-byte command
        moveq   #1,d3                  ; frame count = 1
        bra.s   .do_replay

.cmd_11:
        ; Command 11: multi-frame replay
        moveq   #0,d3
        move.b  2(a0),d3               ; frame count from stream
        lea     3(a0),a2               ; return address = after 3-byte command

.do_replay:
        ; Save return address
        lea     tbk_prev(pc),a3
        move.l  a2,(a3)

        ; Save frame count in buffer[15]
        move.b  d3,15(a1)

        ; Back-reference: target = command_addr - offset
        move.l  a0,a3
        moveq   #0,d4
        move.w  d1,d4
        suba.l  d4,a3                  ; a3 = target address
        move.l  a3,a0                  ; read from target

        ; Dispatch command at target (always a 0X command, not nested)
        bra     .tbk_dispatch

        ; ======== Frame done — bookkeeping ========
.tbk_frame_done:
        ; Save current stream position
        lea     tbk_stream(pc),a2
        move.l  a0,(a2)

        ; Check replay frame counter
        move.b  15(a1),d0              ; buffer[15] = replay frames
        beq.s   .tbk_copy              ; 0 = no replay active

        subq.b  #1,d0
        move.b  d0,15(a1)
        bne.s   .tbk_copy              ; more frames remaining

        ; Replay finished: restore saved stream position
        move.l  tbk_prev(pc),a0
        lea     tbk_stream(pc),a2
        move.l  a0,(a2)

.tbk_copy:
        ; Copy tbk_buffer to music_regs
        lea     tbk_buffer(pc),a2
        lea     music_regs(pc),a3

        ; Registers 0-11 (3 longwords)
        move.l  (a2),(a3)
        move.l  4(a2),4(a3)
        move.l  8(a2),8(a3)
        ; Register 12
        move.b  12(a2),12(a3)

        ; Register 13: only update if flag != $FF
        move.b  13(a2),d0              ; flag byte
        cmpi.b  #$FF,d0
        beq.s   .pf_done
        move.b  14(a2),13(a3)          ; copy reg13 value

.pf_done:
        movem.l (sp)+,d0-d5/a0-a4
        rts

; ============================================================
; Embedded Music Track Pointers (longword offsets from org 0)
; Runtime address computed as: start_base + offset
; ============================================================
music_track_ptrs:
        dc.l    track_menu
        dc.l    track_level1
        dc.l    track_level2
        dc.l    track_level3
        dc.l    track_outro

; ============================================================
; Embedded Compressed Music Tracks (TBK/TPP format)
; Total: ~49KB of compressed music data
; ============================================================
        even
track_menu:
        incbin  "menu_psg_tpp"
        even
track_level1:
        incbin  "music01_psg_tpp"
        even
track_level2:
        incbin  "music02_psg_tpp"
        even
track_level3:
        incbin  "music03_psg_tpp"
        even
track_outro:
        incbin  "outro_psg_tpp"
        even

; ============================================================
; Reclaimable Memory Section
; ============================================================
; This data is only needed during init (draw_side_images).
; After sides are drawn to screen memory, this 4246 bytes can
; be overwritten with extended music/AFX data.
;
; To use: After init completes, load music data starting at
; the address of 'reclaimable_start' (bg1_left label).
; ============================================================
reclaimable_start:

; Side image data (generated from pl1.png, 60x133, QL MODE 8)
; Right side is mirrored from left at runtime (see draw_side_images)
bg1_left:
        incbin  "pl1_left.bin"
        even

; mirror_lut - 256-byte lookup table for reversing 4 pixels in a byte
; Each byte has 4 x 2-bit fields: ABCDEFGH -> GHEFCDAB
; entry[i] = ((i&$03)<<6) | ((i&$0C)<<2) | ((i&$30)>>2) | ((i&$C0)>>6)
mirror_lut:
        dc.b    $00,$40,$80,$C0,$10,$50,$90,$D0,$20,$60,$A0,$E0,$30,$70,$B0,$F0
        dc.b    $04,$44,$84,$C4,$14,$54,$94,$D4,$24,$64,$A4,$E4,$34,$74,$B4,$F4
        dc.b    $08,$48,$88,$C8,$18,$58,$98,$D8,$28,$68,$A8,$E8,$38,$78,$B8,$F8
        dc.b    $0C,$4C,$8C,$CC,$1C,$5C,$9C,$DC,$2C,$6C,$AC,$EC,$3C,$7C,$BC,$FC
        dc.b    $01,$41,$81,$C1,$11,$51,$91,$D1,$21,$61,$A1,$E1,$31,$71,$B1,$F1
        dc.b    $05,$45,$85,$C5,$15,$55,$95,$D5,$25,$65,$A5,$E5,$35,$75,$B5,$F5
        dc.b    $09,$49,$89,$C9,$19,$59,$99,$D9,$29,$69,$A9,$E9,$39,$79,$B9,$F9
        dc.b    $0D,$4D,$8D,$CD,$1D,$5D,$9D,$DD,$2D,$6D,$AD,$ED,$3D,$7D,$BD,$FD
        dc.b    $02,$42,$82,$C2,$12,$52,$92,$D2,$22,$62,$A2,$E2,$32,$72,$B2,$F2
        dc.b    $06,$46,$86,$C6,$16,$56,$96,$D6,$26,$66,$A6,$E6,$36,$76,$B6,$F6
        dc.b    $0A,$4A,$8A,$CA,$1A,$5A,$9A,$DA,$2A,$6A,$AA,$EA,$3A,$7A,$BA,$FA
        dc.b    $0E,$4E,$8E,$CE,$1E,$5E,$9E,$DE,$2E,$6E,$AE,$EE,$3E,$7E,$BE,$FE
        dc.b    $03,$43,$83,$C3,$13,$53,$93,$D3,$23,$63,$A3,$E3,$33,$73,$B3,$F3
        dc.b    $07,$47,$87,$C7,$17,$57,$97,$D7,$27,$67,$A7,$E7,$37,$77,$B7,$F7
        dc.b    $0B,$4B,$8B,$CB,$1B,$5B,$9B,$DB,$2B,$6B,$AB,$EB,$3B,$7B,$BB,$FB
        dc.b    $0F,$4F,$8F,$CF,$1F,$5F,$9F,$DF,$2F,$6F,$AF,$EF,$3F,$7F,$BF,$FF
        even

reclaimable_end:
; Total reclaimable: reclaimable_end - reclaimable_start = 4246 bytes

; ============================================================
; End of Old Tower - Music Edition
; ============================================================

        end
