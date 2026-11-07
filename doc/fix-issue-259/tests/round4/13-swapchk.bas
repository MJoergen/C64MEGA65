10 print chr$(147)"13-swapchk: swap integrity, display on"
15 print "c64 $4000 holds i, reu $0000 holds 255-i"
20 b=57088:x=peek(b)
40 for i=0 to 255:poke 16384+i,i:poke 16640+i,255-i:next
50 d=11:gosub 800
60 poke b+9,0:poke b+10,0:poke b+2,0:poke b+3,65:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,1:poke b+1,176
70 d=27:gosub 800:t=0
80 for r=1 to 20
90 poke b+2,0:poke b+3,64:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,1:poke b+1,178
100 d=11:gosub 800:p=r and 1
120 poke b+2,0:poke b+3,66:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,1:poke b+1,177
130 n=0:for i=0 to 255:c=peek(16384+i):e=peek(16896+i)
140 if p=1 then if c<>255-i or e<>i then print " run"r" pos"i" c64"c" reu"e:n=n+1
150 if p=0 then if c<>i or e<>255-i then print " run"r" pos"i" c64"c" reu"e:n=n+1
160 next:t=t+n:d=27:gosub 800:next
170 print "20 x 256b swap: wrong bytes:"t
180 print "16kb swap at $5000, about 3 minutes..."
190 for i=0 to 16383:poke 20480+i,(i+int(i/256))and 255:next
200 d=11:gosub 800
210 poke b+2,0:poke b+3,80:poke b+4,0:poke b+5,0:poke b+6,1:poke b+7,0:poke b+8,64:poke b+1,176
220 for i=0 to 16383:poke 20480+i,255-((i+int(i/256))and 255):next
230 d=27:gosub 800
240 poke b+2,0:poke b+3,80:poke b+4,0:poke b+5,0:poke b+6,1:poke b+7,0:poke b+8,64:poke b+1,178
250 d=11:gosub 800:n=0
260 for i=0 to 16383:v=(i+int(i/256))and 255:if peek(20480+i)<>v then print " c64 pos"i" got"peek(20480+i)" exp"v:n=n+1
270 next:print "16kb swap: wrong c64 bytes:"n
280 poke b+2,0:poke b+3,80:poke b+4,0:poke b+5,0:poke b+6,1:poke b+7,0:poke b+8,64:poke b+1,177
290 n=0:for i=0 to 16383:v=255-((i+int(i/256))and 255):if peek(20480+i)<>v then print " reu pos"i" got"peek(20480+i)" exp"v:n=n+1
300 next:print "16kb swap: wrong reu bytes:"n
310 d=27:gosub 800:end
800 poke 53265,d:for w=1 to 100:next:return
