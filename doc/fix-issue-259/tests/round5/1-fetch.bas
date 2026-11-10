10 print chr$(147)"1-fetch: 20 x 4kb fetch, display on"
20 b=57088:x=peek(b):gosub 900:print "preparing, one minute..."
25 a=20480:for p=0 to 15:for j=0 to 255:poke a,(j+p)and 255:poke a+4096,255:a=a+1:next j,p
30 d=11:gosub 800
40 poke b+9,0:poke b+10,0:poke b+2,0:poke b+3,80:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,16:poke b+1,176
45 poke b+2,0:poke b+3,96:poke b+6,1:poke b+1,176
50 t=0:g=0:q=0
60 for r=1 to 20
65 poke b+10,0:poke b+2,0:poke b+3,96:poke b+4,0:poke b+5,0:poke b+6,1:poke b+7,0:poke b+8,16:poke b+1,177
70 d=27:gosub 800
80 poke b+6,0:x=peek(b):poke b+1,177:s=peek(b)
90 d=11:gosub 800:ca=24576:bk=0:ln=4096:gosub 1000
100 if (s and 96)=64 and nw=0 then g=g+1
110 if (s and 96)<>64 or nw<0 then if q<12 then q=q+1:print "run"r"status"s"check"nw
120 if nw>0 then t=t+nw:if q<12 then q=q+1:print "run"r":"nw"wrong, first pos"fp"got"peek(24576+fp)
130 next:d=27:gosub 800:print "runs ok:"g"of 20, bad bytes:"t:gosub 900:end
800 poke 53265,d:for w=1 to 100:next:return
