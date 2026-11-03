10 print chr$(147)"2-stash: stash w/ display on, fetch w/ off"
20 b=57088:x=peek(b):for i=0 to 255:poke 16384+i,i:next:t=0
30 for r=1 to 20
40 d=27:gosub 800
50 poke b+9,0:poke b+10,0:poke b+2,0:poke b+3,64:poke b+4,0:poke b+5,0:poke b+6,0
55 poke b+7,0:poke b+8,1:poke b+1,176
60 d=11:gosub 800
70 for i=0 to 255:poke 16640+i,255:next
80 poke b+2,0:poke b+3,65:poke b+1,177
90 n=0:for i=0 to 255:v=peek(16640+i):if v<>i then print "run"r" pos"i" got"v:n=n+1
100 next:t=t+n:if n=0 then print "run"r" ok"
110 next:d=27:gosub 800:print "total bad bytes:"t:end
800 poke 53265,d:for w=1 to 100:next:return
