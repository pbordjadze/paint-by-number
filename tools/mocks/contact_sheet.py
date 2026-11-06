import sys
from PIL import Image, ImageDraw
out=sys.argv[1]; files=sys.argv[2:]
W=420
ims=[Image.open(f).convert('RGB') for f in files]
ims=[i.resize((W,int(i.height*W/i.width))) for i in ims]
H=max(i.height for i in ims)+30
sheet=Image.new('RGB',(W*len(ims)+10*(len(ims)-1),H),'white')
d=ImageDraw.Draw(sheet)
for k,(i,f) in enumerate(zip(ims,files)):
    x=k*(W+10); sheet.paste(i,(x,30)); d.text((x+4,8),f.split('/')[-1].replace('iphone-','').replace('.png','')[:60],fill='black')
sheet.save(out)
