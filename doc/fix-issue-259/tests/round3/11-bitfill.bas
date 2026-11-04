10 print chr$(147)"11-bitfill: cmd bit fill chain in ml"
15 print "16kb, c64 $5000, pattern $aa, bank 0 x4"
16 print "r=fixed-reu verifies faulted (of 4)"
17 print "c=fixed-c64 verifies faulted (of 4)"
18 print "1st=first fault: quarter*2+1 (r) or +2 (c)"
20 b=57088:x=peek(b):for v=0 to 9:read v$:poke 3075,v:sys 3072
30 print v$":r"peek(3076)"c"peek(3078)"cpu"peek(3077)"1st"peek(3079):next:end
40 data "0 exact chain","1 no swap","2 no sprites","3 cli (irq on)"
50 data "4 no $ff00","5 no fetch","6 stash+verc","7 stash+verr+verc"
60 data "8 exact+planted err","9 as 8, display off"
