10 print chr$(147)"16-soak: register writes only, no dma"
20 b=57088:x=peek(b):q=30:dim g(8),m(8):for k=0 to 8:read g(k),m(k):next
30 data 2,255,3,255,4,255,5,255,6,7,7,255,8,255,9,224,10,192
40 print "runs"q"minutes. min, writes, wrong,":print "wrong since the last line"
50 t0=ti:n=0:e=0:l=0:c=0
60 for k=0 to 8:for p=0 to 1:v=85+85*p:if g(k)=9 and p=1 then v=42
70 poke b+g(k),v:n=n+1:if (peek(b+g(k)) and m(k))<>(v and m(k)) then e=e+1:c=c+1
80 next p,k
90 t=int((ti-t0)/10800):if t=l then 60
100 l=t:print 3*t;n;e;c:c=0:if 3*t<q then 60
110 poke b+9,0:poke b+10,0:print "done:"e"wrong of"n:end
