#!/usr/bin/env python3
from pathlib import Path
import gc, subprocess
import torch
import soundfile as sf
from qwen_tts import Qwen3TTSModel

ROOT=Path('/workspace/ctnetwork-local')
MODEL=ROOT/'models/qwen3-tts/1.7B-VoiceDesign'
OUT=Path('/workspace/ringside-news-ep1-f06')
OUT.mkdir(parents=True,exist_ok=True)
INSTRUCT="Contemporary American female narrator, mature and polished, deeper register, calm authority, smooth deliberate pacing, sophisticated documentary presence, natural and modern."
CHUNKS=[
"CM Punk just threw himself directly back into the WWE Championship picture. One of AEW’s biggest champions has officially been ruled out of All Out. And there could be another major name headed toward AEW. This isn’t a recap. This is what’s happening across professional wrestling right now. This is Ringside News.",
"We start with the WWE Championship, because things just got complicated. Sami Zayn remains WWE Champion, but CM Punk made sure nobody left SmackDown talking about a simple title defense. Punk entered the situation involving Sami Zayn and Kevin Owens and struck Owens with the championship, directly affecting the finish. But Punk wasn’t there to help Sami. Afterward, Punk made his intentions pretty clear.",
"The championship picture now has Sami Zayn holding the gold, Kevin Owens with unfinished business, and CM Punk still very much involved. And with Money in the Bank approaching, WWE suddenly has multiple directions it could take with its top championship. The important story here isn't simply who won Friday night. It's that WWE's main-event picture just got a lot more crowded.",
"Over in AEW, there is a significant change involving the Women’s World Championship. Mercedes Moné is not medically cleared to compete at All Out after suffering a broken nose. Instead, Willow Nightingale and Thekla will meet at All Out to determine the next challenger. The winner gets Mercedes at WrestleDream. So while Mercedes remains champion, AEW has had to change course for one of its biggest upcoming events.",
"And AEW has championship business happening tonight on Collision. Andrade El Ídolo is scheduled to defend the AEW National Championship against Daniel Garcia. Darby Allin also puts the TNT Championship on the line against Myron Reed. Two championships. Two challengers. And with All Out getting closer, tonight could change several pieces of AEW’s upcoming picture.",
"Now it's time for Rumor Watch. And remember: this is where reported information stays reported until the promotion itself confirms it. There is reporting that Ilja Dragunov has signed with AEW, with promotional preparations reportedly underway. As of this update, we're treating that as a report, not an official AEW announcement. But if it becomes official, that would give AEW another major name with an immediate path to high-profile matches. We’ll keep watching this one.",
"Now, around the rest of the wrestling world. CMLL celebrated its ninety-third Anniversary in Arena México, and Místico defeated longtime rival Averno in their mask-versus-hair showdown. Averno lost his hair, and the rivalry still wasn't finished when the bell rang. Andrade El Ídolo also picked up a victory over Volador Junior on the anniversary card. That event featured talent crossing over from multiple major promotions, another example of just how connected the wrestling world has become.",
"CM Punk is back in the WWE Championship conversation. Mercedes Moné is out of All Out. AEW has two championship matches tonight. And another major name may be preparing to enter the AEW picture. Stories are moving fast, and we'll stay on them. That’s your Ringside News update. For breaking stories, developing reports, injuries, contracts, returns and everything happening beyond the matches, stay Ringside."
]
def run(cmd): subprocess.run(cmd,check=True)
tts=Qwen3TTSModel.from_pretrained(str(MODEL),device_map='cuda:0',dtype=torch.bfloat16)
parts=[]
for i,text in enumerate(CHUNKS,1):
    torch.manual_seed(606)
    wavs,sr=tts.generate_voice_design(text=text,language='English',instruct=INSTRUCT,max_new_tokens=4096)
    raw=OUT/f'part_{i:02d}_raw.wav'; clean=OUT/f'part_{i:02d}.wav'
    sf.write(raw,wavs[0],sr)
    run(['ffmpeg','-y','-loglevel','error','-i',str(raw),'-af','highpass=f=65,acompressor=threshold=-18dB:ratio=2.2:attack=12:release=100,loudnorm=I=-16:TP=-1.5:LRA=8,alimiter=limit=0.95','-ar','48000','-ac','1','-c:a','pcm_s16le',str(clean)])
    raw.unlink(missing_ok=True); parts.append(clean); gc.collect(); torch.cuda.empty_cache()
concat=OUT/'concat.txt'; concat.write_text('\n'.join(f"file '{p}'" for p in parts)+'\n')
master=OUT/'Ringside_News_Ep1_F06.wav'
run(['ffmpeg','-y','-loglevel','error','-f','concat','-safe','0','-i',str(concat),'-c:a','pcm_s16le','-ar','48000','-ac','1',str(master)])
dur=float(subprocess.check_output(['ffprobe','-v','error','-show_entries','format=duration','-of','default=nw=1:nk=1',str(master)],text=True).strip())
Path('/workspace/ringside-news-f06-status.txt').write_text('0')
Path('/workspace/ringside-news-f06-duration.txt').write_text(str(dur))
print('RINGSIDE_NEWS_F06_READY',dur,flush=True)
