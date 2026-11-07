; ============================================================
; Music tracks, OTZ-packed (tools/mkmusic.py) - generated, do not edit
; ============================================================
NUM_TRACKS      equ 5
MUSIC_BUF_SIZE  equ 10158             ; largest track
; per track: packed data offset from music_tracks (word), raw length (word)
music_tracks:
        dc.w    trk0_z-music_tracks,10158
        dc.w    trk1_z-music_tracks,7772
        dc.w    trk2_z-music_tracks,6922
        dc.w    trk3_z-music_tracks,5824
        dc.w    trk4_z-music_tracks,5180
trk0_z:   incbin  "menu_25hz_mrg2_tpp.otz"
trk1_z:   incbin  "music01_25hz_mrg2_tpp.otz"
trk2_z:   incbin  "music02_25hz_mrg2_tpp.otz"
trk3_z:   incbin  "music03_25hz_mrg2_tpp.otz"
trk4_z:   incbin  "outro_25hz_mrg2_tpp.otz"
        even
