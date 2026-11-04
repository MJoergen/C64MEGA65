10 print chr$(147)"10-after: reu data after a faulting verify"
15 print "256b 0..255, verify w/o autoload, display on"
20 b=57088:x=peek(b):for i=0 to 255:poke 16384+i,i:next
30 d=11:gosub 800
40 poke b+9,0:poke b+10,0:poke b+2,0:poke b+3,64:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,1
50 poke b+1,176:x=peek(b):d=27:gosub 800:t=0:f=0
60 for r=1 to 20
70 poke b+2,0:poke b+3,64:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,1:poke b+1,147
80 s=peek(b):if (s and 32)=0 then 150
90 f=f+1:print "run"r" fault at byte"peek(b+2)+256*peek(b+3)-16385" len"peek(b+7)+256*peek(b+8)" st"s
100 d=11:gosub 800:for i=0 to 255:poke 16640+i,255:next
110 poke b+2,0:poke b+3,65:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,1:poke b+1,145:x=peek(b)
120 n=0:for i=0 to 255:v=peek(16640+i):if v<>i then print " pos"i" got"v:n=n+1
130 next:t=t+n:if n=0 then print " reu data intact"
140 d=27:gosub 800
150 next:print f" faults in 20, wrong reu bytes after them:"t
160 print "control: byte 100 changed, display off":d=11:gosub 800:poke 16484,77
170 poke b+2,0:poke b+3,64:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,1:poke b+1,147
180 s=peek(b):print "st"s" fault at byte"peek(b+2)+256*peek(b+3)-16385" (expect 100)"
190 poke 16484,100:d=27:gosub 800:end
800 poke 53265,d:for w=1 to 100:next:return
