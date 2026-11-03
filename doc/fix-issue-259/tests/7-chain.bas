10 print chr$(147)"7-chain: 16kb fixed-c64 $aa, display on"
15 print "a=stash,verify b=stash,fetch,verify"
16 print "c=stash,fixedreu-verify,verify"
20 b=57088:x=peek(b)
30 for m=1 to 3:print "chain "chr$(64+m)": ";
40 for r=1 to 5
50 poke 16384,170:poke b+9,0:poke b+10,128:poke b+2,0:poke b+3,64:poke b+4,0
55 poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,64
60 poke b+1,176
70 if m=2 then poke b+10,0:poke b+1,177:poke b+10,128
75 if m=3 then poke b+10,64:poke b+1,179:x=peek(b):poke b+10,128
80 poke b+1,179
90 if (peek(b) and 32)=32 then print "fault ";:goto 110
100 print "ok ";
110 next:print:next:end
