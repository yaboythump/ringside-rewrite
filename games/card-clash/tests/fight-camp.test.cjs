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
  assert.match(html,/function fightCamp\(/);
  assert.match(html,/function train\(\)/);
  assert.match(html,/collection:\[\.\.\.startingDeck\]/);
  assert.match(html,/Start a new career\?/);
  assert.match(html,/if\(dialog\.returnValue==="start"\)startCareer/);
  assert.match(html,/unlockCard\(C,id\)/);
  assert.match(html,/rcc-career/);
});

function gameRuntime(native){
  const no = () => {};
  const gradient = {addColorStop:no};
  const ctx = new Proxy({}, {
    get:(_,name)=>name==="createLinearGradient"||name==="createRadialGradient"?()=>gradient:no,
    set:()=>true
  });
  const button = {onclick:null,classList:{add:no,remove:no},appendChild:no,addEventListener:no,focus:no,scrollIntoView:no,style:{}};
  const app = {innerHTML:"",querySelectorAll:()=>[],querySelector:()=>button};
  const cv = {getContext:()=>ctx};
  const memory=new Map();
  const doc={
    body:{classList:{toggle:no},appendChild:no},
    querySelector:sel=>sel==="#app"?app:sel==="#arena"?cv:button,
    querySelectorAll:()=>[],
    addEventListener:no,
    createElement:()=>({className:"",style:{},innerHTML:"",remove:no,setAttribute:no,querySelector:()=>button})
  };
  const hot={ready:no,snapshot:no};
  const win={claude:{hot},confirm:()=>true,RingsideNative:native};
  const runtime=vm.createContext({
    document:doc,window:win,matchMedia:()=>({matches:true}),
    Image:class{set src(value){this._src=value}},
    addEventListener:no,requestAnimationFrame:no,setTimeout:fn=>{fn();},
    innerWidth:375,innerHeight:740,devicePixelRatio:1,
    localStorage:{getItem:k=>memory.get(k)||null,setItem:(k,v)=>memory.set(k,v)}
  });
  vm.runInContext(script,runtime,{timeout:3000});
  return {app,memory,run:code=>vm.runInContext(code,runtime,{timeout:3000})};
}

test("Fight Camp can render after starting an actual career in a DOM harness", () => {
  const {app,memory,run}=gameRuntime();
  run("newCareer('raven');fightCamp();");
  assert.match(app.innerHTML,/Scout your opponent/);
  assert.match(app.innerHTML,/Unlocked reserves/);
  assert.match(app.innerHTML,/Equipped deck/);
  assert.match(app.innerHTML,/Coach.s read/);
  assert.match(app.innerHTML,/To the ring/);
  assert.ok(memory.has("rcc-career"),"Career state saved locally");
});

test("Career purses fund permanent shop cards and swaps keep the deck size", () => {
  const {run,memory}=gameRuntime();
  run("newCareer('raven')");
  assert.equal(run("C.cash"),0);
  assert.equal(run("buyCard(C,'shopPalm')"),false);
  assert.equal(run("awardPurse(C,false,true,true)"),0);
  assert.equal(run("awardPurse(C,true)"),45);
  assert.equal(run("buyCard(C,'shopPalm')"),true);
  assert.equal(run("C.cash"),0);
  assert.equal(run("buyCard(C,'shopPalm')"),false);
  assert.equal(run("C.deck.includes('shopPalm')"),false);
  assert.equal(run("swapCard(C,'shopPalm','chop')"),true);
  assert.equal(run("swapCard(C,'shopPalm','taunt')"),false);
  assert.equal(run("C.deck.length"),15);
  assert.equal(run("cardCounts(C.collection).chop"),2);
  run("saveCareer()");
  const stored=JSON.parse(memory.get("rcc-career"));
  assert.equal(stored.cash,0);
  assert.ok(stored.deck.includes("shopPalm"));
  assert.equal(run("loadCareer().cash"),0);
  assert.equal(run("normalizeCareer({...C,w:8,cash:undefined}).cash"),360);
});

test("all 24 wrestlers have valid decks, a finisher and a divisional opponent pool", () => {
  const {run}=gameRuntime();
  assert.equal(run("roster().length"),24);
  assert.equal(run("roster().filter(w=>divisionOf(w.id)==='women').length"),8);
  assert.equal(run("roster().every(w=>w.hp>0&&w.fin.dmg>0&&w.sig.length>=2&&w.sig.every(id=>Object.hasOwn(CARDS,id)))"),true);
});

test("Create-a-Wrestler validates real selections and survives a save reload", () => {
  const {run,app}=gameRuntime();
  run(`
    const input={name:'  <Rook>  & Rose ',style:'tech',palette:'jade',look:'mask',skin:3,gear:'elite',
      personality:'villain',finisher:'dive',move:'haymaker',division:'women'};
    const made=customWrestler(input);
    newCareer(made.id,made);
  `);
  assert.match(app.innerHTML,/&lt;Rook&gt; &amp; Rose/);
  assert.equal(run("loadCareer().profile.name"),"<Rook> & Rose");
  assert.equal(run("C.champ"),"imani");
  assert.equal(run("C.align"),-2);
  assert.equal(run("C.deck.includes('haymaker')"),true);
  assert.equal(run("WRESTLERS.custom.fin.pierce"),true);
  assert.equal(run("customWrestler({...input,style:'constructor'})"),null);
  assert.equal(run("customWrestler({...input,name:'   '})"),null);
  assert.equal(run("C.contenders.every(id=>divisionOf(id)==='women')"),true);
});

test("legacy career keeps rank, deck, booking, records, defenses, and champion peak", () => {
  const {run,memory}=gameRuntime();
  const deck=initial();
  memory.set("rcc-career",JSON.stringify({
    wid:"raven",champ:"silas",contenders:["dutch","raven","kid","brick","tank","jett","ox"],
    booked:{id:"dutch",title:false,stip:null},news:["Prior show"],week:13,w:8,l:4,peak:0,defenses:3,reigns:1,deck
  }));
  assert.equal(run("C=loadCareer(); C.contenders.indexOf('raven')"),1);
  assert.equal(run("C.booked.id"),"dutch");
  assert.equal(run("C.week"),13);
  assert.equal(run("C.w+C.l"),12);
  assert.equal(run("C.defenses"),3);
  assert.equal(run("C.reigns"),1);
  assert.equal(run("C.peak"),0);
  assert.equal(run("C.deck.join(',')"),deck.join(","));
  assert.equal(run("C.collection.join(',')"),deck.join(","));
  assert.equal(run("C.history.length"),0);
});

test("World Championship booking takes priority over a rivalry, records a reign then defense and loss", () => {
  const {run}=gameRuntime();
  run(`newCareer('raven'); C.week=4; C.arc={foe:'kid',heat:5}; C.booked=null;
    C.contenders=['raven',...C.contenders.filter(id=>id!=='raven')];`);
  assert.equal(run("book().title"),"main");
  assert.equal(run("C.booked.id"),"silas");
  assert.equal(run("recordCareerMatch(true,4).wonTitle"),true);
  assert.equal(run("C.champ"),"raven");
  assert.equal(run("C.history[0].title"),"World Championship");
  assert.equal(run("C.contenders.includes('raven')"),false);
  run("C.week=8;book();recordCareerMatch(true,3);");
  assert.equal(run("C.defenses"),1);
  assert.equal(run("C.history[0].action"),"retained");
  run("C.week=12;book();recordCareerMatch(false,3);");
  assert.equal(run("C.contenders.filter(id=>id==='raven').length"),1);
  assert.equal(run("C.contenders.includes(C.champ)"),false);
  assert.equal(run("C.history.length"),3);
  assert.equal(run("C.results.length"),3);
});

test("Continental win leaves the World holder and rankings intact", () => {
  const {run}=gameRuntime();
  run(`newCareer('brick'); C.week=4; C.booked=null;
    C.contenders=C.contenders.filter(id=>id!=='brick');C.contenders.splice(1,0,'brick');`);
  assert.equal(run("book().title"),"secondary");
  run("recordCareerMatch(true,3);");
  assert.equal(run("C.secondary"),"brick");
  assert.equal(run("C.champ"),"silas");
  assert.equal(run("myRank()"),1);
  assert.equal(run("C.history[0].title"),"Continental Championship");
});

test("Women's career uses a separate roster and championship history", () => {
  const {run}=gameRuntime();
  run("newCareer('nova');C.week=4;C.booked=null;C.contenders=['nova',...C.contenders.filter(id=>id!=='nova')];book();recordCareerMatch(true,3);");
  assert.equal(run("C.champ"),"nova");
  assert.equal(run("C.secondary"),null);
  assert.match(run("C.history[0].title"),/Women.s Championship/);
});

test("training tiers unlock with XP and match rewards remain owned", () => {
  const {run}=gameRuntime();
  run("newCareer('brick');");
  assert.equal(run("availableTraining(C).includes('roundhouse')"),false);
  assert.equal(run("availableTraining(C).includes('rolling')"),false);
  assert.equal(run("C.xp=44; recordCareerMatch(true,3).level"),2);
  assert.equal(run("C.collection.length"),16);
  assert.equal(run("availableTraining(C).includes('roundhouse')"),true);
  assert.equal(run("C.xp=135;availableTraining(C).includes('rolling')"),true);
});

test("faction pacts affect the next bout and betrayal sets up a persistent feud", () => {
  const {run}=gameRuntime();
  run("newCareer('brick');storyOffer(C).actions[0][1]();");
  assert.equal(run("C.arc.faction"),"guild");
  assert.equal(run("C.hpMod"),5);
  run("const ally=C.arc.ally;storyOffer(C).actions[1][1]();saveCareer();C=loadCareer();");
  assert.equal(run("C.arc.ally"),null);
  assert.equal(run("C.arc.foe===ally&&C.arc.heat===4&&C.align<0"),true);
});

test("eight-entrant tournament advances all bracket sides and crowns one wrestler", () => {
  const {run}=gameRuntime();
  run(`const rounds=buildBracket(['brick','raven','dutch','kid','tank','jett','ox','silas']);
    for(let i=0;i<3;i++) resolveBracket(rounds,i,'brick',true,(a,b)=>b);`);
  assert.equal(run("rounds[0].filter(b=>b.winner).length"),4);
  assert.equal(run("rounds[1].filter(b=>b.winner).length"),2);
  assert.equal(run("rounds[2][0].winner"),"brick");
  assert.equal(run("rounds[2][0].b"),"silas");
});

test("blocked hits preserve Exposed, piercing hits consume it, and finishers apply their effect", () => {
  const {run}=gameRuntime();
  run("const defender=makeFighter('brick'), attacker=makeFighter('raven');defender.exposed=true;defender.block=11;");
  assert.equal(run("damage(defender,5)"),0);
  assert.equal(run("defender.exposed"),true);
  assert.equal(run("finishMove(attacker,defender)"),19);
  assert.equal(run("defender.exposed"),false);
  assert.equal(run("defender.block"),6);
});

test("a grapple reversal that drops the AI to zero resolves a pin", async () => {
  const {run}=gameRuntime();
  run(`G={mode:'exhibition',pid:'dutch',oid:'brick',round:0,log:[],turn:1,stats:{fin:0,kicks:0,rev:0},bars:{},
    p:makeFighter('dutch'),o:makeFighter('brick'),intent:{type:'grapple',dmg:10}};
    G.p.reversal=true;G.o.hp=4;oppAct();`);
  assert.equal(run("G.busy"),true);
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(run("G.over"),true);
  assert.equal(run("G.stats.rev"),1);
});

test("tag commits the turn, preserves bench health and can award the belts", async () => {
  const {run,memory}=gameRuntime();
  assert.equal(run("startTag('brick','brick','silas','tank',false)"),false);
  assert.equal(run("startTag('brick','raven','silas','tank',true)"),true);
  await new Promise(resolve=>setImmediate(resolve));
  run("G.intent={type:'hype',hype:3};G.p.hp=33;playerTag();");
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(run("G.p.w.id"),"raven");
  assert.equal(run("G.pBench.hp"),33);
  assert.equal(run("G.turn"),2);
  run("finishMatch(true);");
  const saved=JSON.parse(memory.get("rcc-tag"));
  assert.deepEqual(saved.champions,["brick","raven"]);
  assert.equal(saved.history[0].action,"won");
});

test("a cup saves before the first match and resumes the exact bracket after a win", async () => {
  const {run,memory}=gameRuntime();
  run("startTournament('nova');");
  const opening=JSON.parse(memory.get("rcc-cup"));
  assert.equal(opening.pid,"nova");
  assert.equal(run("loadCup().round"),0);
  run(`const bout=G.bracket[0].find(game=>game.a==='nova'||game.b==='nova');
    G.oid=bout.a==='nova'?bout.b:bout.a;startMatch();`);
  await new Promise(resolve=>setImmediate(resolve));
  run("finishMatch(true);");
  assert.equal(run("loadCup().round"),1);
  assert.equal(run("loadCup().bracket[1].some(game=>game.a==='nova'||game.b==='nova')"),true);
  const positions=JSON.parse(memory.get("rcc-cup")).bracket[0].map(({a,b})=>[a,b]);
  assert.deepEqual(positions,opening.bracket[0].map(({a,b})=>[a,b]));
  run("titleScreen();championshipCupMenu();");
  assert.equal(run("G.round"),1);
  assert.equal(run("G.pid"),"nova");
});

test("cup saves contain the final winner on elimination and invalid brackets are rejected", async () => {
  const {run}=gameRuntime();
  run(`startTournament('nova');
    const bout=G.bracket[0].find(game=>game.a==='nova'||game.b==='nova');
    G.oid=bout.a==='nova'?bout.b:bout.a;startMatch();`);
  await new Promise(resolve=>setImmediate(resolve));
  run("finishMatch(false);");
  assert.equal(run("Boolean(loadCup().bracket[2][0].winner)"),true);
  assert.equal(run("loadCup().bracket[2][0].winner==='nova'"),false);
  assert.equal(run("G.bracket[0][0].winner='constructor';normalizeCup(G)"),null);
});

test("standalone tag promotion migrates a previously saved champion pair", () => {
  const {run,memory}=gameRuntime();
  memory.set("rcc-tag",JSON.stringify(["brick","raven"]));
  assert.equal(run("tagPromotion().champions.join(',')"),"brick,raven");
  assert.equal(run("tagPromotion().history.length"),0);
  assert.equal(run("recordTagChampions(tagPromotion(),['raven','brick'])"),"retained");
});

test("a career tag team qualifies for the title and preserves the singles booking", () => {
  const {run}=gameRuntime();
  run(`newCareer('nova');C.arc.ally='nyx';C.arc.faction='lights';
    const play=(won)=>{const booking=careerTagBooking(C);
      const [pid,partner]=booking.pair,[oid,otherPartner]=booking.opponents;
      return recordCareerTag(C,{pid,partner,oid,otherPartner,forTitle:booking.forTitle,tagWeek:C.week},won);
    };`);
  assert.equal(run("careerTagBooking(C)"),null);
  run("C.week=4;C.booked=null;book();const mainEvent=C.booked;play(true);");
  assert.equal(run("C.booked===mainEvent&&C.week===4&&C.w===0"),true);
  assert.equal(run("careerTagBooking(C)"),null);
  run("C.week=8;play(true);C.week=12;");
  assert.equal(run("careerTagBooking(C).forTitle"),true);
  assert.equal(run("careerTagBooking(C).opponents.join(',')"),"imani,alba");
  assert.match(run("play(true)"),/wins the Tag Team Championship/);
  assert.equal(run("C.tag.champions.join(',')"),"nova,nyx");
  assert.equal(run("C.tag.history[0].week"),12);
  run("C.week=16;play(true);");
  assert.equal(run("C.tag.history[0].action"),"retained");
  assert.equal(run("C.tag.partners.nyx.wins"),4);
});

test("betraying a championship partner vacates the belts without clearing team records", () => {
  const {run}=gameRuntime();
  run(`newCareer('nova');C.arc.ally='nyx';C.arc.faction='lights';C.tag.champions=['nova','nyx'];
    C.tag.partners.nyx={wins:3,losses:1};storyOffer(C).actions[1][1]();saveCareer();C=loadCareer();`);
  assert.equal(run("C.tag.champions"),null);
  assert.equal(run("C.tag.history[0].action"),"vacated");
  assert.equal(run("C.tag.partners.nyx.wins"),3);
});

test("contracts persist progress and award each earned move once", () => {
  const {run}=gameRuntime();
  run("newCareer('raven');");
  assert.equal(run("signContract(C,'wins')"),true);
  assert.equal(run("signContract(C,'spotlight')"),false);
  assert.equal(run("recordCareerMatch(true,2).contract"),null);
  run("saveCareer();C=loadCareer();");
  assert.equal(run("C.office.active.progress"),1);
  assert.equal(run("C.office.active.deadline"),4);
  run("book();recordCareerMatch(true,2);");
  assert.equal(run("C.office.active"),null);
  assert.equal(run("C.office.results[0].won"),true);
  assert.equal(run("cardCounts(C.collection).turnbuckle"),1);
  run("signContract(C,'wins');book();recordCareerMatch(true,2);book();recordCareerMatch(true,2);");
  assert.equal(run("cardCounts(C.collection).turnbuckle"),1);
});

test("a contract expires on its final show and a loss resets a win streak", () => {
  const {run}=gameRuntime();
  run("newCareer('brick');signContract(C,'wins');recordCareerMatch(true,2);");
  run("book();recordCareerMatch(false,2);");
  assert.equal(run("C.office.active.progress"),0);
  run("book();recordCareerMatch(false,2);book();recordCareerMatch(true,2);");
  assert.equal(run("C.office.active"),null);
  assert.equal(run("C.office.results[0].won"),false);
  assert.equal(run("C.collection.includes('turnbuckle')"),false);
});

test("a rivalry contract books the correct opponent without overriding a title match", () => {
  const {run}=gameRuntime();
  run("newCareer('brick');C.arc.foe='raven';C.arc.heat=3;signContract(C,'rivalry');C.booked=null;");
  assert.equal(run("book().id"),"raven");
  run("C.week=4;C.contenders=['brick',...C.contenders.filter(id=>id!=='brick')];C.booked=null;");
  assert.equal(run("book().title"),"main");
  assert.equal(run("book().id"),"silas");
});

test("rehab uses a segment and injuries otherwise fade after two singles bouts", () => {
  const {run}=gameRuntime();
  run("newCareer('brick');C.office.injury=2;saveCareer();C=loadCareer();");
  assert.equal(run("injuryPenalty(C)"),6);
  run("recordCareerMatch(true,3);");
  assert.equal(run("C.office.injury"),1);
  run("book();recordCareerMatch(false,3);");
  assert.equal(run("injuryPenalty(C)"),0);
  run("C.office.injury=2;");
  assert.equal(run("rehabilitate(C)"),true);
  assert.equal(run("C.segDone"),true);
  assert.equal(run("injuryPenalty(C)"),0);
});

test("embedded portrait assets bind to both the original and expanded rosters", () => {
  const loaded=script.slice(start,end).replace("/*__PORTRAITS__*/",'raven:"original",hana:"expanded"');
  const result=vm.runInNewContext(loaded+'\n[WRESTLERS.raven.img,WRESTLERS.hana.img].join(",")');
  assert.equal(result,"original,expanded");
});

test("the iPhone bridge owns its career saves while browser storage stays separate", () => {
  const saved=new Map();
  const bridge={
    getItem:key=>saved.get(key)??null,
    setItem:(key,value)=>saved.set(key,value),
  };
  const {run,memory}=gameRuntime(bridge);
  run("newCareer('brick');");
  assert.equal(JSON.parse(saved.get("rcc-career")).wid,"brick");
  assert.equal(memory.has("rcc-career"),false);
  assert.equal(gameRuntime(bridge).run("loadCareer().wid"),"brick");
});

test("partial legacy and malformed career fields recover without losing valid progress", () => {
  const {run,memory}=gameRuntime();
  run("startCareer('brick');");
  const saved=JSON.parse(memory.get("rcc-career"));
  Object.assign(saved,{week:13,w:8,l:4,peak:4,best:"bad",hypeBonus:null,hpMod:"bad",contenders:null,
    history:[null,{week:12,title:"World",wrestler:"Brick Malone",action:"won"}],
    results:[null,{week:12,opponent:"Raven",won:true,rating:4}]});
  memory.set("rcc-career",JSON.stringify(saved));
  memory.set("rcc-best","null");
  run("titleScreen();C=loadCareer();hub('records');careerJournal();");
  assert.equal(run("C.week"),13);
  assert.equal(run("C.w"),8);
  assert.equal(run("C.l"),4);
  assert.equal(run("C.peak"),4);
  assert.equal(run("C.best"),0);
  assert.equal(run("C.history.length"),1);
  assert.equal(run("C.results.length"),1);
  assert.equal(run("C.deck.length"),saved.deck.length);
});
