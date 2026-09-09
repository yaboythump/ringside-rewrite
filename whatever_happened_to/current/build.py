from __future__ import annotations
import os, subprocess, sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT=Path(__file__).resolve().parent
REPO=ROOT.parents[1]
OUT=ROOT/'output'; OUT.mkdir(parents=True,exist_ok=True)
CHUNKS=REPO/'marcus'/'chunks'; CHUNKS.mkdir(parents=True,exist_ok=True)
W,H=1920,1080
SECTIONS=[
('THE INTERNET BEFORE THE ALGORITHM','Top 8. Profile songs. Glitter HTML. And Tom.'),
('2003: MYSPACE ARRIVES','Your page actually felt like yours.'),
('TOP 8 DRAMA','Friend rankings were public.'),
('MUSIC CHANGED EVERYTHING','Bands reached fans without waiting for radio.'),
('$580 MILLION BET','News Corp bought Intermix Media in 2005.'),
('$900 MILLION GOOGLE DEAL','Traffic turned MySpace into a money machine.'),
('FACEBOOK TAKES THE CROWN','MySpace was a destination. Facebook became a habit.'),
('THE COLLAPSE','$580M → $35M in six years.'),
('MYSPACE NEVER FULLY DIED','The site survived. The culture moved on.'),
('THE INTERNET ABSORBED MYSPACE','Profiles became brands. Friends became followers.'),]
SHORTS=[(8,43,'The Top 8 Was Social Media Warfare'),(76,111,'Why Everybody Was Friends With Tom'),(146,181,'MySpace Changed Music'),(215,250,'News Corp Paid $580 Million'),(322,357,'How Facebook Took the Crown'),(423,458,'How $580M Became $35M')]

def run(cmd,env=None):
    print('+',' '.join(str(x) for x in cmd)); subprocess.run(cmd,check=True,env=env)

def fnt(n,b=False):
    p='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf' if b else '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    return ImageFont.truetype(p,n)

def dur(p):
    r=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(p)],capture_output=True,text=True,check=True)
    return float(r.stdout.strip())

def card(i,title,sub):
    im=Image.new('RGB',(W,H),(8,15,35)); d=ImageDraw.Draw(im)
    d.rectangle((0,0,W,22),fill=(48,119,255)); d.rectangle((0,H-22,W,H),fill=(240,55,145))
    # browser chrome / Y2K profile recreation
    d.rounded_rectangle((120,190,1800,890),30,fill=(236,241,250),outline='white',width=4)
    d.rectangle((120,190,1800,275),fill=(209,220,238))
    for k,c in enumerate([(255,90,80),(255,190,70),(70,200,115)]):
        x=160+k*44; d.ellipse((x,220,x+24,244),fill=c)
    d.rounded_rectangle((350,213,1735,252),16,fill='white'); d.text((380,219),'myspace.com/profile',font=fnt(24),fill=(80,90,115))
    if i in (0,2):
        d.rectangle((165,315,530,820),fill=(33,93,174)); d.text((205,350),'MySpace',font=fnt(50,True),fill='white'); d.text((205,430),'THUMP’S TOP 8',font=fnt(28,True),fill='white')
        for j in range(8):
            x=590+(j%4)*275; y=330+(j//4)*235; d.rounded_rectangle((x,y,x+220,y+185),18,fill=(224,230,243),outline=(170,180,205),width=2)
            d.ellipse((x+70,y+22,x+150,y+102),fill=(65+12*j,85+7*j,165)); d.text((x+48,y+128),'TOM' if j==0 else f'FRIEND {j+1}',font=fnt(22,True),fill=(35,45,75))
    elif i==3:
        d.text((210,350),'MYSPACE MUSIC',font=fnt(62,True),fill=(37,93,188)); d.polygon([(370,520),(370,690),(520,605)],fill=(240,55,145)); d.text((710,470),'ADD TO PROFILE',font=fnt(46,True),fill=(35,45,75)); d.text((710,560),'TOUR DATES',font=fnt(42,True),fill=(35,45,75)); d.text((710,650),'NEW SINGLE.mp3',font=fnt(42,True),fill=(35,45,75))
    elif i in (4,5,7):
        d.text((210,365),'NEWS CORP + MYSPACE',font=fnt(56,True),fill=(35,45,75)); d.text((220,505),'$580M',font=fnt(135,True),fill=(65,190,120));
        if i==7: d.text((840,535),'→',font=fnt(100,True),fill=(235,180,50)); d.text((1070,505),'$35M',font=fnt(135,True),fill=(235,75,90))
        elif i==5: d.text((930,505),'$900M GOOGLE DEAL',font=fnt(64,True),fill=(55,110,210))
    elif i==6:
        d.rounded_rectangle((190,350,850,760),30,fill=(38,100,190)); d.rounded_rectangle((1070,350,1730,760),30,fill=(225,232,245)); d.text((300,505),'MYSPACE',font=fnt(70,True),fill='white'); d.text((1170,505),'FACEBOOK',font=fnt(70,True),fill=(45,85,150)); d.text((900,525),'VS',font=fnt(52,True),fill=(230,180,55))
    else:
        items=['PROFILE SONG → SHORT-FORM AUDIO','FRIENDS → FOLLOWERS','COMMENTS → REPLIES','ARTIST PAGES → CREATOR BRANDS']
        for j,t in enumerate(items): d.rounded_rectangle((260,340+j*115,1660,430+j*115),20,fill=(225,232,245)); d.text((310,365+j*115),t,font=fnt(34,True),fill=(35,45,75))
    d.rounded_rectangle((100,55,1820,155),28,fill=(5,10,24),outline='white',width=2); d.text((145,82),title,font=fnt(40,True),fill='white'); d.text((145,980),sub,font=fnt(30),fill=(210,220,245))
    p=OUT/f'card_{i:02d}.png'; im.save(p); return p

def main():
    wavs=[]
    for i in range(10):
        env=os.environ.copy(); env['CHUNK_INDEX']=str(i); run([sys.executable,str(REPO/'marcus'/'myspace_pilot.py')],env=env); wavs.append(CHUNKS/f'marcus_{i:02d}.wav')
    clips=[]
    for i,(title,sub) in enumerate(SECTIONS):
        img=card(i,title,sub); audio=wavs[i]; length=dur(audio); clip=OUT/f'section_{i:02d}.mp4'
        vf="scale=2200:-2,zoompan=z='min(zoom+0.0008,1.09)':x='iw/2-(iw/zoom/2)+sin(on/20)*7':y='ih/2-(ih/zoom/2)+cos(on/24)*5':d=1:s=1920x1080:fps=30,fade=t=in:st=0:d=.2"
        run(['ffmpeg','-y','-loop','1','-i',str(img),'-i',str(audio),'-t',f'{length:.3f}','-vf',vf,'-c:v','libx264','-preset','veryfast','-crf','20','-pix_fmt','yuv420p','-c:a','aac','-b:a','192k','-shortest',str(clip)]); clips.append(clip)
    lst=OUT/'concat.txt'; lst.write_text('\n'.join("file '%s'"%p.resolve() for p in clips),encoding='utf-8'); dry=OUT/'dry.mp4'; run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(lst),'-c','copy',str(dry)])
    total=dur(dry); bgm=OUT/'bgm.wav'; run(['ffmpeg','-y','-f','lavfi','-i',f'sine=frequency=110:sample_rate=48000:duration={total}','-af','volume=.025,lowpass=f=700',str(bgm)])
    full=OUT/'full.mp4'; run(['ffmpeg','-y','-i',str(dry),'-i',str(bgm),'-filter_complex','[0:a]volume=1[voice];[1:a]volume=.35[music];[voice][music]amix=inputs=2:duration=first:normalize=0,alimiter=limit=.95[a]','-map','0:v','-map','[a]','-c:v','copy','-c:a','aac','-b:a','192k','-movflags','+faststart',str(full)])
    im=Image.new('RGB',(W,H),(7,14,34)); d=ImageDraw.Draw(im); d.text((110,120),'WHATEVER HAPPENED TO',font=fnt(62,True),fill='white'); d.text((110,250),'MYSPACE?',font=fnt(170,True),fill=(70,145,255)); d.text((110,540),'$580M',font=fnt(105,True),fill=(75,205,130)); d.text((620,555),'→',font=fnt(92,True),fill=(245,195,60)); d.text((810,540),'$35M',font=fnt(105,True),fill=(245,80,100)); d.rounded_rectangle((110,750,1640,900),30,fill=(240,244,252)); d.text((170,792),'HOW DID IT FALL THIS HARD?',font=fnt(52,True),fill=(25,38,70)); im.save(OUT/'thumbnail.jpg',quality=94)
    for n,(start,end,title) in enumerate(SHORTS,1):
        start=min(start,max(0,total-45)); end=min(end,total); length=max(8,end-start); out=OUT/f'short_{n:02d}.mp4'; safe=title.replace("'",'').replace(':','-')[:40]
        vf=f"scale=-2:1920,crop=1080:1920:(iw-1080)/2:0,drawbox=x=0:y=0:w=1080:h=180:color=black@0.6:t=fill,drawtext=fontfile=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf:text='{safe}':fontcolor=white:fontsize=46:x=(w-text_w)/2:y=60"
        run(['ffmpeg','-y','-ss',str(start),'-i',str(full),'-t',str(length),'-vf',vf,'-c:v','libx264','-preset','veryfast','-crf','21','-c:a','aac','-b:a','160k','-movflags','+faststart',str(out)])
    print(f'BUILT duration={total:.2f}s')
if __name__=='__main__': main()
