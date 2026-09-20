#!/usr/bin/env python3
from __future__ import annotations

import base64
import json
import os
import pathlib
import re
import time

import requests
import websocket

REPO = pathlib.Path(__file__).resolve().parents[1]
CMD = json.loads((REPO / "hhwi-scott-la-rock-finish-command.json").read_text())
POD_ID = os.environ["POD_ID"]
PASSWORD = pathlib.Path(os.environ["JUPYTER_PASSWORD_FILE"]).read_text().strip()
BASE = f"https://{POD_ID}-8888.proxy.runpod.net"


def connect():
    s = requests.Session()
    last = None
    for _ in range(90):
        try:
            r = s.get(BASE + "/login", timeout=15)
            if r.status_code == 200:
                break
            last = f"login HTTP {r.status_code}"
        except Exception as exc:
            last = repr(exc)
        time.sleep(4)
    else:
        raise RuntimeError(f"Jupyter unavailable: {last}")
    m = re.search(r'name="_xsrf" value="([^"]+)"', r.text)
    if not m:
        raise RuntimeError("Jupyter XSRF token missing")
    rr = s.post(
        BASE + "/login",
        data={"_xsrf": m.group(1), "password": PASSWORD, "next": "/"},
        timeout=30,
        allow_redirects=False,
    )
    if rr.status_code not in (200, 302, 303):
        rr.raise_for_status()
    xs = s.cookies.get("_xsrf")
    headers = {"X-XSRFToken": xs} if xs else {}
    s.get(BASE + "/api/status", headers=headers, timeout=30).raise_for_status()
    t = s.post(BASE + "/api/terminals", headers=headers, json={}, timeout=30)
    t.raise_for_status()
    name = t.json()["name"]
    cookie = "; ".join(f"{c.name}={c.value}" for c in s.cookies)
    ws = websocket.create_connection(
        f"wss://{POD_ID}-8888.proxy.runpod.net/terminals/websocket/{name}",
        cookie=cookie,
        origin=BASE,
        timeout=60,
    )
    return s, headers, name, ws


def remote_source() -> str:
    command_b64 = base64.b64encode(json.dumps(CMD).encode()).decode()
    return r'''
import base64
import json
import os
import pathlib
import re
import shutil
import subprocess
import textwrap
import urllib.request

ROOT = pathlib.Path("/workspace/ctnetwork-local")
EP = ROOT / "episodes/hhwi_scott_la_rock"
AS = EP / "final_assets"
MOTION = EP / "motion"
FINAL = EP / "final"
for p in (AS, AS/"stills", AS/"clips", AS/"narration", AS/"sfx", FINAL):
    p.mkdir(parents=True, exist_ok=True)

cmd = json.loads(base64.b64decode("__COMMAND_B64__"))


def run(args):
    args = [str(x) for x in args]
    print("+", " ".join(args), flush=True)
    subprocess.run(args, check=True)


def download(url, dest):
    dest = pathlib.Path(dest)
    if dest.exists() and dest.stat().st_size > 4096:
        print("REUSE", dest, dest.stat().st_size, flush=True)
        return
    req = urllib.request.Request(url, headers={"User-Agent": "CTNETWORK-HHWI/1.0"})
    with urllib.request.urlopen(req, timeout=300) as r, open(dest, "wb") as f:
        while True:
            b = r.read(4 * 1024 * 1024)
            if not b:
                break
            f.write(b)
    if dest.stat().st_size < 4096:
        raise RuntimeError(f"download failed: {dest}")
    print("DOWNLOADED", dest, dest.stat().st_size, flush=True)


def duration(path):
    x = subprocess.check_output(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=nw=1:nk=1", str(path)],
        text=True,
    ).strip()
    return float(x)


# Inputs
for item in cmd["stills"]:
    download(item["url"], AS / "stills" / f"scene_{int(item['scene']):02d}.png")
download(cmd["music_url"], AS / "music.mp3")
for sfx in cmd.get("sfx", []):
    download(sfx["url"], AS / "sfx" / sfx["filename"])

ref = pathlib.Path(cmd["narrator_reference_path"])
if not ref.exists() or ref.stat().st_size < 4096:
    raise RuntimeError(f"F06 reference missing: {ref}")

# Narration: F06, model loaded once, chunked consistently.
paragraphs = [p.strip() for p in cmd["narration_text"].split("\n\n") if p.strip()]
chunks, buf = [], ""
for p in paragraphs:
    candidate = (buf + "\n\n" + p).strip() if buf else p
    if len(candidate) > 850 and buf:
        chunks.append(buf)
        buf = p
    else:
        buf = candidate
if buf:
    chunks.append(buf)
(AS/"narration"/"chunks.json").write_text(json.dumps(chunks, indent=2))
(AS/"narration"/"reference.txt").write_text(cmd["narrator_reference_text"].strip() + "\n")

narrator_py = AS / "narration" / "make_f06.py"
narrator_py.write_text(textwrap.dedent("""
    import json, pathlib, numpy as np, soundfile as sf, torch
    from qwen_tts import Qwen3TTSModel

    root=pathlib.Path('/workspace/ctnetwork-local/episodes/hhwi_scott_la_rock/final_assets/narration')
    chunks=json.loads((root/'chunks.json').read_text())
    ref_text=(root/'reference.txt').read_text().strip()
    ref_audio='/workspace/ctnetwork-local/narrator-auditions/female-urban-10/F06.wav'
    model=Qwen3TTSModel.from_pretrained(
        '/workspace/ctnetwork-local/models/qwen3-tts/1.7B-Base',
        device_map='cuda:0',
        dtype=torch.bfloat16,
    )
    pieces=[]; sr=None
    for i,text in enumerate(chunks,1):
        print(f'F06_CHUNK {i}/{len(chunks)} chars={len(text)}', flush=True)
        wavs,this_sr=model.generate_voice_clone(
            text=text,
            language='English',
            ref_audio=ref_audio,
            ref_text=ref_text,
        )
        x=np.asarray(wavs[0],dtype=np.float32).squeeze()
        sr=this_sr if sr is None else sr
        if this_sr != sr:
            raise RuntimeError('sample rate changed')
        pieces.append(x)
        pieces.append(np.zeros(int(sr*0.28),dtype=np.float32))
    out=np.concatenate(pieces[:-1])
    sf.write(str(root/'F06_full.wav'), out, sr)
    print('F06_READY', len(out)/sr, sr, flush=True)
"""))
qpy = ROOT / "envs/qwen3-tts/bin/python"
if not qpy.exists():
    raise RuntimeError("Qwen environment missing")
if (ROOT / "status/qwen_smoke.status").read_text().strip() != "PASS":
    raise RuntimeError("Qwen narrator engine not certified")
run([qpy, narrator_py])

narration = AS / "narration/F06_full.wav"
narr_dur = duration(narration)
print("NARRATION_DURATION", narr_dur, flush=True)

# Normalize 8 animated scenes. Existing outputs remain the approved key motion shots.
motion_names = [
    "hhwi_motion_01_bronx.mp4",
    "hhwi_motion_02_young_krs.mp4",
    "hhwi_motion_03_meeting.mp4",
    "hhwi_motion_04_studio.mp4",
    "hhwi_motion_05_performance.mp4",
    "hhwi_motion_06_survival.mp4",
    "hhwi_motion_07_unity.mp4",
    "hhwi_motion_08_legacy.mp4",
]
norm_motion = []
for i, name in enumerate(motion_names, 1):
    src = MOTION / name
    if not src.exists() or src.stat().st_size < 4096:
        raise RuntimeError(f"motion shot missing: {src}")
    out = AS / "clips" / f"motion_{i:02d}.mp4"
    run([
        "ffmpeg", "-y", "-i", src, "-an",
        "-vf", "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,fps=30,format=yuv420p",
        "-c:v", "libx264", "-preset", "fast", "-crf", "18", "-movflags", "+faststart", out,
    ])
    norm_motion.append(out)

motion_total = sum(duration(p) for p in norm_motion)
still_seconds = max(7.5, (narr_dur - motion_total) / 12.0)
print("TIMING", json.dumps({"narration": narr_dur, "motion_total": motion_total, "still_seconds": still_seconds}), flush=True)

# 12 premium still-motion clips.
moves = [
    "zoompan=z='min(zoom+0.00035,1.075)':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)'",
    "zoompan=z='min(zoom+0.00030,1.065)':x='0':y='ih/2-(ih/zoom/2)'",
    "zoompan=z='min(zoom+0.00030,1.065)':x='iw-(iw/zoom)':y='ih/2-(ih/zoom/2)'",
    "zoompan=z='min(zoom+0.00028,1.055)':x='iw/2-(iw/zoom/2)':y='0'",
]
still_clips = {}
for n, item in enumerate(cmd["stills"]):
    scene = int(item["scene"])
    src = AS / "stills" / f"scene_{scene:02d}.png"
    out = AS / "clips" / f"still_{scene:02d}.mp4"
    frames = max(1, int(round(still_seconds * 30)))
    vf = (
        "scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,"
        + moves[n % len(moves)]
        + f":d={frames}:s=1920x1080:fps=30,"
        + "eq=contrast=1.03:saturation=0.94,format=yuv420p"
    )
    run([
        "ffmpeg", "-y", "-loop", "1", "-i", src, "-t", f"{still_seconds:.3f}",
        "-vf", vf, "-an", "-c:v", "libx264", "-preset", "fast", "-crf", "18",
        "-movflags", "+faststart", out,
    ])
    still_clips[scene] = out

sequence = [
    norm_motion[0], norm_motion[1], norm_motion[2], norm_motion[3],
    still_clips[9], norm_motion[4], still_clips[10], still_clips[11],
    still_clips[12], still_clips[13], norm_motion[5], still_clips[14],
    norm_motion[6], still_clips[15], still_clips[16], still_clips[17],
    still_clips[18], still_clips[19], still_clips[20], norm_motion[7],
]
concat = AS / "clips/sequence.txt"
concat.write_text("".join(f"file '{p}'\n" for p in sequence))
visual = AS / "visual_master.mp4"
run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", concat, "-c", "copy", visual])

# Music + subtle SFX under F06.
inputs = ["-i", str(visual), "-i", str(narration), "-stream_loop", "-1", "-i", str(AS/"music.mp3")]
sfx_files = []
for sfx in cmd.get("sfx", []):
    p = AS / "sfx" / sfx["filename"]
    sfx_files.append((p, int(sfx["delay_ms"]), float(sfx.get("volume", 0.18))))
    inputs += ["-i", str(p)]

filters = [
    "[1:a]aresample=48000,volume=1.0[voice]",
    "[2:a]aresample=48000,volume=0.10[bed]",
]
mix_labels = ["[bed]"]
for j, (_, delay, volume) in enumerate(sfx_files, start=3):
    label = f"sfx{j}"
    filters.append(f"[{j}:a]aresample=48000,volume={volume},adelay={delay}|{delay}[{label}]")
    mix_labels.append(f"[{label}]")
if len(mix_labels) > 1:
    filters.append("".join(mix_labels) + f"amix=inputs={len(mix_labels)}:duration=longest:normalize=0[fx]")
else:
    filters.append("[bed]anull[fx]")
filters.append("[voice][fx]amix=inputs=2:duration=first:dropout_transition=2,loudnorm=I=-16:TP=-1.5:LRA=9[aout]")

master = FINAL / "HHWI_What_If_Scott_La_Rock_Never_Died.mp4"
run([
    "ffmpeg", "-y", *inputs,
    "-filter_complex", ";".join(filters),
    "-map", "0:v:0", "-map", "[aout]",
    "-t", f"{narr_dur:.3f}",
    "-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p",
    "-c:a", "aac", "-b:a", "192k", "-ar", "48000",
    "-movflags", "+faststart", master,
])

probe = json.loads(subprocess.check_output([
    "ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", master
], text=True))
v = [s for s in probe.get("streams", []) if s.get("codec_type") == "video"]
a = [s for s in probe.get("streams", []) if s.get("codec_type") == "audio"]
dur = float(probe.get("format", {}).get("duration") or 0)
size = master.stat().st_size
black = subprocess.run(
    ["ffmpeg", "-hide_banner", "-i", str(master), "-vf", "blackdetect=d=1:pix_th=0.10", "-an", "-f", "null", "-"],
    text=True, capture_output=True,
).stderr
black_total = sum(float(x) for x in re.findall(r"black_duration:([0-9.]+)", black))
qc = {
    "file": str(master),
    "narrator": "F06",
    "duration": dur,
    "bytes": size,
    "video_streams": len(v),
    "audio_streams": len(a),
    "width": int(v[0].get("width") or 0) if v else 0,
    "height": int(v[0].get("height") or 0) if v else 0,
    "scene_count": 20,
    "animated_scene_count": 8,
    "support_scene_count": 12,
    "burned_captions": False,
    "black_ratio": black_total / dur if dur else 1.0,
}
qc["pass"] = bool(
    v and a and dur > 120 and size > 5_000_000
    and qc["width"] == 1920 and qc["height"] == 1080
    and qc["black_ratio"] < 0.05
)
(FINAL/"qc.json").write_text(json.dumps(qc, indent=2) + "\n")
print("FINAL_QC", json.dumps(qc), flush=True)
if not qc["pass"]:
    raise SystemExit(91)
print("FINAL_READY", master, size, flush=True)
'''.replace("__COMMAND_B64__", command_b64)


def execute():
    s, headers, term, ws = connect()
    source = remote_source()
    enc = base64.b64encode(source.encode()).decode()
    marker = "__HHWI_SCOTT_F06_DONE__"
    ws.send(json.dumps([
        "stdin",
        f"echo {enc} | base64 -d >/tmp/hhwi_scott_f06_final.py; python3 /tmp/hhwi_scott_f06_final.py; rc=$?; echo {marker}:$rc\n",
    ]))
    output = ""
    rc = None
    deadline = time.time() + 6900
    try:
        while time.time() < deadline:
            try:
                msg = ws.recv()
            except Exception as exc:
                print("websocket", repr(exc), flush=True)
                continue
            try:
                data = json.loads(msg)
            except Exception:
                continue
            if isinstance(data, list) and len(data) >= 2 and data[0] == "stdout":
                txt = data[1]
                output += txt
                sys.stdout.write(txt)
                sys.stdout.flush()
                mm = re.search(re.escape(marker) + r":(\d+)", output)
                if mm:
                    rc = int(mm.group(1))
                    break
    finally:
        ws.close()
        try:
            s.delete(BASE + f"/api/terminals/{term}", headers=headers, timeout=10)
        except Exception:
            pass
    if rc is None:
        raise RuntimeError("final render timed out")
    if rc != 0:
        raise RuntimeError(f"final render failed rc={rc}")

    outdir = REPO / "deliverables"
    outdir.mkdir(exist_ok=True)
    targets = [
        (
            "HHWI_What_If_Scott_La_Rock_Never_Died.mp4",
            "ctnetwork-local/episodes/hhwi_scott_la_rock/final/HHWI_What_If_Scott_La_Rock_Never_Died.mp4",
        ),
        ("qc.json", "ctnetwork-local/episodes/hhwi_scott_la_rock/final/qc.json"),
    ]
    for local, rel in targets:
        dest = outdir / local
        ok = False
        for candidate in (f"/files/workspace/{rel}", f"/files/{rel}"):
            resp = s.get(BASE + candidate, headers=headers, stream=True, timeout=900)
            if resp.status_code == 200:
                with open(dest, "wb") as f:
                    for chunk in resp.iter_content(4 * 1024 * 1024):
                        if chunk:
                            f.write(chunk)
                if dest.stat().st_size > 100:
                    print("DOWNLOADED", dest, dest.stat().st_size, candidate, flush=True)
                    ok = True
                    break
        if not ok:
            raise RuntimeError(f"could not download {rel}")


if __name__ == "__main__":
    import sys
    execute()
