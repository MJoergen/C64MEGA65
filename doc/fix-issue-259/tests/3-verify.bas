10 print chr$(147)"3-verify: clean data, verify w/ display on"
20 b=57088:x=peek(b)
30 for p=1 to 5:l=256:a=0:if p=3 then l=4096
31 if p=4 then l=65536:a=128
32 if p=5 then l=16384:a=128
33 if p=1 then print "256b 0..255: ";
34 if p=2 then print "256b all $aa: ";
36 if p=3 then print "4kb 0..255 repeated: ";
37 if p=4 then print "64kb fixed-c64 $aa: ";
38 if p=5 then print "16kb fixed-c64 $aa: ";
39 if p>3 then poke 16384,170:goto 50
40 for i=0 to l-1:v=i and 255:if p=2 then v=170
45 poke 16384+i,v:next
50 d=11:gosub 800:lh=l/256:if lh=256 then lh=0
60 poke b+9,0:poke b+10,a:poke b+2,0:poke b+3,64:poke b+4,0:poke b+5,0:poke b+6,0
62 poke b+7,0:poke b+8,lh:poke b+1,176
65 poke b+1,179:if (peek(b) and 32)=32 then print "(fault w/ display off!) ";
70 d=27:gosub 800:n=0:m=100:if p>2 then m=25
75 if p=4 then m=10
80 for r=1 to m:poke b+1,179:if (peek(b) and 32)=32 then n=n+1
90 next:print n" faults in"m
100 next:end
800 poke 53265,d:for w=1 to 100:next:return
