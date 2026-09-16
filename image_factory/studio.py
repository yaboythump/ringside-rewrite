#!/usr/bin/env python3
"""CTNETWORK local-only image workflows. No paid APIs or publishing routes."""
from pathlib import Path
import argparse,hashlib,json,os,re,shutil,time,uuid
import requests
from PIL import Image,ImageDraw,ImageFont,ImageOps,ImageStat
ROOT=Path(os.getenv('CTN_IMAGE_ROOT','/workspace/ctnetwork-local/image-factory'))
API=os.getenv('CTN_IMAGE_API','http://127.0.0.1:8191')
PRESETS={
 'hip_hop_what_if':{'name':'HIP HOP WHAT IF','accent':'#E7B64C','secondary':'#BD242F','style':'epic cinematic hip hop documentary poster, black and deep charcoal, metallic gold and red accents, dramatic depth, photographic archival atmosphere, emotional visual conflict','prompt':'A vintage gold studio microphone at right foreground, an empty record studio and a rain-soaked New York skyline behind it, an alternate history where a legendary hip hop group never formed. Dramatic gold rim light, deep crimson shadows, premium movie key art, left third dark empty space for headline. No text, no logos.','hook':'ONE MEETING.\nEVERYTHING CHANGED.'},
 'ringside_rewrite':{'name':'RINGSIDE REWRITE','accent':'#D6B36C','secondary':'#AE2738','style':'premium wrestling documentary poster, black, charcoal, championship gold, steel silver, crimson accent, dramatic fight-night lighting','prompt':'An empty professional wrestling ring at center right, a gleaming unbranded championship belt lying in foreground, one crimson spotlight cutting through smoky darkness, roaring arena implied in distant bokeh, cinematic sports documentary composition. Left third dark negative space. No text, no official logos.','hook':'ONE BETRAYAL.\nA NEW TIMELINE.'},
 'whatever_happened_to':{'name':'WHATEVER HAPPENED TO...?','accent':'#D8AE53','secondary':'#95623B','style':'premium nostalgic archive documentary, warm amber light, black and gold, film grain, old photographs, analog technology, reflective mood','prompt':'A forgotten early 2000s silver desktop computer on an old wooden desk, CRT monitor glowing blue, a stack of unlabeled VHS tapes and dusty photographs, warm gold desk lamp, dark archival room, premium nostalgic documentary photography, evocative depth and shadows. No text, no people, no logos.','hook':'EVERYONE LOGGED IN.\nTHEN IT DISAPPEARED.'},
 'the_six_report':{'name':'THE SIX REPORT','accent':'#FF174F','secondary':'#BA1242','style':'black and neon crimson intelligence dossier, modern gaming-news visual identity, palm silhouettes, white italic type reserved for overlay, deep shadows','prompt':'A cinematic editorial illustration of a tropical coastal city at night, palm silhouettes, rain-wet boulevard, red neon skyline, dark unbranded sports car in lower foreground, black and crimson dossier atmosphere, space at top for news headline. Original editorial concept, not a game screenshot. No text, no logos.','hook':'THE CITY.\nTHE QUESTIONS.'}}
FORMATS={'youtube_thumbnail':(1280,720),'episode_key_art':(1920,1080),'facebook_social':(1080,1350),'shorts_reels_cover':(1080,1920),'promotional_poster':(2000,3000),'transparent_png':(1600,1600)}
def save_json(p,obj):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(obj,indent=2)+'\n')
def node(t,**i):return {'class_type':t,'inputs':i}
def flux(prompt,width=1280,height=720,seed=42,reference=None,prefix='raw'):
 w={'1':node('UNETLoader',unet_name='flux-2-klein-4b.safetensors',weight_dtype='default'),
 '2':node('CLIPLoader',clip_name='qwen_3_4b.safetensors',type='flux2',device='default'),
 '3':node('VAELoader',vae_name='flux2-vae.safetensors'),
 '4':node('CLIPTextEncode',text=prompt,clip=['2',0]),
 '5':node('ConditioningZeroOut',conditioning=['4',0]),
 '6':node('EmptyFlux2LatentImage',width=width,height=height,batch_size=1),
 '7':node('RandomNoise',noise_seed=seed),
 '8':node('KSamplerSelect',sampler_name='euler'),
 '9':node('Flux2Scheduler',steps=4,width=width,height=height),
 '10':node('CFGGuider',model=['1',0],positive=['4',0],negative=['5',0],cfg=1.0),
 '11':node('SamplerCustomAdvanced',noise=['7',0],guider=['10',0],sampler=['8',0],sigmas=['9',0],latent_image=['6',0]),
 '12':node('VAEDecode',samples=['11',0],vae=['3',0]),
 '13':node('SaveImage',images=['12',0],filename_prefix=prefix)}
 if reference:
  w['20']=node('LoadImage',image=reference)
  w['21']=node('VAEEncode',pixels=['20',0],vae=['3',0])
  w['22']=node('ReferenceLatent',conditioning=['4',0],latent=['21',0])
  w['23']=node('ReferenceLatent',conditioning=['5',0],latent=['21',0])
  w['10']['inputs'].update(positive=['22',0],negative=['23',0])
 return w

def sdxl(prompt,image,mask=None,denoise=.25,seed=42,prefix='detail'):
 w={'1':node('CheckpointLoaderSimple',ckpt_name='sd_xl_base_1.0.safetensors'),
 '2':node('CLIPTextEncode',clip=['1',1],text=prompt),
 '3':node('CLIPTextEncode',clip=['1',1],text='blurry, low quality, distorted, watermark, text'),
 '4':node('LoadImage',image=image),
 '5':node('VAEEncode',pixels=['4',0],vae=['1',2]),
 '6':node('KSampler',model=['1',0],positive=['2',0],negative=['3',0],latent_image=['5',0],seed=seed,steps=24,cfg=5.5,sampler_name='dpmpp_2m',scheduler='karras',denoise=denoise),
 '7':node('VAEDecode',samples=['6',0],vae=['1',2]),
 '8':node('SaveImage',images=['7',0],filename_prefix=prefix)}
 if mask:
  w['9']=node('LoadImageMask',image=mask,channel='red')
  w['5']=node('VAEEncodeForInpaint',pixels=['4',0],vae=['1',2],mask=['9',0],grow_mask_by=8)
  # Composite unchanged pixels back exactly after masked generation.
  w['10']=node('ImageCompositeMasked',destination=['4',0],source=['7',0],x=0,y=0,resize_source=False,mask=['9',0])
  w['8']['inputs']['images']=['10',0]
 return w

def upscale(image,prefix='upscaled'):
 return {'1':node('LoadImage',image=image),'2':node('UpscaleModelLoader',model_name='RealESRGAN_x4plus.pth'),'3':node('ImageUpscaleWithModel',upscale_model=['2',0],image=['1',0]),'4':node('SaveImage',images=['3',0],filename_prefix=prefix)}

def upload(path):
 with open(path,'rb') as f:r=requests.post(API+'/upload/image',files={'image':(Path(path).name,f,'image/png')},data={'overwrite':'false'},timeout=90)
 r.raise_for_status();d=r.json();return '/'.join(x for x in [d.get('subfolder'),d['name']] if x)
def execute(w,dest,timeout=900):
 info=requests.get(API+'/object_info',timeout=30).json()
 missing=set(n['class_type'] for n in w.values())-set(info);assert not missing, f'Missing nodes: {missing}'
 r=requests.post(API+'/prompt',json={'prompt':w,'client_id':'ctnetwork-image-factory'},timeout=45)
 if not r.ok:raise RuntimeError(r.text[:2500])
 pid=r.json()['prompt_id'];save_json(dest.with_suffix('.workflow.json'),w)
 print('IMAGE_JOB',pid,str(dest),flush=True);end=time.time()+timeout
 while time.time()<end:
  h=requests.get(API+'/history/'+pid,timeout=30).json().get(pid)
  if h:
   if h.get('status',{}).get('status_str')=='error':raise RuntimeError(json.dumps(h['status'])[-2500:])
   for n in h.get('outputs',{}).values():
    for im in n.get('images',[]):
     r=requests.get(API+'/view',params=im,timeout=120);r.raise_for_status();dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(r.content)
     with Image.open(dest) as p:p.verify()
     save_json(dest.with_suffix('.provenance.json'),{'prompt_id':pid,'workflow':dest.with_suffix('.workflow.json').name,'local_only':True,'paid_generation_credits':0})
     return dest
   raise RuntimeError('Completed prompt returned no image')
  time.sleep(3)
 raise TimeoutError('Image job deadline reached: '+pid)
def font(size):return ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf',size)
def package(image,out,show,kind,headline=None):
 preset=PRESETS[show];size=FORMATS[kind];img=ImageOps.fit(Image.open(image).convert('RGB'),size,method=Image.Resampling.LANCZOS)
 W,H=size;overlay=Image.new('RGBA',size);d=ImageDraw.Draw(overlay)
 # Safe inset for text; portrait cover keeps essential type away from platform controls.
 top=int(H*(.13 if kind=='shorts_reels_cover' else .06));margin=int(W*.065)
 for y in range(H):
  a=int(175*max(0,1-y/(H*.44))+205*max(0,(y-H*.5)/(H*.5)))
  d.line((0,y,W,y),fill=(0,0,0,min(a,235)))
 img=Image.alpha_composite(img.convert('RGBA'),overlay);d=ImageDraw.Draw(img)
 label=preset['name'];fs=int(W*.028)
 while d.textbbox((0,0),label,font=font(fs))[2]>W-2*margin:fs-=1
 d.text((margin,top),label,font=font(fs),fill='white',stroke_width=1)
 d.rectangle((margin,top+fs+14,margin+int(W*.19),top+fs+19),fill=preset['accent'])
 lines=(headline or preset['hook']).split('\n');fs=int(W*(.069 if H<W else .085))
 while max(d.textbbox((0,0),s,font=font(fs))[2] for s in lines)>W-2*margin:fs-=1
 bottom=int(H*(.23 if kind=='shorts_reels_cover' else .085));y=H-bottom-len(lines)*int(fs*1.18)
 for i,s in enumerate(lines):
  d.text((margin,y),s,font=font(fs),fill='white' if i==0 else preset['accent'],stroke_width=max(1,fs//28),stroke_fill='black');y+=int(fs*1.18)
 d.text((margin,H-int(H*.045)-int(W*.015)),'CTNETWORK  /  CONCEPT ART',font=font(max(12,int(W*.015))),fill='#CCCCCC')
 out.parent.mkdir(parents=True,exist_ok=True)
 if kind=='youtube_thumbnail':
  img.convert('RGB').save(out,quality=94,optimize=True)
  if out.stat().st_size>2_000_000:img.convert('RGB').save(out,quality=85,optimize=True)
 else:img.convert('RGB').save(out)
 return out

def export_templates():
 for show,p in PRESETS.items():save_json(ROOT/'presets'/f'{show}.json',{**p,'preserve_existing_brand_assets':True,'publish_allowed':False,'source_priority':'local','official_gameplay_first':show=='the_six_report'})
 for kind,(w,h) in FORMATS.items():
  gw,gh=(1280,720) if w>h else ((768,1152) if h/w<1.6 else (720,1280))
  if w==h:gw=gh=1024
  save_json(ROOT/'workflows'/f'{kind}.api.json',flux('Replace with approved show artwork brief. No text or logos.',gw,gh,prefix='ctnetwork/'+kind))
 save_json(ROOT/'workflows/reference_edit.api.json',flux('Preserve the subject. Replace background with a cinematic studio.',reference='reference.png'))
 save_json(ROOT/'workflows/image_to_image.api.json',sdxl('Preserve composition and improve realistic texture.','reference.png'))
 save_json(ROOT/'workflows/detail_enhancement.api.json',sdxl('Preserve composition and improve fine texture, natural realistic detail.','reference.png',denoise=.18))
 save_json(ROOT/'workflows/inpaint.api.json',sdxl('A gold microphone','reference.png','mask.png',denoise=.8))
 save_json(ROOT/'workflows/upscale_4x.api.json',upscale('reference.png'))
 save_json(ROOT/'workflows/background_removal.json',{'engine':'rembg','model':'u2net','device':'cpu','output':'RGBA PNG','local_only':True})
 save_json(ROOT/'defaults.json',{'premium_images_default':'local_comfyui','fallback_to_paid_services':False,'paid_generation_credit_limit':0,'approval_required':True,'primary_model':'FLUX.2 Klein 4B','editing_model':'SDXL 1.0','upscaler':'Real-ESRGAN x4plus','background_removal':'U2Net','shows':list(PRESETS),'output_root':str(ROOT/'output'),'ready_for_approval':'/workspace/ctnetwork-local/ready_for_approval/images'})
def qc(path,expected=None,alpha=False):
 with Image.open(path) as im:
  im.load();assert not expected or im.size==expected,(im.size,expected)
  assert min(ImageStat.Stat(im.convert('RGB')).stddev)>5,'Blank/near-flat output'
  if alpha:assert im.mode=='RGBA' and im.getchannel('A').getextrema()[0]<50 and im.getchannel('A').getextrema()[1]>200,'Invalid transparency'
  return {'file':str(path),'size':im.size,'mode':im.mode,'bytes':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'pass':True}
def background(source,dest):
 os.environ['U2NET_HOME']=str(ROOT/'models/rembg')
 from rembg import remove,new_session
 remove(Image.open(source),session=new_session('u2net')).save(dest)
 return dest

def certify():
 export_templates();stamp=time.strftime('%Y%m%d-%H%M%S');out=ROOT/'output'/('certification-'+stamp);out.mkdir(parents=True)
 report={'status':'TESTING','local_only':True,'paid_generation_credits':0,'outputs':[],'workflows':{},'publish_allowed':False};save_json(ROOT/'status/latest.json',report)
 generated={}
 for ix,(show,p) in enumerate(PRESETS.items()):
  dest=out/show/'keyart_raw.png';generated[show]=execute(flux(p['prompt']+' '+p['style'],1280,720,42+ix,prefix='ctnetwork/'+show),dest)
  report['outputs'].append(qc(dest,(1280,720)))
  thumb=package(dest,out/show/'youtube_thumbnail.jpg',show,'youtube_thumbnail');report['outputs'].append(qc(thumb,FORMATS['youtube_thumbnail']))
  assert thumb.stat().st_size<2_000_000
 show='hip_hop_what_if';raw=generated[show];name=upload(raw)
 edited=execute(flux('Keep the microphone and recording studio from the reference. Change the city view outside to sunset, glowing amber sky. Preserve the cinematic gold and red documentary style. No text.',1280,720,55,name,prefix='ctnetwork/reference-edit'),out/show/'reference_edit.png')
 report['outputs'].append(qc(edited));report['workflows']['reference_edit']=True
 detail=execute(sdxl('Premium documentary photograph of a vintage gold studio microphone, crisp realistic metal texture, cinematic warm lighting, preserve composition',name,denoise=.18),out/show/'detail_enhancement.png');report['outputs'].append(qc(detail));report['workflows']['image_to_image_and_detail']=True
 mask=Image.new('RGB',(1280,720),'black');ImageDraw.Draw(mask).ellipse((720,190,1150,670),fill='white');mp=out/'mask.png';mask.save(mp)
 painted=execute(sdxl('A shiny vintage silver studio microphone, cinematic red and gold studio background, realistic photograph',name,upload(mp),denoise=.85),out/show/'inpaint.png');report['outputs'].append(qc(painted))
 import numpy as np
 a=np.asarray(Image.open(raw).convert('RGB'));b=np.asarray(Image.open(painted).convert('RGB'));m=np.asarray(mask)[:,:,0]>0
 assert np.array_equal(a[~m],b[~m]),'Inpainting changed unmasked pixels'
 assert np.mean(abs(a[m].astype(float)-b[m].astype(float)))>1,'Inpainting produced no change'
 report['workflows']['inpainting_preserves_unmasked_pixels']=True
 up=execute(upscale(upload(detail),'ctnetwork/upscale'),out/show/'upscale_4x.png',timeout=1500);report['outputs'].append(qc(up,(5120,2880)));report['workflows']['ai_upscale_4x']=True
 for kind in ['episode_key_art','facebook_social','shorts_reels_cover','promotional_poster']:
  if kind in ['shorts_reels_cover','promotional_poster','facebook_social']:
   portrait=out/show/'portrait_raw.png'
   if not portrait.exists():execute(flux(PRESETS[show]['prompt']+' Vertical composition, microphone centered, dramatic tall city skyline.',768,1152,63,prefix='ctnetwork/portrait'),portrait)
   source=portrait
  else:source=up
  file=package(source,out/show/(kind+'.png'),show,kind);report['outputs'].append(qc(file,FORMATS[kind]));report['workflows'][kind]=True
 subject=execute(flux('A single vintage studio microphone made of brushed gold with its stand, full object isolated on a plain pale gray background, studio product photograph, no shadows outside object, no text.',1024,1024,98,prefix='ctnetwork/transparent-source'),out/'transparent_source.png')
 cut=background(subject,out/'transparent_asset.png')
 cutim=ImageOps.contain(Image.open(cut),(1500,1500),Image.Resampling.LANCZOS);canvas=Image.new('RGBA',(1600,1600));canvas.alpha_composite(cutim,((1600-cutim.width)//2,(1600-cutim.height)//2));canvas.save(cut)
 report['outputs'].append(qc(cut,(1600,1600),True));report['workflows']['transparent_png']=True;report['workflows']['youtube_thumbnails_all_four_shows']=True
 # Persist review package on the existing volume. No external upload.
 ready=Path('/workspace/ctnetwork-local/ready_for_approval/images')/out.name;ready.mkdir(parents=True,exist_ok=True)
 for p in out.rglob('*'):
  if p.is_file():dest=ready/p.relative_to(out);dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(p,dest)
 report.update(status='TECHNICAL_PASS_AWAITING_VISUAL_REVIEW',review_folder=str(ready),output_folder=str(out))
 save_json(out/'report.json',report);save_json(ready/'report.json',report);save_json(ROOT/'status/latest.json',report)
 print('IMAGE_FACTORY_TECHNICAL_PASS',json.dumps(report),flush=True)
def main():
 parser=argparse.ArgumentParser();parser.add_argument('action',choices=['templates','certify','job']);parser.add_argument('--manifest');a=parser.parse_args()
 if a.action=='templates':export_templates()
 elif a.action=='certify':certify()
 else:
  m=json.loads(Path(a.manifest).read_text());assert m.get('provider','local')=='local','Paid service fallback disabled'
  show=m['show'];kind=m['format'];assert show in PRESETS and kind in FORMATS
  job=m.get('job_id',uuid.uuid4().hex);assert re.fullmatch('[A-Za-z0-9_-]{1,100}',job)
  out=ROOT/'output'/show/job;out.mkdir(parents=True,exist_ok=False)
  W,H=FORMATS[kind];w,h=(1280,720) if W>H else (720,1280)
  if W==H:w=h=1024
  reference=upload(m['reference']) if m.get('reference') else None
  raw=execute(flux(m['prompt']+' '+PRESETS[show]['style'],w,h,m.get('seed',42),reference,prefix='ctnetwork/'+show+'/'+job),out/'raw.png')
  final=out/('asset.jpg' if kind=='youtube_thumbnail' else 'asset.png')
  if kind=='transparent_png':
   background(raw,final)
   im=ImageOps.contain(Image.open(final),(1500,1500),Image.Resampling.LANCZOS);canvas=Image.new('RGBA',(1600,1600));canvas.alpha_composite(im,((1600-im.width)//2,(1600-im.height)//2));canvas.save(final)
  else:package(raw,final,show,kind,m.get('headline'))
  save_json(out/'result.json',{'output':str(final),'qc':qc(final,alpha=kind=='transparent_png'),'approval_required':True,'publish_allowed':False})
if __name__=='__main__':main()
