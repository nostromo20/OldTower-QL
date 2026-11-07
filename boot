100 REMark Old Tower v2.0 - Sinclair QL
110 REMark To load from another drive change dev$, e.g. "flp1_"
120 dev$="mdv1_"
130 MODE 4: CLS
140 PRINT "Old Tower v2.0 - loading..."
150 adr=RESPR(82344): LBYTES dev$&"oldtower",adr
160 MODE 8
170 CALL adr
