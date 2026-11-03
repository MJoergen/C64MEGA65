10 print chr$(147)"6-idle: stash 64k w/ display off, wait 10s, verify"
20 b=57088:x=peek(b)
30 for m=1 to 4:w=27:v=11:if m=2 then w=11:v=27
32 if m=3 then w=27:v=27
34 if m=4 then w=11:v=11
40 poke 16384,170:poke b+9,0:poke b+10,128:poke b+2,0:poke b+3,64:poke b+4,0
45 poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,0
50 d=11:gosub 800:poke b+1,176
60 d=w:gosub 800:ti$="000000"
65 if ti<600 then 65
70 d=v:gosub 800:poke b+1,179:f=peek(b) and 32
80 print "wait display"w" verify display"v;
85 if f=32 then print ": fault":goto 100
90 print ": ok"
100 next:d=27:gosub 800:end
800 poke 53265,d:for w1=1 to 100:next:return
