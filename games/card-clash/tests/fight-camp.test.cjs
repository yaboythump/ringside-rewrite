"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const html = fs.readFileSync(path.join(__dirname, "..", "src.html"), "utf8");
const script = html.split("<script>")[1]?.split("</script>")[0];
assert.ok(script, "Game script exists");

const start = script.indexOf("const WRESTLERS = {");
const end = script.indexOf("let G=null;", start);
assert.ok(start !== -1 && end > start, "Pure card and roster definitions exist");

// Evaluate the actual production card definitions and gameplay helpers, not mocks.
const sandbox = {};
vm.runInNewContext(
  script.slice(start, end) +
  "\nglobalThis.testing={WRESTLERS,CARDS,BASE_DECK,cardCounts,normalizeLoadout,equipCard,unequipCard,unlockCard,MIN_CAMP_DECK,MAX_CAMP_DECK};",
  sandbox
);
const {WRESTLERS,CARDS,BASE_DECK,cardCounts,normalizeLoadout,equipCard,unequipCard,unlockCard,MIN_CAMP_DECK,MAX_CAMP_DECK} = sandbox.testing;
const initial = (id="raven") => [...BASE_DECK,...WRESTLERS[id].sig,...WRESTLERS[id].sig.slice(0,1)];

test("whole game JavaScript parses", () => {
  assert.doesNotThrow(() => new vm.Script(script));
});

test("older careers acquire a move collection without losing their deck", () => {
  const cards = initial();
  const save = {wid:"raven",deck:[...cards]};
  normalizeLoadout(save);
  assert.equal(save.deck.join(","),cards.join(","));
  assert.equal(save.collection.join(","),cards.join(","));
  assert.equal(save.deck.length,15);
});

test("repeated normalization cannot duplicate earned cards", () => {
  const save = {wid:"raven",deck:initial()};
  normalizeLoadout(save);
  normalizeLoadout(save);
  assert.equal(save.collection.length,save.deck.length);
});

test("unequipping keeps a permanent copy available for re-equipping", () => {
  const save = normalizeLoadout({wid:"raven",deck:initial()});
  const before = save.collection.length;
  assert.equal(unequipCard(save,"chop"),true);
  assert.equal(save.collection.length,before);
  assert.equal(save.deck.length,14);
  assert.equal(equipCard(save,"chop"),true);
  assert.equal(save.deck.length,15);
  assert.equal(save.collection.length,before);
  assert.equal(equipCard(save,"spear"),false,"unearned moves cannot be equipped");
});

test("deck floor of 10 and ceiling of 20 are enforced", () => {
  const save = normalizeLoadout({wid:"raven",deck:initial()});
  while(save.deck.length>MIN_CAMP_DECK) assert.equal(unequipCard(save,save.deck[0]),true);
  assert.equal(unequipCard(save,save.deck[0]),false);
  assert.equal(save.deck.length,MIN_CAMP_DECK);
  const missing = 11;
  for(let i=0;i<missing;i++) save.collection.push("spear");
  while(save.deck.length<MAX_CAMP_DECK) assert.equal(equipCard(save,"spear"),true);
  assert.equal(equipCard(save,"spear"),false);
  assert.equal(save.deck.length,MAX_CAMP_DECK);
});

test("training adds to the collection and automatically equips only when room exists", () => {
  const save = normalizeLoadout({wid:"raven",deck:initial()});
  const before = save.deck.length;
  assert.equal(unlockCard(save,"spear"),true);
  assert.equal(save.deck.length,before+1);
  assert.equal(cardCounts(save.collection).spear,1);
  while(save.deck.length<MAX_CAMP_DECK) unlockCard(save,"spear");
  const wasEarned = save.collection.length;
  assert.equal(unlockCard(save,"spear"),true);
  assert.equal(save.deck.length,MAX_CAMP_DECK);
  assert.equal(save.collection.length,wasEarned+1);
});

test("invalid and malformed saved card IDs do not enter the deck", () => {
  const save = normalizeLoadout({wid:"brick",deck:[...initial("brick"),"not-a-card"],collection:["not-a-card"]});
  assert.ok(save.deck.every(id=>!!CARDS[id]));
  assert.ok(save.collection.every(id=>!!CARDS[id]));
  assert.equal(equipCard(save,"not-a-card"),false);
  assert.equal(unlockCard(save,"not-a-card"),false);
});

test("legacy decks above the new cap retain existing cards until the user removes them", () => {
  const longDeck = [...initial(),...initial()];
  const save = normalizeLoadout({wid:"raven",deck:longDeck});
  assert.equal(save.deck.length,longDeck.length);
  assert.equal(equipCard(save,"chop"),false);
  assert.ok(save.collection.length>=save.deck.length);
});

test("the career UI exposes Fight Camp, weekly training and save protection", () => {
  assert.match(html,/id="fight-camp"/);
  assert.match(html,/function fightCamp\(\)/);
  assert.match(html,/function train\(\)/);
  assert.match(html,/collection:\[\.\.\.startingDeck\]/);
  assert.match(html,/window\.confirm\("Start a new career\?/);
  assert.match(html,/unlockCard\(C,id\)/);
  assert.match(html,/rcc-career/);
});

test("Fight Camp can render after starting an actual career in a DOM harness", () => {
  const no = () => {};
  const gradient = {addColorStop:no};
  const ctx = new Proxy({}, {
    get:(_,name)=>name==="createLinearGradient"||name==="createRadialGradient"?()=>gradient:no,
    set:()=>true
  });
  const button = {onclick:null,addEventListener:no,focus:no,scrollIntoView:no,style:{}};
  const app = {innerHTML:"",querySelectorAll:()=>[],querySelector:()=>button};
  const cv = {getContext:()=>ctx};
  const memory=new Map();
  const doc={
    querySelector:sel=>sel==="#app"?app:sel==="#arena"?cv:button,
    querySelectorAll:()=>[],
    addEventListener:no,
    createElement:()=>({className:"",innerHTML:"",remove:no,querySelector:()=>button})
  };
  const hot={ready:no,snapshot:no};
  const win={claude:{hot},confirm:()=>true};
  const runtime=vm.createContext({
    document:doc,window:win,matchMedia:()=>({matches:true}),
    Image:class{set src(value){this._src=value}},
    addEventListener:no,requestAnimationFrame:no,
    innerWidth:375,innerHeight:740,devicePixelRatio:1,
    localStorage:{getItem:k=>memory.get(k)||null,setItem:(k,v)=>memory.set(k,v)}
  });
  vm.runInContext(script,runtime,{timeout:3000});
  vm.runInContext("newCareer('raven');fightCamp();",runtime,{timeout:3000});
  assert.match(app.innerHTML,/Scout your opponent/);
  assert.match(app.innerHTML,/Unlocked reserves/);
  assert.match(app.innerHTML,/Equipped deck/);
  assert.match(app.innerHTML,/Coach.s read/);
  assert.match(app.innerHTML,/To the ring/);
  assert.ok(memory.has("rcc-career"),"Career state saved locally");
});
