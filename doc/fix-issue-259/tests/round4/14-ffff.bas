10 print chr$(147)"14-ffff: verify, kernal out, $ffff set"
15 print "256b verify at $2000 from raster 50, x10"
20 print "d=data, f=byte at $ffff and in the"
25 print "ranges a drifting address can reach"
30 print "faults iff d<>255: data bus floats"
35 print "faults iff d<>f: ram at $ffff served"
40 print "  d   f  faults  byte"
50 for k=0 to 6:read d,f:poke 3075,d:poke 3076,f:poke 3077,10:sys 3072
60 n=peek(3078):print d;f;n;:if n>0 then print peek(3080)+256*peek(3081)-8193;
65 if (peek(3079) and 32)=32 then print " (fault w/ display off!)";
70 print:next:end
80 data 255,0,0,0,0,255,255,255,85,170,170,85,170,170
