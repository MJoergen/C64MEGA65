10 print chr$(147)"12-position: 256b verify at raster l"
15 print "byte 255 + len 1 = ran to the end"
20 b=57088:x=peek(b):t=3584
30 for l=50 to 52 step 2:poke 3075,10:poke 3076,l:sys 3072
40 print "line"l": off-status"peek(3077)
45 print " st byte len cyc end"
50 for r=0 to 9:p=t+16*r:s=peek(p):k=peek(p+1)+256*peek(p+2)-16385:n=peek(p+5)+256*peek(p+6)
60 c=65535-peek(p+7)-256*peek(p+8):e=peek(p+9)+2*(peek(p+10)and128)
70 print s;k;n;c;e:next
80 if l=50 then print "photo now, then press a key":poke 198,0
85 if l=50 then get a$:if a$="" then 85
87 if l=50 then print chr$(147)
90 next:end
