import json,struct,csv,collections,os,urllib.request
from wdt import chunks
import maid; maid.loadlf()
UA={"User-Agent":"dungeon-map-tools/0.1"}
allw=json.load(open('allwmo.json'))
W=collections.defaultdict(list)
for r in csv.DictReader(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'data', 'raw', '1.60.1.70291/WMOMinimapTexture.csv'))): W[int(r['WMOID'])].append(r)
fids=sorted({int(f) for m in allw.values() for f in m})
print(len(fids),'distinct WMO files',flush=True)
info={}
os.makedirs('wmoroot',exist_ok=True)
for f in fids:
    p=f'wmoroot/{f}.wmo'
    try:
        if not os.path.exists(p):
            req=urllib.request.Request(f"https://wago.tools/api/casc/{f}?download&version=1.60.1.70291",headers=UA)
            open(p,'wb').write(urllib.request.urlopen(req).read())
        b=open(p,'rb').read(); c=dict(chunks(b)); mo=c['MOHD']
        info[f]=struct.unpack('<I',mo[32:36])[0] if len(mo)>=36 else None
        info[f]=(info[f],struct.unpack('<I',mo[4:8])[0])
    except Exception as e: info[f]=None
json.dump(info,open('wmoinfo.json','w'))
for m,ws in allw.items():
    rows=[]
    for f,n in ws.items():
        i=info.get(int(f))
        if i and i[0] in W:
            rows.append((i[0],maid.lf.get(int(f)),i[1],len(W[i[0]]),n))
    print('==',m,'WMOs with minimap tiles:',len(rows),'of',len(ws))
    for r in sorted(rows,key=lambda r:-r[3])[:8]: print('   wmoid',r[0],r[1],'groups',r[2],'tiles',r[3],'placements',r[4])
