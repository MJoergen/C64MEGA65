900 rem reu check: are register writes kept, do a 1-byte stash and fetch run?
905 zv=(zv+37)and 255:poke b+9,0:poke b+10,0:poke b+2,85:poke b+3,170:poke b+7,165:poke b+8,90
910 za=peek(b+2):zb=peek(b+3):zc=peek(b+7):zd=peek(b+8):ze=0
915 if za<>85 or zb<>170 or zc<>165 or zd<>90 then ze=1
920 poke 49152,zv:poke 49153,255-zv
925 poke b+2,0:poke b+3,192:poke b+4,0:poke b+5,255:poke b+6,2:poke b+7,1:poke b+8,0
930 zs=peek(b):poke b+1,144:zs=peek(b):zf=peek(b+2):zg=peek(b+7)
935 if (zs and 96)<>64 or zf<>1 or zg<>1 then ze=ze+2
940 poke b+2,1:poke b+3,192:poke b+4,0:poke b+5,255:poke b+6,2:poke b+7,1:poke b+8,0
945 poke b+1,145:zt=peek(b):zh=peek(49153)
950 if (zt and 96)<>64 or zh<>zv then ze=ze+4
955 if ze=0 then print "reu check ok":return
960 print "reu check failed"ze":"za;zb;zc;zd;zs;zf;zg;zt;zh;zv:return
1000 rem compare ln bytes at c64 address ca with reu bank bk from address 0 (display off):
1001 rem nw = wrong bytes (-1: the verify did not run), fp = first wrong position
1010 nw=0:fp=-1:zk=0
1020 zq=ca+zk:zl=ln-zk:poke b+10,0:poke b+2,zq and 255:poke b+3,zq/256:poke b+4,zk and 255:poke b+5,zk/256:poke b+6,bk
1030 poke b+7,zl and 255:poke b+8,zl/256:zx=peek(b):poke b+1,147:zx=peek(b)
1040 if (zx and 96)=0 then nw=-1:return
1050 if (zx and 32)=0 then return
1060 zp=peek(b+2)+256*peek(b+3)-ca-1:nw=nw+1:if fp<0 then fp=zp
1070 zk=zp+1:if zk<ln then 1020
1080 return
