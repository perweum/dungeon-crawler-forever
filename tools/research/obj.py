import sys,os,struct,urllib.request,maid
from wdt import chunks
maid.loadlf()
UA={"User-Agent":"dungeon-map-tools/0.1"}
def get(fid,path):
    if not os.path.exists(path):
        open(path,'wb').write(urllib.request.urlopen(urllib.request.Request(f"https://wago.tools/api/casc/{fid}?download&version=1.60.1.70291",headers=UA)).read())
    return open(path,'rb').read()
def wmos(m):
    res={}
    for x,y,v in maid.tiles(f'wdt/{m}.wdt'):
        try: b=get(v[1],f'obj/{m}_{x}_{y}.adt')
        except Exception as e: continue
        c=dict(chunks(b))
        if 'MODF' not in c: continue
        mwid=struct.unpack(f'<{len(c["MWID"])//4}I',c['MWID']) if 'MWID' in c else ()
        for i in range(0,len(c['MODF']),64):
            nid,uid=struct.unpack('<II',c['MODF'][i:i+8])
            fid=mwid[nid] if nid<len(mwid) else None
            res.setdefault(fid,[]).append((x,y,uid))
    return res
if __name__=='__main__':
    for m in sys.argv[1:]:
        r=wmos(m); print(m,len(r))
        for f,l in r.items(): print('  ',f,maid.lf.get(f),len(l))
