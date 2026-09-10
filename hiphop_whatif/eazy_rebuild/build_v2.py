from __future__ import annotations

import json, math, random, subprocess, wave, time
from pathlib import Path
from urllib.parse import quote

import numpy as np
import requests
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'output'; ASSETS = ROOT / 'assets'; AUDIO = ROOT / 'audio'; SCENES = ROOT / 'scenes'; SEGS = ROOT / 'segments'
for d in (OUT, ASSETS, AUDIO, SCENES, SEGS): d.mkdir(parents=True, exist_ok=True)
JOB = json.loads((ROOT/'job.json').read_text())
W,H,FPS=1920,1080,30
FONT_B='/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf'
FONT_R='/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf'

def run(cmd,label):
    print('STEP',label,flush=True); subprocess.run(cmd,check=True)

def dur(p):
    return float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(p)],text=True).strip())

def fnt(sz,bold=True): return ImageFont.truetype(FONT_B if bold else FONT_R,sz)

SOURCES=[
 ('la_skyline','Los_Angeles_-_Skyline.jpg'),
 ('compton_street','Compton_ave_in_Watts,_California.jpg'),
 ('studio_mic','Microphone_studio.jpg'),
 ('turntable','Turntable-1328823.jpg'),
 ('cassette','Audio_cassette_tapes.jpg'),
 ('crowd','Concert_crowd_(Unsplash).jpg'),
 ('palms','Palms.jpg'),
 ('la_skyline2','Downtown_Los_Angeles_skyline2.jpg')]

def curl(name): return 'https://commons.wikimedia.org/wiki/Special:Redirect/file/'+quote(name,safe='(),_-')

def robust_get(url, min_bytes=10000):
    last=None
    for attempt in range(6):
        try:
            r=requests.get(url,timeout=120,allow_redirects=True,headers={'User-Agent':'CTNETWORK-HipHopWhatIf/2.0 (media production; contact via repository)'})
            if r.status_code==429:
                time.sleep(4+attempt*4); continue
            r.raise_for_status()
            if len(r.content)<min_bytes: raise RuntimeError(f'suspicious payload {len(r.content)}')
            return r.content
        except Exception as e:
            last=e; time.sleep(3+attempt*3)
    raise RuntimeError(f'download failed after retries: {url}: {last}')

def fetch_sources():
    for key,name in SOURCES:
        p=ASSETS/(key+Path(name).suffix.lower())
        if not (p.exists() and p.stat().st_size>10000):
            p.write_bytes(robust_get(curl(name)))
            print('SOURCE',key,p.stat().st_size,flush=True)
        time.sleep(2.5)

def crop_fill(img,w=W,h=H,bx=.5,by=.5):
    img=img.convert('RGB'); scale=max(w/img.width,h/img.height); nw,nh=int(img.width*scale),int(img.height*scale)
    img=img.resize((nw,nh),Image.Resampling.LANCZOS); x=int((nw-w)*max(0,min(1,bx))); y=int((nh-h)*max(0,min(1,by)))
    return img.crop((x,y,x+w,y+h))

def grade(img,idx):
    img=ImageEnhance.Contrast(img).enhance(1.26); img=ImageEnhance.Color(img).enhance(.70)
    a=np.asarray(img).astype(np.float32); a[...,0]*=1.11; a[...,1]*=.87; a[...,2]*=.78
    yy,xx=np.mgrid[0:H,0:W]; dist=np.sqrt(((xx-W/2)/(W*.78))**2+((yy-H/2)/(H*.80))**2)
    a*=np.clip(1-.38*dist,.52,1.0)[...,None]
    rng=np.random.default_rng(900+idx); a+=rng.normal(0,6,(H,W,1))
    return Image.fromarray(np.clip(a,0,255).astype(np.uint8))

def overlays(img,idx):
    lay=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(lay,'RGBA')
    if idx%2==0: d.ellipse((-300,-220,800,760),fill=(170,18,28,55))
    else: d.ellipse((W-900,-250,W+200,720),fill=(220,145,55,42))
    lay=lay.filter(ImageFilter.GaussianBlur(95)); img=Image.alpha_composite(img.convert('RGBA'),lay)
    lay=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(lay,'RGBA'); d.rectangle((0,0,W,25),fill=(0,0,0,115)); d.rectangle((0,H-30,W,H),fill=(0,0,0,120))
    for n in range(9):
        x=(idx*71+n*229)%W; d.line((x,0,x+random.randint(-25,25),H),fill=(255,245,225,random.randint(4,11)),width=1)
    return Image.alpha_composite(img,lay).convert('RGB')

def silhouettes(img,idx,count=1):
    lay=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(lay,'RGBA'); base=1430 if idx%2 else 390
    for i in range(count):
        x=base+(i-(count-1)/2)*180; y=575+(i%2)*18; d.ellipse((x-65,y-210,x+65,y-80),fill=(4,4,6,205)); d.rounded_rectangle((x-92,y-85,x+92,980),38,fill=(4,4,6,218))
    return Image.alpha_composite(img.convert('RGBA'),lay).convert('RGB')

def scene(idx):
    key,_=SOURCES[idx%len(SOURCES)]; p=next(ASSETS.glob(key+'.*')); img=Image.open(p)
    bx=[.12,.28,.47,.66,.86][idx%5]; by=[.12,.34,.52,.70][idx%4]; img=crop_fill(img,bx=bx,by=by); img=grade(img,idx); img=overlays(img,idx)
    if idx in (2,5,8,11,13,16,18,21): img=silhouettes(img,idx,1+(idx%3))
    lay=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(lay,'RGBA'); d.text((65,55),'HIP HOP WHAT IF',font=fnt(30),fill=(245,240,225,215))
    beat={0:'COMPTON • THE REAL STORY',6:'1995 • THE TIMELINE TURNS',9:'RUTHLESS • WHAT COMES NEXT?',12:'A REUNION THAT COULD HAVE HAPPENED',15:'THE WEST COAST RIPPLE',18:'LEGACY • BUSINESS • TIME',21:'A DIFFERENT FUTURE'}.get(idx)
    if beat: d.text((68,956),beat,font=fnt(31),fill=(235,199,125,225))
    if idx==0:
        d.text((85,680),'WHAT IF',font=fnt(78),fill=(245,240,225,238)); d.text((85,760),'EAZY-E',font=fnt(120),fill=(228,40,49,248)); d.text((85,880),'NEVER DIED?',font=fnt(80),fill=(245,240,225,240))
    if idx==23:
        d.text((85,790),'ONE LIFE. A DIFFERENT WEST COAST.',font=fnt(64),fill=(245,240,225,235)); d.text((85,875),'HIP HOP WHAT IF',font=fnt(50),fill=(225,44,52,235))
    return Image.alpha_composite(img.convert('RGBA'),lay).convert('RGB')

def thumbnail():
    src=Image.open(next(ASSETS.glob('la_skyline2.*'))); img=crop_fill(src,1280,720,.55,.45); img=ImageEnhance.Contrast(img).enhance(1.38); img=ImageEnhance.Color(img).enhance(.65).convert('RGBA')
    lay=Image.new('RGBA',(1280,720),(0,0,0,0)); d=ImageDraw.Draw(lay,'RGBA'); d.rectangle((0,0,1280,720),fill=(0,0,0,100))
    d.text((55,100),'WHAT IF',font=ImageFont.truetype(FONT_B,70),fill=(245,240,225,245)); d.text((55,180),'EAZY-E',font=ImageFont.truetype(FONT_B,112),fill=(232,40,48,255)); d.text((55,300),'NEVER DIED?',font=ImageFont.truetype(FONT_B,78),fill=(245,240,225,250)); d.text((60,575),'A DIFFERENT WEST COAST',font=ImageFont.truetype(FONT_B,36),fill=(232,193,116,245)); d.ellipse((900,115,1110,325),fill=(4,4,6,225)); d.rounded_rectangle((845,300,1165,710),65,fill=(4,4,6,232))
    Image.alpha_composite(img,lay).convert('RGB').save(OUT/'thumbnail.jpg',quality=92)

def music(seconds):
    sr=48000;n=int(seconds*sr);t=np.arange(n,dtype=np.float32)/sr; audio=np.zeros(n,dtype=np.float32); roots=[55.,49.,43.65,49.]; bar=60/86*4
    for b in range(int(math.ceil(seconds/bar))):
        st=b*bar;root=roots[b%4];s=int(st*sr);e=min(n,int((st+bar)*sr));tt=t[s:e]-st;env=np.minimum(1,tt/.25)*np.minimum(1,(bar-tt)/.4);audio[s:e]+=.026*np.sin(2*np.pi*root*tt)*env+.012*np.sin(2*np.pi*root*1.5*tt)*env
    rng=np.random.default_rng(82); beat=60/86
    def hit(ts,k):
        s=int(ts*sr)
        if s>=n:return
        du=.20 if k=='k' else .13;m=min(int(du*sr),n-s);tt=np.arange(m)/sr
        sig=(np.sin(2*np.pi*(70-28*tt/du)*tt)*np.exp(-tt*17)*.20) if k=='k' else (rng.normal(0,1,m)*np.exp(-tt*(27 if k=='s' else 62))*(.05 if k=='s' else .012)); audio[s:s+m]+=sig.astype(np.float32)
    b=0
    while b*beat<seconds:
        ts=b*beat
        if b%4 in (0,2):hit(ts,'k')
        if b%4 in (1,3):hit(ts,'s')
        hit(ts,'h');hit(ts+beat/2,'h');b+=1
    pcm=(np.clip(np.tanh(audio*1.1),-1,1)*32767).astype('<i2')
    with wave.open(str(OUT/'music.wav'),'wb') as w:w.setnchannels(1);w.setsampwidth(2);w.setframerate(sr);w.writeframes(pcm.tobytes())

def main():
    fetch_sources(); norms=[]
    for i,u in enumerate(JOB['audio_urls']):
        raw=AUDIO/f'raw_{i:02d}.wav';norm=AUDIO/f'norm_{i:02d}.wav';raw.write_bytes(robust_get(u,4096));run(['ffmpeg','-y','-v','error','-i',str(raw),'-ar','48000','-ac','2','-c:a','pcm_s16le',str(norm)],f'audio {i}');run(['ffmpeg','-v','error','-i',str(norm),'-f','null','-'],f'audio qc {i}');norms.append(norm)
    (AUDIO/'concat.txt').write_text('\n'.join("file '"+p.name+"'" for p in norms)+'\n');run(['ffmpeg','-y','-v','error','-f','concat','-safe','0','-i',str(AUDIO/'concat.txt'),'-c:a','pcm_s16le',str(OUT/'narration.wav')],'narration concat');total=dur(OUT/'narration.wav')
    if total<240:raise RuntimeError(f'narration too short {total}')
    nsc=24;sd=total/nsc;rows=[]
    for i in range(nsc):
        fr=SCENES/f'scene_{i:02d}.jpg';scene(i).save(fr,quality=91);sg=SEGS/f'seg_{i:02d}.mp4';frames=max(1,int(math.ceil(sd*FPS)));z=f"1+0.055*on/{frames}";x="iw/2-(iw/zoom/2)+sin(on/55)*24" if i%2 else "iw/2-(iw/zoom/2)";y="ih/2-(ih/zoom/2)+cos(on/65)*16" if i%3==0 else "ih/2-(ih/zoom/2)";fo=max(.2,sd-.35);vf=f"scale=2220:1249,zoompan=z='{z}':x='{x}':y='{y}':d={frames}:s=1920x1080:fps={FPS},fade=t=in:st=0:d=.25,fade=t=out:st={fo:.3f}:d=.30,format=yuv420p";run(['ffmpeg','-y','-v','error','-loop','1','-i',str(fr),'-t',f'{sd:.3f}','-vf',vf,'-an','-c:v','libx264','-preset','veryfast','-crf','20',str(sg)],f'scene {i}');rows.append(f"file '{sg.as_posix()}'")
    (ROOT/'visuals.txt').write_text('\n'.join(rows)+'\n');run(['ffmpeg','-y','-v','error','-f','concat','-safe','0','-i',str(ROOT/'visuals.txt'),'-c','copy',str(OUT/'visual.mp4')],'visual concat');music(total+2);run(['ffmpeg','-y','-v','error','-i',str(OUT/'visual.mp4'),'-i',str(OUT/'narration.wav'),'-i',str(OUT/'music.wav'),'-filter_complex','[1:a]volume=1.0[a1];[2:a]volume=0.16[a2];[a1][a2]amix=inputs=2:duration=first:dropout_transition=2,alimiter=limit=0.94[a]','-map','0:v:0','-map','[a]','-c:v','copy','-c:a','aac','-b:a','192k','-shortest',str(OUT/'full.mp4')],'master');thumbnail()
    for i,st in enumerate([5,72,142,214,282],1):
        md=max(20,min(55,total-st-2));run(['ffmpeg','-y','-v','error','-ss',str(st),'-i',str(OUT/'full.mp4'),'-t',str(md),'-vf','scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1','-c:v','libx264','-preset','veryfast','-crf','20','-c:a','aac','-b:a','160k',str(OUT/f'short_{i:02d}.mp4')],f'short {i}')
    picks=[0,4,8,12,16,20];sheet=Image.new('RGB',(1920,720),(0,0,0))
    for j,i in enumerate(picks):sheet.paste(Image.open(SCENES/f'scene_{i:02d}.jpg').resize((640,360),Image.Resampling.LANCZOS),((j%3)*640,(j//3)*360))
    sheet.save(OUT/'internal_preview.jpg',quality=88);print('BUILD_PASS',total,flush=True)

if __name__=='__main__':main()
