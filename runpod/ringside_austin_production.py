#!/usr/bin/env python3
import argparse, json, os, pathlib, subprocess, sys, time, glob
from concurrent.futures import ThreadPoolExecutor, as_completed
import requests

def run(args, check=True):
    args=[str(x) for x in args]
    print("+", " ".join(args), flush=True)
    return subprocess.run(args, check=check)

def duration(path):
    out=subprocess.check_output([
        "ffprobe","-v","error","-show_entries","format=duration",
        "-of","default=nw=1:nk=1",str(path)
    ], text=True).strip()
    return float(out)

def download(url, dest):
    dest=pathlib.Path(dest)
    if dest.exists() and dest.stat().st_size > 4096:
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    with requests.get(url, stream=True, timeout=240) as r:
        r.raise_for_status()
        with open(dest,"wb") as f:
            for chunk in r.iter_content(1024*1024):
                if chunk:
                    f.write(chunk)
    if dest.stat().st_size < 4096:
        raise RuntimeError(f"download too small: {dest}")
    return dest

def find_audio(root, needles, exts=(".mp3",".wav",".m4a",".aac",".flac")):
    root=pathlib.Path(root)
    for base in [
        root/"music", root/"assets", root/"sfx", root/"episodes", root
    ]:
        if not base.exists():
            continue
        try:
            for p in base.rglob("*"):
                if not p.is_file() or p.suffix.lower() not in exts:
                    continue
                name=p.name.lower()
                if any(n in name for n in needles):
                    return p
        except Exception:
            pass
    return None

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--command", required=True)
    args=ap.parse_args()
    cmd=json.load(open(args.command))

    ROOT=pathlib.Path("/workspace/ctnetwork-local/episodes/ringside_austin_neck")
    assets=ROOT/"assets"; motion=ROOT/"motion"; stills=ROOT/"stills"; clips=ROOT/"clips"; final=ROOT/"final"
    for p in (assets,motion,stills,clips,final):
        p.mkdir(parents=True, exist_ok=True)

    storyboard=download(cmd["storyboard_url"], assets/"storyboard.png")
    helper=pathlib.Path("/workspace/ctnetwork-local/controller/ctnetwork_higgsfield_video.py")
    if not helper.exists():
        raise RuntimeError("Higgsfield helper missing")

    # ---------- 8 motion shots ----------
    def make_motion(sc):
        scene=int(sc["scene"])
        out=motion/f"motion_{scene:02d}.mp4"
        src=motion/f"source_{scene:02d}.png"
        try:
            call=[
                sys.executable, str(helper),
                "--image", sc["image_url"],
                "--prompt", sc["prompt"],
                "--negative-prompt", sc.get("negative_prompt",""),
                "--model", sc.get("model","kling-video/v2.5-turbo/standard/image-to-video"),
                "--duration", str(int(sc.get("duration",5))),
                "--cfg-scale", str(float(sc.get("cfg_scale",0.5))),
                "--output", str(out)
            ]
            run(call)
            if not out.exists() or out.stat().st_size < 100000:
                raise RuntimeError("motion output missing")
            return scene, out, "kling"
        except Exception as exc:
            print(f"MOTION_FALLBACK scene={scene}: {exc}", flush=True)
            download(sc["image_url"], src)
            frames=int(sc.get("duration",5))*30
            vf=(
                "scale=1920:1080:force_original_aspect_ratio=increase,"
                "crop=1920:1080,"
                f"zoompan=z='min(zoom+0.00045,1.06)':"
                f"x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d={frames}:s=1920x1080:fps=30,"
                "format=yuv420p"
            )
            run(["ffmpeg","-y","-loop","1","-i",src,"-t",str(sc.get("duration",5)),
                 "-vf",vf,"-an","-c:v","libx264","-preset","fast","-crf","18",
                 "-movflags","+faststart",out])
            return scene, out, "fallback"

    motion_map={}
    with ThreadPoolExecutor(max_workers=4) as ex:
        futs=[ex.submit(make_motion,sc) for sc in cmd["motions"]]
        for fut in as_completed(futs):
            scene,path,mode=fut.result()
            print(f"MOTION_READY scene={scene} mode={mode} path={path}", flush=True)
            motion_map[scene]=path

    # normalize all motion clips
    for scene,p in list(motion_map.items()):
        norm=clips/f"motion_{scene:02d}.mp4"
        run(["ffmpeg","-y","-i",p,"-an",
             "-vf","scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,fps=30,format=yuv420p",
             "-c:v","libx264","-preset","fast","-crf","18","-movflags","+faststart",norm])
        motion_map[scene]=norm

    # ---------- F06 narration ----------
    narration_text=cmd["narration_text"].strip()
    (assets/"narration.txt").write_text(narration_text+"\n")
    ref=pathlib.Path(cmd.get("narrator_reference_path","/workspace/ctnetwork-local/narrator-auditions/female-urban-10/F06.wav"))
    if not ref.exists():
        raise RuntimeError(f"F06 reference missing: {ref}")
    ref_text=cmd.get("narrator_reference_text","This is C T Network. The real story starts where the headline ends. Stay with me.")
    (assets/"ref_text.txt").write_text(ref_text+"\n")

    qpy=pathlib.Path("/workspace/ctnetwork-local/envs/qwen3-tts/bin/python")
    model_path=pathlib.Path("/workspace/ctnetwork-local/models/qwen3-tts/1.7B-Base")
    if not qpy.exists():
        raise RuntimeError("Qwen TTS environment missing")
    nar=assets/"f06_narration.wav"
    narrate=assets/"make_f06.py"
    narrate.write_text(r'''
import pathlib, numpy as np, soundfile as sf, torch
from qwen_tts import Qwen3TTSModel
root=pathlib.Path("/workspace/ctnetwork-local/episodes/ringside_austin_neck/assets")
text=(root/"narration.txt").read_text().strip()
ref_text=(root/"ref_text.txt").read_text().strip()
paras=[p.strip() for p in text.split("\n\n") if p.strip()]
model=Qwen3TTSModel.from_pretrained(
    "/workspace/ctnetwork-local/models/qwen3-tts/1.7B-Base",
    device_map="cuda:0", dtype=torch.bfloat16
)
parts=[]; sr=None
for i,p in enumerate(paras,1):
    print(f"NARRATION {i}/{len(paras)} chars={len(p)}", flush=True)
    wavs,this_sr=model.generate_voice_clone(
        text=p, language="English",
        ref_audio="/workspace/ctnetwork-local/narrator-auditions/female-urban-10/F06.wav",
        ref_text=ref_text
    )
    x=np.asarray(wavs[0],dtype=np.float32).squeeze()
    if sr is None: sr=this_sr
    if sr != this_sr: raise RuntimeError("sample rate changed")
    parts.append(x)
    parts.append(np.zeros(int(sr*0.25),dtype=np.float32))
out=np.concatenate(parts[:-1]) if len(parts)>1 else parts[0]
sf.write(str(root/"f06_narration.wav"),out,sr)
print("NARRATION_READY",len(out)/sr,sr,flush=True)
''')
    run([qpy,narrate])
    narr_dur=duration(nar)
    print("NARRATION_DURATION",narr_dur,flush=True)

    # ---------- 12 storyboard stills ----------
    x_starts=[3,304,620,932,1242]
    y_starts=[64,292,520,748]
    still_scenes=[3,4,6,7,9,10,12,13,14,16,17,18]
    for scene in still_scenes:
        row=(scene-1)//5
        col=(scene-1)%5
        x=x_starts[col]; y=y_starts[row]
        out=stills/f"scene_{scene:02d}.png"
        run(["ffmpeg","-y","-i",storyboard,
             "-vf",f"crop=289:175:{x}:{y},scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080",
             "-frames:v","1",out])

    motion_total=sum(duration(p) for p in motion_map.values())
    still_seconds=max(8.0,(narr_dur-motion_total)/len(still_scenes))
    print("TIMING",json.dumps({"narration":narr_dur,"motion_total":motion_total,"still_seconds":still_seconds}),flush=True)

    still_map={}
    motions=[
        "zoompan=z='min(zoom+0.00028,1.055)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'",
        "zoompan=z='min(zoom+0.00025,1.05)':x='(iw-iw/zoom)*on/(d-1)':y='ih/2-(ih/zoom/2)'",
        "zoompan=z='min(zoom+0.00025,1.05)':x='(iw-iw/zoom)*(1-on/(d-1))':y='ih/2-(ih/zoom/2)'"
    ]
    for idx,scene in enumerate(still_scenes):
        src=stills/f"scene_{scene:02d}.png"; out=clips/f"still_{scene:02d}.mp4"
        frames=max(1,int(round(still_seconds*30)))
        vf=f"{motions[idx%len(motions)]}:d={frames}:s=1920x1080:fps=30,eq=contrast=1.04:saturation=0.96,format=yuv420p"
        run(["ffmpeg","-y","-loop","1","-i",src,"-t",f"{still_seconds:.3f}",
             "-vf",vf,"-an","-c:v","libx264","-preset","fast","-crf","18","-movflags","+faststart",out])
        still_map[scene]=out

    sequence=[]
    for scene in range(1,21):
        if scene in motion_map: sequence.append(motion_map[scene])
        elif scene in still_map: sequence.append(still_map[scene])
        else: raise RuntimeError(f"scene {scene} missing")
    concat=clips/"sequence.txt"
    concat.write_text("".join("file '%s'\n"%str(p).replace("'","'\\''") for p in sequence))
    visual=final/"visual_master.mp4"
    run(["ffmpeg","-y","-f","concat","-safe","0","-i",concat,"-c","copy",visual])

    # ---------- audio bed / crowd / bell ----------
    audio_root="/workspace/ctnetwork-local"
    music=find_audio(audio_root,["ringside","wrestl","arena","rock_bed","rock-bed"])
    crowd=find_audio(audio_root,["crowd","arena_crowd","audience"])
    bell=find_audio(audio_root,["ring_bell","ringbell","bell"])
    if bell is None:
        bell=assets/"synthetic_ring_bell.wav"
        run(["ffmpeg","-y",
             "-f","lavfi","-i","sine=frequency=880:duration=0.55",
             "-f","lavfi","-i","sine=frequency=1760:duration=0.42",
             "-filter_complex","[0:a]volume=0.55[a0];[1:a]volume=0.25[a1];[a0][a1]amix=inputs=2,highpass=f=500,aecho=0.8:0.6:45:0.35",
             bell])
    print("AUDIO_ASSETS",json.dumps({
        "music":str(music) if music else None,
        "crowd":str(crowd) if crowd else None,
        "bell":str(bell) if bell else None
    }),flush=True)

    master=final/"Ringside_Rewrite_What_If_Stone_Cold_Never_Broke_His_Neck.mp4"
    ff=["ffmpeg","-y","-i",visual,"-i",nar]
    filters=["[1:a]aresample=48000,volume=1.0[voice]"]
    mixlabels=["[voice]"]
    input_index=2
    if music:
        ff += ["-stream_loop","-1","-i",music]
        filters.append(f"[{input_index}:a]aresample=48000,volume=0.10[bed]")
        mixlabels.append("[bed]"); input_index+=1
    if crowd:
        ff += ["-stream_loop","-1","-i",crowd]
        filters.append(f"[{input_index}:a]aresample=48000,volume=0.045[crowd]")
        mixlabels.append("[crowd]"); input_index+=1
    if bell:
        ff += ["-i",bell]
        filters.append(f"[{input_index}:a]aresample=48000,adelay=300|300,volume=0.20[bell]")
        mixlabels.append("[bell]"); input_index+=1
    filters.append("".join(mixlabels)+f"amix=inputs={len(mixlabels)}:duration=first:dropout_transition=2,loudnorm=I=-16:TP=-1.5:LRA=11[a]")
    ff += ["-filter_complex",";".join(filters),"-map","0:v:0","-map","[a]",
           "-t",f"{narr_dur:.3f}","-c:v","libx264","-preset","medium","-crf","18",
           "-pix_fmt","yuv420p","-c:a","aac","-b:a","192k","-ar","48000",
           "-movflags","+faststart",master]
    run(ff)

    probe=json.loads(subprocess.check_output([
        "ffprobe","-v","error","-show_streams","-show_format","-of","json",master
    ],text=True))
    vids=[s for s in probe["streams"] if s.get("codec_type")=="video"]
    auds=[s for s in probe["streams"] if s.get("codec_type")=="audio"]
    qc={
        "path":str(master),
        "bytes":master.stat().st_size,
        "duration":float(probe["format"].get("duration",0)),
        "video_streams":len(vids),
        "audio_streams":len(auds),
        "width":int(vids[0].get("width",0)) if vids else 0,
        "height":int(vids[0].get("height",0)) if vids else 0,
        "scene_count":20,
        "animated_scene_count":8,
        "support_scene_count":12,
        "narrator":"F06",
        "server_assembled":True,
        "burned_captions":False
    }
    qc["pass"]=(
        qc["duration"]>150 and qc["video_streams"]==1 and qc["audio_streams"]==1
        and qc["width"]==1920 and qc["height"]==1080 and qc["bytes"]>5000000
    )
    (final/"qc.json").write_text(json.dumps(qc,indent=2)+"\n")
    print("QC_RESULT",json.dumps(qc),flush=True)
    if not qc["pass"]:
        raise RuntimeError("QC failed")
    print("FINAL_READY",master,flush=True)

if __name__=="__main__":
    main()
