10 print chr$(147)"13-swapchk: 20 x 4kb swap, display on"
20 b=57088:x=peek(b):gosub 900:print "preparing, one minute..."
25 a=20480:for p=0 to 15:for j=0 to 255:v=(j+p)and 255:poke a,v:poke a+4096,255-v:a=a+1:next j,p
30 d=11:gosub 800
40 poke b+9,0:poke b+10,0:poke b+2,0:poke b+3,80:poke b+4,0:poke b+5,0:poke b+6,2:poke b+7,0:poke b+8,16:poke b+1,176
45 poke b+2,0:poke b+3,96:poke b+6,3:poke b+1,176
50 t1=0:t2=0:g=0:q=0
60 for r=1 to 20
65 poke b+10,0:poke b+2,0:poke b+3,80:poke b+4,0:poke b+5,0:poke b+6,2:poke b+7,0:poke b+8,16:poke b+1,177
70 poke b+2,0:poke b+3,96:poke b+6,1:poke b+1,176
75 d=27:gosub 800
80 poke b+2,0:poke b+3,80:x=peek(b):poke b+1,178:s=peek(b)
90 d=11:gosub 800:ca=20480:bk=3:ln=4096:gosub 1000:n1=nw:f1=fp:if n1>0 then c1=peek(20480+f1)
100 poke b+10,0:poke b+2,0:poke b+3,112:poke b+4,0:poke b+5,0:poke b+6,1:poke b+7,0:poke b+8,16:poke b+1,177
110 ca=28672:bk=2:ln=4096:gosub 1000:n2=nw:f2=fp
120 if (s and 96)=64 and n1=0 and n2=0 then g=g+1
130 if (s and 96)<>64 or n1<0 or n2<0 then if q<12 then q=q+1:print "run"r"status"s"checks"n1;n2
140 if n1>0 then t1=t1+n1:if q<12 then q=q+1:print "run"r"c64:"n1"wrong, pos"f1"got"c1
150 if n2>0 then t2=t2+n2:if q<12 then q=q+1:print "run"r"reu:"n2"wrong, pos"f2"got"peek(28672+f2)
160 next:d=27:gosub 800:print "runs ok:"g"of 20, wrong c64:"t1"reu:"t2:gosub 900:end
800 poke 53265,d:for w=1 to 100:next:return
