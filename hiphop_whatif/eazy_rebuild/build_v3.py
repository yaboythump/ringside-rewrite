from __future__ import annotations
import json, math, random, subprocess, wave, time
from pathlib import Path
from urllib.parse import quote
import numpy as np, requests
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance
ROOT=Path(__file__).resolve().parent; OUT=ROOT/'output'; ASSETS=ROOT/'assets'; AUDIO=ROOT/'audio'; SCENES=ROOT/'scenes'; SEGS=ROOT/'segments'
for d in (OUT,ASSETS,AUDIO,SCENES,SEGS): d.mkdir(parents=True,exist_ok=True)
JOB=json.loads((ROOT/'job.json').read_text()); W,H,FPS=1920,1080,30
FB='/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf'; FR='/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf'
SOURCES=[('la','Los_Angeles_-_Skyline.jpg'),('street','Compton_ave_in_Watts,_California.jpg'),('mic','Microphone_studio.jpg'),('vinyl','Turntable-1328823.jpg'),('tape','Audio_cassette_tapes.jpg'),('crowd','Concert_crowd_(Unsplash).jpg')]
def run(c,l): print('STEP',l,flush=True); subprocess.run(c,check=True)
def duration(p): return float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(p)],text=True).strip())
def ft(s,b=True): return ImageFont.truetype(FB if b else FR,s)
def url(n): return 'https://commons.wikimedia.org/wiki/Special:Redirect/file/'+quote(n,safe='(),_-')
def get(u,minb=10000):
 last=None
 for a in range(7):
  try:
   r=requests.get(u,timeout=120,allow_redirects=True,headers={'User-Agent':'CTNETWORK-HHWI/3.0'}); 
   if r.status_code==429: time.sleep(5+a*4); continue
   r.raise_for_status();
   if len(r.content)<minb: raise RuntimeError('payload too small')
   return r.content
  except Exception as e: last=e; time.sleep(3+a*3)
 raise RuntimeError(f'download failed {u}: {last}')
def fetch():
 for k,n in SOURCES:
  p=ASSETS/(k+Path(n).suffix.lower())
  if not(p.exists() and p.stat().st_size>10000): p.write_bytes(get(url(n))); print('SOURCE',k,p.stat().st_size,flush=True)
  time.sleep(2)
def crop(im,w=W,h=H,bx=.5,by=.5):
 im=im.convert('RGB'); s=max(w/im.width,h/im.height); nw,nh=int(im.width*s),int(im.height*s); im=im.resize((nw,nh),Image.Resampling.LANCZOS); x=int((nw-w)*bx); y=int((nh-h)*by); return im.crop((x,y,x+w,y+h))
def grade(im,i):
 im=ImageEnhance.Contrast(im).enhance(1.27); im=ImageEnhance.Color(im).enhance(.68); a=np.asarray(im).astype(np.float32); a[...,0]*=1.11;a[...,1]*=.87;a[...,2]*=.78
 yy,xx=np.mgrid[0:H,0:W]; q=np.sqrt(((xx-W/2)/(W*.8))**2+((yy-H/2)/(H*.82))**2); a*=np.clip(1-.36*q,.54,1)[...,None]; a+=np.random.default_rng(1000+i).normal(0,6,(H,W,1)); return Image.fromarray(np.clip(a,0,255).astype(np.uint8))
def scene(i):
 k,_=SOURCES[i%len(SOURCES)]; im=Image.open(next(ASSETS.glob(k+'.*'))); im=crop(im,bx=[.08,.25,.43,.62,.82][i%5],by=[.10,.30,.50,.68][i%4]); im=grade(im,i).convert('RGBA')
 glow=Image.new('RGBA',(W,H),(0,0,0,0));g=ImageDraw.Draw(glow,'RGBA'); g.ellipse((-260,-180,760,760),fill=(175,18,28,50)) if i%2==0 else g.ellipse((W-780,-180,W+160,680),fill=(220,150,58,40)); glow=glow.filter(ImageFilter.GaussianBlur(90)); im=Image.alpha_composite(im,glow)
 lay=Image.new('RGBA',(W,H),(0,0,0,0));d=ImageDraw.Draw(lay,'RGBA'); d.rectangle((0,0,W,24),fill=(0,0,0,105));d.rectangle((0,H-28,W,H),fill=(0,0,0,110)); d.text((60,48),'HIP HOP WHAT IF',font=ft(29),fill=(245,240,225,215))
 if i in (2,5,8,11,14,17,20):
  base=1450 if i%2 else 400
  for j in range(1+(i%2)):
   x=base+j*170; d.ellipse((x-62,350,x+62,480),fill=(4,4,6,205));d.rounded_rectangle((x-90,465,x+90,980),36,fill=(4,4,6,220))
 tags={0:'COMPTON • THE REAL STORY',6:'1995 • THE TIMELINE TURNS',9:'RUTHLESS • WHAT COMES NEXT?',12:'THE REUNION THAT COULD HAVE BEEN',15:'THE WEST COAST RIPPLE',18:'LEGACY • BUSINESS • TIME',21:'A DIFFERENT FUTURE'}
 if i in tags:d.text((65,950),tags[i],font=ft(30),fill=(235,199,125,225))
 if i==0:d.text((80,680),'WHAT IF',font=ft(76),fill=(245,240,225,238));d.text((80,758),'EAZY-E',font=ft(118),fill=(230,40,48,248));d.text((80,875),'NEVER DIED?',font=ft(78),fill=(245,240,225,240))
 if i==23:d.text((80,790),'ONE LIFE. A DIFFERENT WEST COAST.',font=ft(62),fill=(245,240,225,235));d.text((80,875),'HIP HOP WHAT IF',font=ft(50),fill=(225,44,52,235))
 return Image.alpha_composite(im,lay).convert('RGB')
def thumb():
 im=crop(Image.open(next(ASSETS.glob('la.*'))),1280,720,.55,.45); im=ImageEnhance.Contrast(im).enhance(1.4); im=ImageEnhance.Color(im).enhance(.64).convert('RGBA'); lay=Image.new('RGBA',(1280,720),(0,0,0,0));d=ImageDraw.Draw(lay,'RGBA');d.rectangle((0,0,1280,720),fill=(0,0,0,105));d.text((55,100),'WHAT IF',font=ImageFont.truetype(FB,70),fill='white');d.text((55,180),'EAZY-E',font=ImageFont.truetype(FB,112),fill=(232,40,48));d.text((55,300),'NEVER DIED?',font=ImageFont.truetype(FB,78),fill='white');d.text((60,575),'A DIFFERENT WEST COAST',font=ImageFont.truetype(FB,36),fill=(232,193,116));d.ellipse((900,115,1110,325),fill=(4,4,6,225));d.rounded_rectangle((845,300,1165,710),65,fill=(4,4,6,232));Image.alpha_composite(im,lay).convert('RGB').save(OUT/'thumbnail.jpg',quality=92)
def music(sec):
 sr=48000;n=int(sec*sr);t=np.arange(n,dtype=np.float32)/sr;a=np.zeros(n,dtype=np.float32);roots=[55.,49.,43.65,49.];bar=60/86*4
 for b in range(int(math.ceil(sec/bar))):
  st=b*bar;r=roots[b%4];s=int(st*sr);e=min(n,int((st+bar)*sr));tt=t[s:e]-st;env=np.minimum(1,tt/.25)*np.minimum(1,(bar-tt)/.4);a[s:e]+=.026*np.sin(2*np.pi*r*tt)*env+.012*np.sin(2*np.pi*r*1.5*tt)*env
 pcm=(np.clip(np.tanh(a*1.1),-1,1)*32767).astype('<i2');w=wave.open(str(OUT/'music.wav'),'wb');w.setnchannels(1);w.setsampwidth(2);w.setframerate(sr);w.writeframes(pcm.tobytes());w.close()
def main():
 fetch();norm=[]
 for i,u in enumerate(JOB['audio_urls']):
  raw=AUDIO/f'r{i}.wav';nw=AUDIO/f'n{i}.wav';raw.write_bytes(get(u,4096));run(['ffmpeg','-y','-v','error','-i',str(raw),'-ar','48000','-ac','2','-c:a','pcm_s16le',str(nw)],f'audio{i}');run(['ffmpeg','-v','error','-i',str(nw),'-f','null','-'],f'audioqc{i}');norm.append(nw)
 (AUDIO/'list.txt').write_text('\n'.join("file '"+p.name+"'" for p in norm)+'\n');run(['ffmpeg','-y','-v','error','-f','concat','-safe','0','-i',str(AUDIO/'list.txt'),'-c:a','pcm_s16le',str(OUT/'narration.wav')],'narration');total=duration(OUT/'narration.wav');
 if total<240:raise RuntimeError('narration too short')
 sd=total/24; rows=[]
 for i in range(24):
  fr=SCENES/f's{i:02d}.jpg';scene(i).save(fr,quality=91);sg=SEGS/f's{i:02d}.mp4';frames=max(1,int(math.ceil(sd*FPS)));z=f"1+0.055*on/{frames}";x="iw/2-(iw/zoom/2)+sin(on/55)*24" if i%2 else "iw/2-(iw/zoom/2)";y="ih/2-(ih/zoom/2)+cos(on/65)*16" if i%3==0 else "ih/2-(ih/zoom/2)";fo=max(.2,sd-.35);vf=f"scale=2220:1249,zoompan=z='{z}':x='{x}':y='{y}':d={frames}:s=1920x1080:fps={FPS},fade=t=in:st=0:d=.25,fade=t=out:st={fo:.3f}:d=.30,format=yuv420p";run(['ffmpeg','-y','-v','error','-loop','1','-i',str(fr),'-t',f'{sd:.3f}','-vf',vf,'-an','-c:v','libx264','-preset','veryfast','-crf','20',str(sg)],f'scene{i}');rows.append(f"file '{sg.as_posix()}'")
 (ROOT/'visuals.txt').write_text('\n'.join(rows)+'\n');run(['ffmpeg','-y','-v','error','-f','concat','-safe','0','-i',str(ROOT/'visuals.txt'),'-c','copy',str(OUT/'visual.mp4')],'visual');music(total+2);run(['ffmpeg','-y','-v','error','-i',str(OUT/'visual.mp4'),'-i',str(OUT/'narration.wav'),'-i',str(OUT/'music.wav'),'-filter_complex','[1:a]volume=1[a1];[2:a]volume=.16[a2];[a1][a2]amix=inputs=2:duration=first,alimiter=limit=.94[a]','-map','0:v','-map','[a]','-c:v','copy','-c:a','aac','-b:a','192k','-shortest',str(OUT/'full.mp4')],'master');thumb()
 for i,st in enumerate([5,72,142,214,282],1):
  md=max(20,min(55,total-st-2));run(['ffmpeg','-y','-v','error','-ss',str(st),'-i',str(OUT/'full.mp4'),'-t',str(md),'-vf','scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1','-c:v','libx264','-preset','veryfast','-crf','20','-c:a','aac','-b:a','160k',str(OUT/f'short_{i:02d}.mp4')],f'short{i}')
 sheet=Image.new('RGB',(1920,720),(0,0,0));
 for j,i in enumerate([0,4,8,12,16,20]):sheet.paste(Image.open(SCENES/f's{i:02d}.jpg').resize((640,360),Image.Resampling.LANCZOS),((j%3)*640,(j//3)*360))
 sheet.save(OUT/'internal_preview.jpg',quality=88);print('BUILD_PASS',total,flush=True)
if __name__=='__main__':main()