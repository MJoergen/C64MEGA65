import sys
d=open(sys.argv[1],'rb').read()
r=lambda a:d[a-0x8000]
seen={}
for job in range(0x80,0x100):
    idx=r(0xC1E7+job)
    seen.setdefault(idx,[]).append(job)
for idx,jobs in sorted(seen.items()):
    if idx>40: continue
    h=r(0xC1A5+2*idx)|r(0xC1A6+2*idx)<<8
    m=r(0xC163+idx); m2=r(0xC184+idx)
    js=' '.join('%02X'%j for j in jobs)
    st=[n for b,n in zip(range(7,-1,-1),['cache','b6','motor','ready','RA','cachetrk','jobtrk','side']) if m>>b&1]
    print('idx %2d  handler $%04X  mask %s %-40s $86=%02X  jobs: %s'%(idx,h,format(m,'08b'),'+'.join(st),m2,js if len(js)<40 else js[:40]+'...'))
