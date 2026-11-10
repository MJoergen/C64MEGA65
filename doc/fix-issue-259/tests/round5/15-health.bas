10 print chr$(147)"15-health: does the reu answer?"
20 b=57088:x=peek(b):dim g(8),m(8),w(8),o(8)
30 for k=0 to 8:read g(k),m(k):next
35 data 2,255,3,255,4,255,5,255,6,7,7,255,8,255,9,224,10,192
40 for r=1 to 20:for k=0 to 8:for p=0 to 1:v=85+85*p:if g(k)=9 and p=1 then v=42
50 poke b+g(k),v:z=v and m(k):y=peek(b+g(k)) and m(k)
60 if y<>z then w(k)=w(k)+1:o(k)=o(k) or ((y or z) and not (y and z))
70 next p,k,r:poke b+9,0:poke b+10,0
80 print "register, wrong of 40 writes, wrong bits"
90 for k=0 to 8:print g(k);w(k);o(k):next
200 d=11:gosub 800
210 for i=0 to 255:poke 16384+i,i:poke 16640+i,255:next
220 poke b+9,0:poke b+10,0:poke b+2,0:poke b+3,64:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,1
230 x=peek(b):poke b+1,144:s1=peek(b):a1=peek(b+2)+256*peek(b+3):l1=peek(b+7)+256*peek(b+8)
240 poke b+2,0:poke b+3,65:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,1:poke b+1,145:s2=peek(b)
250 n=0:for i=0 to 255:if peek(16640+i)<>i then n=n+1
260 next
270 poke b+2,0:poke b+3,64:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,1:poke b+1,147:s3=peek(b)
280 poke 16484,0
290 poke b+2,0:poke b+3,64:poke b+4,0:poke b+5,0:poke b+6,0:poke b+7,0:poke b+8,1:poke b+1,147:s4=peek(b)
295 k4=peek(b+2)+256*peek(b+3)-16385
300 d=27:gosub 800
310 print "stash  status"s1"adr"a1"len"l1
320 print "fetch  status"s2"wrong bytes"n
330 print "verify status"s3
340 print "verify, byte 100 changed:"s4"byte"k4
350 e=0:for k=0 to 8:e=e+w(k):next
360 if (s1 and 96)<>64 or a1<>16640 or l1<>1 or (s2 and 96)<>64 or n<>0 then e=e+1
370 if (s3 and 96)<>64 or (s4 and 96)<>32 or k4<>100 then e=e+1
380 if e=0 then print "result: reu awake"
390 if e>0 then print "result: reu does not answer correctly"
400 end
800 poke 53265,d:for w=1 to 100:next:return
