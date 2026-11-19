#!/usr/bin/env python3
"""Genera el icono de la app (1024x1024, sin transparencia). Uso: python3 scripts/generate-app-icon.py [grados]"""
from PIL import Image, ImageDraw, ImageFilter
import math, sys
S=4096; F=S/1024
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
# background vertical gradient
bg=Image.new('RGB',(S,S))
top=(22,30,56); bot=(6,9,20)
d=ImageDraw.Draw(bg)
for y in range(S):
    d.line([(0,y),(S,y)],fill=lerp(top,bot,y/S))
# glow
glow=Image.new('L',(S,S),0)
gd=ImageDraw.Draw(glow)
r=int(330*F); c=S//2
gd.ellipse([c-r,c-r,c+r,c+r],fill=255)
glow=glow.filter(ImageFilter.GaussianBlur(160*F))
glowcol=Image.new('RGB',(S,S),(33,107,255))
bg=Image.composite(glowcol,bg,glow.point(lambda v:int(v*0.55)))
# dumbbell mask (horizontal, centered), then rotate
m=Image.new('L',(S,S),0); md=ImageDraw.Draw(m)
def rr(cx,cy,w,h,rad):
    md.rounded_rectangle([c+(cx-w/2)*F, c+(cy-h/2)*F, c+(cx+w/2)*F, c+(cy+h/2)*F], radius=rad*F, fill=255)
k=0.88
def r2(cx,cy,w,h,rad): rr(cx*k,cy*k,w*k,h*k,rad*k)
r2(0,0,760,50,25)          # bar
for sx in (-1,1):
    r2(sx*200,0,70,240,30)  # inner plate
    r2(sx*290,0,86,340,38)  # outer plate
    r2(sx*370,0,44,96,20)   # end cap
m=m.rotate(35 if len(sys.argv)<2 else float(sys.argv[1]), resample=Image.BICUBIC, center=(c,c))
# gradient fill for dumbbell
fill=Image.new('RGB',(S,S)); fd=ImageDraw.Draw(fill)
a=(140,195,255); b=(33,107,255)
for y in range(S):
    fd.line([(0,y),(S,y)],fill=lerp(a,b,min(1,max(0,(y-S*0.22)/(S*0.56)))))
# soft shadow
sh=m.filter(ImageFilter.GaussianBlur(30*F)).point(lambda v:int(v*0.5))
bg=Image.composite(Image.new('RGB',(S,S),(0,0,0)),bg,sh)
out=Image.composite(fill,bg,m)
out=out.resize((1024,1024),Image.LANCZOS)
out.save('GymTracker/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png')
