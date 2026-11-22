import sys
d=open(sys.argv[1],'rb').read()
t=int(sys.argv[2],16)
lo,hi=t&0xff,t>>8
for o in range(len(d)-4):
    if d[o]==0xA9 and d[o+1]==lo and (hi in d[o+2:o+10]):
        print('lo/hi imm near %05x bank %d addr $%04X'%(o,o//0x2000,0x8000+(o%0x2000)), d[o:o+10].hex())
    if d[o]==lo and d[o+1]==hi:
        print('abs %05x bank %d addr $%04X'%(o,o//0x2000,0x8000+(o%0x2000)), d[max(0,o-1):o+3].hex())
