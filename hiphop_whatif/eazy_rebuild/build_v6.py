"""Single source-to-release renderer. No prior MP4 or generated-media credits."""
from __future__ import annotations
import json
import math
import shutil
import subprocess
import tempfile
from pathlib import Path
from PIL import Image
import build_v3 as audio_tools
import upgrade_v5 as visuals
from qc import EXPECTED_DURATION, SHORT_STARTS, checked, probe, validate_media, package

ROOT = Path(__file__).resolve().parent
OUT = ROOT/'output'
# Keep the established 24-scene timing; replace every generic silhouette scene.
PLAN = dict(visuals.PLAN)
PLAN.update({
    1:('compton',.25,'THE REAL STORY'), 3:('nwa',.30,'RUTHLESS RECORDS'),
    5:('eazy_sketch',.50,'1995'), 7:('compton',.75,'AN ALTERNATE TIMELINE'),
    9:('bone',.65,'RUTHLESS • WHAT COMES NEXT?'), 11:('yella',.50,'N.W.A.'),
    13:('ren',.50,'UNFINISHED BUSINESS'), 15:('dre',.50,'THE WEST COAST RIPPLE'),
    17:('nwa',.20,'A DIFFERENT BALANCE'), 19:('compton',.20,'LEGACY • BUSINESS • TIME'),
    21:('bone',.70,'A DIFFERENT FUTURE'), 23:('eazy_sketch',.50,'ONE LIFE. A DIFFERENT WEST COAST.')
})

def ff(*args):
    return checked(['ffmpeg','-y','-v','error','-xerror',*map(str,args)])

def main():
    OUT.mkdir(exist_ok=True)
    # Scratch renders cannot accidentally pick up old/truncated scene files.
    with tempfile.TemporaryDirectory(prefix='eazy-v6-',dir=ROOT) as temp:
        work = Path(temp)
        visuals.download()
        job = json.loads((ROOT/'job.json').read_text())
        assert job['profile'] == 'HipHopWhatIf'
        assert len(job['audio_urls']) == 8
        audio_files = []
        for i,url in enumerate(job['audio_urls']):
            raw = audio_tools.AUDIO/f'r{i}.wav'
            if not raw.exists():
                raw.write_bytes(audio_tools.get(url,4096))
            normal = work/f'a{i}.wav'
            ff('-i',raw,'-ar',48000,'-ac',2,'-c:a','pcm_s16le',normal)
            audio_files.append(normal)
        listing = work/'audio.txt'
        listing.write_text(''.join(f"file '{p.name}'\n" for p in audio_files))
        narration = work/'narration.wav'
        ff('-f','concat','-safe',0,'-i',listing,'-c:a','pcm_s16le',narration)
        total = float(probe(narration)['format']['duration'])
        assert abs(total-EXPECTED_DURATION) < .05, f'Locked narration changed: {total}'
        # Preserve the existing locally synthesized music and relative mix.
        audio_tools.OUT = work
        audio_tools.music(total+2)
        mixed = work/'mix.wav'
        ff('-i',narration,'-i',work/'music.wav','-filter_complex',
           '[0:a]volume=1[a];[1:a]volume=0.16[b];[a][b]amix=inputs=2:duration=first,alimiter=limit=0.94[out]',
           '-map','[out]','-c:a','pcm_s16le',mixed)
        measured = subprocess.run(['ffmpeg','-v','info','-i',str(mixed),'-af',
            'loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json','-f','null','-'],
            capture_output=True,text=True,check=True)
        levels = json.loads(measured.stderr[measured.stderr.rfind('{'):])
        normalization = ('loudnorm=I=-16:TP=-1.5:LRA=11:linear=true:' +
            ':'.join(f'{key}={levels[value]}' for key,value in [
                ('measured_I','input_i'),('measured_TP','input_tp'),
                ('measured_LRA','input_lra'),('measured_thresh','input_thresh'),('offset','target_offset')]))
        rows=[]
        sheet=Image.new('RGB',(1920,1620))
        total_frames=round(total*30)
        for i in range(24):
            print(f'RENDER scene {i+1}/24',flush=True)
            key,bias,label=PLAN[i]
            frame=visuals.make_frame(i,key,bias,label)
            path=work/f'f{i:02d}.jpg'; frame.save(path,quality=94)
            sheet.paste(frame.resize((480,270)),((i%4)*480,(i//4)*270))
            count=round((i+1)*total_frames/24)-round(i*total_frames/24)
            segment=work/f's{i:02d}.mp4'
            vf=(f"scale=2200:1238,zoompan=z='1+0.048*on/{count}':"
                f"x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2':d={count}:s=1920x1080:fps=30,format=yuv420p")
            ff('-i',path,'-vf',vf,'-frames:v',count,'-an','-c:v','libx264',
               '-threads',2,'-preset','veryfast','-crf',20,segment)
            validate_media(segment,count/30,audio=False,frames=count)
            rows.append(f"file '{segment.name}'\n")
        listing=work/'visuals.txt'; listing.write_text(''.join(rows))
        master=work/'full.mp4'
        ff('-f','concat','-safe',0,'-i',listing,'-i',mixed,'-map','0:v:0','-map','1:a:0',
           '-af',normalization,'-c:v','copy','-c:a','aac','-b:a','192k','-ar',48000,
           '-t',total,'-movflags','+faststart',master)
        validate_media(master,total,frames=total_frames)
        for i,start in enumerate(SHORT_STARTS,1):
            print(f'RENDER short {i}/5',flush=True)
            # Preserve all subjects and title text instead of cropping off side portraits.
            layout=('[0:v]split=2[bg][fg];'
                    '[bg]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,'
                    'boxblur=30:2,eq=brightness=-0.18[back];'
                    '[fg]scale=1080:608[front];[back][front]overlay=0:(H-h)/2,setsar=1[v]')
            ff('-ss',start,'-i',master,'-t',55,'-filter_complex',layout,
               '-map','[v]','-map','0:a:0','-c:v','libx264','-threads',2,'-preset','veryfast',
               '-crf',20,'-c:a','aac','-b:a','192k','-ar',48000,'-movflags','+faststart',work/f'short_{i:02d}.mp4')
        visuals.OUT=work
        visuals.make_thumb()
        sheet.save(work/'internal_preview.jpg',quality=92)
        shutil.copyfile(ROOT/'visual-credits.md',work/'visual-credits.md')
        package(work)
        # Only promote a complete validated package; no PASS for partial renders.
        for name in ['full.mp4',*[f'short_{i:02d}.mp4' for i in range(1,6)],
                     'thumbnail.jpg','internal_preview.jpg','visual-credits.md','qc-report.json']:
            (work/name).replace(OUT/name)
    print('BUILD_V6_PASS',flush=True)

if __name__ == '__main__':
    main()
