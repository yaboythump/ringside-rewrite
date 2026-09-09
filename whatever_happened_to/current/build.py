from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
OUT = ROOT / 'output'
OUT.mkdir(parents=True, exist_ok=True)
CHUNK_DIR = REPO / 'marcus' / 'chunks'
CHUNK_DIR.mkdir(parents=True, exist_ok=True)

W, H = 1920, 1080
ACCENT = (38, 116, 255)
PINK = (244, 52, 145)
WHITE = (246, 248, 255)
INK = (12, 18, 34)

SECTIONS = [
    ('THE INTERNET BEFORE THE ALGORITHM', 'Top 8. Profile songs. Glitter HTML. And Tom.', 'top8'),
    ('2003: MYSPACE ARRIVES', 'Your page actually felt like yours.', 'browser'),
    ('TOP 8 DRAMA', 'MySpace made friendship rankings public.', 'top8'),
    ('MUSIC CHANGED EVERYTHING', 'Bands could reach fans without waiting for radio.', 'music'),
    ('$580 MILLION BET', 'News Corp bought Intermix Media in 2005.', 'money'),
    ('$900 MILLION GOOGLE DEAL', 'Traffic turned MySpace into a money machine.', 'money'),
    ('FACEBOOK TAKES THE CROWN', 'MySpace was a destination. Facebook became a habit.', 'versus'),
    ('THE COLLAPSE', '$580M → $35M in six years.', 'collapse'),
    ('MYSPACE NEVER FULLY DIED', 'The site survived. The culture moved on.', 'legacy'),
    ('THE INTERNET ABSORBED MYSPACE', 'Profiles became brands. Friends became followers.', 'legacy'),
]

SHORT_SPECS = [
    (8, 43, 'The Top 8 Was Social Media Warfare'),
    (76, 111, 'Why Everybody Was Friends With Tom'),
    (146, 181, 'MySpace Changed Music Before Streaming Took Over'),
    (215, 250, 'News Corp Paid $580 Million for MySpace'),
    (322, 357, 'How Facebook Took MySpace’s Crown'),
    (423, 458, 'How $580 Million Became $35 Million'),
]


def font(size: int, bold: bool = False):
    candidates = [
        '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf' if bold else '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
        '/usr/share/fonts/truetype/liberation2/LiberationSans-Bold.ttf' if bold else '/usr/share/fonts/truetype/liberation2/LiberationSans-Regular.ttf',
    ]
    for p in candidates:
        if Path(p).exists():
            return ImageFont.truetype(p, size=size)
    return ImageFont.load_default()


def gradient_bg(seed: int):
    im = Image.new('RGB', (W, H), INK)
    px = im.load()
    for y in range(H):
        for x in range(0, W, 4):
            t = (x / W) * .55 + (y / H) * .45
            c1 = (18 + seed*3 % 35, 30, 68 + seed*9 % 80)
            c2 = (8, 11 + seed*2 % 25, 28)
            r = int(c1[0]*(1-t) + c2[0]*t)
            g = int(c1[1]*(1-t) + c2[1]*t)
            b = int(c1[2]*(1-t) + c2[2]*t)
            for xx in range(x, min(x+4,W)):
                px[xx,y] = (r,g,b)
    return im


def browser_shell(d: ImageDraw.ImageDraw):
    x0,y0,x1,y1 = 170,175,1750,930
    d.rounded_rectangle((x0,y0,x1,y1), 30, fill=(238,242,250), outline=(255,255,255), width=4)
    d.rounded_rectangle((x0,y0,x1,y0+82), 30, fill=(209,218,235))
    for i,c in enumerate([(255,91,82),(255,190,73),(70,201,116)]):
        cx=x0+42+i*42; cy=y0+41
        d.ellipse((cx-11,cy-11,cx+11,cy+11), fill=c)
    d.rounded_rectangle((x0+190,y0+22,x1-35,y0+63),18,fill=(250,252,255))
    d.text((x0+220,y0+30),'myspace.com/profile',font=font(25),fill=(70,80,105))
    return (x0,y0,x1,y1)


def draw_top8(d):
    x0,y0,x1,y1 = browser_shell(d)
    d.rectangle((x0+45,y0+115,x0+410,y1-50), fill=(31,91,172))
    d.text((x0+80,y0+145),'MySpace',font=font(52,True),fill='white')
    d.text((x0+80,y0+225),'View My:',font=font(25),fill='white')
    d.text((x0+80,y0+265),'Pics  |  Videos',font=font(22),fill=(190,220,255))
    d.text((x0+455,y0+122),'THUMP’S TOP 8',font=font(42,True),fill=(25,35,62))
    for i in range(8):
        col=i%4; row=i//4
        x=x0+465+col*245; y=y0+205+row*285
        d.rounded_rectangle((x,y,x+195,y+205),18,fill=(235,236,246),outline=(175,183,210),width=3)
        d.ellipse((x+46,y+22,x+150,y+126),fill=(55+20*i,80+10*i,160+6*i))
        label='TOM' if i==0 else f'FRIEND {i+1}'
        d.text((x+28,y+150),label,font=font(24,True),fill=(30,38,67))


def draw_music(d):
    x0,y0,x1,y1=browser_shell(d)
    d.text((x0+80,y0+120),'MYSPACE MUSIC',font=font(54,True),fill=(28,65,145))
    d.text((x0+80,y0+190),'Artist Profile',font=font(26),fill=(75,85,110))
    d.rounded_rectangle((x0+80,y0+260,x0+650,y0+640),28,fill=(23,29,48))
    d.ellipse((x0+150,y0+330,x0+430,y0+610),fill=(240,55,125))
    d.polygon([(x0+250,y0+400),(x0+250,y0+540),(x0+375,y0+470)],fill='white')
    for i,txt in enumerate(['01  NEW SINGLE.mp3','02  TOUR DATES','03  ADD TO PROFILE']):
        yy=y0+285+i*105
        d.rounded_rectangle((x0+730,yy,x1-80,yy+72),18,fill=(224,230,245))
        d.text((x0+770,yy+18),txt,font=font(28,True),fill=(35,48,85))


def draw_money(d, collapse=False):
    d.text((145,245),'NEWS CORP',font=font(72,True),fill=WHITE)
    d.text((145,335),'BOUGHT MYSPACE',font=font(72,True),fill=WHITE)
    d.text((145,475),'$580M',font=font(160,True),fill=(94,226,150))
    if collapse:
        d.text((970,500),'→',font=font(130,True),fill=(250,210,88))
        d.text((1190,475),'$35M',font=font(160,True),fill=(255,89,96))
        d.text((1195,655),'SIX YEARS LATER',font=font(38,True),fill=(255,180,184))
    else:
        d.text((150,680),'2005',font=font(48,True),fill=(178,197,255))
        d.rounded_rectangle((1020,285,1710,780),40,fill=(240,245,255))
        d.text((1115,365),'BIG TECH',font=font(44,True),fill=(28,42,80))
        d.text((1115,430),'BIG MEDIA',font=font(44,True),fill=(28,42,80))
        d.text((1115,495),'BIG BET',font=font(44,True),fill=PINK)


def draw_versus(d):
    d.rounded_rectangle((120,245,875,825),45,fill=(39,101,193))
    d.rounded_rectangle((1045,245,1800,825),45,fill=(235,239,248))
    d.text((235,385),'MYSPACE',font=font(85,True),fill='white')
    d.text((1165,385),'FACEBOOK',font=font(85,True),fill=(45,84,150))
    d.text((330,580),'DESTINATION',font=font(38,True),fill=(195,220,255))
    d.text((1275,580),'HABIT',font=font(38,True),fill=(95,110,145))
    d.text((900,490),'VS',font=font(55,True),fill=(255,196,72))


def draw_legacy(d):
    items=['PROFILE SONG → SHORT-FORM AUDIO','FRIENDS → FOLLOWERS','COMMENTS → REPLIES','ARTIST PAGES → CREATOR BRANDS']
    for i,t in enumerate(items):
        y=285+i*145
        d.rounded_rectangle((210,y,1710,y+105),28,fill=(235,240,251),outline=(255,255,255),width=2)
        d.text((270,y+27),t,font=font(38,True),fill=(30,45,83))


def make_card(i, title, subtitle, mode):
    im=gradient_bg(i)
    d=ImageDraw.Draw(im)
    # neon rails
    d.rectangle((0,0,W,18),fill=ACCENT); d.rectangle((0,H-18,W,H),fill=PINK)
    if mode=='top8': draw_top8(d)
    elif mode=='music': draw_music(d)
    elif mode=='money': draw_money(d,False)
    elif mode=='collapse': draw_money(d,True)
    elif mode=='versus': draw_versus(d)
    elif mode=='legacy': draw_legacy(d)
    else:
        browser_shell(d)
        d.text((330,365),'MYSPACE',font=font(145,True),fill=(36,100,205))
        d.text((335,540),'A PLACE THAT FELT LIKE YOURS',font=font(42,True),fill=(50,62,92))
    # title banner
    d.rounded_rectangle((105,65,1815,160),30,fill=(9,14,29),outline=(255,255,255),width=2)
    d.text((145,84),title,font=font(38,True),fill=WHITE)
    d.text((145,995),subtitle,font=font(29),fill=(210,220,245))
    p=OUT/f'card_{i:02d}.png'; im.save(p,quality=95); return p


def run(cmd):
    print('+', ' '.join(map(str,cmd)))
    subprocess.run(cmd,check=True)


def generate_narration():
    wavs=[]
    for idx in range(10):
        env=os.environ.copy(); env['CHUNK_INDEX']=str(idx)
        run([sys.executable, str(REPO/'marcus'/'myspace_pilot.py')]) if False else subprocess.run([sys.executable,str(REPO/'marcus'/'myspace_pilot.py')],check=True,env=env)
        wav=CHUNK_DIR/f'marcus_{idx:02d}.wav'
        wavs.append(wav)
    concat=OUT/'narration_concat.txt'
    concat.write_text('\n'.join("file '%s'"%p.resolve() for p in wavs),encoding='utf-8')
    raw=OUT/'marcus_raw.wav'; master=OUT/'marcus_master.wav'
    run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(concat),'-c:a','pcm_s16le',str(raw)])
    run(['ffmpeg','-y','-i',str(raw),'-af','highpass=f=70,equalizer=f=3000:t=q:w=1.2:g=1.1,acompressor=threshold=-18dB:ratio=2.3:attack=15:release=120,loudnorm=I=-16:TP=-1.5:LRA=7,alimiter=limit=0.95',str(master)])
    return wavs, master


def duration(path):
    r=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(path)],check=True,capture_output=True,text=True)
    return float(r.stdout.strip())


def main():
    wavs, narration=generate_narration()
    cards=[]
    for i,s in enumerate(SECTIONS): cards.append(make_card(i,*s))
    clips=[]
    for i,(wav,card) in enumerate(zip(wavs,cards)):
        dur=duration(wav)
        clip=OUT/f'section_{i:02d}.mp4'
        # subtle motion + flashes from each section's topic-specific frame
        vf=(f"scale=2200:-2,zoompan=z='min(zoom+0.0009,1.10)':x='iw/2-(iw/zoom/2)+sin(on/18)*8':y='ih/2-(ih/zoom/2)+cos(on/23)*5':d=1:s=1920x1080:fps=30,"
            f"eq=contrast=1.04:saturation=1.08,fade=t=in:st=0:d=.25,fade=t=out:st={max(.3,dur-.28):.2f}:d=.25")
        run(['ffmpeg','-y','-loop','1','-i',str(card),'-i',str(wav),'-t',f'{dur:.3f}','-vf',vf,'-c:v','libx264','-preset','veryfast','-crf','20','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-shortest',str(clip)])
        clips.append(clip)
    concat=OUT/'video_concat.txt'; concat.write_text('\n'.join("file '%s'"%p.resolve() for p in clips),encoding='utf-8')
    dry=OUT/'full_dry.mp4'
    run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(concat),'-c','copy',str(dry)])
    dur=duration(dry)
    # original zero-credit Y2K/newsroom bed: soft synth pulses + bass, generated locally
    bgm=OUT/'bgm.wav'
    filt=(f"sine=frequency=110:sample_rate=48000:duration={dur}[a];"
          f"sine=frequency=220:sample_rate=48000:duration={dur}[b];"
          f"sine=frequency=440:sample_rate=48000:duration={dur}[c];"
          "[a]volume=.035[a1];[b]volume=.018[b1];[c]volume=.009[c1];[a1][b1][c1]amix=inputs=3,lowpass=f=1400,afade=t=in:d=2,afade=t=out:st=1:d=1")
    run(['ffmpeg','-y','-f','lavfi','-i',filt,'-t',f'{dur:.2f}',str(bgm)])
    full=OUT/'full.mp4'
    run(['ffmpeg','-y','-i',str(dry),'-i',str(bgm),'-filter_complex','[0:a]volume=1.0[voice];[1:a]volume=.42[music];[voice][music]amix=inputs=2:duration=first:normalize=0,alimiter=limit=.95[a]','-map','0:v','-map','[a]','-c:v','copy','-c:a','aac','-b:a','192k','-movflags','+faststart',str(full)])

    # thumbnail
    im=gradient_bg(88); d=ImageDraw.Draw(im)
    d.rectangle((0,0,W,H),outline=(255,255,255),width=10)
    d.text((125,130),'WHATEVER HAPPENED TO',font=font(64,True),fill=(225,235,255))
    d.text((125,255),'MYSPACE?',font=font(168,True),fill=(75,145,255))
    d.text((125,520),'$580M',font=font(100,True),fill=(99,226,150))
    d.text((655,535),'→',font=font(85,True),fill=(255,212,82))
    d.text((835,520),'$35M',font=font(100,True),fill=(255,90,110))
    d.rounded_rectangle((125,735,1610,880),35,fill=(245,247,252))
    d.text((180,770),'HOW DID IT FALL THIS HARD?',font=font(51,True),fill=(26,38,72))
    # Tom-style generic avatar callback (no copied photo)
    d.ellipse((1540,140,1845,445),fill=(230,210,185)); d.rectangle((1570,420,1815,780),fill=(28,55,105))
    d.text((1600,800),'TOM?',font=font(40,True),fill=(210,225,255))
    im.save(OUT/'thumbnail.jpg',quality=94)

    # six vertical shorts cut from the approved master
    for n,(start,end,title) in enumerate(SHORT_SPECS,1):
        if start >= dur-4: start=max(0,dur-40)
        end=min(end,dur)
        length=max(8,end-start)
        out=OUT/f'short_{n:02d}.mp4'
        vf=("scale=-2:1920,crop=1080:1920:(iw-1080)/2:0,"
            "drawbox=x=0:y=0:w=1080:h=180:color=black@0.58:t=fill,"
            f"drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='{title.replace(':','\\:').replace("'",'')[:42]}':fontcolor=white:fontsize=48:x=(w-text_w)/2:y=58:box=0")
        run(['ffmpeg','-y','-ss',f'{start:.2f}','-i',str(full),'-t',f'{length:.2f}','-vf',vf,'-c:v','libx264','-preset','veryfast','-crf','21','-c:a','aac','-b:a','160k','-movflags','+faststart',str(out)])
    print(f'BUILT full={full} duration={dur:.2f}s shorts=6 thumbnail=thumbnail.jpg')

if __name__=='__main__':
    main()
