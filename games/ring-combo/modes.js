const rules = {
  standard:['Singles','Win by pinfall. Match 4 for a Clothesline and 5 for a finisher.'],
  cage:['Steel Cage','Match Showboat tiles to climb. Escape at 100% when your rival is below half health. Strikes pull climbers down.'],
  hardcore:['Hardcore','Match weapons for heavy damage. Chairs and brass knucks are legal. Win by pinfall.'],
  submission:['Submission','Build hold pressure with Grapple tiles. At 100%, lock in the hold. The defender must match Recover or Reversal tiles to escape.'],
  iron:['Iron Man','Two minutes. Score the most pinfalls. Both wrestlers recover after each fall. A tie is a draw.'],
  last:['Last Man Standing','Drop your opponent to zero health. A downed wrestler must clear tiles to beat the ten-count.'],
  tag:['Tag Team','Tag to rest and recover. Build team momentum by matching tiles. Win by pinfall.'],
};
const opposite = side => side==='p'?'o':'p';
const hpKey = side => side+'hp';
const maxKey = side => side+'max';
const weak = side => st[hpKey(side)] <= st[maxKey(side)]/2;
const tilePool = () => st?.mode==='hardcore' ? [...TYPES,'weapon'] : TYPES;
let queued={mode:'standard',queue:'ladder'};
function initMode(){
  Object.assign(st,{
    mode:queued.mode,queue:queued.queue,event:queued.event,cup:queued.cup,
    originalOpponent:st.opp.id,originalHero:hero.id,titleChallenge:queued.titleChallenge,signatureUses:0,climb:{p:0,o:0},
    pressure:{p:0,o:0},reversal:{p:0,o:0},rope:{p:1,o:1},falls:{p:0,o:0},
    remaining:120,downed:null,recovery:null,teamMomentum:{p:0,o:0},
    charge:{},active:{p:0,o:0},teams:null,
  });
  if(st.event==='ambush'){st.php-=20;sfx.chair();}
  if(st.mode==='tag'){
    const opponent=st.opp;
    const rival=LADDER[(LADDER.findIndex(w=>w.id===opponent.id)+1)%LADDER.length];
    const member=(w,hp)=>({wrestler:w,hp,max:hp,stamina:100});
    st.teams={p:[member(hero,st.pmax),member(queued.partner,100+stat(queued.partner,2)*2)],
      o:[member(opponent,st.omax),member(rival,rival.hp)]};
  }
  $('app').dataset.mode=st.mode;
}
function damage(target,value,type='hit'){
  if(value<=0) return 0;
  if (st.reversal[target] && type==='finish') {
    st.reversal[target]=0;
    value=0;
    st[hpKey(opposite(target))]-=7;
    sfx.guard(); haptic(24);
    say('<b>FINISHER COUNTERED!</b>');
  } else if(st.reversal[target]) {
    value*=0.45;
    st.reversal[target]=0;
    sfx.guard();
  }
  st[hpKey(target)]-=value;
  if (value>0){shake(target+'Box');fx('-'+Math.round(value),'#ff6b80',1,target==='p'?1:5);}
  return value;
}
function chargeTiles(t, side){
  if(side!=='p') return;
  const meter=st.charge[hero.id] ??= {};
  for(const id of wrestlerData(hero).slots){
    const move=moves[id];
    meter[id]=Math.min(move.charge,(meter[id]||0)+(t[move.tile]||0));
  }
}
function modeTally(t,who,blocks,tiles){
  const defender=opposite(who);
  if(st.recovery && who===st.recovery.side){
    st.recovery.got+=(t.heal+t.reversal)*2+t.kick;
    return true;
  }
  if(st.downed && who===st.downed.side){st.downed.got+=tiles;return true}
  chargeTiles(t,who);
  if(st.mode==='cage'){
    st.climb[who]=Math.min(100,st.climb[who]+t.show*9);
    st.climb[defender]=Math.max(0,st.climb[defender]-t.strike*3-t.kick*2);
    if (t.show) sfx.cage();
  }
  if(st.mode==='submission'){
    st.pressure[who]=Math.min(100,st.pressure[who]+t.grapple*9);
    st.pressure[defender]=Math.max(0,st.pressure[defender]-t.heal*4-t.reversal*5);
  }
  if(st.mode==='tag'){
    const active=st.teams[who][st.active[who]], partner=st.teams[who][1-st.active[who]];
    active.stamina=Math.min(100,Math.max(0,active.stamina-7+t.heal*5));
    partner.stamina=Math.min(100,partner.stamina+5);
    partner.hp=Math.min(partner.max,partner.hp+2);
    st.teamMomentum[who]=Math.min(100,st.teamMomentum[who]+t.show*7+t.grapple*4+3);
  }
  if(t.weapon|| (st.mode==='hardcore' && blocks)){
    damage(defender,t.weapon*6+blocks*5);sfx.chair();haptic(20);
  }
  return false;
}
const activeStamina = side => st.teams ? 0.75+st.teams[side][st.active[side]].stamina/400 : 1;
function tagSide(side){
  const team=st.teams[side], old=team[st.active[side]], next=team[1-st.active[side]];
  if(next.hp<=0) return false;
  old.hp=st[hpKey(side)];
  old.stamina=Math.max(0,old.stamina-8);
  st.active[side]=1-st.active[side];
  st[hpKey(side)]=next.hp;
  st[maxKey(side)]=next.max;
  if(side==='p') hero=next.wrestler;
  else {st.opp=next.wrestler;st.trickIn=st.opp.trickEvery;st.nextTrick=pickOne(st.opp.tricks);st.guard=false;}
  $('pImg').src=pic(hero.img);$('pName').textContent=hero.name;
  $('oImg').src=pic(st.opp.img);$('oName').textContent=st.opp.name;
  applyLook();
  sfx.tag();say('<b>TAG!</b> '+next.wrestler.name+' enters fresh.');
  return true;
}
function teamAttack(side){
  const target=opposite(side);
  const value=st.teamMomentum[side]>=100 ? 38 : 21;
  st.teamMomentum[side]-=value===38?100:60;
  const landed=damage(target,value,value===38?'finish':'hit');
  sfx.finisher();haptic(35);
  if(!landed) return;
  if(side==='p' && value===38) st.finUsed=true;
  say(value===38?'<b>TEAM FINISHER!</b>':'<b>DOUBLE-TEAM ATTACK!</b>');
}
function matchReady(){
  return st && !ended && !busy && !overlayOpen() && st.turn==='p' && !st.kick && !st.pin && !st.downed && !st.recovery;
}
function playerAction(action){
  if(!matchReady()) return;
  busy=true;hideHint();clearSel();
  action();
  ui();
  runTurn(endPlayerTurn());
}
function useSignature(id){
  if(!matchReady()) return;
  const move=moves[id], meter=st.charge[hero.id];
  if(!wrestlerData(hero).slots.includes(id) || !meter || meter[id]<move.charge) return;
  playerAction(()=>{
    meter[id]=0;st.signatureUses++;
    const strength=move.strength+(profile.cards[id]-1)*3;
    say('<b>'+move.name+'!</b>');
    if(move.effect==='counter'){
      st.reversal.p=1;
      damage('o',strength);sfx.guard();
    } else if(move.effect==='hold'){
      if(st.mode==='submission') st.pressure.p=Math.min(100,st.pressure.p+strength*2);
      else clockLeft+=2;
      damage('o',strength+stat(hero,1));sfx.grapple();
    } else {
      if(move.effect==='finish'){
        st.guard=false;
        st.finUsed=!!damage('o',strength+stat(hero,0),'finish');
        sfx.finisher();haptic(28);
      } else {damage('o',strength+Math.floor(stat(hero,0)/2));sfx[move.tile]();}
    }
  });
}
function showMode(){
  const mode=st.mode, panel=$('stipulation'), player=st.teams?.p[st.active.p], partner=st.teams?.p[1-st.active.p];
  panel.textContent=({
    standard:'',
    cage:'ESCAPE  You '+st.climb.p+'% · Rival '+st.climb.o+'%',
    hardcore:'NO DQ · Weapon matches deal extra damage',
    submission:'HOLD  You '+st.pressure.p+'% · Rival '+st.pressure.o+'%',
    iron:'IRON MAN  '+Math.ceil(st.remaining)+'s · Falls '+st.falls.p+'–'+st.falls.o,
    last:'LAST MAN STANDING · Beat the ten-count',
    tag:player?'TEAM '+st.teamMomentum.p+'% · '+Math.round(player.stamina)+' stamina · '+first(partner.wrestler.name)+' '+Math.max(0,Math.round(partner.hp))+' HP':''
  })[mode];
  panel.hidden=!panel.textContent;
  const lock=!matchReady();
  const equipped=wrestlerData(hero).slots;
  $('moveBar').querySelectorAll('button').forEach((button,i)=>{
    const move=moves[equipped[i]];
    const amount=st.charge[hero.id]?.[move.id]||0;
    const label=move.name+' · '+ICON[move.tile]+' '+amount+'/'+move.charge;
    if(button.textContent!==label) button.textContent=label;
    button.disabled=lock||amount<move.charge;
    button.dataset.move=move.id;
  });
  $('tagTools').hidden=mode!=='tag';
  if(mode==='tag'){
    $('tagBtn').textContent='Tag '+first(partner.wrestler.name);
    $('tagBtn').disabled=lock||partner.hp<=0;
    $('teamBtn').textContent=st.teamMomentum.p>=100?'Team finisher':'Double-team';
    $('teamBtn').disabled=lock||st.teamMomentum.p<60;
  }
  if(st.recovery||st.downed) showRecovery();
}
function showRecovery(){
  const hold=st.recovery, challenge=hold||st.downed;
  $('pin').hidden=false;
  $('pinCount').textContent=hold?'TAP OUT?':challenge.count?String(challenge.count):'DOWN!';
  $('pinNeed').textContent=(challenge.side==='p'?'You':'Rival')+' · '+Math.min(challenge.got,challenge.need)+' / '+challenge.need+
    (hold?' escape points · '+challenge.turns+' moves left':' recovery points');
}
function beginRecovery(side,hold){
  const action=hold?{side,got:0,need:side==='p'?8:10,turns:2}:{side,got:0,need:9+(st.recoveries?.[side]||0)*4,time:10,count:0};
  if(hold){st.recovery=action;sfx.hold();}
  else {st.downed=action;st[hpKey(side)]=0;sfx.knuxBoom();}
  say(hold?'<b>SUBMISSION LOCKED!</b> Match Recover, Reversal or Kick to break the hold.':
    '<b>DOWN FOR THE COUNT!</b> Clear tiles before ten.');
  showRecovery();
}
function finishRecovery(wonEscape,hold){
  const action=hold?st.recovery:st.downed,side=action.side;
  st.recovery=null;st.downed=null;$('pin').hidden=true;
  if(!wonEscape){if(!hold)sfx.refCount(10);return finishMatch(opposite(side)==='p'?'win':'lose',hold?'Submission':'Ten-count knockout');}
  st[hpKey(side)]=Math.max(st[hpKey(side)],hold?20:26);
  st.pressure[opposite(side)]=0;
  if(!hold){st.recoveries??={p:0,o:0};st.recoveries[side]++;}
  sfx.kickout();say(hold?'<b>THE HOLD IS BROKEN!</b>':'<b>BACK ON THEIR FEET!</b>');
}
function ironExpired(){
  if(st.mode!=='iron'||st.remaining>0) return false;
  const {p,o}=st.falls;
  finishMatch(p===o?'draw':p>o?'win':'lose','Time expired · '+p+'–'+o);
  return true;
}
function scoreFall(side){
  if(st.mode!=='iron'){finishMatch(side==='p'?'win':'lose','Pinfall');return;}
  st.falls[side]++;
  st.php=st.pmax;st.ohp=st.omax;st.kick=null;st.pin=null;st.guard=false;st.kickouts=0;st.crowd=0;
  st.rope={p:1,o:1};st.reversal={p:0,o:0};
  fillFresh();sfx.bellStart();say('<b>FALL SCORED!</b> '+st.falls.p+'–'+st.falls.o);
  if(!ironExpired()) yourTurn();
}
function advanceSpecial(side){
  const target=opposite(side);
  if(st.mode==='cage' && weak(target) && st.climb[side]>=100){
    finishMatch(side==='p'?'win':'lose','Escaped the Steel Cage');sfx.cage();return true;
  }
  if(st.mode==='last' && st[hpKey(target)]<=0){beginRecovery(target,false);return true;}
  if(st.mode==='submission' && (st.pressure[side]>=100 || st[hpKey(target)]<=0)){
    beginRecovery(target,true);return true;
  }
  return false;
}
async function rivalRecovery(){
  while((st.recovery||st.downed)?.side==='o'&&!ended){
    const challenge=st.recovery||st.downed;
    const mv=aiPick();
    if(mv) await doSwap(...mv[0],...mv[1],'o');
    if(challenge.got>=challenge.need){finishRecovery(true,!!st.recovery);break;}
    if(st.recovery){
      if(--challenge.turns<=0){finishRecovery(false,true);break;}
    } else {
      for(let i=0;i<3&&challenge.count<10;i++){
        challenge.count++;challenge.time=10-challenge.count;
        if(challenge.count<10)sfx.refCount(challenge.count);
        showRecovery();await sleep(380);
      }
      if(challenge.count>=10){finishRecovery(false,false);break;}
    }
    if(!findMove('o')) fillFresh();
  }
  yourTurn();
}
