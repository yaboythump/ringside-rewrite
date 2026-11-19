import {chromium} from 'playwright';
import assert from 'node:assert/strict';
import {pathToFileURL} from 'node:url';
import path from 'node:path';
import fs from 'node:fs/promises';
import http from 'node:http';
const root=path.resolve('games/detective-duo');
const server=http.createServer(async(req,res)=>{try{const name=decodeURIComponent(new URL(req.url,'http://localhost').pathname);const file=path.resolve(root,'.'+(name==='/'?'/index.html':name));if(!file.startsWith(root+'/'))throw Error();const types={'.html':'text/html','.css':'text/css','.js':'text/javascript','.webp':'image/webp'};res.setHeader('Content-Type',types[path.extname(file)]||'application/octet-stream');res.end(await fs.readFile(file))}catch{res.writeHead(404);res.end()}});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const output='games/detective-duo/tests/artifacts';await fs.mkdir(output,{recursive:true});
const browser=await chromium.launch({headless:true,...(process.env.DD_CHROMIUM?{executablePath:process.env.DD_CHROMIUM}:{})});
const page=await browser.newPage({viewport:{width:390,height:844},hasTouch:true,deviceScaleFactor:2});
const errors=[];page.on('pageerror',e=>errors.push(e.message));
const state=()=>page.evaluate(()=>DetectiveDuoTest.state());
const close=()=>page.locator('#dismissModal').click();
try{
 await page.goto('http://127.0.0.1:'+server.address().port+'/');
 await page.screenshot({animations:'disabled',path:output+'/01-main-menu.png'});
 await page.locator('#continueGame').click();await page.locator('#beginCase').click();
 assert.equal(await page.locator('#scene-art img').evaluate(i=>i.complete&&i.naturalWidth>1000),true);
 await page.screenshot({animations:'disabled',path:output+'/02-compact-investigation.png'});
 // Every clue must be touch reachable, show its inspection, and retain state.
 for(const room of ['suite','hall','security','roof']){
  await page.locator('[data-room="'+room+'"]').click();
  const labels=await page.locator('.hotspot').evaluateAll(bs=>bs.map(b=>b.getAttribute('aria-label')));
  for(const label of labels){
   const b=page.getByRole('button',{name:label,exact:true});
   const rect=await b.boundingBox();assert.ok(rect.width>=43&&rect.height>=43);
   assert.ok(rect.x>=0&&rect.x+rect.width<=390,'hotspot inside screen '+label);
   await b.tap();assert.equal(await page.locator('.inspect-photo').isVisible(),true);await close();
  }
 }
 assert.equal((await state()).found.length,16);
 await page.locator('[data-tab="interviews"]').click();
 for(const id of ['mara','theo','iris','elias']){
  await page.locator('[data-person="'+id+'"]').click();
  for(let i=0;i<3;i++){await page.locator('[data-question="'+i+'"]').click();assert.ok((await state()).dialogue.length>20)}
 }
 assert.equal((await state()).interviewed.filter(k=>!k.endsWith(':intro')).length,12);
 await page.screenshot({animations:'disabled',path:output+'/03-compact-interview.png'});
 for(const [a,b] of [['phone','logbook'],['camera','panel'],['trolley','gate'],['note','envelope']]){
  await page.locator('[data-tab="evidence"]').click();await page.locator('[data-evidence="'+a+'"]').click();await page.locator('[data-evidence="'+b+'"]').click();await page.locator('#goDeduce').click();await page.locator('#linkNow').click();
 }
 assert.equal((await state()).linked.length,4);assert.equal(await page.locator('.thread').count(),4);
 const before=await state();
 for(const size of [{width:940,height:800},{width:1180,height:820},{width:844,height:390},{width:600,height:900},{width:320,height:568},{width:390,height:844}]){
  await page.setViewportSize(size);await page.waitForTimeout(250);
  const layout=await page.evaluate(()=>({w:innerWidth,h:innerHeight,sw:document.documentElement.scrollWidth,sh:document.documentElement.scrollHeight,main:document.querySelector('.main').getBoundingClientRect().toJSON(),desk:document.querySelector('.desk').getBoundingClientRect().toJSON()}));
  assert.ok(layout.sw<=layout.w+1,'no horizontal overflow '+JSON.stringify(size));assert.ok(layout.sh<=layout.h+1,'no vertical page overflow '+JSON.stringify(size));assert.ok(layout.desk.bottom<=layout.h+1);
  assert.equal((await state()).found.length,before.found.length);assert.equal((await state()).dialogue,before.dialogue);
 }
 await page.setViewportSize({width:1180,height:820});await page.locator('[data-room="suite"]').click();await page.locator('[data-tab="evidence"]').click();await page.screenshot({animations:'disabled',path:output+'/04-expanded-evidence.png'});
 await page.locator('[data-tab="deductions"]').click();await page.screenshot({animations:'disabled',path:output+'/05-expanded-deductions.png'});
 await page.locator('[data-tab="interviews"]').click();await page.locator('[data-person="mara"]').click();await page.screenshot({animations:'disabled',path:output+'/06-expanded-interview.png'});
 assert.equal((await page.evaluate(()=>NoirAudio.state())).status,'running');
 await page.locator('#settings').click();await page.locator('#audioSettings').click();await page.locator('#music-setting').uncheck();await page.locator('#sound-setting').uncheck();assert.equal((await page.evaluate(()=>NoirAudio.state())).music,false);assert.equal((await page.evaluate(()=>NoirAudio.state())).sound,false);await page.locator('#closeSettings').click();
 await page.locator('#newGame').click();assert.equal((await state()).found.length,16,'reset warning preserves progress');await page.locator('#cancelReset').click();await page.locator('#continueGame').click();
 await page.reload();await page.locator('#continueGame').click();assert.equal((await state()).found.length,16);assert.equal((await page.evaluate(()=>NoirAudio.state())).music,false);
 await page.locator('#settings').click();await page.locator('#newGame').click();await page.locator('#resetCase').click();await page.locator('#beginCase').click();assert.equal((await state()).found.length,0);
 // Corrupt saves must recover without exceptions.
 await page.evaluate(()=>localStorage.setItem('detective_duo_v1','{broken'));await page.reload();await page.locator('#continueGame').click();await page.locator('#beginCase').click();assert.equal((await state()).found.length,0);
 await page.evaluate(()=>navigator.serviceWorker.ready);await page.waitForFunction(()=>!!navigator.serviceWorker.controller);await page.context().setOffline(true);await page.reload();await page.locator('#continueGame').click();assert.equal(await page.locator('#scene-art img').evaluate(i=>i.complete&&i.naturalWidth>1000),true,'scene loads offline');await page.context().setOffline(false);assert.deepEqual(errors,[]);console.log('PASS: 16 touch discoveries, 12 interviews, all deductions, inspection art, audio settings, reset/corrupt-save recovery, six display sizes, fold state continuity');
}finally{await browser.close();await new Promise(resolve=>server.close(resolve))}
