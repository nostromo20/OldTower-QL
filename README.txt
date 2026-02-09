
          ___  _     ____    _____  ___  _    _ _____ ____
         / _ \| |   |  _ \  |_   _|/ _ \| |  | | ____|  _ \
        | | | | |   | | | |   | | | | | | |  | |  _| | |_) |
        | |_| | |___| |_| |   | | | |_| | |/\| | |___|  _ <
         \___/|_____|____/    |_|  \___/|__/\__|_____|_| \_\

              ============================================
                       SINCLAIR QL CONVERSION
              ============================================

                         - RELEASE 2026 -

         An unofficial conversion of the ZX Spectrum classic
                    for the Sinclair QL computer


 ============================================================================
                              BACKGROUND
 ============================================================================

 Old Tower was originally released for the ZX Spectrum 48K/128K in 2018
 by RetroSouls (Russia). It was created for the ZX-DEV M.I.A Remakes 2018
 competition where it placed 3rd. The game was inspired by the mobile hit
 "Tomb of the Mask" and features the world's first multicolor scroller
 for the ZX Spectrum.

 You play as a little explorer navigating a tower full of deadly traps,
 cannons, and bats. Quick thinking and precise timing are your only
 weapons as you collect coins and find the exit in each of the 21 levels.


 ============================================================================
                           ORIGINAL CREDITS
 ============================================================================

              CODE & GAME DESIGN ............. Denis Grachev
              MUSIC .......................... Oleg Nikitin
              GRAPHICS ....................... Ivan Seleznev

                         (c) 2018 RetroSouls
                         https://www.retrosouls.net/


 ============================================================================
                         SINCLAIR QL VERSION
 ============================================================================

              QL CONVERSION .................. Jim McKay

 This conversion is a ground up rewrite that faithfully recreates the original
 ZX Spectrum experience on the Sinclair QL, featuring:

   * All 21 original levels
   * Full colour graphics with smooth vertical scrolling
   * QSound AY chip audio (music + sound effects)
   * IPC beeper fallback for systems without QSound
   * Automatic frame rate detection (25fps/50fps)
   * Two editions: Standard (SFX only) and Large Memory (full music)


 ============================================================================
                              EDITIONS
 ============================================================================

 STANDARD EDITION (OldTower)
 ---------------------
 Binary: OldTower (~57KB)

 Sound effects via QSound or IPC beeper. Runs on any 128KB QL system.
 Recommended for real hardware with limited memory expansion.


 LARGE MEMORY EDITION (OldTower_M)
 --------------------------
 Binary: OldTower_M (~110KB) : Fits on a Microdrive!!!

 Full music and sound effects. Features five compressed music tracks
 that match the original ZX Spectrum 128K experience. Requires 256KB
 QL or expanded system. Recommended for emulators or expanded QLs.


 ============================================================================
                               LOADING
 ============================================================================

 OQDOS executable:

   EXEC_W mdv1_OldTower   

 ============================================================================
                              CONTROLS
 ============================================================================

      MOVEMENT:           Q = UP      A = DOWN
                          O = LEFT    P = RIGHT

                    - or use CURSOR KEYS -

      SWAP HEROES:        SPACE

      RESET LEVEL:        R

      RETURN TO TITLE:    ESC

      QUIT GAME:          ESC (from title screen)


 ============================================================================
                             HOW TO PLAY
 ============================================================================

 Your goal is to collect all coins in each level and reach the exit.
 The exit only becomes active once all coins have been collected.

 MOVEMENT
 --------
 Press a direction to launch your hero in that direction. Once moving,
 your hero will continue until hitting a wall or obstacle. Plan your
 routes carefully - some moves cannot be undone!

 TWO HEROES
 ----------
 Some levels feature two heroes. Press SPACE to swap control between
 them. Both heroes must reach the exit to complete the level.

 HAZARDS
 -------
   * SPIKES - Instant death if you hit them from the wrong direction
   * BATS - Flying enemies that patrol set routes
   * CANNONS - Fire projectiles that must be avoided
   * CRACKED BLOCKS - Crumble after being touched

 SPECIAL TILES
 -------------
   * ONE-WAY PLATFORMS - Can only pass through in one direction
   * REFLECTORS - Redirect your movement at 90 degrees
   * BOUNCE PADS - Reverse your vertical direction
   * HIDDEN BLOCKS - Become solid when touched


 ============================================================================
                               LEVELS
 ============================================================================

   Title Screen (Level 00) - Menu
   Levels 01-15 - Main tower ascent
   Levels 21-25 - Bonus challenge rooms

   Total: 21 playable levels


 ============================================================================
                           TECHNICAL NOTES
 ============================================================================

 * Requires 128KB QL or expanded system
 * Runs in MODE 8 (256x256, 8 colours)
 * Uses QSound ROM for AY-3-8910 sound chip emulation
 * Falls back to IPC beeper if QSound not available
 * Auto-detects 50fps or 25fps display timing
 * Large Memory Edition uses TBK compressed music format


 ============================================================================
                             THANKS TO
 ============================================================================

 * Denis Grachev, Oleg Nikitin, and Ivan Seleznev for the original game
 * RetroSouls for releasing the source code
 * The QL community for keeping the platform alive
 * QSound developers for AY chip emulation on QL


 ============================================================================

                        THANKS FOR PLAYING!

                              J.Mckay

 ============================================================================
