import {chromium} from "playwright";
import {pathToFileURL} from "node:url";
import path from "node:path";
import assert from "node:assert/strict";
import fs from "node:fs/promises";
await fs.mkdir("games/detective-duo/tests/artifacts",{recursive:true});

const browser=await chromium.launch({headless:true,...(process.env.DD_CHROMIUM?{executablePath:process.env.DD_CHROMIUM}:{})});
const page=await browser.newPage({viewport:{width:390,height:844},deviceScaleFactor:2});
const errors=[];
page.on("pageerror",error=>errors.push(error.message));
const url=pathToFileURL(path.resolve("games/detective-duo/index.html")).href;
const state=()=>page.evaluate(()=>window.DetectiveDuoTest.state());
try {
  await page.goto(url);
  await page.locator("#continueGame").click();
  assert.equal(await page.locator("#beginCase").isVisible(),true,"intro visible");
  await page.locator("#beginCase").click();
  assert.equal((await state()).briefed,true);
  assert.equal(await page.locator(".hotspot").count(),4);
  await page.getByRole("button",{name:"Collect Interrupted call"}).click();
  assert.ok((await state()).found.includes("phone"));
  await page.locator("#dismissModal").click();
  await page.locator('[data-room="hall"]').click();
  await page.getByRole("button",{name:"Collect Camera playback"}).click();
  await page.locator("#dismissModal").click();
  await page.getByRole("button",{name:"Collect Linen trolley"}).click();
  await page.locator("#dismissModal").click();
  await page.locator('[data-room="security"]').click();
  await page.getByRole("button",{name:"Collect Incident log"}).click();
  await page.locator("#dismissModal").click();
  await page.locator('[data-room="roof"]').click();
  await page.getByRole("button",{name:"Collect Service gate"}).click();
  await page.locator("#dismissModal").click();
  await page.getByRole("button",{name:"Collect Override panel"}).click();
  await page.locator("#dismissModal").click();
  await page.getByRole("button",{name:"Collect Invoice envelope"}).click();
  await page.locator("#dismissModal").click();
  await page.locator('[data-room="suite"]').click();
  await page.getByRole("button",{name:"Collect Reporter notes"}).click();
  await page.locator("#dismissModal").click();
  assert.equal((await state()).found.length,8,"eight useful clues");
  await page.locator('[data-tab="evidence"]').click();
  await page.locator('[data-evidence="phone"]').click();
  await page.locator('[data-evidence="logbook"]').click();
  await page.locator("#goDeduce").click();
  await page.locator("#linkNow").click();
  assert.ok((await state()).linked.includes("timeline"),"timeline deduction");
  const selected=await state();
  assert.equal(selected.selected.length,0,"selection clears");
  // Incorrect pairing cannot falsely create a lead.
  await page.locator("#pickEvidence").click();
  await page.locator('[data-evidence="camera"]').click();
  await page.locator('[data-evidence="phone"]').click();
  await page.locator("#goDeduce").click();
  await page.locator("#linkNow").click();
  assert.equal((await state()).linked.length,1,"bad deduction rejected");
  for(const [a,b] of [["camera","panel"],["trolley","gate"],["note","envelope"]]){
    await page.locator("#pickEvidence").click();
    await page.locator('[data-evidence="'+a+'"]').click();
    await page.locator('[data-evidence="'+b+'"]').click();
    await page.locator("#goDeduce").click();
    await page.locator("#linkNow").click();
  }
  assert.equal((await state()).linked.length,4,"all deductions solved");
  await page.locator('[data-tab="interviews"]').click();
  await page.locator('[data-person="mara"]').click();
  await page.locator('[data-question="2"]').click();
  assert.match((await state()).dialogue,/invoices/i);
  await page.locator('[data-tab="verdict"]').click();
  await page.locator('[data-answer="suspect"][data-value="mara"]').click();
  await page.locator('[data-answer="motive"][data-value="fraud"]').click();
  await page.locator('[data-answer="route"][data-value="lift"]').click();
  await page.locator("#submitCase").click();
  assert.equal((await state()).finished,false,"wrong solution rejected");
  await page.locator("#dismissModal").click();
  await page.locator('[data-answer="route"][data-value="roof"]').click();
  await page.locator("#submitCase").click();
  assert.equal((await state()).finished,true,"correct solution closes case");
  assert.equal((await state()).score,100);
  await page.locator("#dismissModal").click();
  const before=await state();
  await page.reload();
  await page.locator("#continueGame").click();
  const after=await state();
  assert.equal(after.finished,true,"state survives reload");
  assert.equal(after.linked.length,before.linked.length);
  const folded=await page.evaluate(()=>({
    width:innerWidth,scroll:document.documentElement.scrollWidth,
    main:document.querySelector(".main").getBoundingClientRect(),
    stage:document.querySelector(".stage-panel").getBoundingClientRect(),
    desk:document.querySelector(".desk").getBoundingClientRect()
  }));
  assert.ok(folded.scroll<=folded.width+3,"no horizontal overflow folded");
  assert.ok(folded.stage.bottom<=folded.desk.top+2,"folded layout stacks panels");
  assert.ok(folded.desk.bottom<=844,"folded game fits without whole-page scrolling");
  await page.screenshot({animations:'disabled',path:"games/detective-duo/tests/artifacts/07-solved-compact.png"});
  await page.setViewportSize({width:940,height:800});
  await page.screenshot({animations:'disabled',path:"games/detective-duo/tests/artifacts/08-solved-expanded.png"});
  const open=await page.evaluate(()=>({
    width:innerWidth,scroll:document.documentElement.scrollWidth,
    stage:document.querySelector(".stage-panel").getBoundingClientRect(),
    desk:document.querySelector(".desk").getBoundingClientRect()
  }));
  assert.ok(open.scroll<=open.width+3,"no unfolded overflow");
  assert.ok(open.stage.right<=open.desk.left+2,"unfolded layout is side-by-side");
  assert.equal((await state()).finished,true,"fold change retains solved case");
  assert.deepEqual(errors,[],"no browser errors");
  console.log("PASS: playable detective case, 8 clue discoveries, interviews, valid/invalid deductions, verdict, persistence, foldable layouts");
}finally{await browser.close()}
