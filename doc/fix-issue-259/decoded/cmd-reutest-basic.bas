    5 print"{clr}{wht}":poke53280,0:poke53281,0:ifpeek(65533)=255then&:ifpeek(215)=128then{CTRL-Z}20,0,59,24
   10 print chr$(14)"{clr}        CMD 1750/1750XL REU Test"
   20 print"{lblu}           (c) 1997 CMD, Inc.
   22 print"{grn} {SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{yel}"
   24 sa=peek(174)+peek(175)*256-3
   25 sys sa
   30 ml=3*4096:sb=250
   32 h$="0123456789abcdef"
   40 sys ml:ifpeek(sb)<>0then1000
   42 ifabs((peek(53433)and128)=128)=0then1140
   50 :
   52 gosub1200
   60 sys ml+3:sz=peek(sb)*64:gosub1100
   70 :
   80 print"{cyn} Testing Computer Buffer Memory: ";
   90 sys ml+6:ifpeek(sb)<>0then1400
   92 print"{wht}OK"
   93 :
  100 print"{cyn} Testing Block/Page Addressing : ";
  110 sys ml+9:ifpeek(sb)<>0then1500
  120 print"{wht}OK"
  122 :
  130 print"{cyn} Testing Byte Addressing       : ";
  140 sys ml+12:ifpeek(sb)<>0then1500
  142 print"{wht}OK"
  149 :
  150 print"{cyn} Testing Interrupt Register    : ";
  152 sys ml+18:ifpeek(sb)<>0then1500
  154 print"{wht}OK"
  159 :
  160 print"{cyn} Testing Address Control       : ";
  166 sys ml+21:ifpeek(sb)<>0then1500
  168 print"{wht}OK"
  169 :
  170 print"{cyn} Testing $FF00 Option          : ";
  176 sys ml+24:ifpeek(sb)<>0then1500
  178 print"{wht}OK"
  179 :
  180 print"{cyn} Testing CBR Refresh Integrity : ";
  181 pokesb,170:sys ml+27:ifpeek(sb)<>0then1500
  182 ti$="000000"
  183 t=int(ti/60):ift<10then183
  184 sys ml+30:ifpeek(sb)<>0then1500
  186 print"{wht}OK"
  187 :
  190 print"{cyn} Testing Bit Fill Pattern      : ";
  191 fori=0to255 step 17:pokesb,i
  192 ln$=mid$(h$,(iand15)+1,1):hn$=mid$(h$,int(i/16)+1,1)
  193 print"{left}{left}{left}{left}{left}{left}{left}("hn$ln$") : ";
  194 sys ml+15:ifpeek(sb)<>0then1500
  195 next
  196 print"{wht}OK"
  197 :
  200 print"{down}{yel} Test Successful! No Errors Encountered"
  900 goto1600
  999 :
 1000 print"{home}{down}{down}{down}{yel} REU not found! Possible bad connection"
 1010 print" or faulty computer."
 1020 goto1600
 1099 :
 1100 print"{home}{down}{down}{down}{yel} REU Capacity:{wht}";
 1110 ifsz<1024thenprintsz"{left}K"
 1120 ifsz>1023thenprint(sz/1024)"{left}MB"
 1122 print"{grn} {SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}"
 1130 return
 1139 :
 1140 print"{home}{down}{down}{down}{yel} WARNING: CMD SuperCPU found! Please"
 1150 print" disable it and run the test again!"
 1160 goto1600
 1169 :
 1199 :
 1200 print"{home}{down}{down}{down}{yel} WARNING: All data currently in the REU"
 1210 print" will be erased. Continue (Y/N)?"
 1220 geta$:ifa$=""then1220
 1230 ifa$<>"y"thengoto1600
 1240 print"{home}{down}{down}{down}                                       "
 1250 print"                                       "
 1260 return
 1299 :
 1400 print"{wht}Error!"
 1410 print"{down}{yel} Unreliable memory detected in your"
 1420 print" computer. Repairs may be necessary."
 1430 print" If possible, try testing your REU on"
 1440 print" another computer."
 1450 goto1600
 1499 :
 1500 print"{wht}Error!"
 1510 print"{down}{yel} There may be a poor connection between"
 1520 print" the REU and your computer, or your "
 1530 print" computer may have a faulty component."
 1540 print" Shut off your computer, remove the REU"
 1550 print" and check the cartridge port contacts."
 1560 print" If errors persist, your computer may"
 1570 print"{$a0}need repairs. If possible, try testing"
 1580 print" your REU on another computer before"
 1590 print" contacting CMD."
 1600 print"{wht} Press <RETURN> to end program"
 1610 geta$:ifa$<>chr$(13)then1610
 1620 print"{clr}{home}{home}"
 1630 new
