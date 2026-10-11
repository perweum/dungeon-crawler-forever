import struct,sys
from wdt import parse
lf={}
def loadlf():
    for l in open('lf.csv',encoding='utf-8'):
        i,_,p=l.rstrip('\n').partition(';'); lf[int(i)]=p
def tiles(path):
    r=parse(path); main=r['MAIN']; maid=r['MAID']; out=[]
    for i in range(4096):
        f=struct.unpack('<I',main[i*8:i*8+4])[0]
        if f&1:
            v=struct.unpack('<8I',maid[i*32:i*32+32])
            out.append((i%64,i//64,v))  # x=col? MAIN index = y*64+x
    return out
if __name__=='__main__':
    loadlf()
    t=tiles(sys.argv[1])
    print(len(t))
    for x,y,v in t[:6]: print(x,y,v,[lf.get(a) for a in v[5:]])
    print(sum(1 for _,_,v in t if v[7]), 'with minimap fid;', sum(1 for _,_,v in t if v[7] and v[7] in lf),'named')
    xs=[x for x,_,_ in t]; ys=[y for _,y,_ in t]; print('x',min(xs),max(xs),'y',min(ys),max(ys))
