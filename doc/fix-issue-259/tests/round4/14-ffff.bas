10 print chr$(147)"14-ffff: verify w/ kernal out, $ffff set"
15 print "256b inc. verify, uniform data, display on"
20 print "faults iff data<>255: data bus floats"
25 print "faults iff data<>$ffff: ram $ffff served"
30 for k=0 to 3:read d,f:poke 3075,d:poke 3076,f:poke 3077,50:sys 3072
40 print "data"d" ram $ffff"f":"peek(3078)" faults in 50";
45 if (peek(3079) and 32)=32 then print " (fault w/ display off!)";
50 print:next:end
60 data 255,0,0,0,0,255,255,255
