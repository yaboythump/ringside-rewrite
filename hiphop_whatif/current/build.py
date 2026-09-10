from __future__ import annotations

import json, math, os, random, subprocess, wave
from pathlib import Path

import numpy as np
import requests
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent
OUT = ROOT / "output"
AUDIO = ROOT / "audio"
FRAMES = ROOT / "frames"
SEGS = ROOT / "segments"
for d in (OUT, AUDIO, FRAMES, SEGS): d.mkdir(parents=True, exist_ok=True)

JOB = json.loads((ROOT / "job.json").read_text(encoding="utf-8"))
W, H, FPS = 1920, 1080, 30
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf"
FONT_R = "/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed.ttf"


def run(cmd, label):
    print(f"STEP {label}", flush=True)
    subprocess.run(cmd, check=True)


def probe_duration(path: Path) -> float:
    out = subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","default=nw=1:nk=1",str(path)], text=True).strip()
    return float(out)


def fnt(size, bold=True): return ImageFont.truetype(FONT_B if bold else FONT_R, size)


def gradient(top, bottom):
    img = Image.new("RGB", (W,H))
    p = img.load()
    for y in range(H):
        t = y/(H-1)
        c = tuple(int(top[i]*(1-t)+bottom[i]*t) for i in range(3))
        for x in range(W): p[x,y]=c
    return img


def add_grain(img, amount=18, seed=1):
    rng=np.random.default_rng(seed)
    arr=np.asarray(img).astype(np.int16)
    noise=rng.normal(0, amount, arr.shape[:2]+(1,)).astype(np.int16)
    arr=np.clip(arr+noise,0,255).astype(np.uint8)
    return Image.fromarray(arr)


def skyline(draw, base_y=760, seed=0):
    random.seed(seed)
    x=0
    while x<W:
        bw=random.randint(70,150); bh=random.randint(120,420)
        draw.rectangle((x,base_y-bh,x+bw,base_y), fill=(12,12,16))
        for wy in range(base_y-bh+35, base_y-25, 48):
            for wx in range(x+20, x+bw-15, 38):
                if random.random()<0.55: draw.rectangle((wx,wy,wx+8,wy+12), fill=(210,120,35))
        x+=bw+12


def palms(draw):
    for x in (170, 1540, 1740):
        draw.line((x,820,x+18,510), fill=(20,20,20), width=18)
        cx,cy=x+18,510
        for ang in range(0,360,40):
            dx=math.cos(math.radians(ang))*120; dy=math.sin(math.radians(ang))*55
            draw.line((cx,cy,cx+dx,cy+dy), fill=(20,20,20), width=13)


def brand(draw, kicker):
    draw.rounded_rectangle((65,55,410,125), 18, fill=(5,5,8,220), outline=(180,28,38), width=3)
    draw.text((88,72), "HIP HOP WHAT IF", font=fnt(38), fill=(242,242,238))
    draw.text((70,965), kicker, font=fnt(28,False), fill=(210,190,150))


def scene(idx:int):
    palettes=[((8,7,10),(68,18,22)),((8,8,9),(55,32,9)),((6,8,12),(45,15,20)),((6,5,8),(74,12,18)),((5,7,10),(18,40,70)),((9,7,6),(70,35,8)),((5,5,7),(47,11,18)),((5,7,10),(18,24,48))]
    img=gradient(*palettes[idx]); d=ImageDraw.Draw(img,"RGBA")
    skyline(d, seed=idx+10); palms(d)
    if idx==0:
        d.ellipse((640,215,1220,795), fill=(12,12,14,220), outline=(210,45,55), width=6)
        d.ellipse((725,300,1135,710), outline=(190,150,80), width=20)
        d.ellipse((855,430,1005,580), fill=(8,8,8))
        d.text((535,785),"ONE LIFE. A DIFFERENT WEST COAST.",font=fnt(54),fill=(245,238,220))
        brand(d,"COMPTON • 1995 • THE QUESTION")
    elif idx==1:
        d.rounded_rectangle((300,250,1080,820),35,fill=(10,10,12,225),outline=(150,115,55),width=5)
        for y in range(330,700,80): d.line((370,y,1010,y),fill=(125,95,45),width=3)
        d.ellipse((1210,320,1580,690),fill=(25,20,14),outline=(180,35,42),width=9)
        d.ellipse((1310,420,1480,590),fill=(5,5,5))
        d.text((330,275),"RUTHLESS RECORDS",font=fnt(62),fill=(245,240,225))
        d.text((330,720),"THE FOUNDER STAYS IN THE ROOM",font=fnt(38),fill=(205,165,92))
        brand(d,"LABEL • STUDIO • SURVIVAL")
    elif idx==2:
        d.polygon([(260,255),(1110,210),(1180,760),(330,820)],fill=(226,216,191,235),outline=(40,30,25),width=5)
        d.text((370,315),"FEBRUARY 1995",font=fnt(46),fill=(35,25,20))
        d.text((370,390),"REUNION TALK GETS LOUDER",font=fnt(62),fill=(110,20,26))
        d.line((370,500,1020,500),fill=(40,40,40),width=4)
        d.text((370,545),"Then the real timeline stops.",font=fnt(38,False),fill=(55,45,40))
        d.text((370,610),"Our rewrite starts here.",font=fnt(38),fill=(95,15,20))
        brand(d,"REAL HISTORY → TIMELINE FORK")
    elif idx==3:
        for x,c in [(650,(170,25,35)),(960,(205,165,90)),(1270,(70,90,145))]:
            d.polygon([(x-150,150),(x+150,150),(x+45,900),(x-45,900)],fill=c+(70,))
            d.ellipse((x-90,420,x+90,600),fill=(5,5,7,240))
            d.rectangle((x-55,590,x+55,875),fill=(5,5,7,240))
        d.text((470,220),"ONE ALBUM. ONE TOUR. ONE MOMENT.",font=fnt(56),fill=(245,242,230))
        brand(d,"N W A REUNION • HYPOTHETICAL")
    elif idx==4:
        d.rounded_rectangle((320,240,1600,825),45,fill=(8,10,16,220),outline=(155,35,45),width=5)
        pts=[(450,650),(710,520),(1000,610),(1260,420),(1480,540)]
        for a,b in zip(pts,pts[1:]): d.line((*a,*b),fill=(215,55,60),width=9)
        for p in pts: d.ellipse((p[0]-18,p[1]-18,p[0]+18,p[1]+18),fill=(230,180,90))
        d.text((390,290),"THE WEST COAST GETS ANOTHER CENTER",font=fnt(50),fill=(245,240,226))
        d.text((390,745),"Legacy • Competition • New Artists",font=fnt(38,False),fill=(190,170,135))
        brand(d,"RIPPLE EFFECTS")
    elif idx==5:
        d.rounded_rectangle((250,220,850,790),28,fill=(232,222,198,235),outline=(60,45,25),width=4)
        d.text((310,280),"CONTRACT",font=fnt(62),fill=(35,25,20))
        for y in range(390,680,58): d.line((315,y,760,y),fill=(95,80,60),width=3)
        d.ellipse((1080,300,1640,860),fill=(20,18,13),outline=(190,145,70),width=10)
        d.ellipse((1220,440,1500,720),fill=(5,5,5))
        d.text((875,185),"FEUD → BUSINESS",font=fnt(70),fill=(245,240,220))
        brand(d,"CONTRACTS • OWNERSHIP • LEVERAGE")
    elif idx==6:
        for row in range(5):
            for col in range(16):
                x=170+col*105+(row%2)*35; y=470+row*90
                d.ellipse((x,y,x+38,y+38),fill=(20,20,23,230))
        d.rectangle((260,220,1660,420),fill=(8,8,10,220),outline=(180,30,38),width=5)
        d.text((390,265),"A DIFFERENT STORY DOMINATES 1996",font=fnt(58),fill=(245,238,220))
        brand(d,"CROWD • CULTURE • COMPETITION")
    else:
        d.line((250,760,1650,330),fill=(210,40,48),width=18)
        for x,y,yr in [(330,735,"1995"),(690,625,"1996"),(1080,505,"2000s"),(1510,365,"LEGACY")]:
            d.ellipse((x-25,y-25,x+25,y+25),fill=(230,185,95))
            d.text((x-55,y+45),yr,font=fnt(34),fill=(245,240,225))
        d.text((360,210),"EAZY-E ISN'T FROZEN IN 1995",font=fnt(68),fill=(246,241,225))
        d.text((465,300),"HE GETS TO CHOOSE WHAT COMES NEXT",font=fnt(42,False),fill=(210,180,135))
        brand(d,"THE LEGACY THAT COULD HAVE BEEN")
    img=add_grain(img,14,idx+90).filter(ImageFilter.GaussianBlur(0.15))
    return img


def make_thumb():
    img=gradient((4,4,7),(82,13,18)); d=ImageDraw.Draw(img,"RGBA"); skyline(d,760,77); palms(d)
    d.ellipse((1180,180,1680,680),fill=(6,6,7,235),outline=(220,170,85),width=12)
    d.rectangle((1215,650,1645,900),fill=(6,6,7,235))
    d.text((90,170),"WHAT IF",font=fnt(112),fill=(236,228,205))
    d.text((90,305),"EAZY-E",font=fnt(150),fill=(220,38,48))
    d.text((90,475),"NEVER DIED?",font=fnt(112),fill=(245,242,230))
    d.rounded_rectangle((95,690,790,785),24,fill=(8,8,10,225),outline=(212,165,88),width=4)
    d.text((130,712),"A DIFFERENT WEST COAST",font=fnt(42),fill=(220,190,130))
    img=add_grain(img,12,333)
    img.resize((1280,720),Image.Resampling.LANCZOS).save(OUT/"thumbnail.jpg",quality=89,optimize=True)


def synth_music(seconds:float):
    sr=48000; n=int(seconds*sr); t=np.arange(n,dtype=np.float32)/sr
    audio=np.zeros(n,dtype=np.float32)
    bpm=88; beat=60.0/bpm
    # low bass bed
    audio += 0.035*np.sin(2*np.pi*55*t)
    rng=np.random.default_rng(45)
    def add_hit(start, kind):
        s=int(start*sr); dur=0.20 if kind=='kick' else 0.12; m=min(int(dur*sr),n-s)
        if m<=0:return
        tt=np.arange(m,dtype=np.float32)/sr
        if kind=='kick': sig=np.sin(2*np.pi*(72-36*tt/dur)*tt)*np.exp(-tt*18)*0.38
        elif kind=='snare': sig=rng.normal(0,1,m).astype(np.float32)*np.exp(-tt*28)*0.12
        else: sig=rng.normal(0,1,m).astype(np.float32)*np.exp(-tt*55)*0.035
        audio[s:s+m]+=sig
    b=0
    while b*beat<seconds:
        ts=b*beat
        if b%4 in (0,2): add_hit(ts,'kick')
        if b%4 in (1,3): add_hit(ts,'snare')
        add_hit(ts,'hat'); add_hit(ts+beat/2,'hat')
        b+=1
    audio=np.tanh(audio*1.2)
    pcm=(np.clip(audio,-1,1)*32767).astype('<i2')
    with wave.open(str(OUT/"music.wav"),'wb') as wv:
        wv.setnchannels(1); wv.setsampwidth(2); wv.setframerate(sr); wv.writeframes(pcm.tobytes())


def main():
    urls=JOB['audio_urls']
    normalized=[]
    for i,u in enumerate(urls):
        raw=AUDIO/f"raw_{i:02d}.wav"; norm=AUDIO/f"norm_{i:02d}.wav"
        r=requests.get(u,timeout=90); r.raise_for_status(); raw.write_bytes(r.content)
        if len(r.content)<4096: raise RuntimeError(f"Audio chunk {i} suspiciously small")
        run(["ffmpeg","-y","-v","error","-i",str(raw),"-af","aresample=48000","-ac","2","-c:a","pcm_s16le",str(norm)],f"normalize audio {i}")
        run(["ffmpeg","-v","error","-i",str(norm),"-f","null","-"],f"decode audio {i}")
        normalized.append(norm)
    concat=AUDIO/"concat.txt"; concat.write_text("\n".join(f"file '{p.name}'" for p in normalized)+"\n")
    run(["ffmpeg","-y","-v","error","-f","concat","-safe","0","-i",str(concat),"-c:a","pcm_s16le",str(OUT/"narration.wav")],"concat narration")
    durations=[probe_duration(p) for p in normalized]; total=sum(durations)
    # render scene stills and motion segments
    vlist=ROOT/"videos.txt"; rows=[]
    for i,dur in enumerate(durations):
        frame=FRAMES/f"scene_{i:02d}.jpg"; scene(i).save(frame,quality=92)
        seg=SEGS/f"seg_{i:02d}.mp4"; frames=max(1,int(math.ceil(dur*FPS)))
        z="1+0.035*on/%d"%frames
        x="iw/2-(iw/zoom/2)+sin(on/45)*18" if i%2 else "iw/2-(iw/zoom/2)"
        y="ih/2-(ih/zoom/2)+cos(on/50)*12" if i%3==0 else "ih/2-(ih/zoom/2)"
        vf=f"scale=2300:-1,zoompan=z='{z}':x='{x}':y='{y}':d=1:s=1920x1080:fps={FPS},format=yuv420p"
        run(["ffmpeg","-y","-v","error","-loop","1","-i",str(frame),"-t",f"{dur:.3f}","-vf",vf,"-an","-c:v","libx264","-preset","veryfast","-crf","21","-movflags","+faststart",str(seg)],f"render scene {i}")
        rows.append(f"file '{seg.as_posix()}'")
    vlist.write_text("\n".join(rows)+"\n")
    run(["ffmpeg","-y","-v","error","-f","concat","-safe","0","-i",str(vlist),"-c","copy",str(OUT/"visual.mp4")],"concat visuals")
    synth_music(total+2)
    run(["ffmpeg","-y","-v","error","-i",str(OUT/"visual.mp4"),"-i",str(OUT/"narration.wav"),"-i",str(OUT/"music.wav"),"-filter_complex","[1:a]loudnorm=I=-16:TP=-1.5:LRA=11[n];[2:a]volume=0.10[m];[n][m]amix=inputs=2:duration=first:dropout_transition=2[a]","-map","0:v:0","-map","[a]","-c:v","copy","-c:a","aac","-b:a","192k","-shortest","-movflags","+faststart",str(OUT/"full.mp4")],"mix master")
    make_thumb()
    starts=[0.0]
    c=0.0
    for d in durations[:-1]: c+=d; starts.append(c)
    picks=[0,2,3,5,7]
    for j,idx in enumerate(picks,1):
        start=starts[idx]; maxdur=max(8.0,total-start-0.25); dur=min(58.0,maxdur)
        out=OUT/f"short_{j:02d}.mp4"
        fc="[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=30:2,eq=brightness=-0.16[bg];[0:v]scale=1080:-2[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2,format=yuv420p[v]"
        run(["ffmpeg","-y","-v","error","-ss",f"{start:.3f}","-i",str(OUT/"full.mp4"),"-t",f"{dur:.3f}","-filter_complex",fc,"-map","[v]","-map","0:a:0","-c:v","libx264","-preset","veryfast","-crf","22","-c:a","aac","-b:a","160k","-movflags","+faststart",str(out)],f"short {j}")
    # QC
    for p in [OUT/"full.mp4"]+[OUT/f"short_{i:02d}.mp4" for i in range(1,6)]:
        run(["ffmpeg","-v","error","-i",str(p),"-f","null","-"],f"QC decode {p.name}")
    print(json.dumps({"duration":probe_duration(OUT/'full.mp4'),"shorts":5,"status":"built"},indent=2))

if __name__=='__main__': main()
