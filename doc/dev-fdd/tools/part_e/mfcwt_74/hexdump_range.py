import sys
d=open(sys.argv[1],'rb').read()
a=int(sys.argv[2],16); n=int(sys.argv[3],16)
for o in range(a,a+n,16):
    b=d[o:o+16]
    s=''.join(chr(c) if 32<=c<127 else '.' for c in b)
    print('%05x: %s  %s'%(o,' '.join('%02x'%c for c in b),s))
