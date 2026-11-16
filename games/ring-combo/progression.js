const SAVE = 'ringcombo-profile', BACKUP = 'ringcombo-profile-backup';
const attributes = ['Power','Technique','Stamina','Charisma'];
const moves = {
  jab: ['Corner Barrage','Strike','strike',7,12,'Common','hit'],
  slam: ['Ring Rattler','Grapple','grapple',8,15,'Common','hit'],
  lock: ['Crossface Lock','Submission','grapple',9,12,'Rare','hold'],
  counter: ['Slip & Counter','Reversal','reversal',4,8,'Common','counter'],
  power: ['Concrete Driver','Power','grapple',10,22,'Epic','hit','brick'],
  flight: ['Midnight Dive','High-Flying','kick',9,20,'Epic','hit','raven'],
  bridge: ['Harlan Bridge','Submission','grapple',8,15,'Epic','hold','dutch'],
  surge: ['Voltage Surge','Finisher','show',11,22,'Epic','finish','kid'],
  cutter: ['Lights Out','Finisher','show',12,24,'Rare','finish'],
  drop: ['Springboard Drop','High-Flying','kick',9,18,'Rare','hit'],
  lariat: ['Breakaway Lariat','Power','strike',10,20,'Rare','hit'],
};
for (const [id, [name,category,tile,charge,strength,rarity,effect,only]] of Object.entries(moves)) {
  moves[id] = {id,name,category,tile,charge,strength,rarity,effect,only};
}
const signatures = {brick:'power',raven:'flight',dutch:'bridge',kid:'surge'};
const cosmetics = {
  attire:{name:'Gold ring gear',price:140},
  pose:{name:'Pyro entrance',price:145},
  celebration:{name:'Gold confetti',price:150},
  arena:{name:'Electric Blue Ropes',price:180},
};
const badgeRules = {
  debut:['First Bell',p=>p.stats.wins>=1,30],
  streak:['On a Roll',p=>p.stats.best>=3,60],
  cards:['Move Collector',p=>Object.keys(p.cards).length>=10,70],
  gold:['Gold Standard',p=>!!p.career.titles.world,125],
  bracket:['Tournament Champion',p=>p.stats.cups>=1,85],
  team:['Perfect Tandem',p=>!!p.career.titles.tag,95],
};
const newSave = () => ({
  version:1,cash:80,settings:{music:0.38,effects:0.8,motion:true,haptics:true,muted:read('ringcombo-muted')==='1'},
  wrestlers:{},cards:Object.fromEntries(['jab','slam','counter',...Object.values(signatures)].map(id=>[id,1])),
  cosmetics:{},arena:false,career:{wins:0,losses:0,tagWins:0,titles:{},history:[],rivals:{},choice:null},
  stats:{wins:0,losses:0,draws:0,streak:0,best:0,cups:0},badges:{},records:[],
  daily:null,weekly:null,played:0,
});
function read(key){try{return (window.RingsideNative ?? localStorage).getItem(key)}catch{return null}}
function write(key,value){(window.RingsideNative ?? localStorage).setItem(key,value)}
const dailyGoals = {
  wins:['Win two matches',2,50],moves:['Activate three signature moves',3,45],special:['Win a stipulation match',1,55]
};
function decode(raw){
  try {
    const value = JSON.parse(raw);
    if (!value || typeof value!=='object' || Array.isArray(value)) return null;
    if (value.version!==1 || !Number.isSafeInteger(value.cash) || value.cash<0) return null;
    const defaults = newSave();
    for (const key of ['settings','wrestlers','cards','cosmetics','career','stats','badges']) {
      const section = value[key];
      value[key]={...defaults[key],...(section && typeof section==='object' && !Array.isArray(section) ? section : {})};
    }
    for (const key of ['titles','rivals']) {
      if (!value.career[key] || typeof value.career[key]!=='object' || Array.isArray(value.career[key])) value.career[key]={};
    }
    if (!Array.isArray(value.career.history)) value.career.history=[];
    if (!Array.isArray(value.records)) value.records=[];
    if (!Number.isFinite(value.played) || value.played<0) value.played=0;
    for (const [id,entry] of Object.entries(value.wrestlers)) {
      if (!roster[id]?.stats || !entry || !Number.isFinite(entry.xp) || !Array.isArray(entry.mods) ||
        entry.mods.length!==4 || !entry.mods.every(mod=>Number.isInteger(mod) && mod>=0 && mod<=4) ||
        !Array.isArray(entry.slots) || entry.slots.length!==4 ||
        !entry.slots.every(slot=>moves[slot] && value.cards[slot] && (!moves[slot].only || moves[slot].only===id))) delete value.wrestlers[id];
    }
    for (const key of ['music','effects']){
      const volume=value.settings[key];
      value.settings[key]=Number.isFinite(volume)?Math.min(1,Math.max(0,volume)):defaults.settings[key];
    }
    for(const [id,level] of Object.entries(value.cards)){
      if(!moves[id]) delete value.cards[id];
      else if(!Number.isInteger(level) || level<1 || level>3) value.cards[id]=defaults.cards[id]||1;
    }
    for(const section of ['stats','career']){
      for(const [key,score] of Object.entries(defaults[section])){
        if(typeof score==='number' && (!Number.isSafeInteger(value[section][key])||value[section][key]<0)) value[section][key]=score;
      }
    }
    for(const [id,rival] of Object.entries(value.career.rivals)){
      if(!roster[id]?.tricks || !rival || !Number.isFinite(rival.heat)) delete value.career.rivals[id];
    }
    for(const [id,title] of Object.entries(value.career.titles)){
      if(!championship[id] || !roster[title?.holder]?.stats) delete value.career.titles[id];
    }
    if (!(Number.isInteger(value.daily?.id) && Number.isFinite(value.daily?.opened) &&
          value.daily?.claimed && Object.keys(dailyGoals).every(id=>Number.isFinite(value.daily?.objectives?.[id])))) value.daily=null;
    if (!(Array.isArray(value.weekly?.opponents) && value.weekly.opponents.every(id=>roster[id]?.tricks) &&
        value.weekly.opponents.length===3 && Number.isInteger(value.weekly?.id) && Number.isFinite(value.weekly.opened) &&
        Number.isInteger(value.weekly.round) && value.weekly.round>=0 && value.weekly.round<=3)) value.weekly=null;
    return {...defaults,...value};
  }catch{return null}
}
let savedSnapshot=read(SAVE);
const current=decode(savedSnapshot);
const recovered=current || decode(read(BACKUP));
let saveWarning=savedSnapshot && !current ? (recovered?'Recovered your last backup.':'Save could not be read. Existing data is preserved.') : '';
let saveLocked=!!savedSnapshot && !recovered;
let profile=recovered || newSave();
function warnSave(message){
  saveWarning=message;
  $('saveNotice').textContent=message;
}
function persist(){
  if(saveLocked) return false;
  try {
    const old=read(SAVE);
    if(old!==savedSnapshot){
      saveLocked=true;
      warnSave('Another session changed your save. Reopen the game to continue saving.');
      return false;
    }
    if(old && decode(old)) write(BACKUP,old);
    const updated=JSON.stringify(profile);
    write(SAVE,updated);
    savedSnapshot=updated;
    return true;
  } catch {
    warnSave('Storage unavailable. Progress is available for this session.');
    return false;
  }
}
document.addEventListener('ringside-save-error',()=>{
  saveWarning='iPhone storage write failed. Progress may only last this session.';
  $('saveNotice').textContent=saveWarning;
});
function wrestlerData(w){
  return profile.wrestlers[w.id] ??= {xp:0,mods:[0,0,0,0],slots:['jab','slam','counter',signatures[w.id]],look:{}};
}
const levelOf = w => Math.min(12,1+Math.floor(wrestlerData(w).xp/80));
const stat = (w,i) => w.stats ? w.stats[i]+wrestlerData(w).mods[i] : 3;
const owns = (key,w) => !!profile.cosmetics[key+(w ? '-'+w.id : '')];
function spend(cost,action){
  if (profile.cash<cost) return false;
  profile.cash-=cost;
  action();
  awardBadges();
  persist();
  return true;
}
function awardBadges(){
  for (const [id,[,condition,pay]] of Object.entries(badgeRules)){
    if (!profile.badges[id] && condition(profile)){
      profile.badges[id]=true;
      profile.cash+=pay;
    }
  }
}

const DAY = 86400000;
function events(){
  const day=Math.floor(Date.now()/DAY);
  const week=Math.floor((day+3)/7);
  // Never roll back an event or mint repeat prizes. Advancing an offline clock
  // also requires a new block of active play since the last event opened.
  if (!profile.daily || (day>profile.daily.id && profile.played-profile.daily.opened>=1200)){
    profile.daily={id:day,opened:profile.played,objectives:{wins:0,moves:0,special:0},claimed:{}};
    persist();
  }
  if (!profile.weekly || (week>profile.weekly.id && profile.played-profile.weekly.opened>=3600)){
    const offset=((week%4)+4)%4;
    profile.weekly={id:week,opened:profile.played,round:0,eliminated:false,opponents:[0,1,2].map(i=>LADDER[(offset+i)%4].id)};
    persist();
  }
}
const storyEvents = {
  rematch:{name:'Settle the score',description:'A familiar rival wants a rematch. Meet them in a Steel Cage.',mode:'cage',bonus:45},
  ambush:{name:'Payback in the ring',description:'Your rival jumps you before the bell. Start hurt and fight back under Hardcore rules.',mode:'hardcore',bonus:65},
  defense:{name:'Fight for your title',description:'Put your latest title on the line in an Iron Man defense.',mode:'iron',bonus:95},
};
function contenderTitle(mode){
  const c=profile.career;
  return Object.keys(championship).find(id=>{
    const tag=id==='tag';
    return tag===(mode==='tag') && (tag?c.tagWins:c.wins)>=championship[id].wins-1 && !c.titles[id];
  });
}
function careerOpponent(mode,choice,title){
  const c=profile.career;
  const rival=Object.entries(c.rivals).filter(([id])=>roster[id]?.tricks)
    .sort((a,b)=>b[1].heat-a[1].heat)[0];
  const wins=mode==='tag'?c.tagWins:c.wins;
  const ladderOpponent=LADDER[Math.min(3,Math.floor(wins/2))];
  const champions={prospect:'tank',arena:'ox',world:'silas',tag:'ox'};
  const base=title ? roster[champions[title]] : choice && rival ? roster[rival[0]] : ladderOpponent;
  return {...base,hp:base.hp+Math.min(20,wins*2),smart:Math.min(1,base.smart+wins*0.04)};
}
function titleChange(id,result,reason){
  const c=profile.career;
  if (!id) return;
  c.titles[id]=result==='Lost'?null:{holder:st.originalHero,partner:st.mode==='tag'?st.teams.p[1].wrestler.id:null,defenses:(c.titles[id]?.defenses||0)+(result==='Defended'?1:0)};
  c.history.unshift({title:id,result,opponent:st.originalOpponent,reason});
  c.history=c.history.slice(0,60);
}
function settleCareer(result){
  const c=profile.career, id=st.originalOpponent;
  const rival=c.rivals[id] ??= {wins:0,losses:0,titles:0,heat:0,meetings:0};
  rival.meetings++;
  rival.heat=Math.min(10,rival.heat+(result==='win'?1:2));
  const defend=st.event==='defense' ? ['world','arena','prospect'].find(id=>c.titles[id]) : null;
  if (result==='lose'){
    c.losses++; rival.losses++;
    if (defend) {titleChange(defend,'Lost','Title defense');rival.titles++;}
    return defend ? 'The title changed hands.' : '';
  }
  if (result!=='win') return '';
  rival.wins++;
  if (st.mode==='tag') c.tagWins++; else c.wins++;
  const title=st.titleChallenge;
  if (defend || title){
    const id=defend || title;
    titleChange(id,defend?'Defended':'Won',defend?'Title defense':'Career milestone');
    rival.titles++; profile.cash+=defend?90:75;
    st.titleWon=id;
    return (defend?'Title defended · ':'New champion · ')+championship[id].name;
  }
  if ([1,3,5,9,12].includes(c.wins) && st.mode!=='tag') profile.cash+=35;
  return c.wins===1?'Rookie debut won. Climb the contender rankings.':'';
}
function settleResult(result){
  const won=result==='win', stats=profile.stats;
  events();
  const before=profile.cash;
  if (won){stats.wins++;stats.streak++;stats.best=Math.max(stats.best,stats.streak);profile.cash+=st.mode==='standard'?26:34;}
  else {stats[result==='draw'?'draws':'losses']++;stats.streak=0;}
  const competitors=st.mode==='tag'?st.teams.p.map(member=>member.wrestler):[hero];
  for (const w of competitors) wrestlerData(w).xp+=won?40:18;
  const goals=profile.daily.objectives;
  goals.moves+=st.signatureUses;
  if (won){goals.wins++;if(st.mode!=='standard') goals.special++;}
  let note='';
  if (st.queue==='career'){
    note=settleCareer(result);
    if(won && storyEvents[st.event]) profile.cash+=storyEvents[st.event].bonus;
    profile.career.choice=null;
  }
  if (st.queue==='weekly' && profile.weekly.id===st.cup){
    if (won && ++profile.weekly.round===3){profile.cash+=140;stats.cups++;profile.cards.cutter??=1;note='Weekly champion · Lights Out unlocked';}
    if (!won) profile.weekly.eliminated=true;
  }
  profile.records.unshift({wrestler:st.originalHero,opponent:st.originalOpponent,mode:st.mode,result});
  profile.records=profile.records.slice(0,60);
  awardBadges();
  persist();
  return {cash:profile.cash-before,note};
}
