10 print chr$(147)"9-values: 256b inc. verify, uniform data"
20 b=57088:x=peek(b):gosub 900:dim v(7):for k=0 to 7:read v(k):next
25 data 255,0,170,85,254,127,15,240
30 for k=0 to 7:v=v(k):for i=0 to 255:poke 16384+i,v:next
40 d=11:gosub 800
50 poke b+9,0:poke b+10,0:poke b+2,0:poke b+3,64:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,1
60 poke b+1,176:poke b+1,179:if (peek(b) and 32)=32 then print "(fault w/ display off!)";
70 d=27:gosub 800:n=0:u=0:for r=1 to 50:poke b+1,179:s=peek(b):if (s and 32)=32 then n=n+1
75 if (s and 96)=0 then u=u+1
80 next:print "value"v":"n" faults in 50";:if u>0 then print "("u"not run!)";
85 print
90 next:gosub 900:end
800 poke 53265,d:for w=1 to 100:next:return
