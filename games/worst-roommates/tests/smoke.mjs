import { chromium } from "playwright";
import { pathToFileURL } from "node:url";
import path from "node:path";
import fs from "node:fs";

const html = path.resolve("games/worst-roommates.html");
if (!fs.existsSync(html)) throw new Error("Built game HTML not found");
const browser = await chromium.launch({ headless: true });
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
const errors = [];
page.on("pageerror", error => errors.push(error.message));
try {
  await page.goto(pathToFileURL(html).href);
  await page.locator(".mode-buttons [data-mode='story']").waitFor();
  const getState = () => page.evaluate(() => window.WorstRoommatesGameplay.state());
  let state = await getState();
  if (state.mode !== "story" || state.story.cash !== 75) throw new Error("Story mode did not initialize");
  await page.locator("[data-action='work']").click();
  state = await getState();
  if (state.story.cash !== 110) throw new Error("Work action did not earn $35. state=" + JSON.stringify(state) + "; pageerrors=" + JSON.stringify(errors));
  await page.locator("#cast .cm").nth(1).click();
  state = await getState();
  if (state.selected !== "Brenda") throw new Error("Roommate selection failed");
  await page.locator(".mode-buttons [data-mode='chaos']").click();
  await page.locator("[data-action='prank']").click();
  state = await getState();
  if (state.mode !== "chaos" || state.chaos.score < 65) throw new Error("Chaos scoring did not work");
  await page.locator("[data-action='disaster']").click();
  state = await getState();
  if (state.chaos.score <= 65) throw new Error("Disaster did not add chaos score");
  await page.locator(".mode-buttons [data-mode='director']").click();
  const visibleDirector = await page.locator(".director-panel").isVisible();
  const hiddenDash = await page.locator("#playDash").isHidden();
  if (!visibleDirector || !hiddenDash) throw new Error("Director controls not restored");
  await page.locator(".mode-buttons [data-mode='story']").click();
  await page.locator("#playRestart").click();
  state = await getState();
  if (state.story.cash !== 75 || state.story.day !== 1) throw new Error("New Lease did not reset Story Mode");
  const width = await page.evaluate(() => ({ inner: innerWidth, page: document.body.scrollWidth }));
  if (width.page > width.inner + 5) throw new Error("Mobile viewport horizontal overflow");
  if (errors.length) throw new Error("JavaScript errors: " + errors.join(" | "));
  console.log("PASS: Story actions, selection, Chaos score, disasters, Director mode, restart and mobile layout");
} finally {
  await browser.close();
}
