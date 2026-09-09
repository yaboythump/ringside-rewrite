from __future__ import annotations
import math, os, random, subprocess
from pathlib import Path
import numpy as np
import soundfile as sf
from PIL import Image, ImageDraw, ImageFont, ImageFilter

ROOT = Path(__file__).resolve().parent
REPO = ROOT.parents[1]
OUT = ROOT / 'output'
SCENEDIR = OUT / 'scenes'
OUT.mkdir(parents=True, exist_ok=True)
SCENEDIR.mkdir(parents=True, exist_ok=True)
CHUNKS = REPO / 'marcus' / 'chunks'
W,H = 1280,720
FPS = 15
RNG = random.Random(2003)
COUNTS = [8,7,8,7,7,7,8,8,7,7]  # 74 visual changes

WHITE=(245,248,255); INK=(20,28,48); BLUE=(50,116,214); BLUE2=(88,160,255)
PINK=(239,63,150); GOLD=(245,188,63); GREEN=(66,191,125); RED=(235,72,86)
NAVY=(7,13,30); PALE=(229,236,248); SILVER=(174,188,213); PURPLE=(110,68,196)


def run(cmd):
    print('+', ' '.join(str(x) for x in cmd), flush=True)
    subprocess.run(cmd, check=True)

def duration(path: Path) -> float:
    r=subprocess.run(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(path)],capture_output=True,text=True,check=True)
    return float(r.stdout.strip())

def font(size:int,bold=False):
    p='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf' if bold else '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    return ImageFont.truetype(p,size)

def fit(draw,text,box,max_size=64,min_size=22,bold=True):
    x0,y0,x1,y1=box
    for s in range(max_size,min_size-1,-2):
        f=font(s,bold)
        bb=draw.multiline_textbbox((0,0),text,font=f,spacing=4)
        if bb[2]-bb[0] <= x1-x0 and bb[3]-bb[1] <= y1-y0:
            return f
    return font(min_size,bold)

def rounded(draw,box,fill,outline=None,width=2,r=18):
    draw.rounded_rectangle(box,radius=r,fill=fill,outline=outline,width=width)

def scanlines(im):
    d=ImageDraw.Draw(im,'RGBA')
    for y in range(0,H,4): d.line((0,y,W,y),fill=(255,255,255,10),width=1)
    # subtle corner vignette
    ov=Image.new('RGBA',(W,H),(0,0,0,0)); od=ImageDraw.Draw(ov,'RGBA')
    for i in range(55):
        a=int(i*1.1); od.rectangle((i,i,W-i,H-i),outline=(0,0,0,a),width=1)
    im.alpha_composite(ov)

def base(bg=NAVY):
    im=Image.new('RGBA',(W,H),bg+(255,))
    d=ImageDraw.Draw(im,'RGBA')
    # Y2K glow streaks
    d.ellipse((-220,-180,500,420),fill=(40,120,255,70))
    d.ellipse((930,410,1460,900),fill=(245,50,145,55))
    return im,d

def top_brand(d,section=None):
    rounded(d,(24,20,260,61),(4,8,20,215),(120,170,255,140),1,14)
    d.text((42,30),'WHATEVER HAPPENED TO…?',font=font(22,True),fill=WHITE)
    if section:
        rounded(d,(980,21,1254,60),(12,18,38,205),(255,255,255,70),1,14)
        f=fit(d,section,(995,27,1240,55),24,16,True); d.text((995,29),section,font=f,fill=(218,228,248))

def browser(d,box,url='myspace.com',dark=False):
    x0,y0,x1,y1=box; body=(238,243,251,255) if not dark else (20,27,45,255)
    chrome=(205,217,237,255) if not dark else (38,48,70,255)
    rounded(d,box,body,(255,255,255,160),2,20)
    d.rounded_rectangle((x0,y0,x1,y0+58),radius=20,fill=chrome)
    d.rectangle((x0,y0+38,x1,y0+58),fill=chrome)
    for k,c in enumerate([(255,85,80),(255,190,60),(73,199,105)]):
        cx=x0+28+k*34; cy=y0+28; d.ellipse((cx-9,cy-9,cx+9,cy+9),fill=c)
    rounded(d,(x0+145,y0+15,x1-24,y0+44),(255,255,255,235) if not dark else (9,14,26,230),None,0,12)
    d.text((x0+165,y0+21),url,font=font(16),fill=(77,88,110) if not dark else (184,200,230))
    return (x0,y0+58,x1,y1)

def myspace_logo(d,x,y,scale=1.0,color=BLUE):
    r=int(16*scale); gap=int(10*scale)
    for j in range(3):
        cx=x+j*(2*r+gap)
        d.ellipse((cx-r,y-r,cx+r,y+r),fill=color)
        d.rounded_rectangle((cx-r-2,y+r-2,cx+r+2,y+r+int(32*scale)),radius=int(8*scale),fill=color)
    d.text((x+int(105*scale),y-int(21*scale)),'myspace',font=font(max(18,int(34*scale)),True),fill=color)

def profile_window(d,box,variant=0):
    x0,y0,x1,y1=browser(d,box,'myspace.com/profile/view')
    # left profile rail
    d.rectangle((x0+20,y0+18,x0+250,y1-20),fill=(33,91,172,255))
    d.text((x0+42,y0+36),'MY PROFILE',font=font(26,True),fill=WHITE)
    d.rectangle((x0+45,y0+90,x0+220,y0+225),fill=(208,218,237,255))
    d.ellipse((x0+90,y0+112,x0+175,y0+197),fill=(78,101,166,255))
    d.text((x0+48,y0+247),'Mood: nostalgic',font=font(18,True),fill=WHITE)
    d.text((x0+48,y0+282),'Song: autoplay.mp3',font=font(16),fill=WHITE)
    # content rail
    cx=x0+285
    d.text((cx,y0+28),'Thump is in your extended network',font=font(24,True),fill=(35,52,88))
    rounded(d,(cx,y0+75,x1-25,y0+145),(245,220,244,255),(222,122,190,255),2,14)
    d.text((cx+20,y0+92),'“Thanks 4 the add!!!”  ★ glitter ★',font=font(23,True),fill=(120,38,112))
    if variant%2==0:
        d.text((cx,y0+175),'About Me',font=font(24,True),fill=(37,94,183))
        d.multiline_text((cx,y0+210),'custom HTML • wild fonts • profile song\ncomments • photos • bulletins',font=font(20),fill=(55,65,90),spacing=8)
    else:
        d.text((cx,y0+175),'Now Playing',font=font(24,True),fill=(37,94,183))
        rounded(d,(cx,y0+215,x1-40,y0+285),(219,226,241,255),(160,176,208,255),1,12)
        d.polygon([(cx+24,y0+236),(cx+24,y0+267),(cx+50,y0+251)],fill=PINK)
        d.text((cx+72,y0+235),'YOUR FAVORITE SONG — whether they asked or not',font=font(18,True),fill=(45,55,85))

def top8(d,box,drama=False,tom=False):
    x0,y0,x1,y1=box
    rounded(d,box,(239,244,252,255),(255,255,255,180),2,20)
    d.text((x0+28,y0+24),'THUMP’S TOP 8',font=font(30,True),fill=(37,91,177))
    for j in range(8):
        col=j%4; row=j//4
        bx=x0+35+col*((x1-x0-90)//4); by=y0+85+row*190
        bw=150
        rounded(d,(bx,by,bx+bw,by+150),(220,229,244,255),(164,180,211,255),1,14)
        color=(66+15*j,82+7*j,158+4*j)
        if tom and j==0: color=(92,126,179)
        d.ellipse((bx+40,by+16,bx+110,by+86),fill=color)
        label='TOM' if tom and j==0 else f'FRIEND {j+1}'
        d.text((bx+24,by+102),label,font=font(17,True),fill=(35,48,80))
        if drama and j in (2,6):
            d.line((bx+5,by+5,bx+bw-5,by+145),fill=RED,width=6)
            d.line((bx+bw-5,by+5,bx+5,by+145),fill=RED,width=6)

def html_editor(d,box):
    x0,y0,x1,y1=box
    rounded(d,box,(15,20,34,255),(120,160,235,180),2,18)
    lines=['<style>','body { background: url(glitter.gif); }','.profile { color: #ff4fb3; }','a:hover { text-shadow: 0 0 8px #66aaff; }','</style>','<embed src="favorite_song.mp3" autoplay="true">']
    for i,line in enumerate(lines):
        c=(120,205,255) if '<' in line else (240,130,205)
        d.text((x0+28,y0+30+i*48),line,font=font(22,False),fill=c)

def newspaper(d,headline,sub,big=None):
    rounded(d,(115,108,1165,626),(243,239,227,255),(255,255,255,170),2,10)
    d.text((150,135),'THE INTERNET DAILY',font=font(28,True),fill=(35,35,35))
    d.line((150,180,1128,180),fill=(50,50,50),width=2)
    f=fit(d,headline,(150,205,1125,330),64,34,True)
    d.multiline_text((150,210),headline,font=f,fill=(20,20,20),spacing=6)
    if big:
        d.text((150,365),big,font=font(104,True),fill=(36,103,182))
    d.multiline_text((150,505),sub,font=font(23),fill=(50,50,50),spacing=7)

def chart(d,box,values,labels,title,accent=BLUE):
    x0,y0,x1,y1=box
    rounded(d,box,(237,243,252,255),(255,255,255,170),2,20)
    d.text((x0+28,y0+24),title,font=font(26,True),fill=(40,55,90))
    ax0=x0+85; ay1=y1-65; ax1=x1-45; ay0=y0+90
    d.line((ax0,ay0,ax0,ay1),fill=(120,135,165),width=2); d.line((ax0,ay1,ax1,ay1),fill=(120,135,165),width=2)
    lo=min(values); hi=max(values); span=max(1,hi-lo)
    pts=[]
    for i,v in enumerate(values):
        x=ax0+(ax1-ax0)*i/(len(values)-1)
        y=ay1-(ay1-ay0)*(v-lo)/span
        pts.append((x,y))
    d.line(pts,fill=accent,width=7)
    for (x,y),lab,v in zip(pts,labels,values):
        d.ellipse((x-8,y-8,x+8,y+8),fill=accent)
        d.text((x-28,ay1+16),lab,font=font(16,True),fill=(70,80,105))
        d.text((x-35,y-35),str(v),font=font(18,True),fill=(45,55,85))

def split_battle(d):
    rounded(d,(45,115,610,630),(38,96,182,255),(120,176,255,200),3,24)
    rounded(d,(670,115,1235,630),(237,241,248,255),(255,255,255,210),3,24)
    d.text((115,155),'MYSPACE',font=font(55,True),fill=WHITE)
    d.text((800,155),'FACEBOOK',font=font(55,True),fill=(47,87,150))
    d.text((526,334),'VS',font=font(58,True),fill=GOLD)
    # messy left
    for i in range(7):
        x=90+(i%3)*160; y=255+(i//3)*100
        rounded(d,(x,y,x+130,y+72),(255,255,255,40),(255,255,255,75),1,10)
        d.text((x+12,y+21),['HTML','MUSIC','GLITTER','ADS','TOP 8','COMMENTS','BLOGS'][i],font=font(17,True),fill=WHITE)
    # clean right
    for i,t in enumerate(['NEWS FEED','FRIENDS','UPDATES','PHOTOS']):
        rounded(d,(760,270+i*72,1145,325+i*72),(220,229,243,255),(176,191,218,255),1,11)
        d.text((790,290+i*72),t,font=font(18,True),fill=(48,73,120))

def impact(d,big,small='',color=BLUE):
    d.rectangle((0,0,W,H),fill=(5,9,23,255))
    # diagonal energy streaks
    for k in range(9):
        x=-100+k*190
        d.polygon([(x,720),(x+90,720),(x+430,0),(x+340,0)],fill=(color[0],color[1],color[2],25+5*k))
    f=fit(d,big,(70,180,1210,445),132,48,True)
    bb=d.multiline_textbbox((0,0),big,font=f,spacing=4); tw=bb[2]-bb[0]
    d.multiline_text(((W-tw)/2,205),big,font=f,fill=WHITE,spacing=4,align='center')
    if small:
        fs=fit(d,small,(120,500,1160,600),42,24,True); bb=d.textbbox((0,0),small,font=fs); d.text(((W-(bb[2]-bb[0]))/2,520),small,font=fs,fill=color)

def make_scene(chunk,variant,global_idx):
    im,d=base(); section=['HOOK','2003','TOP 8','MUSIC','BIG BUSINESS','CHAOS','FACEBOOK','THE FALL','STILL ALIVE','LEGACY'][chunk]
    top_brand(d,section)

    if chunk==0:
        if variant==0: impact(d,'BEFORE FACEBOOK…','THERE WAS MYSPACE',BLUE2)
        elif variant==1:
            browser(d,(70,92,1210,648),'myspace.com'); myspace_logo(d,150,175,1.6); d.text((150,280),'Email',font=font(22,True),fill=INK); rounded(d,(150,315,565,365),WHITE,(155,170,200),1,10); d.text((150,405),'Password',font=font(22,True),fill=INK); rounded(d,(150,440,565,490),WHITE,(155,170,200),1,10); rounded(d,(150,525,395,585),BLUE,None,0,12); d.text((205,542),'SIGN IN',font=font(24,True),fill=WHITE)
        elif variant==2: profile_window(d,(58,90,1222,650),0)
        elif variant==3: top8(d,(110,105,1170,635),True,True); d.text((830,72),'YOU MOVED ME?!',font=font(36,True),fill=RED)
        elif variant==4:
            profile_window(d,(58,90,1222,650),1); rounded(d,(720,250,1155,345),(11,17,35,235),(255,255,255,120),2,16); d.text((755,278),'♪ AUTOPLAYING NOW',font=font(25,True),fill=PINK)
        elif variant==5:
            im,d=base((10,8,28)); top_brand(d,section); d.text((65,120),'GLITTER. HTML. COMMENTS. MUSIC.',font=font(45,True),fill=WHITE)
            for i,t in enumerate(['★ GLITTER ★','<HTML>','TOP 8','COMMENTS','PROFILE SONG']):
                x=75+(i%3)*395; y=240+(i//3)*180; rounded(d,(x,y,x+335,y+120),(30+20*i,40,95+18*i,230),(255,255,255,100),2,18); d.text((x+25,y+38),t,font=font(28,True),fill=WHITE)
        elif variant==6: impact(d,'THE INTERNET\nLIVED HERE','FOR A FEW YEARS',PINK)
        else: impact(d,'WHAT HAPPENED\nTO MYSPACE?','RISE • FALL • LEGACY',BLUE2)

    elif chunk==1:
        if variant==0: impact(d,'2003','MYSPACE ARRIVES',BLUE2)
        elif variant==1:
            browser(d,(55,95,1225,655),'myspace.com/editprofile'); d.text((90,145),'Customize Your Profile',font=font(40,True),fill=(40,78,142)); html_editor(d,(105,220,725,600)); rounded(d,(765,220,1165,600),(255,245,252,255),(225,120,190),2,16); d.text((820,270),'LIVE PREVIEW',font=font(25,True),fill=(120,50,110)); d.rectangle((825,330,1100,520),fill=(51,91,170)); d.text((875,390),'YOUR\nPROFILE',font=font(42,True),fill=WHITE)
        elif variant==2:
            d.text((60,105),'THE WEB STOPPED LOOKING LIKE AN OFFICE',font=font(38,True),fill=WHITE)
            for i,(t,c) in enumerate([('BROADBAND',BLUE),('DIGITAL CAMERAS',PINK),('MUSIC ONLINE',PURPLE),('SOCIAL PAGES',GREEN)]):
                x=80+(i%2)*585; y=220+(i//2)*190; rounded(d,(x,y,x+525,y+150),(c[0],c[1],c[2],190),(255,255,255,80),2,22); d.text((x+38,y+54),t,font=font(33,True),fill=WHITE)
        elif variant==3: profile_window(d,(58,90,1222,650),variant)
        elif variant==4:
            im,d=base((22,8,32)); top_brand(d,section); d.text((70,105),'COLOR PICKER FROM HELL 😂',font=font(42,True),fill=WHITE)
            cols=[(255,55,150),(65,165,255),(98,220,130),(255,190,55),(150,80,220),(245,245,245)]
            for i,c in enumerate(cols):
                x=90+(i%3)*370; y=235+(i//3)*175; d.rectangle((x,y,x+310,y+125),fill=c); d.text((x+20,y+42),['HOT PINK','ELECTRIC BLUE','LIME','GOLD','PURPLE','WHITE'][i],font=font(24,True),fill=INK if i in (3,5) else WHITE)
        elif variant==5:
            html_editor(d,(70,105,1210,640)); d.text((690,515),'“keyboard exploded\ninside a Hot Topic”',font=font(32,True),fill=GOLD)
        else: impact(d,'YOUR PAGE.\nYOUR RULES.','THAT WAS THE MAGIC',PINK)

    elif chunk==2:
        if variant==0: impact(d,'TOP 8','PUBLIC FRIEND RANKINGS 😳',PINK)
        elif variant==1: top8(d,(100,110,1180,640),False,True)
        elif variant==2: top8(d,(100,110,1180,640),True,True); d.text((840,74),'#3 → #7',font=font(42,True),fill=RED)
        elif variant==3:
            rounded(d,(120,120,1160,625),(237,243,252,255),(255,255,255,180),2,20); d.text((165,165),'NEW COMMENT!',font=font(38,True),fill=(38,92,180)); msgs=['why am i #7 now??','wow. removed from top 8. cool.','call me when u get home 😐','TOM would never do this.']
            for i,m in enumerate(msgs): rounded(d,(170,245+i*78,1085,304+i*78),(219,228,243,255),(166,182,214),1,14); d.text((195,265+i*78),m,font=font(22,True),fill=(42,54,85))
        elif variant==4:
            browser(d,(65,100,1215,645),'myspace.com/friends'); d.text((105,160),'Your Friend Space',font=font(34,True),fill=(38,90,178)); d.text((105,210),'You have 1 friend',font=font(24),fill=(60,70,95)); rounded(d,(120,280,520,535),(222,231,245,255),(160,178,210),2,18); d.ellipse((225,315,415,505),fill=(92,126,179)); d.text((265,525),'Tom',font=font(27,True),fill=(35,50,84)); d.text((620,325),'EVERYBODY’S\nFIRST FRIEND',font=font(47,True),fill=(36,90,177))
        elif variant==5: impact(d,'TOM','THE INTERNET’S LANDLORD 😂',BLUE2)
        elif variant==6:
            top8(d,(80,110,1200,645),True,True); d.text((80,74),'FRIENDSHIP STATUS:',font=font(28,True),fill=WHITE); d.text((430,70),'COMPLICATED',font=font(34,True),fill=RED)
        else: impact(d,'ALGORITHMS DO IT\nQUIETLY NOW','PROBABLY SAFER',GOLD)

    elif chunk==3:
        if variant==0: impact(d,'MYSPACE MUSIC','BEFORE STREAMING TOOK OVER',PINK)
        elif variant in (1,2,3):
            browser(d,(60,95,1220,650),'myspace.com/music/artist'); d.text((100,150),'MYSPACE MUSIC',font=font(38,True),fill=(37,91,180)); rounded(d,(100,225,470,575),(29,56,108,255),(130,180,255),2,18); d.text((145,265),'BAND NAME',font=font(36,True),fill=WHITE); d.text((145,330),'NEW SINGLE',font=font(22),fill=(190,210,245)); d.polygon([(165,405),(165,495),(245,450)],fill=PINK); d.text((520,245),'ADD SONG TO PROFILE',font=font(30,True),fill=(45,60,90)); d.text((520,320),'SHOW DATES',font=font(28,True),fill=(45,60,90)); d.text((520,385),'MESSAGE ARTIST',font=font(28,True),fill=(45,60,90)); d.text((520,450),'ADD FRIEND',font=font(28,True),fill=(45,60,90));
            if variant==2: rounded(d,(710,505,1130,580),(255,225,240,255),(230,100,170),2,14); d.text((750,528),'FANS SPREAD THE SONG',font=font(20,True),fill=(120,45,105))
            if variant==3: d.text((540,535),'DIRECT-TO-FAN\nBEFORE IT WAS NORMAL',font=font(31,True),fill=(38,92,180))
        elif variant==4:
            impact(d,'100,000,000','REGISTERED PROFILE MILESTONE — 2006',GREEN)
        elif variant==5:
            d.text((65,105),'CULTURE MACHINE',font=font(52,True),fill=WHITE)
            for i,t in enumerate(['ARTISTS','COMEDIANS','FILMMAKERS','BRANDS','TEENS','FANS']):
                ang=i*math.pi/3; cx=640+330*math.cos(ang); cy=380+210*math.sin(ang); rounded(d,(cx-120,cy-48,cx+120,cy+48),(38,75+15*i,150+10*i,220),(255,255,255,85),2,16); bb=d.textbbox((0,0),t,font=font(23,True)); d.text((cx-(bb[2]-bb[0])/2,cy-15),t,font=font(23,True),fill=WHITE)
        else: impact(d,'BIG BUSINESS\nNOTICED','AND THE MONEY GOT SERIOUS',GOLD)

    elif chunk==4:
        if variant==0: impact(d,'$580 MILLION','NEWS CORP BUYS INTERMIX — 2005',GREEN)
        elif variant==1: newspaper(d,'NEWS CORP AGREES TO BUY\nMYSPACE PARENT INTERMIX','The cash acquisition put one of the fastest-growing social networks inside a media empire.','$580M')
        elif variant==2:
            d.text((60,105),'AT FIRST… IT LOOKED CHEAP',font=font(47,True),fill=WHITE); d.text((80,235),'$580M',font=font(120,True),fill=GREEN); d.text((520,265),'→',font=font(90,True),fill=GOLD); d.text((700,235),'MYSPACE\nEXPLODES',font=font(64,True),fill=BLUE2)
        elif variant==3: impact(d,'$900 MILLION','GOOGLE / FOX INTERACTIVE DEAL',GOLD)
        elif variant==4:
            rounded(d,(90,115,1190,625),(237,243,252,255),(255,255,255,170),2,22); d.text((145,160),'GOOGLE SEARCH + ADS',font=font(42,True),fill=(55,94,175)); d.text((145,245),'GUARANTEED MINIMUM\nREVENUE-SHARE PAYMENTS',font=font(34,True),fill=(45,60,90)); d.text((145,400),'$900M',font=font(120,True),fill=GOLD); d.text((720,430),'subject to traffic requirements',font=font(20),fill=(85,95,115))
        elif variant==5:
            d.text((60,90),'2007: THE CENTER OF ONLINE CULTURE',font=font(41,True),fill=WHITE)
            for i,t in enumerate(['MUSIC','CELEBRITIES','BRANDS','FILM','COMEDY','EVERYBODY']):
                x=75+(i%3)*395; y=210+(i//3)*190; rounded(d,(x,y,x+340,y+145),(25+10*i,65+9*i,135+12*i,230),(255,255,255,80),2,20); d.text((x+35,y+52),t,font=font(29,True),fill=WHITE)
        else: impact(d,'SMARTEST INTERNET\nPURCHASE EVER?','FOR A MINUTE… IT LOOKED LIKE IT',GREEN)

    elif chunk==5:
        if variant==0: impact(d,'THEN IT GOT MESSY','FREEDOM → CHAOS',RED)
        elif variant==1:
            browser(d,(55,95,1225,655),'myspace.com/home');
            for i in range(13):
                x=85+(i%4)*280; y=165+(i//4)*125; rounded(d,(x,y,x+245,y+95),((60+15*i)%220,55+8*i,130+5*i,245),(255,255,255,80),1,12); d.text((x+16,y+31),['AD','BULLETIN','MUSIC','COMMENT','GLITTER','PROFILE','BLOG','VIDEO','FRIENDS','PROMO','POPUP','EVENT','MORE ADS'][i],font=font(18,True),fill=WHITE)
        elif variant==2:
            rounded(d,(110,135,1170,610),(237,243,252,255),(255,255,255,170),2,22); d.text((160,185),'LOADING YOUR PROFILE…',font=font(38,True),fill=(38,88,172)); d.rectangle((165,290,1110,360),fill=(205,215,232)); d.rectangle((165,290,690,360),fill=BLUE); d.text((165,410),'HTML + autoplay music + ads + widgets + glitter = 😵',font=font(29,True),fill=(54,65,95))
        elif variant==3:
            d.text((65,105),'ONE PRODUCT. TOO MANY JOBS.',font=font(43,True),fill=WHITE)
            for i,t in enumerate(['SOCIAL NETWORK','MUSIC PLATFORM','MEDIA COMPANY','AD MACHINE','ENTERTAINMENT PORTAL','CREATOR HUB']):
                x=80+(i%2)*590; y=205+(i//2)*135; rounded(d,(x,y,x+530,y+100),(30,55+10*i,105+18*i,225),(255,255,255,70),2,18); d.text((x+30,y+34),t,font=font(25,True),fill=WHITE)
        elif variant==4: split_battle(d)
        elif variant==5: impact(d,'DESTINATION','vs. HABIT',BLUE2)
        else:
            split_battle(d); d.text((80,655),'MYSPACE: expressive, wild, cluttered',font=font(21,True),fill=(180,205,245)); d.text((730,655),'FACEBOOK: clean, repeatable, sticky',font=font(21,True),fill=(210,220,235))

    elif chunk==6:
        if variant==0: impact(d,'APRIL 2008','THE CROWN STARTS MOVING',GOLD)
        elif variant==1:
            rounded(d,(120,130,1160,610),(237,243,252,255),(255,255,255,180),2,20); d.text((180,185),'GLOBAL UNIQUE USERS',font=font(36,True),fill=(45,60,90)); d.text((190,300),'FACEBOOK',font=font(32,True),fill=(45,85,150)); d.text((650,285),'116.4M',font=font(82,True),fill=BLUE); d.text((190,435),'MYSPACE',font=font(32,True),fill=(45,85,150)); d.text((650,420),'115.7M',font=font(82,True),fill=PINK)
        elif variant==2:
            d.text((65,100),'IT WASN’T ONE THING',font=font(50,True),fill=WHITE)
            factors=['PRODUCT SPEED','LEADERSHIP CHANGES','CORPORATE PRESSURE','CLUTTER','NETWORK EFFECT','FACEBOOK FOCUS']
            for i,t in enumerate(factors):
                x=75+(i%3)*400; y=230+(i//3)*185; rounded(d,(x,y,x+350,y+135),(34,62+10*i,120+16*i,230),(255,255,255,85),2,18); d.text((x+28,y+48),t,font=font(22,True),fill=WHITE)
        elif variant==3: chart(d,(100,125,1180,620),[40,65,88,101,116.4],["'04","'05","'06","'07","'08"],'FACEBOOK KEEPS CLIMBING',BLUE)
        elif variant==4: impact(d,'THE PRODUCT IS\nEVERYBODY YOU KNOW','NETWORK EFFECTS ARE BRUTAL',PINK)
        elif variant==5:
            d.text((65,100),'WHEN YOUR FRIENDS MOVE…',font=font(44,True),fill=WHITE)
            for i in range(9):
                x=120+i*115; y=350+45*math.sin(i); d.ellipse((x-30,y-30,x+30,y+30),fill=(75,115,185)); d.line((x+30,y,x+80,y),fill=(180,195,220),width=4)
            d.text((925,285),'→ FACEBOOK',font=font(38,True),fill=BLUE2)
        elif variant==6: impact(d,'MOMENTUM\nCHANGED SIDES','AND THEN IT ACCELERATED',RED)
        else: split_battle(d)

    elif chunk==7:
        if variant==0: impact(d,'THE COLLAPSE','76.3M → 35M MONTHLY AUDIENCE',RED)
        elif variant==1: chart(d,(95,120,1185,620),[76.3,68,57,44,35],["Oct '08","'09","'10","Early '11","May '11"],'MYSPACE MONTHLY AUDIENCE',RED)
        elif variant==2:
            newspaper(d,'MYSPACE CUTS JOBS\nAS MOMENTUM FADES','The site remained huge, but the growth story had reversed.','2009')
        elif variant==3:
            newspaper(d,'SPECIFIC MEDIA BUYS MYSPACE','June 2011: cash and equity deal.','$35M')
        elif variant==4:
            impact(d,'$580M  →  $35M','SIX YEARS',RED)
        elif variant==5:
            im,d=base((22,6,12)); top_brand(d,section); myspace_logo(d,215,310,2.0,(90,110,145)); d.line((120,170,1160,610),fill=RED,width=13); d.line((1080,150,170,650),fill=(170,35,55),width=7); d.text((760,500),'THE FALL',font=font(70,True),fill=WHITE)
        elif variant==6: impact(d,'SIX YEARS.','THAT NUMBER DOESN’T NEED DRAMATIC MUSIC…',GOLD)
        else: impact(d,'…BUT WE GAVE IT\nDRAMATIC MUSIC ANYWAY 😂','',PINK)

    elif chunk==8:
        if variant==0: impact(d,'BUT WAIT…','MYSPACE STILL EXISTS',GREEN)
        elif variant==1:
            browser(d,(55,95,1225,655),'myspace.com',True); d.text((110,155),'myspace',font=font(52,True),fill=WHITE); d.text((110,235),'Discover',font=font(29,True),fill=(185,205,235)); d.text((300,235),'Music',font=font(29,True),fill=(185,205,235)); d.text((450,235),'Videos',font=font(29,True),fill=(185,205,235)); d.text((600,235),'People',font=font(29,True),fill=(185,205,235)); rounded(d,(110,330,1120,565),(32,42,66,255),(80,105,150),2,18); d.text((160,390),'ENTERTAINMENT + DISCOVERY',font=font(40,True),fill=WHITE)
        elif variant==2:
            impact(d,'YES, REALLY.','STILL ONLINE IN 2026',GREEN)
        elif variant==3:
            d.text((65,100),'THE IDEAS SURVIVED',font=font(49,True),fill=WHITE); pairs=[('ARTIST PAGES','CREATOR PAGES'),('DIRECT FANS','FOLLOWERS'),('PROFILE SONG','STREAMING LINKS'),('COMMENTS','REPLIES')]
            for i,(a,b) in enumerate(pairs):
                y=215+i*105; rounded(d,(90,y,500,y+72),(34,74,145,230),(255,255,255,70),2,14); d.text((125,y+22),a,font=font(22,True),fill=WHITE); d.text((555,y+14),'→',font=font(37,True),fill=GOLD); rounded(d,(660,y,1180,y+72),(55,35+8*i,105+13*i,230),(255,255,255,70),2,14); d.text((700,y+22),b,font=font(22,True),fill=WHITE)
        elif variant==4:
            d.text((65,100),'CREATORS BEFORE “CREATOR ECONOMY”',font=font(39,True),fill=WHITE)
            for i,t in enumerate(['MUSIC','PHOTOS','MESSAGING','PERSONAL BRAND','FAN CONNECTION','DISCOVERY']):
                x=75+(i%3)*395; y=230+(i//3)*170; rounded(d,(x,y,x+340,y+120),(28,62+10*i,125+14*i,225),(255,255,255,80),2,18); d.text((x+30,y+42),t,font=font(24,True),fill=WHITE)
        elif variant==5: impact(d,'THE NAME SURVIVED','THE CULTURE MOVED ON',BLUE2)
        else: impact(d,'A LOT OF THE INTERNET\nSTILL LOOKS LIKE MYSPACE','JUST CLEANER 😂',PINK)

    else:
        if variant==0: impact(d,'MAYBE IT NEVER\nDISAPPEARED','MAYBE THE INTERNET ABSORBED IT',BLUE2)
        elif variant==1:
            pairs=[('PROFILE','PERSONAL BRAND'),('FRIENDS','FOLLOWERS'),('PROFILE SONG','SHORT-FORM AUDIO'),('COMMENTS','REPLIES')]
            for i,(a,b) in enumerate(pairs):
                y=150+i*125; d.text((95,y),a,font=font(31,True),fill=WHITE); d.text((495,y),'→',font=font(34,True),fill=GOLD); d.text((590,y),b,font=font(31,True),fill=BLUE2)
        elif variant==2:
            top8(d,(90,115,1190,635),False,True); d.text((85,75),'TOP 8 → ALGORITHM',font=font(36,True),fill=WHITE)
        elif variant==3: impact(d,'NOW THEY RANK\nEVERYBODY QUIETLY','PROBABLY SAFER FOR FRIENDSHIPS',GOLD)
        elif variant==4:
            rounded(d,(160,135,1120,610),(234,241,252,255),(255,255,255,180),2,22); d.ellipse((470,210,810,550),fill=(92,126,179)); d.text((545,570),'TOM',font=font(31,True),fill=(38,60,100)); d.text((280,95),'THE ONE INTERNET FRIEND\nWHO NEVER CAUSED DRAMA',font=font(34,True),fill=WHITE)
        elif variant==5:
            impact(d,'I’M MARCUS','WHATEVER HAPPENED TO…?',PINK)
        else:
            impact(d,'NOW YOU KNOW\nWHAT HAPPENED TO IT.','WHATEVER HAPPENED TO…?',BLUE2)

    # final polish
    scanlines(im)
    return im.convert('RGB')


def synth_music(total:float, boundaries:list[float], out:Path):
    sr=48000; block=sr*5
    with sf.SoundFile(out,'w',samplerate=sr,channels=1,subtype='PCM_16') as f:
        total_n=int(total*sr)
        for start in range(0,total_n,block):
            n=min(block,total_n-start); t=(start+np.arange(n))/sr
            # section-dependent harmonic identity
            sec=max(0,min(len(boundaries)-2, np.searchsorted(boundaries,t[0],side='right')-1))
            roots=[55,65.4,73.4,82.4,61.7,55,49,43.65,65.4,55]
            root=roots[sec]
            bpm=[86,88,90,92,88,84,82,78,86,84][sec]
            beat=60.0/bpm
            phase=np.mod(t,beat)
            kick=np.exp(-phase*18.0)*np.sin(2*np.pi*(root*0.95)*t)
            half=np.mod(t+beat/2,beat)
            clap=np.exp(-half*35.0)*np.sin(2*np.pi*180*t)
            arp=(np.sin(2*np.pi*root*2*t)+0.6*np.sin(2*np.pi*root*2.5*t)+0.45*np.sin(2*np.pi*root*3*t))/2.05
            pad=0.55*np.sin(2*np.pi*root*t)+0.28*np.sin(2*np.pi*root*1.5*t)
            # collapse gets darker and more sparse
            if sec==7:
                sig=.018*pad+.011*kick+.003*clap
            else:
                sig=.014*pad+.009*arp+.010*kick+.003*clap
            # soft digital shimmer
            sig += .0025*np.sin(2*np.pi*(880+70*np.sin(2*np.pi*.08*t))*t)
            sig=np.tanh(sig*1.3)
            f.write(sig.astype(np.float32))

def synth_sfx(total:float,boundaries:list[float],out:Path):
    sr=48000; n=int(total*sr); a=np.zeros(n,dtype=np.float32)
    def hit(time_s,kind=0):
        s=int(time_s*sr); L=min(int(.55*sr),n-s)
        if L<=0:return
        tt=np.arange(L)/sr
        if kind==0:
            w=.18*np.exp(-tt*9)*np.sin(2*np.pi*(90-35*tt)*tt)
        else:
            w=.12*np.exp(-tt*12)*(np.sin(2*np.pi*950*tt)+.5*np.sin(2*np.pi*1450*tt))
        a[s:s+L]+=w.astype(np.float32)
    for i,b in enumerate(boundaries[:-1]): hit(b,1 if i%2 else 0)
    # extra financial-collapse hit near chunk 7
    if len(boundaries)>8: hit(boundaries[7]+2.0,0); hit(boundaries[7]+18.0,1)
    sf.write(out,a,sr,subtype='PCM_16')

def make_thumbnail():
    im,d=base((5,9,22));
    # fractured browser shards
    for i in range(7):
        x=40+i*165; y=80+(i%3)*55
        rounded(d,(x,y,x+290,y+210),(235,241,252,220),(255,255,255,100),2,16)
        d.rectangle((x,y,x+290,y+45),fill=(198,214,239,235))
        d.text((x+18,y+12),'myspace.com',font=font(15,True),fill=(60,80,115))
        d.line((x+20,y+65,x+260,y+180),fill=(120,150,205),width=3)
    # dark panel for text
    d.rounded_rectangle((35,34,1245,686),radius=28,fill=(3,7,19,105),outline=(255,255,255,40),width=2)
    myspace_logo(d,80,135,1.5,BLUE2)
    d.text((78,225),'WHAT HAPPENED?',font=font(75,True),fill=WHITE)
    d.text((82,380),'$580M',font=font(82,True),fill=GREEN)
    d.text((440,398),'→',font=font(65,True),fill=GOLD)
    d.text((570,380),'$35M',font=font(82,True),fill=RED)
    d.text((84,505),'THE RISE & FALL OF MYSPACE',font=font(37,True),fill=(205,220,248))
    # red crash arrow
    d.line((1050,210,900,515),fill=RED,width=18); d.polygon([(900,515),(946,472),(967,535)],fill=RED)
    scanlines(im)
    im.convert('RGB').save(OUT/'thumbnail.jpg',quality=95)

def make_short(full:Path,start:float,length:float,out:Path):
    fc="[0:v]split=2[bg][fg];[bg]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,gblur=sigma=28[bg];[fg]scale=1040:-2[fg];[bg][fg]overlay=(W-w)/2:(H-h)/2"
    run(['ffmpeg','-y','-ss',f'{start:.3f}','-i',str(full),'-t',f'{length:.3f}','-filter_complex',fc,'-c:v','libx264','-preset','veryfast','-crf','21','-pix_fmt','yuv420p','-c:a','aac','-b:a','160k','-movflags','+faststart',str(out)])


def main():
    wavs=[CHUNKS/f'marcus_{i:02d}.wav' for i in range(10)]
    for p in wavs:
        if not p.exists() or p.stat().st_size<1000: raise SystemExit(f'Missing Marcus chunk: {p}')
    durs=[duration(p) for p in wavs]
    bounds=[0.0]
    for d in durs: bounds.append(bounds[-1]+d)
    total=bounds[-1]

    # Narration master
    concat=OUT/'narration.ffconcat'; concat.write_text('\n'.join(["ffconcat version 1.0"]+[f"file '{p.resolve()}'" for p in wavs]),encoding='utf-8')
    raw=OUT/'Marcus_MySpace_RAW.wav'; mastered=OUT/'Marcus_MySpace_MASTERED.wav'
    run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(concat),'-c:a','pcm_s16le',str(raw)])
    run(['ffmpeg','-y','-i',str(raw),'-af','highpass=f=70,equalizer=f=3000:t=q:w=1.2:g=1.1,acompressor=threshold=-18dB:ratio=2.3:attack=15:release=120,loudnorm=I=-16:TP=-1.5:LRA=7,alimiter=limit=.95',str(mastered)])

    # 74 documentary scenes, duration-locked to each narration chunk
    entries=['ffconcat version 1.0']; global_idx=0
    for chunk,(count,chunk_dur) in enumerate(zip(COUNTS,durs)):
        first=1.15 if chunk else 1.8
        remaining=max(0.1,chunk_dur-first)
        normal=remaining/(count-1)
        for variant in range(count):
            img=make_scene(chunk,variant,global_idx)
            p=SCENEDIR/f'{global_idx:03d}.jpg'; img.save(p,quality=93)
            entries.append(f"file '{p.resolve()}'")
            entries.append(f"duration {first if variant==0 else normal:.6f}")
            global_idx+=1
    last=SCENEDIR/f'{global_idx-1:03d}.jpg'; entries.append(f"file '{last.resolve()}'")
    scenelist=OUT/'scenes.ffconcat'; scenelist.write_text('\n'.join(entries),encoding='utf-8')

    visuals=OUT/'visuals.mp4'
    vf="scale=1344:756,crop=1280:720:x='32+10*sin(n/18)':y='18+6*cos(n/23)',noise=alls=1.6:allf=t,unsharp=5:5:0.22:5:5:0.0,fps=15"
    run(['ffmpeg','-y','-f','concat','-safe','0','-i',str(scenelist),'-vf',vf,'-t',f'{total:.3f}','-c:v','libx264','-preset','veryfast','-crf','21','-pix_fmt','yuv420p','-an',str(visuals)])

    music=OUT/'myspace_y2k_bed.wav'; sfx=OUT/'myspace_sfx.wav'
    synth_music(total,bounds,music); synth_sfx(total,bounds,sfx)

    full=OUT/'full.mp4'
    mix="[1:a]volume=1[voice];[2:a]volume=.78[music];[3:a]volume=.62[sfx];[voice][music][sfx]amix=inputs=3:duration=first:normalize=0,alimiter=limit=.96[a]"
    run(['ffmpeg','-y','-i',str(visuals),'-i',str(mastered),'-i',str(music),'-i',str(sfx),'-filter_complex',mix,'-map','0:v','-map','[a]','-c:v','copy','-c:a','aac','-b:a','192k','-movflags','+faststart','-shortest',str(full)])
    make_thumbnail()

    # Shorts chosen from strongest master moments; preserve 16:9 frame over blurred vertical background.
    picks=[
        (bounds[2]+2, min(43,durs[2]-3)),
        (bounds[2]+max(20,durs[2]-30), min(28,durs[2]-max(20,durs[2]-30))),
        (bounds[3]+2, min(44,durs[3]-3)),
        (max(bounds[3]+24,bounds[4]-18), min(42,total-max(bounds[3]+24,bounds[4]-18)-1)),
        (bounds[5]+8, min(48,durs[5]-9)),
        (bounds[7]+12, min(42,durs[7]-13)),
    ]
    for i,(start,length) in enumerate(picks,1):
        length=max(10,min(58,length)); start=max(0,min(start,total-length-.2)); make_short(full,start,length,OUT/f'short_{i:02d}.mp4')

    print(f'BUILT flashy MySpace master: scenes={global_idx} duration={duration(full):.2f}s',flush=True)

if __name__=='__main__':
    main()
