import sys
d=open(sys.argv[1],'rb').read()
t=int(sys.argv[2],16); lo,hi=t&0xff,t>>8
for o in range(len(d)-6):
    # LDA #lo ... LDX/LDY #hi within 6 bytes, or LDX #lo LDY #hi
    if d[o] in (0xA9,0xA2,0xA0) and d[o+1]==lo:
        w=d[o+2:o+8]
        for k in range(len(w)-1):
            if w[k] in (0xA9,0xA2,0xA0) and w[k+1]==hi:
                print('%05x bank %d $%04X: %s'%(o,o//0x2000,0x8000+o%0x2000,d[o:o+8].hex())); break
