10 print chr$(147)"5-sprites: 64k fixed-c64 stash+verify"
15 print "display on, without / with 8 sprites"
20 b=57088:x=peek(b)
30 for i=0 to 7:poke 2040+i,255:poke 53248+2*i,40+i*30:poke 53249+2*i,224:poke 53287+i,i+1:next
35 poke 53264,192
40 for sp=0 to 1:v=255*sp:poke 53269,v:print "sprites"v": ";
50 for r=1 to 5
60 poke 16384,170:poke b+9,0:poke b+10,128:poke b+2,0:poke b+3,64:poke b+4,0
65 poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,0
70 poke b+1,176:poke b+1,179
80 if (peek(b) and 32)=32 then print "fault ";:goto 100
90 print "ok ";
100 next:print:next:poke 53269,0:end
