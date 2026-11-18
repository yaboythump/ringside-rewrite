import { chromium } from "playwright";
import { pathToFileURL } from "node:url";
import path from "node:path";
import fs from "node:fs";

const html = path.resolve("games/worst-roommates.html");
if (!fs.existsSync(html)) throw new Error("Built game HTML not found");
const browser = await chromium.launch({ headless: true, ...(process.env.WRE_CHROMIUM_PATH ? {executablePath:process.env.WRE_CHROMIUM_PATH} : {}) });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
const errors = [];
page.on("pageerror", error => errors.push(error.message));
try {
  await page.goto(pathToFileURL(html).href);
  await page.locator("#dockActions [data-dock-action='work']").waitFor();
  const getState = () => page.evaluate(() => window.WorstRoommatesGameplay.state());
  let state = await getState();
  if (state.mode !== "story" || state.story.cash !== 75) throw new Error("Story mode did not initialize");
  await page.locator("#dockActions [data-dock-action='work']").click();
  state = await getState();
  if (state.story.cash !== 110) throw new Error("Work action did not earn $35. state=" + JSON.stringify(state) + "; pageerrors=" + JSON.stringify(errors));
  await page.locator("#dockSelected").click();
  await page.locator("#cast .cm").nth(1).click();
  await page.locator("#closeConsole").click();
  state = await getState();
  if (state.selected !== "Brenda") throw new Error("Roommate selection failed");
  await page.locator("#dockMode").click();
  await page.locator(".mode-buttons [data-mode='chaos']").click();
  await page.locator("#closeConsole").click();
  await page.locator("#dockActions [data-dock-action='prank']").click();
  state = await getState();
  if (state.mode !== "chaos" || state.chaos.score < 65) throw new Error("Chaos scoring did not work");
  await page.locator("#dockActions [data-dock-action='disaster']").click();
  state = await getState();
  if (state.chaos.score <= 65) throw new Error("Disaster did not add chaos score");
  await page.locator("#dockMode").click();
  await page.locator(".mode-buttons [data-mode='director']").click();
  const visibleDirector = await page.locator(".director-panel").isVisible();
  const hiddenDash = await page.locator("#playDash").isHidden();
  if (!visibleDirector || !hiddenDash) throw new Error("Director controls not restored");
  await page.locator("#closeConsole").click();
  await page.locator("#dockMode").click();
  await page.locator(".mode-buttons [data-mode='story']").click();
  await page.locator("#playRestart").click();
  await page.locator("#closeConsole").click();
  state = await getState();
  if (state.story.cash !== 75 || state.story.day !== 1) throw new Error("New Lease did not reset Story Mode");
  const width = await page.evaluate(() => ({ inner: innerWidth, page: document.body.scrollWidth }));
  if (width.page > width.inner + 5) throw new Error("Mobile viewport horizontal overflow");
  const folded = await page.evaluate(() => {
    const stage = document.querySelector("#stage").getBoundingClientRect();
    const dock = document.querySelector("#duoDock").getBoundingClientRect();
    return { stageBottom: stage.bottom, dockTop: dock.top, scrollHeight: document.documentElement.scrollHeight,
      viewHeight: innerHeight, dockDisplay: getComputedStyle(document.querySelector("#duoDock")).display };
  });
  if(folded.dockDisplay==="none" || folded.stageBottom>folded.dockTop || folded.scrollHeight>folded.viewHeight+5)
    throw new Error("Folded viewport requires scrolling: "+JSON.stringify(folded));
  await page.setViewportSize({width:890,height:1120});
  const wide = await page.evaluate(() => {
    const stage=document.querySelector("#stage").getBoundingClientRect();
    const controls=document.querySelector("#duoControls").getBoundingClientRect();
    return {stageRight:stage.right,controlsLeft:controls.left,visible:getComputedStyle(document.querySelector("#duoControls")).display!=="none",
      dockHidden:getComputedStyle(document.querySelector("#duoDock")).display==="none"};
  });
  if(!wide.visible||!wide.dockHidden||wide.stageRight>wide.controlsLeft)
    throw new Error("Unfolded control room not side-by-side: "+JSON.stringify(wide));
  await page.locator("#consoleQuickActions [data-dock-action='work']").click();
  state=await getState();
  if(state.story.cash!==110) throw new Error("Unfolded quick actions did not earn cash");
  await page.setViewportSize({width:390,height:844});
  state=await getState();
  if(state.story.cash!==110) throw new Error("Folding the phone reset the game");
  if (errors.length) throw new Error("JavaScript errors: " + errors.join(" | "));
  console.log("PASS: no-scroll Duo dock, Story/Chaos/Director, cast, restart, fold continuity and unfolded controls");
} finally {
  await browser.close();
}
