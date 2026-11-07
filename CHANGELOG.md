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
