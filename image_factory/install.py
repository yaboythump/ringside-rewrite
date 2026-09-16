#!/usr/bin/env python3
"""Additive CTNETWORK image studio installer. Never upgrades production packages."""
import hashlib,json,os,pathlib,subprocess,sys,time,urllib.request
ROOT=pathlib.Path('/workspace/ctnetwork-local/image-factory')
COMFY=pathlib.Path('/workspace/ComfyUI')
def run(args,**kw):
 print('RUN', ' '.join(map(str,args)),flush=True); return subprocess.run(list(map(str,args)),check=True,**kw)
def main():
 ROOT.mkdir(parents=True,exist_ok=True)
 for d in ['models/checkpoints','models/diffusion_models','models/text_encoders','models/vae','models/upscale_models','models/rembg','workflows','presets','input','output','logs','status','brand']:(ROOT/d).mkdir(parents=True,exist_ok=True)
 assert (COMFY/'main.py').exists(),'Audited ComfyUI is missing; refusing blind reinstall'
 # Leave the existing production virtualenv untouched.
 env=ROOT/'venv'; py=env/'bin/python'
 if not py.exists():run([sys.executable,'-m','venv','--system-site-packages',env])
 # Explicit constraints keep the functioning CUDA stack in place.
 torchver=subprocess.check_output([sys.executable,'-c','import torch;print(torch.__version__)'],text=True).strip()
 constraint=ROOT/'constraints.txt';constraint.write_text('torch=='+torchver+'\n')
 run([py,'-m','pip','install','--disable-pip-version-check','-c',constraint,'-r',COMFY/'requirements.txt','rembg[cpu]','requests','Pillow'],timeout=1200)
 models=[
 ('diffusion_models/flux-2-klein-4b.safetensors','https://huggingface.co/Comfy-Org/flux2-klein/resolve/main/split_files/diffusion_models/flux-2-klein-4b.safetensors'),
 ('text_encoders/qwen_3_4b.safetensors','https://huggingface.co/Comfy-Org/flux2-klein/resolve/main/split_files/text_encoders/qwen_3_4b.safetensors'),
 ('vae/flux2-vae.safetensors','https://huggingface.co/Comfy-Org/flux2-klein/resolve/main/split_files/vae/flux2-vae.safetensors'),
 ('checkpoints/sd_xl_base_1.0.safetensors','https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors'),
 ('upscale_models/RealESRGAN_x4plus.pth','https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth')]
 manifest=[]
 for rel,url in models:
  dest=ROOT/'models'/rel; old=COMFY/'models'/rel
  if not dest.exists() and old.is_file() and old.stat().st_size>1000000:dest.symlink_to(old)
  if not dest.exists():
   partial=dest.with_suffix(dest.suffix+'.part')
   run(['curl','--fail','--location','--retry','4','--retry-delay','3','--connect-timeout','30','--max-time','1500','--continue-at','-','--output',partial,url],timeout=1560)
   assert partial.stat().st_size>1000000, 'Invalid model download'
   if dest.suffix=='.safetensors':
    with partial.open('rb') as f:
     size=int.from_bytes(f.read(8),'little');assert 0<size<100_000_000;header=json.loads(f.read(size));assert len(header)>1
   partial.rename(dest)
  manifest.append({'file':rel,'bytes':dest.stat().st_size,'source':url})
  print('MODEL_READY',rel,dest.stat().st_size,flush=True)
 # Load extra model directories for this service only; no production config mutation.
 (ROOT/'model_paths.yaml').write_text('ctnetwork_images:\n  base_path: '+str(ROOT/'models')+'\n'+''.join('  '+x+': '+x+'\n' for x in ['checkpoints','diffusion_models','text_encoders','vae','upscale_models']))
 os.environ['U2NET_HOME']=str(ROOT/'models/rembg')
 run([py,'-c',"from rembg import new_session;new_session('u2net');print('REMBG_MODEL_READY')"],env=os.environ.copy(),timeout=900)
 manifest.append({'file':'rembg/u2net.onnx','source':'https://github.com/danielgatis/rembg','purpose':'local background removal'})
 (ROOT/'status/models.json').write_text(json.dumps(manifest,indent=2))
 print('IMAGE_INSTALL_COMPLETE',flush=True)
if __name__=='__main__':main()
