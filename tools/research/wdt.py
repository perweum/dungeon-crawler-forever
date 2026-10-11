import struct,sys
def chunks(b):
    o=0
    while o+8<=len(b):
        tag=b[o:o+4][::-1].decode('latin1'); sz=struct.unpack('<I',b[o+4:o+8])[0]
        yield tag,b[o+8:o+8+sz]; o+=8+sz
def parse(path):
    b=open(path,'rb').read(); res={}
    for t,d in chunks(b):
        res[t]=d
    return res
if __name__=='__main__':
    r=parse(sys.argv[1])
    print({k:len(v) for k,v in r.items()})
    if 'MPHD' in r: print('MPHD flags',struct.unpack('<I',r['MPHD'][:4]))
    if 'MAIN' in r:
        n=sum(1 for i in range(64*64) if struct.unpack('<II',r['MAIN'][i*8:i*8+8])[0]&1)
        print('adts',n)
    if 'MWMO' in r: print(r['MWMO'].split(b'\0')[:5])
    if 'MODF' in r:
        for i in range(0,len(r['MODF']),64):
            print(struct.unpack('<II3f3f6fHHHH',r['MODF'][i:i+64]))
