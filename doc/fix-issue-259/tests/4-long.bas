10 print chr$(147)"4-long: fixed-c64 stash+verify of $aa"
15 print "m1=display on/on m2=off/on m3=on/off"
20 b=57088:x=peek(b):dim ll(5),lh(5):for k=1 to 5:read ll(k),lh(k):next
25 data 0,1,0,16,0,64,0,128,0,0
30 gosub 900
40 for m=1 to 3:s=27:v=27:if m=2 then s=11
45 if m=3 then v=11
50 for k=1 to 5:l=ll(k)+256*lh(k):if l=0 then l=65536
60 print "m"m" l"l": ";
70 for r=1 to 3
80 poke 16384,170:poke b+9,0:poke b+10,128:poke b+2,0:poke b+3,64:poke b+4,0
85 poke b+5,0:poke b+6,0:poke b+7,ll(k):poke b+8,lh(k)
90 d=s:gosub 800:poke b+1,176
100 d=v:gosub 800:poke b+1,179
110 if (peek(b) and 32)=32 then print "fault ";:goto 130
120 print "ok ";
130 next:print
140 next:next
150 gosub 950:end
800 poke 53265,d:for w=1 to 100:next:return
900 d=11:gosub 800
910 poke 16385,85:poke b+9,0:poke b+10,0:poke b+2,1:poke b+3,64:poke b+4,0:poke b+5,0
915 poke b+6,7:poke b+7,1:poke b+8,0:poke b+1,176
920 poke b+10,64:poke b+2,0:poke b+3,80:poke b+7,0:poke b+8,48:poke b+1,177
930 d=27:gosub 800:return
950 d=11:gosub 800
960 poke b+10,64:poke b+2,0:poke b+3,80:poke b+4,0:poke b+5,0:poke b+6,7
965 poke b+7,0:poke b+8,48:poke b+1,179
970 d=27:gosub 800:if (peek(b) and 32)=32 then print "ram canary $5000-$7fff changed!":return
980 print "ram canary $5000-$7fff ok":return
