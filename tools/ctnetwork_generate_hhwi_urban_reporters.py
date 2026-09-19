#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import gc, json, subprocess, tarfile, shutil
import torch
import soundfile as sf
from huggingface_hub import snapshot_download
from qwen_tts import Qwen3TTSModel

ROOT=Path("/workspace/ctnetwork-local")
MODEL=ROOT/"models/qwen3-tts/1.7B-VoiceDesign"
OUT=ROOT/"narrator-auditions/hhwi-urban-reporter-8"
PACKAGE=Path("/workspace/CTNETWORK_HHWI_Urban_Reporter_Auditions.tar.gz")

TEXT=(
    "What if the biggest move in hip hop never happened? "
    "One decision could have changed the label, the rivalry, and the careers that followed. "
    "This is Hip Hop What If, where we break down the timeline and ask what really could have happened."
)

VOICES={
"H01":"Black American female hip-hop culture reporter, early 30s, confident and sharp, grounded conversational cadence, warm lower-mid register, authentic urban media energy, documentary seriousness, natural emphasis, never radio-announcer or exaggerated.",
"H02":"Black American female entertainment journalist, late 20s to early 30s, smooth confident delivery, contemporary hip-hop newsroom cadence, slightly smoky tone, fast but controlled pacing, natural attitude, polished without sounding corporate.",
"H03":"Black American female hip-hop documentary narrator, mature lower register, gritty but clean tone, calm authority, rhythmic urban cadence, serious storytelling presence, subtle attitude, emotionally grounded and natural.",
"H04":"Black American female culture commentator, energetic and conversational, New York-style media cadence without caricature, crisp punchy phrasing, confident personality, modern hip-hop reporter feel, professional but street-aware.",
"H05":"Black American female music journalist, relaxed low-mid register, confident cool delivery, intelligent and conversational, understated swagger, premium documentary tone, authentic hip-hop culture reporting cadence.",
"H06":"Black American female hip-hop reporter, strong medium register, urgent but controlled delivery, natural urban conversational rhythm, sharp hooks, emotionally engaged, newsroom polish with cultural credibility, never robotic.",
"H07":"Black American female culture journalist, slightly husky voice, confident and witty, modern social-documentary cadence, smooth rhythm, grounded authenticity, strong presence without overselling the line.",
"H08":"Black American female veteran hip-hop correspondent, deep warm register, authoritative yet conversational, measured pacing, rich tone, seasoned music-journalist energy, cinematic documentary delivery with subtle urban edge."
}

def run(cmd): subprocess.run(cmd,check=True)

if not MODEL.joinpath("config.json").exists():
    MODEL.mkdir(parents=True,exist_ok=True)
    snapshot_download(repo_id="Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign",local_dir=str(MODEL))

if OUT.exists(): shutil.rmtree(OUT)
OUT.mkdir(parents=True,exist_ok=True)

tts=Qwen3TTSModel.from_pretrained(str(MODEL),device_map="cuda:0",dtype=torch.bfloat16)
manifest={"sample_text":TEXT,"voices":{}}

for label,instruct in VOICES.items():
    print(f"GENERATING={label}",flush=True)
    wavs,sr=tts.generate_voice_design(text=TEXT,language="English",instruct=instruct,max_new_tokens=2048)
    raw=OUT/f"{label}_raw.wav"; wav=OUT/f"{label}.wav"; mp3=OUT/f"{label}.mp3"
    sf.write(raw,wavs[0],sr)
    run(["ffmpeg","-y","-loglevel","error","-i",str(raw),"-af","highpass=f=65,acompressor=threshold=-18dB:ratio=2.2:attack=12:release=100,loudnorm=I=-16:TP=-1.5:LRA=8,alimiter=limit=0.95","-ar","48000","-ac","1","-c:a","pcm_s16le",str(wav)])
    run(["ffmpeg","-y","-loglevel","error","-i",str(wav),"-b:a","192k",str(mp3)])
    dur=float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","default=nw=1:nk=1",str(wav)],text=True).strip())
    manifest["voices"][label]={"instruction":instruct,"duration_seconds":round(dur,2),"wav":wav.name,"mp3":mp3.name}
    raw.unlink(missing_ok=True); gc.collect(); torch.cuda.empty_cache()

sil=OUT/"silence.wav"
run(["ffmpeg","-y","-loglevel","error","-f","lavfi","-i","anullsrc=r=48000:cl=mono","-t","0.75","-c:a","pcm_s16le",str(sil)])
concat=OUT/"concat.txt"; lines=[]; labels=list(VOICES)
for i,label in enumerate(labels):
    lines.append(f"file '{OUT/(label+'.wav')}'")
    if i!=len(labels)-1: lines.append(f"file '{sil}'")
concat.write_text("\n".join(lines)+"\n")
reel=OUT/"CTNETWORK_HHWI_H01-H08_Audition_Reel.mp3"
run(["ffmpeg","-y","-loglevel","error","-f","concat","-safe","0","-i",str(concat),"-b:a","192k",str(reel)])
sil.unlink(missing_ok=True); concat.unlink(missing_ok=True)
OUT.joinpath("manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")

if PACKAGE.exists(): PACKAGE.unlink()
with tarfile.open(PACKAGE,"w:gz") as tf: tf.add(OUT,arcname="hhwi-urban-reporter-8")
print(f"AUDITION_PACKAGE_READY={PACKAGE}",flush=True)
