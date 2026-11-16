"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

test("the WebKit bootstrap restores saved UTF-8 data and posts saves and haptics", () => {
  const source = fs.readFileSync(path.join(
    __dirname, "../ios/RingsideCardClash/RingsideCardClashApp.swift"
  ), "utf8");
  const bootstrap = source.match(/func bootstrap\(\) -> String {[\s\S]*?return """([\s\S]*?)"""/)?.[1];
  assert.ok(bootstrap, "Expected a native bootstrap script");
  const saved = {"rcc-career":JSON.stringify({name:"Naiym “Thump” Cooper"})};
  const encoded = Buffer.from(JSON.stringify(saved), "utf8").toString("base64");
  const js = bootstrap.replace(String.raw`\(encoded)`, encoded)
    .replace(String.raw`\(Self.bridgeName)`, "ringsideGame");
  const messages = [];
  const window = {webkit:{messageHandlers:{ringsideGame:{postMessage:value=>messages.push(value)}}}};
  vm.runInNewContext(js, {window, TextDecoder, Uint8Array, atob});
  const bridge=window.RingsideNative;
  assert.equal(bridge.getItem("rcc-career"),saved["rcc-career"]);
  bridge.setItem("rcc-mute","1");
  bridge.impact("heavy");
  bridge.audio("music-start");
  bridge.audio("ref-3");
  assert.equal(bridge.getItem("rcc-mute"),"1");
  assert.equal(messages[0].key,"rcc-mute");
  assert.equal(messages[1].strength,"heavy");
  assert.equal(messages[2].action,"audio");
  assert.equal(messages[2].cue,"music-start");
  assert.equal(messages[3].cue,"ref-3");
});
