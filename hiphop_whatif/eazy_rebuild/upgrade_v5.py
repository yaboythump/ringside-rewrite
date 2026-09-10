from __future__ import annotations
import json, math, subprocess, time
from pathlib import Path
import requests, numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

ROOT=Path(__file__).resolve().parent
PREV=ROOT/'previous'; OUT=ROOT/'upgrade_output'; ASSETS=ROOT/'upgrade_assets'; FRAMES=ROOT/'upgrade_frames'; SEGS=ROOT/'upgrade_segments'
for d in (OUT,ASSETS,FRAMES,SEGS): d.mkdir(parents=True,exist_ok=True)
W,H,FPS=1920,1080,30
FB='/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf'

SOURCES={
 'nwa':('https://upload.wikimedia.org/wikipedia/commons/8/81/NWA_%281988_or_1989_Ruthless_press_photo%29.png','png'),
 'eazy_sketch':('https://upload.wikimedia.org/wikipedia/commons/0/07/Sketch_of_Eazy-E.jpg','jpg'),
 'bone':('https://live.staticflickr.com/4022/4458099309_cb765f8499_o.jpg','jpg'),
 'compton':('https://upload.wikimedia.org/wikipedia/commons/b/ba/Compton_sign.jpg','jpg'),
 'dre':('https://upload.wikimedia.org/wikipedia/commons/b/ba/Dr._Dre.jpg','jpg'),
 'ren':('https://upload.wikimedia.org/wikipedia/commons/b/bc/MC_Ren_of_NWA_Los_Angeles_1990_photographed_by_Ithaka_Darin_Pappas.jpg','jpg'),
 'yella':('https://upload.wikimedia.org/wikipedia/commons/1/12/DJ_Yella.jpg','jpg'),
}
# 12 subject-specific replacements across the 24-scene master.
PLAN={0:('nwa',.62,'THE QUESTION'),2:('compton',.50,'COMPTON'),4:('eazy_sketch',.52,'EAZY-E'),6:('nwa',.53,'1995 • THE TIMELINE TURNS'),8:('bone',.50,'RUTHLESS • THE NEXT GENERATION'),10:('ren',.48,'N.W.A. • UNFINISHED BUSINESS'),12:('nwa',.55,'THE REUNION THAT COULD HAVE BEEN'),14:('dre',.50,'FEUD → BUSINESS?'),16:('yella',.50,'THE GROUP DYNAMIC CHANGES'),18:('bone',.45,'THE WEST COAST RIPPLE'),20:('eazy_sketch',.58,'TIME CHANGES LEGACY'),22:('nwa',.68,'A DIFFERENT FUTURE')}

def run(c,l): print('STEP',l,flush=True); subprocess.run(c,check=True)
def probe(p): return float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(p)],text=True).strip())
def ft(s): return ImageFont.truetype(FB,s)
def get(url):
 last=None
 for a in range(5):
  try:
   r=requests.get(url,timeout=120,headers={'User-Agent':'CTNETWORK-HHWI/5.0'}); r.raise_for_status()
   if len(r.content)<30000: raise RuntimeError(f'small source {len(r.content)}')
   return r.content
  except Exception as e: last=e; time.sleep(2+a*2)
 raise RuntimeError(f'failed source {url}: {last}')

def download():
 for k,(u,ext) in SOURCES.items():
  p=ASSETS/f'{k}.{ext}'
  if not(p.exists() and p.stat().st_size>30000): p.write_bytes(get(u))
  print('SOURCE',k,p.stat().st_size,flush=True)

def crop_fill(im,bx=.5,by=.5):
 im=im.convert('RGB'); scale=max(W/im.width,H/im.height); nw,nh=int(im.width*scale),int(im.height*scale)
 im=im.resize((nw,nh),Image.Resampling.LANCZOS); x=int(max(0,nw-W)*max(0,min(1,bx))); y=int(max(0,nh-H)*max(0,min(1,by))); return im.crop((x,y,x+W,y+H))

def portrait_canvas(im,side='right'):
 # Full-screen cinematic photo treatment: same photo blurred as environment, sharp subject over it. No card/panel.
 bg=crop_fill(im,.5,.45).filter(ImageFilter.GaussianBlur(32)); bg=ImageEnhance.Brightness(bg).enhance(.52).convert('RGBA')
 fg=im.convert('RGB'); scale=min(850/fg.width,980/fg.height); fg=fg.resize((int(fg.width*scale),int(fg.height*scale)),Image.Resampling.LANCZOS).convert('RGBA')
 # feather a soft photographic edge instead of a rectangular card
 mask=Image.new('L',fg.size,255); mask=mask.filter(ImageFilter.GaussianBlur(2)); fg.putalpha(mask)
 x=W-fg.width-130 if side=='right' else 130; y=H-fg.height
 bg.alpha_composite(fg,(x,y)); return bg.convert('RGB')

def make_frame(idx,key,bias,label):
 im=Image.open(ASSETS/f'{key}.{SOURCES[key][1]}')
 if im.height>im.width*1.18: base=portrait_canvas(im,'right' if idx%4 else 'left')
 else: base=crop_fill(im,bias,.48)
 base=ImageEnhance.Contrast(base).enhance(1.22); base=ImageEnhance.Color(base).enhance(.72)
 a=np.asarray(base).astype(np.float32); a[...,0]*=1.08; a[...,1]*=.88; a[...,2]*=.80
 yy,xx=np.mgrid[0:H,0:W]; dist=np.sqrt(((xx-W/2)/(W*.82))**2+((yy-H/2)/(H*.84))**2); a*=np.clip(1-.32*dist,.60,1.0)[...,None]; a+=np.random.default_rng(5000+idx).normal(0,5,(H,W,1)); base=Image.fromarray(np.clip(a,0,255).astype(np.uint8)).convert('RGBA')
 light=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(light,'RGBA'); d.ellipse((-260,-140,760,760),fill=(180,18,28,45)) if idx%4==0 else d.ellipse((W-820,-170,W+200,720),fill=(214,144,54,32)); light=light.filter(ImageFilter.GaussianBlur(100)); base=Image.alpha_composite(base,light)
 ov=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(ov,'RGBA'); d.text((60,48),'HIP HOP WHAT IF',font=ft(30),fill=(245,240,225,220)); d.text((62,952),label,font=ft(31),fill=(235,199,125,230))
 if idx==0:
  d.text((80,650),'WHAT IF',font=ft(76),fill=(245,240,225,240)); d.text((80,730),'EAZY-E',font=ft(118),fill=(232,40,49,250)); d.text((80,850),'NEVER DIED?',font=ft(78),fill=(245,240,225,242))
 return Image.alpha_composite(base,ov).convert('RGB')

def make_thumb():
 nwa=Image.open(ASSETS/'nwa.png'); base=crop_fill(nwa,.62,.45).resize((1280,720),Image.Resampling.LANCZOS); base=ImageEnhance.Contrast(base).enhance(1.35); base=ImageEnhance.Color(base).enhance(.60).convert('RGBA')
 ov=Image.new('RGBA',(1280,720),(0,0,0,0)); d=ImageDraw.Draw(ov,'RGBA'); d.rectangle((0,0,1280,720),fill=(0,0,0,85)); d.rectangle((0,0,720,720),fill=(0,0,0,75)); d.text((45,80),'WHAT IF',font=ImageFont.truetype(FB,70),fill='white'); d.text((45,160),'EAZY-E',font=ImageFont.truetype(FB,112),fill=(232,40,48)); d.text((45,280),'NEVER DIED?',font=ImageFont.truetype(FB,76),fill='white'); d.text((50,585),'A DIFFERENT WEST COAST',font=ImageFont.truetype(FB,34),fill=(235,199,125)); Image.alpha_composite(base,ov).convert('RGB').save(OUT/'thumbnail.jpg',quality=92)

def main():
 old=PREV/'full.mp4'
 if not old.exists(): raise RuntimeError(f'missing previous full: {old}')
 download(); total=probe(old); sd=total/24; rows=[]
 for i in range(24):
  st=i*sd; seg=SEGS/f's{i:02d}.mp4'
  if i in PLAN:
   key,bias,label=PLAN[i]; fr=FRAMES/f'f{i:02d}.jpg'; make_frame(i,key,bias,label).save(fr,quality=92)
   frames=max(1,int(math.ceil(sd*FPS))); z=f"1+0.048*on/{frames}"; x="iw/2-(iw/zoom/2)+sin(on/58)*18"; y="ih/2-(ih/zoom/2)+cos(on/70)*12"; vf=f"scale=2200:1238,zoompan=z='{z}':x='{x}':y='{y}':d={frames}:s=1920x1080:fps={FPS},format=yuv420p"
   run(['ffmpeg','-y','-v','error','-loop','1','-i',str(fr),'-ss',f'{st:.3f}','-i',str(old),'-t',f'{sd:.3f}','-vf',vf,'-map','0:v:0','-map','1:a:0','-c:v','libx264','-preset','veryfast','-crf','20','-c:a','aac','-b:a','192k','-shortest',str(seg)],f'replace scene {i}')
  else:
   run(['ffmpeg','-y','-v','error','-ss',f'{st:.3f}','-i',str(old),'-t',f'{sd:.3f}','-vf','format=yuv420p','-c:v','libx264','-preset','veryfast','-crf','20','-c:a','aac','-b:a','192k',str(seg)],f'keep scene {i}')
  rows.append(f"file '{seg.as_posix()}'")
 (ROOT/'upgrade_list.txt').write_text('\n'.join(rows)+'\n'); run(['ffmpeg','-y','-v','error','-f','concat','-safe','0','-i',str(ROOT/'upgrade_list.txt'),'-c','copy',str(OUT/'full.mp4')],'concat upgraded master')
 run(['ffmpeg','-v','error','-i',str(OUT/'full.mp4'),'-f','null','-'],'decode upgraded master'); make_thumb()
 # Re-cut five Shorts from the upgraded master
 for n,st in enumerate([5,72,142,214,282],1):
  md=max(20,min(55,total-st-2)); run(['ffmpeg','-y','-v','error','-ss',str(st),'-i',str(OUT/'full.mp4'),'-t',str(md),'-vf','scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1','-c:v','libx264','-preset','veryfast','-crf','20','-c:a','aac','-b:a','160k',str(OUT/f'short_{n:02d}.mp4')],f'short {n}')
 # Preview every replacement scene; internal QC only, never used in final master.
 sheet=Image.new('RGB',(1920,1440),(0,0,0)); ids=list(PLAN.keys())
 for j,i in enumerate(ids): sheet.paste(Image.open(FRAMES/f'f{i:02d}.jpg').resize((480,270),Image.Resampling.LANCZOS),((j%4)*480,(j//4)*270))
 sheet.save(OUT/'internal_preview_v5.jpg',quality=90)
 print('UPGRADE_PASS',probe(OUT/'full.mp4'),flush=True)
if __name__=='__main__': main()
