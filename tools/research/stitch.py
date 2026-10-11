import sys,os,urllib.request,maid
from PIL import Image
maid.loadlf()
UA={"User-Agent":"dungeon-map-tools/0.1"}
def run(m,s=256):
    t=maid.tiles(f'wdt/{m}.wdt'); good=[]
    for x,y,v in t:
        p=f'tiles/{m}_{x}_{y}.blp'
        if not os.path.exists(p):
            try: open(p,'wb').write(urllib.request.urlopen(urllib.request.Request(f"https://wago.tools/api/casc/{v[7]}?download&version=1.60.1.70291",headers=UA)).read())
            except Exception as e: print('miss',m,x,y,v[7],e); continue
        good.append((x,y))
    x0=min(x for x,_ in good); y0=min(y for _,y in good); x1=max(x for x,_ in good); y1=max(y for _,y in good)
    im=Image.new('RGB',((x1-x0+1)*s,(y1-y0+1)*s),(0,0,0)); sizes=set()
    for x,y in good:
        b=Image.open(f'tiles/{m}_{x}_{y}.blp'); sizes.add(b.size); b=b.convert('RGB').resize((s,s))
        im.paste(b,((x-x0)*s,(y-y0)*s))
    im.save(f'st_{m}.png'); print(m,len(good),'tiles',im.size,sizes)
for m in sys.argv[1:]: run(m)
