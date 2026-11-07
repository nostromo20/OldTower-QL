          ___  _     ____    _____  ___  _    _ _____ ____
         / _ \| |   |  _ \  |_   _|/ _ \| |  | | ____|  _ \
        | | | | |   | | | |   | | | | | | |  | |  _| | |_) |
        | |_| | |___| |_| |   | | | |_| | |/\| | |___|  _ <
         \___/|_____|____/    |_|  \___/|__/\__|_____|_| \_\

              ============================================
                       SINCLAIR QL CONVERSION
              ============================================

                         - VERSION 2.0 -

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
   * Steady 25 frames per second on a standard 128K QL
   * QSound AY chip music and sound effects - now on a standard 128K QL
   * IPC beeper sound effects for systems without QSound
   * Controls page on the title screen (press ENTER)


 ============================================================================
                          WHAT'S NEW IN 2.0
 ============================================================================

 * ONE EDITION. The Standard and Large Memory editions are replaced by a
   single game that runs on any 128K QL. With QSound you get the full
   music and sound effects; without it, beeper sound effects.

 * MUSIC ON 128K. The five music tracks and the levels are now packed, so
   the music fits in a standard 128K machine alongside the game.

 * STEADY TIMING. The music keeps time with the QL's 50Hz display clock
   rather than the game's frame rate, so it never drifts or slows down
   when the action gets busy.

 * FASTER. Screen drawing, the keyboard and the sound have been optimised:
   the game now holds 25 frames per second on a standard 128K QL almost
   all of the time. With expansion memory it runs even more smoothly.

 * LOUDER SOUND EFFECTS on QSound.

 * NEW CONTROLS PAGE. Press ENTER on the title screen to see the keys.

 * NEW KEYS. Movement is now on the cursor keys (or joystick) only, and
   ENTER restarts the level. See CONTROLS below.


 ============================================================================
                              REQUIREMENTS
 ============================================================================

 * Sinclair QL with 128K or more. No Toolkit II needed.
 * QSound (optional) for music and AY sound effects.
 * Expansion memory (optional) makes the game run more smoothly.

 Emulators: in Q-emuLator, turn QSound on in the settings for music. With
 QSound, use up to 640K of memory - larger settings clash with QSound's
 memory address.


 ============================================================================
                               LOADING
 ============================================================================

 The game is two files: boot (the loader) and oldtower (the game).

 With the cartridge in mdv1_, reset the QL and press F1 or F2: the game
 loads by itself. Or type:

   LRUN mdv1_boot

 The boot loader reserves memory, loads the game and starts it. To load
 from another drive, change the dev$ line in boot, for example:

   120 dev$="flp1_"

 ESC on the title screen quits back to SuperBASIC.


 ============================================================================
                              CONTROLS
 ============================================================================

      MOVEMENT:           CURSOR KEYS  (or joystick 1)

      SWAP HEROES:        SPACE        (or joystick fire)

      RESTART LEVEL:      ENTER        (costs a life)

      RETURN TO TITLE:    ESC

   On the title screen:

      START GAME:         SPACE        (or joystick fire)

      CONTROLS PAGE:      ENTER

      QUIT GAME:          ESC

 Players of version 1.x: Q/A/O/P and R are no longer used.


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

 * Runs on a standard 128K QL (tested with the JS ROM)
 * MODE 8 (256x256, 8 colours), 25 frames per second
 * Takes over the machine while playing: interrupts are off and the game
   keeps its own time from the 50Hz display signal
 * Uses QSound for AY-3-8910 music and sound effects; falls back to the
   IPC beeper if QSound is not available
 * Music: TBK format tracks, packed with a custom LZ compressor and
   unpacked one track at a time


 ============================================================================
                               SOURCE
 ============================================================================

 OldTower.s is the game. It includes ot_polled.s and the packed data files
 (levels_otz.inc, music_otz.inc, *.otz, tomba_25hz.afb, pl1_left.bin).
 Assemble with vasm (68000, plain binary):

   vasmm68k_mot -Fbin -m68000 -no-opt -DPOLLED=1 -o oldtower OldTower.s

 Leave out -DPOLLED=1 for a version timed by QDOS (QPC2 / SMSQ/E).


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
