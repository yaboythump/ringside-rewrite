from __future__ import annotations

import json, math, random, subprocess, wave
from pathlib import Path
from urllib.parse import quote

import numpy as np
import requests
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageEnhance

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'output'
ASSETS = ROOT / 'assets'
AUDIO = ROOT / 'audio'
SCENES = ROOT / 'scenes'
SEGS = ROOT / 'segments'
for d in (OUT, ASSETS, AUDIO, SCENES, SEGS): d.mkdir(parents=True, exist_ok=True)
JOB = json.loads((ROOT / 'job.json').read_text())
W,H,FPS = 1920,1080,30
FONT_B = '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf'
FONT_R = '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf'

def run(cmd, label):
    print('STEP', label, flush=True)
    subprocess.run(cmd, check=True)

def duration(p):
    return float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(p)], text=True).strip())

def font(sz,bold=True):
    return ImageFont.truetype(FONT_B if bold else FONT_R, sz)

SOURCES = [
    ('la_skyline','Los_Angeles_-_Skyline.jpg'),
    ('compton_street','Compton_ave_in_Watts,_California.jpg'),
    ('studio_mic','Microphone_studio.jpg'),
    ('turntable','Turntable-1328823.jpg'),
    ('cassette','Audio_cassette_tapes.jpg'),
    ('crowd','Concert_crowd_(Unsplash).jpg'),
    ('palms','Palms.jpg'),
    ('la_skyline2','Downtown_Los_Angeles_skyline2.jpg'),
    ('mic2','Shure_SM61_Microphone.jpg'),
    ('cassette_recorder','Cassette_recorder_info.jpg'),
]

def commons_url(name):
    return 'https://commons.wikimedia.org/wiki/Special:Redirect/file/' + quote(name, safe='(),_-')

def fetch_sources():
    for key,name in SOURCES:
        path=ASSETS/(key + Path(name).suffix.lower())
        if path.exists() and path.stat().st_size>10000: continue
        r=requests.get(commons_url(name),timeout=90,allow_redirects=True,headers={'User-Agent':'CTNETWORK/1.0'})
        r.raise_for_status()
        if len(r.content)<10000: raise RuntimeError(f'source too small: {key}')
        path.write_bytes(r.content)
        print('SOURCE', key, len(r.content), flush=True)

def crop_fill(img, w=W, h=H, biasx=.5, biasy=.5):
    img=img.convert('RGB')
    scale=max(w/img.width,h/img.height)
    nw,nh=int(img.width*scale),int(img.height*scale)
    img=img.resize((nw,nh),Image.Resampling.LANCZOS)
    x=int((nw-w)*max(0,min(1,biasx))); y=int((nh-h)*max(0,min(1,biasy)))
    return img.crop((x,y,x+w,y+h))

def cinematic_grade(img, idx):
    img=ImageEnhance.Contrast(img).enhance(1.24)
    img=ImageEnhance.Color(img).enhance(0.72)
    a=np.asarray(img).astype(np.float32)
    # black/red/gold grade without turning the frame into a graphic card
    a[...,0]*=1.10; a[...,1]*=.88; a[...,2]*=.80
    a=np.clip(a,0,255)
    yy,xx=np.mgrid[0:H,0:W]
    cx,cy=W/2,H/2
    dist=np.sqrt(((xx-cx)/(W*.78))**2+((yy-cy)/(H*.80))**2)
    vig=np.clip(1-0.38*dist,0.54,1.0)[...,None]
    a*=vig
    rng=np.random.default_rng(700+idx)
    a+=rng.normal(0,7,(H,W,1))
    return Image.fromarray(np.clip(a,0,255).astype(np.uint8))

def light_leak(img, idx):
    lay=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(lay,'RGBA')
    if idx%2==0:
        d.ellipse((-280,-180,760,760),fill=(185,22,28,60))
    else:
        d.ellipse((W-820,-200,W+240,700),fill=(220,145,58,45))
    lay=lay.filter(ImageFilter.GaussianBlur(90))
    return Image.alpha_composite(img.convert('RGBA'),lay).convert('RGB')

def film_edges(img, idx):
    lay=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(lay,'RGBA')
    # edge texture only; never a central card/panel
    d.rectangle((0,0,W,28),fill=(0,0,0,115)); d.rectangle((0,H-32,W,H),fill=(0,0,0,125))
    for n in range(10):
        x=(n*197 + idx*83)%W
        d.line((x,0,x+random.randint(-30,30),H),fill=(255,245,220,random.randint(4,12)),width=1)
    return Image.alpha_composite(img.convert('RGBA'),lay).convert('RGB')

def silhouette_people(img, count=1, side='right', idx=0):
    lay=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(lay,'RGBA')
    base=1450 if side=='right' else 350
    step=170
    for i in range(count):
        x=base + (i-(count-1)/2)*step
        y=560 + (i%2)*20
        d.ellipse((x-70,y-220,x+70,y-80),fill=(4,4,6,210))
        d.rounded_rectangle((x-95,y-80,x+95,980),35,fill=(4,4,6,220))
    return Image.alpha_composite(img.convert('RGBA'),lay).convert('RGB')

def minimal_tag(img, txt, idx):
    lay=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(lay,'RGBA')
    d.text((70,70),'HIP HOP WHAT IF',font=font(32),fill=(245,240,224,215))
    if txt:
        d.text((70,948),txt,font=font(34),fill=(238,205,135,230))
    return Image.alpha_composite(img.convert('RGBA'),lay).convert('RGB')

def make_scene(idx):
    key,name=SOURCES[idx%len(SOURCES)]
    p=next(ASSETS.glob(key+'.*'))
    src=Image.open(p)
    biasx=[.15,.30,.50,.72,.85][idx%5]; biasy=[.15,.35,.5,.65][idx%4]
    img=crop_fill(src,biasx=biasx,biasy=biasy)
    img=cinematic_grade(img,idx)
    img=light_leak(img,idx)
    if idx in (2,3,8,9,12,13,18,19): img=silhouette_people(img, count=1+(idx%3), side='right' if idx%2 else 'left', idx=idx)
    img=film_edges(img,idx)
    tags={0:'COMPTON • THE REAL STORY',6:'1995 • THE TIMELINE TURNS',9:'RUTHLESS • WHAT COMES NEXT?',12:'THE REUNION THAT COULD HAVE BEEN',15:'THE WEST COAST RIPPLE',18:'LEGACY • BUSINESS • TIME',21:'A DIFFERENT FUTURE'}
    img=minimal_tag(img,tags.get(idx,''),idx)
    # opening/closing title are integrated into a full-bleed photograph, not a card
    if idx==0:
        lay=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(lay,'RGBA')
        d.text((85,670),'WHAT IF',font=font(80),fill=(245,240,225,235))
        d.text((85,755),'EAZY-E',font=font(122),fill=(225,40,48,245))
        d.text((85,875),'NEVER DIED?',font=font(82),fill=(245,240,225,240))
        img=Image.alpha_composite(img.convert('RGBA'),lay).convert('RGB')
    if idx==23:
        lay=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(lay,'RGBA')
        d.text((85,780),'ONE LIFE. A DIFFERENT WEST COAST.',font=font(66),fill=(245,240,225,235))
        d.text((85,870),'HIP HOP WHAT IF',font=font(54),fill=(220,45,52,235))
        img=Image.alpha_composite(img.convert('RGBA'),lay).convert('RGB')
    return img

def make_thumbnail():
    src=Image.open(next(ASSETS.glob('la_skyline2.*')))
    img=crop_fill(src,1280,720,biasx=.55,biasy=.45)
    img=ImageEnhance.Contrast(img).enhance(1.35); img=ImageEnhance.Color(img).enhance(.68)
    a=np.asarray(img).astype(np.float32); a[...,0]*=1.08; a[...,1]*=.80; a[...,2]*=.75
    img=Image.fromarray(np.clip(a,0,255).astype(np.uint8)).convert('RGBA')
    lay=Image.new('RGBA',(1280,720),(0,0,0,0)); d=ImageDraw.Draw(lay,'RGBA')
    d.rectangle((0,0,1280,720),fill=(0,0,0,90))
    d.text((58,100),'WHAT IF',font=ImageFont.truetype(FONT_B,74),fill=(245,240,225,245))
    d.text((58,182),'EAZY-E',font=ImageFont.truetype(FONT_B,112),fill=(230,42,50,255))
    d.text((58,300),'NEVER DIED?',font=ImageFont.truetype(FONT_B,78),fill=(245,240,225,250))
    d.text((62,575),'A DIFFERENT WEST COAST',font=ImageFont.truetype(FONT_B,38),fill=(232,193,116,245))
    # cinematic performer silhouette at right, not a likeness
    d.ellipse((900,120,1110,330),fill=(5,5,6,225)); d.rounded_rectangle((845,300,1165,710),65,fill=(5,5,6,230))
    Image.alpha_composite(img,lay).convert('RGB').save(OUT/'thumbnail.jpg',quality=92)

def synth_music(seconds):
    sr=48000; n=int(seconds*sr); t=np.arange(n,dtype=np.float32)/sr
    audio=np.zeros(n,dtype=np.float32)
    # original restrained 1990s West Coast documentary bed, not a soundalike
    roots=[55.0,49.0,43.65,49.0]
    bar=60/86*4
    for b in range(int(math.ceil(seconds/bar))):
        st=b*bar; root=roots[b%len(roots)]
        s=int(st*sr); e=min(n,int((st+bar)*sr)); tt=t[s:e]-st
        env=np.minimum(1,tt/.25)*np.minimum(1,(bar-tt)/.4)
        audio[s:e]+=0.028*np.sin(2*np.pi*root*tt)*env
        audio[s:e]+=0.014*np.sin(2*np.pi*(root*1.5)*tt)*env
    rng=np.random.default_rng(82); beat=60/86
    def hit(ts,kind):
        s=int(ts*sr)
        if s>=n:return
        dur=.20 if kind=='k' else .13; m=min(int(dur*sr),n-s); tt=np.arange(m)/sr
        if kind=='k': sig=np.sin(2*np.pi*(70-28*tt/dur)*tt)*np.exp(-tt*17)*.22
        elif kind=='s': sig=rng.normal(0,1,m)*np.exp(-tt*27)*.055
        else: sig=rng.normal(0,1,m)*np.exp(-tt*62)*.014
        audio[s:s+m]+=sig.astype(np.float32)
    b=0
    while b*beat<seconds:
        ts=b*beat
        if b%4 in (0,2): hit(ts,'k')
        if b%4 in (1,3): hit(ts,'s')
        hit(ts,'h'); hit(ts+beat/2,'h'); b+=1
    audio=np.tanh(audio*1.1)
    pcm=(np.clip(audio,-1,1)*32767).astype('<i2')
    with wave.open(str(OUT/'music.wav'),'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr); w.writeframes(pcm.tobytes())

def main():
    fetch_sources()
    norms=[]
    for i,u in enumerate(JOB['audio_urls']):
        raw=AUDIO/f'raw_{i:02d}.wav'; norm=AUDIO/f'norm_{i:02d}.wav'
        r=requests.get(u,timeout=90); r.raise_for_status(); raw.write_bytes(r.content)
        if len(r.content)<4096: raise RuntimeError(f'audio {i} too small')
        run(['ffmpeg','-y','-v','error','-i',str(raw),'-ar','48000','-ac','2','-c:a','pcm_s16le',str(norm)],f'audio normalize {i}')
        run(['ffmpeg','-v','error','-i',str(norm),'-f','null','-'],f'audio decode {i}')
        norms.append(norm)
    concat=AUDIO/'concat.txt'; concat.write_text('\n'.join("file '"+p.name+"'" for p in norms)+'\n')
    run(['ffmpeg','-y','-v','error','-f','concat','-safe','0','-i',str(concat),'-c:a','pcm_s16le',str(OUT/'narration.wav')],'concat narration')
    total=duration(OUT/'narration.wav')
    if total<240: raise RuntimeError(f'narration too short {total}')
    scene_count=24
    scene_dur=total/scene_count
    rows=[]
    for i in range(scene_count):
        frame=SCENES/f'scene_{i:02d}.jpg'; make_scene(i).save(frame,quality=91)
        seg=SEGS/f'seg_{i:02d}.mp4'; frames=max(1,int(math.ceil(scene_dur*FPS)))
        z=f"1+0.055*on/{frames}"
        x="iw/2-(iw/zoom/2)+sin(on/55)*24" if i%2 else "iw/2-(iw/zoom/2)"
        y="ih/2-(ih/zoom/2)+cos(on/65)*16" if i%3==0 else "ih/2-(ih/zoom/2)"
        fadeout=max(.2,scene_dur-.35)
        vf=f"scale=2220:1249,zoompan=z='{z}':x='{x}':y='{y}':d={frames}:s=1920x1080:fps={FPS},fade=t=in:st=0:d=.25,fade=t=out:st={fadeout:.3f}:d=.30,format=yuv420p"
        run(['ffmpeg','-y','-v','error','-loop','1','-i',str(frame),'-t',f'{scene_dur:.3f}','-vf',vf,'-an','-c:v','libx264','-preset','veryfast','-crf','20',str(seg)],f'render scene {i}')
        rows.append(f"file '{seg.as_posix()}'")
    (ROOT/'visuals.txt').write_text('\n'.join(rows)+'\n')
    run(['ffmpeg','-y','-v','error','-f','concat','-safe','0','-i',str(ROOT/'visuals.txt'),'-c','copy',str(OUT/'visual.mp4')],'concat visuals')
    synth_music(total+2)
    run(['ffmpeg','-y','-v','error','-i',str(OUT/'visual.mp4'),'-i',str(OUT/'narration.wav'),'-i',str(OUT/'music.wav'),'-filter_complex','[1:a]volume=1.0[a1];[2:a]volume=0.16[a2];[a1][a2]amix=inputs=2:duration=first:dropout_transition=2,alimiter=limit=0.94[a]','-map','0:v:0','-map','[a]','-c:v','copy','-c:a','aac','-b:a','192k','-shortest',str(OUT/'full.mp4')],'master mix')
    make_thumbnail()
    # Five Shorts cut directly from the finished master, no regeneration
    starts=[5,72,142,214,282]
    for i,st in enumerate(starts,1):
        maxdur=max(20,min(55,total-st-2))
        run(['ffmpeg','-y','-v','error','-ss',str(st),'-i',str(OUT/'full.mp4'),'-t',str(maxdur),'-vf','scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,setsar=1','-c:v','libx264','-preset','veryfast','-crf','20','-c:a','aac','-b:a','160k',str(OUT/f'short_{i:02d}.mp4')],f'short {i}')
    # Internal-only contact sheet for visual QC; never used in episode/master
    picks=[0,4,8,12,16,20]
    thumbs=[]
    for i in picks:
        im=Image.open(SCENES/f'scene_{i:02d}.jpg').resize((640,360),Image.Resampling.LANCZOS)
        thumbs.append(im)
    sheet=Image.new('RGB',(1920,720),(0,0,0))
    for j,im in enumerate(thumbs): sheet.paste(im,((j%3)*640,(j//3)*360))
    sheet.save(OUT/'internal_preview.jpg',quality=88)
    print('BUILD_PASS',total,flush=True)

if __name__=='__main__': main()
