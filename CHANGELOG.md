# Old Tower v2.0 Changelog

**Changes from Old Tower v1.2 to v2.0**

## One Edition
- The Standard and Large Memory (music) editions are merged into one game for a standard 128K QL. With QSound it plays the full music and AY sound effects; without QSound it uses beeper sound effects.
- Init-only data (expanded tiles, side images, mirror table) now lives inside the playfield buffer's space and is overwritten once the game starts.
- Levels and music tracks are packed with OTZ, a bit-level LZ format (`otz_decode`), replacing the RLE level data. Tracks are unpacked one at a time into a single buffer when the music changes.

## Timing
- New polled mode (default build): the game runs with interrupts off and keeps its own 50Hz clock from the display frame signal (`poll_tick`).
- Music and sound effects step on that fixed clock (every second tick, 25Hz) instead of once per game frame, so the music never drifts or slows down when frames run long.
- A QDOS-timed build (assembled without `POLLED`) remains for QPC2 / SMSQ/E; it catches up audio steps from the QDOS tick.

## Performance
- Fully unrolled 12-register screen copy, persistent trails and bats (no save/restore), score digit table and cache, coin tiles held in registers.
- Keyboard read directly through the IPC, one row only; the row is read every frame when the hero is standing still and every second frame while moving.
- On a standard 128K QL, frames over the 40ms budget are now rare (about 0.2%); with expansion memory there are none.

## Controls
- Cursor keys (or joystick 1) to move, SPACE (fire) to swap heroes, ENTER to restart the level (costs a life), ESC back to the title / quit.
- Q/A/O/P and R are no longer used.
- New controls page: press ENTER on the title screen.

## Sound
- Sound effects on QSound play at full volume (previously scaled to 75%).

## Loading and Exit
- New `boot` loader (RESPR + LBYTES + CALL); no Toolkit II needed. Change `dev$` in `boot` to load from another drive.
- Quitting returns cleanly to SuperBASIC (previously ended with a "not complete" message).

## Visual
- Title screen shows "v2.0" and "ENTER FOR KEYS".

## Removed
- Unused routines: level number display, buffer-composited bullets.

# Old Tower v1.2 — Music Edition Changelog

**Changes from Old Tower v1.0 (Music Edition) to v1.2**

## Audio Engine

### Direct AY Hardware Writes
- Bypassed QSound ROM dispatch (`AY.WRALL` function 3) in favour of direct port writes to `$000C2000` (data) and `$000C2002` (control). Lower latency and full control over register write ordering.

### Frequency Scaling
- New `scale_periods` routine converts all tone (12-bit), noise (5-bit) and envelope (16-bit) periods from Spectrum AY clock (1.7734 MHz) to QSound clock (750 kHz) using ×27/64 scaling. Applied every frame before hardware write.

### Register Write Reordering
- Amplitudes written first (regs 8-10), then tone/noise periods (regs 0-6), then envelope (regs 11-13), mixer last (reg 7). Minimises audible glitches from partial register updates.

### Conditional Envelope Register (reg13_dirty)
- Register 13 (envelope shape) only written to hardware when the TBK stream actually updates it. Prevents unwanted envelope restarts on frames where envelope data hasn't changed.

### Fixed-Rate 25Hz Audio
- Removed dual-frame 50Hz decode logic. Audio now runs at a fixed 25Hz rate matching the game's frame rate, using pre-decimated music and SFX data.

### 25Hz Decimated Music & SFX Data
- All music tracks switched from `*_psg_tpp` (50Hz) to `*_25hz_mrg2_tpp` (25Hz TBK v2 with merged replay back-references).
- SFX bank switched from `tomba.afb` (513 bytes) to `tomba_25hz.afb` (302 bytes, 25Hz decimated).

### Nested TBK Replay Support
- 4-level replay stack in `psg_frame` handles nested back-references in TBK v2 compressed music data. Previous version only supported single-level replay.
- New `.replay_unwind` routine handles cascading replay exhaustion across stack levels.

### AY.INIT on Startup
- `qsound_init` now calls AY.INIT (QSound function 0) before first use, resetting driver state. Fixes first-run hang when music starts on a fresh emulator/hardware boot.

### Tick Counter Caching
- System tick counter pointer (`sys_vars + $2E`) cached during `qsound_init` rather than using hardcoded address `$2802E`. `prev_audio_tick` synced at startup to prevent initial tick overrun.

### Mixer Sanitisation
- Bits 7-6 of mixer register (reg 7) cleared after TBK decode (`andi.b #$3F`), preventing undefined behaviour from stale high bits.

## SFX Overlay

### Split SFX Processing
- Replaced monolithic `sfx_frame_overlay` with separate `sfx_tick_advance` (advances SFX data) and `sfx_apply_overlay` (applies to AY registers).

### Channel B Only
- SFX overlay restricted to channel B only (was all 3 channels). Reduces music disruption.

### 75% SFX Volume
- SFX amplitude reduced to 75% (`value - value/4`) before comparison with music. Keeps SFX audible without overpowering music.

### Strict Amplitude Priority
- SFX only overrides music when strictly louder (`>` not `>=`). Music wins ties.

### Envelope Protection
- If music channel B uses envelope mode (bit 4 set), music always wins regardless of SFX amplitude.

### Shared Noise Protection
- When SFX uses noise on channel B, noise is disabled on channels A and C (`ori.b #$28` on mixer) to prevent SFX noise bleeding into music channels.

## Audio Continuity During Level Transitions

### Pre-Load Track Change Processing
- In all 4 transition paths (`start_game`, `init_title_screen`, `full_restart_level`, `next_level`): track change (AY silence) is processed *before* `load_current_level`. Prevents stale tones sustaining during heavy decompression.

### Interleaved Audio Updates
- Multiple `audio_update` calls inserted during level load/setup/render sequences to maintain audio continuity across the ~200ms decompression gap.

### psg_init Improvements
- Now clears `ay_regs` in addition to `music_regs` (prevents stale SFX overlay data).
- Clears `replay_stack_depth` and `reg13_dirty` on track switch.

## Title Screen Performance

### Direct-to-Screen Rendering
- Replaced heavy composite/copy/restore pipeline (`composite_trails_to_buffer` → `composite_enemies_to_buffer` → `composite_hero_to_buffer` → `copy_window_to_screen_title`) with lightweight direct-to-screen approach.
- New `title_erase_hero`: restores single hero tile from playfield buffer to screen.
- New `title_blit_coins_to_screen`: iterates coin cache, blits only visible coins from buffer to screen.
- Achieves stable 25fps on stock 68008 QL.

## Visual

### Version Display
- New `draw_version` routine blits pre-rendered "v1.2" bitmap (15×4 pixels, white on black) to bottom-left of intro screen. Called once from `init_title_screen`.

## Removed

### Level Skip
- Removed `=` key level skip functionality (was present in experimental OTF builds, not suitable for release).
