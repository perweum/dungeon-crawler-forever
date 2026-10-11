import struct,csv,sys,os,urllib.request
from PIL import Image
from wdt import chunks
UA={"User-Agent":"dungeon-map-tools/0.1"}
def get(fid,p):
    if not os.path.exists(p): open(p,'wb').write(urllib.request.urlopen(urllib.request.Request(f"https://wago.tools/api/casc/{fid}?download&version=1.60.1.70291",headers=UA)).read())
def run(wid,rootfid,variant):
    get(rootfid,f'wmot/{wid}.wmo')
    c=dict(chunks(open(f'wmot/{wid}.wmo','rb').read())); n=struct.unpack('<I',c['MOHD'][4:8])[0]
    G={}
    for i in range(n):
        fl,x0,y0,z0,x1,y1,z1,no=struct.unpack('<I6fi',c['MOGI'][i*32:i*32+32]); G[i]=(x0,y0,z0,x1,y1,z1)
    T=[r for r in csv.DictReader(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'data', 'raw', '1.60.1.70291/WMOMinimapTexture.csv'))) if r['WMOID']==str(wid)]
    xmin=min(g[0] for g in G.values()); xmax=max(g[3] for g in G.values()); ymin=min(g[1] for g in G.values()); ymax=max(g[4] for g in G.values())
    NB={}
    for r in T: NB[int(r['GroupNum'])]=max(NB.get(int(r['GroupNum']),0),int(r['BlockY'])+1)
    S=2; W=int((ymax-ymin)*S)+300; H=int((xmax-xmin)*S)+300; print(W,H)
    im=Image.new('RGBA',(W,H),(0,0,0,255))
    for r in sorted(T,key=lambda r:int(r['GroupNum'])):
        g=int(r['GroupNum']); get(r['FileDataID'],f"wmot/{r['FileDataID']}.blp")
        b=Image.open(f"wmot/{r['FileDataID']}.blp").convert('RGBA'); bxx,byy=int(r['BlockX']),int(r['BlockY'])
        x0,y0,_,x1,y1,_=G[g]
        if variant==0: px=(ymax-y1)*S+bxx*256; py=(xmax-x1)*S+byy*256
        elif variant==1: px=(y0-ymin)*S+bxx*256; py=(xmax-x1)*S+byy*256
        elif variant==2: px=(x0-xmin)*S+bxx*256; py=(y0-ymin)*S+byy*256
        elif variant==3: px=(ymax-y1)*S+byy*256; py=(xmax-x1)*S+bxx*256
        elif variant==4: px=(ymax-y1)*S+(4-bxx)*256 if g==14 else (ymax-y1)*S+bxx*256; py=(xmax-x1)*S+byy*256
        else: px=(ymax-y1)*S+bxx*256; py=(xmax-x1)*S+(NB[g]-1-byy)*256
        im.alpha_composite(b,(int(px),int(py)))
    im.save(f'wmo_{wid}_v{variant}.png'); print(im.size,Image.open(f"wmot/{T[0]['FileDataID']}.blp").size)
run(int(sys.argv[1]),int(sys.argv[2]),int(sys.argv[3]))
