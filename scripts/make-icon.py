import sys, json, os
from PIL import Image, ImageDraw, ImageFilter
S=1024
out=sys.argv[1]
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(len(a)))
img=Image.new("RGBA",(S,S),(0,0,0,0))
# background squircle-ish
bg=Image.new("RGBA",(S,S),(0,0,0,0))
m=100
grad=Image.new("RGBA",(S,S))
gd=ImageDraw.Draw(grad)
for y in range(S):
    gd.line([(0,y),(S,y)],fill=lerp((44,30,40,255),(18,14,22,255),y/S))
mask=Image.new("L",(S,S),0)
ImageDraw.Draw(mask).rounded_rectangle([m,m,S-m,S-m],radius=185,fill=255)
img.paste(grad,(0,0),mask)
# mascot geometry (unit, y-down) scaled into box
bx,by,bw=262,250,500
def P(x,y): return (bx+x*bw, by+y*bw)
body=Image.new("L",(S,S),0); bd=ImageDraw.Draw(body)
def cubic(p0,c1,c2,p1,n=60):
    pts=[]
    for i in range(n+1):
        t=i/n; u=1-t
        pts.append((u**3*p0[0]+3*u*u*t*c1[0]+3*u*t*t*c2[0]+t**3*p1[0], u**3*p0[1]+3*u*u*t*c1[1]+3*u*t*t*c2[1]+t**3*p1[1]))
    return pts
SEGS=[((0.54,0.03),(0.62,0.22),(0.88,0.36),(0.88,0.62)),
      ((0.88,0.62),(0.88,0.82),(0.71,0.96),(0.50,0.96)),
      ((0.50,0.96),(0.29,0.96),(0.12,0.82),(0.12,0.62)),
      ((0.12,0.62),(0.12,0.46),(0.22,0.38),(0.30,0.26)),
      ((0.30,0.26),(0.34,0.34),(0.40,0.38),(0.44,0.36)),
      ((0.44,0.36),(0.46,0.24),(0.46,0.12),(0.54,0.03))]
def quad(p0,c,p1,n=60):
    return [((1-t)**2*p0[0]+2*(1-t)*t*c[0]+t*t*p1[0],(1-t)**2*p0[1]+2*(1-t)*t*c[1]+t*t*p1[1]) for t in [i/n for i in range(n+1)]]
flame=[]
for a,b,c,d_ in SEGS: flame+=cubic(P(*a),P(*b),P(*c),P(*d_))
bd.polygon(flame,fill=255)
# glow
glow=Image.new("RGBA",(S,S),(255,140,40,0))
gl=body.filter(ImageFilter.GaussianBlur(60))
glow.putalpha(gl.point(lambda v:int(v*0.75)))
img=Image.alpha_composite(img,Image.composite(glow,Image.new("RGBA",(S,S),(0,0,0,0)),mask))
# body gradient
bgrad=Image.new("RGBA",(S,S)); bgd=ImageDraw.Draw(bgrad)
top,bot=by,by+0.95*bw
for y in range(S):
    t=min(max((y-top)/(bot-top),0),1)
    bgd.line([(0,y),(S,y)],fill=lerp((255,214,110,255),(240,92,30,255),t))
img.paste(bgrad,(0,0),body)
d=ImageDraw.Draw(img)
ink=(42,20,16,255)
for cx in (0.36,0.64):
    ex,ey=P(cx,0.64); w,h=0.11*bw/2,0.16*bw/2
    d.ellipse([ex-w,ey-h,ex+w,ey+h],fill=ink)
d.line(quad(P(0.43,0.79),P(0.5,0.85),P(0.57,0.79)),fill=ink,width=22,joint="curve")
for p in [P(0.43,0.79),P(0.57,0.79)]:
    d.ellipse([p[0]-11,p[1]-11,p[0]+11,p[1]+11],fill=ink)
img.save(os.path.join(out,"icon_1024.png"))
images=[]
for base in (16,32,128,256,512):
    for scale in (1,2):
        px=base*scale
        name=f"icon_{base}x{base}{'@2x' if scale==2 else ''}.png"
        img.resize((px,px),Image.LANCZOS).save(os.path.join(out,name))
        images.append({"idiom":"mac","size":f"{base}x{base}","scale":f"{scale}x","filename":name})
os.remove(os.path.join(out,"icon_1024.png"))
json.dump({"images":images,"info":{"author":"xcode","version":1}},open(os.path.join(out,"Contents.json"),"w"),indent=2)
