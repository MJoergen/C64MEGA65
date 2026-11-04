10 print chr$(147)"8-swap: does a swap change the verify?"
15 print "16kb fixed-c64 $aa, verify w/ display on"
20 b=57088:x=peek(b)
30 gosub 900:print "before:";:gosub 950
40 poke b+10,0:poke b+2,0:poke b+3,65:poke b+4,0:poke b+5,64:poke b+6,0:poke b+7,1:poke b+8,0
45 poke b+1,177:print "after 1b fetch:";:gosub 950
50 poke b+10,0:poke b+2,0:poke b+3,65:poke b+4,0:poke b+5,64:poke b+6,0:poke b+7,1:poke b+8,0
55 poke b+1,178:print "after 1b swap:";:gosub 950
60 gosub 900:print "after re-stash:";:gosub 950
70 d=11:gosub 800:poke b+10,0:poke b+2,0:poke b+3,65:poke b+4,0:poke b+5,64:poke b+6,0:poke b+7,0:poke b+8,1
75 poke b+1,178:d=27:gosub 800:print "256b swap/off:";:gosub 950
80 poke b+10,0:poke b+2,0:poke b+3,64:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,64
85 poke b+1,178:gosub 900:print "16kb swap/on+stash:";:gosub 950
90 end
800 poke 53265,d:for w=1 to 100:next:return
900 d=11:gosub 800:poke 16384,170:poke b+9,0:poke b+10,128:poke b+2,0:poke b+3,64:poke b+4,0
910 poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,64:poke b+1,176:d=27:gosub 800:return
950 poke b+10,128:poke b+2,0:poke b+3,64:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,64
960 for r=1 to 3:poke b+1,179:if (peek(b) and 32)=32 then print " fault";:goto 980
970 print " ok";
980 next:print:return
