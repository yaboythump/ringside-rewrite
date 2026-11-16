const menuContent=$('menuContent'), menuFooter=$('menuFooter');
let screen='home', selection=HEROES[0], partner=HEROES[1], mode='standard', queue='ladder', careerEvent=null;
let selectedSlot=0, shopCategory='moves', entranceTimer;
function node(tag,label,style){
  const el=document.createElement(tag);
  if(label!==undefined) el.textContent=label;
  if(style) el.className=style;
  return el;
}
function button(label,action,{parent=menuContent,primary=false,disabled=false}={}){
  const el=node('button',label,primary?'btn':'btn ghost');
  el.type='button';el.disabled=disabled;el.onclick=action;parent.append(el);return el;
}
function line(title,description,parent=menuContent){
  const el=node('div',undefined,'menuRow');
  el.append(node('strong',title));
  if(description) el.append(node('small',description));
  parent.append(el);return el;
}
function selectField(label,items,current,action){
  const wrap=node('label',label,'field'), control=node('select');
  for(const [id,name] of items){const option=node('option',name);option.value=id;control.add(option);}
  control.value=current;control.onchange=()=>action(control.value);wrap.append(control);menuContent.append(wrap);return control;
}
function profilePicker(){
  const grid=node('div',undefined,'rosterGrid');
  for(const w of HEROES){
    const card=node('button',undefined,'rosterCard');
    const image=node('img');image.src=pic(w.img);image.alt='';
    card.append(image,node('b',w.name),node('small',w.style));
    card.setAttribute('aria-pressed',String(w===selection));
    card.onclick=()=>{
      selection=w;
      if(partner===w) partner=HEROES.find(other=>other!==w);
      renderMenu(screen);
    };
    grid.append(card);
  }
  menuContent.append(grid);
}
function setup(nextQueue,nextMode='standard',event=null){
  queue=nextQueue;mode=nextMode;careerEvent=event;
  if(event){profile.career.choice=event;persist();}
  renderMenu('setup');
}
function launchSelection(){
  if(queue==='career' && careerEvent==='defense'){
    const title=['world','arena','prospect'].find(id=>profile.career.titles[id]);
    const holder=profile.career.titles[title]?.holder;
    if(roster[holder]?.stats) selection=roster[holder];
  }
  let opponent;
  if(queue==='weekly'){
    const cup=profile.weekly;
    if(cup.eliminated||cup.round>=3) return renderMenu('weekly');
    opponent=roster[cup.opponents[cup.round]];
  } else if(queue==='career') opponent=careerOpponent(mode,careerEvent);
  else if(queue==='quick') opponent=LADDER[0];
  rung=opponent ? Math.max(0,LADDER.findIndex(w=>w.id===opponent.id)):0;
  queued={mode,queue,event:careerEvent,cup:profile.weekly?.id,opponent,partner,starter:selection};
  $('menu').hidden=true;
  entrance();
}
function entrance(){
  hero=queued.starter;
  $('entrancePic').src=pic(hero.img);
  $('entranceName').textContent=hero.name;
  $('entranceRules').textContent=rules[queued.mode][0]+' · '+rules[queued.mode][1];
  $('entrance').classList.toggle('pyro',owns('pose',hero)&&!!wrestlerData(hero).look?.pose);
  $('between').hidden=true;$('entrance').hidden=false;
  sfx.init();sfx.theme(hero);
  musicActive=true;syncMusic();
  clearTimeout(entranceTimer);entranceTimer=setTimeout(beginMatch,1550);
}
function applyLook(){
  $('pBox').classList.toggle('goldAttire',owns('attire',hero)&&!!wrestlerData(hero).look?.attire);
  board.classList.toggle('blueRopes',profile.arena);
}
function renderMenu(next){
  screen=next;menuContent.replaceChildren();menuFooter.replaceChildren();menuContent.scrollTop=0;
  $('menuBack').hidden=next==='home';
  $('menuTitle').textContent=({home:'Ringside Combo',setup:'Choose your wrestler',career:'Road to Gold',
    wrestlers:'Wrestlers',profile:'Wrestler profile',shop:'Ringside Shop',daily:'Daily challenges',
    weekly:'Weekly tournament',badges:'Achievements',settings:'Settings',stats:'Career statistics',more:'More'})[next];
  $('saveNotice').textContent=saveWarning;
  document.documentElement.classList.toggle('reducedMotion',!profile.settings.motion);
  switch(next){
  case 'home': {
    const spotlight=node('div',undefined,'spotlight');
    const mark=node('span','CTINTERACTIVE');spotlight.append(mark,node('strong','RINGSIDE'),node('b','COMBO'));
    menuContent.append(spotlight);
    for(const [name,destination] of [['Play','setup'],['Career','career'],['Wrestlers','wrestlers'],['Shop','shop']]){
      button(name,()=>destination==='setup'?setup('ladder'):renderMenu(destination),{primary:name==='Play'}).classList.add('navButton');
    }
    button('More',()=>renderMenu('more'),{parent:menuFooter});
    button('Settings',()=>renderMenu('settings'),{parent:menuFooter});
    break;
  }
  case 'more':
    for(const [label,destination] of [['Daily challenges','daily'],['Weekly tournament','weekly'],['Achievements','badges'],['Career statistics','stats']]){
      button(label,()=>renderMenu(destination)).classList.add('navButton');
    }
    break;
  case 'setup':
    if(queue==='ladder'||queue==='quick'){
      selectField('Match type',[['ladder','Championship Ladder'],...Object.entries(rules).map(([id,[name]])=>[id,name])],
        queue==='ladder'?'ladder':mode,id=>{queue=id==='ladder'?'ladder':'quick';mode=id==='ladder'?'standard':id;renderMenu('setup');});
    } else line(rules[mode][0],queue==='weekly'?'Weekly tournament':careerEvent?storyEvents[careerEvent].name:'Road to Gold');
    profilePicker();
    if(mode==='tag') selectField('Tag partner',HEROES.filter(w=>w!==selection).map(w=>[w.id,w.name]),partner.id,id=>{partner=roster[id];});
    const instructions=node('details');instructions.append(node('summary','Match rules'),node('p',rules[mode][1]));
    menuContent.append(instructions);
    button('Start Match',launchSelection,{parent:menuFooter,primary:true});
    break;
  case 'career': {
    const c=profile.career;
    const rank=Math.max(1,8-c.wins);
    line(c.wins?'Contender #'+rank:'Rookie debut',c.wins+' wins · '+c.losses+' losses · '+c.tagWins+' tag wins');
    button(c.wins?'Book next match':'Make your debut',()=>setup('career'),{primary:true});
    button('Tag title run',()=>setup('career','tag'));
    const heat=Math.max(0,...Object.values(c.rivals).map(r=>r.heat));
    if(heat>=2) button(storyEvents.rematch.name,()=>setup('career','cage','rematch'));
    if(heat>=4) button(storyEvents.ambush.name,()=>setup('career','hardcore','ambush'));
    if(['world','arena','prospect'].some(id=>c.titles[id])) button(storyEvents.defense.name,()=>setup('career','iron','defense'));
    for(const [id,title] of Object.entries(championship)){
      const held=c.titles[id];
      line(title.name,held?(roster[held.holder]?.name||'Champion')+(held.partner?' & '+roster[held.partner]?.name:'')+' · '+held.defenses+' defenses':
        'Unlock at '+title.wins+(id==='tag'?' tag wins':' singles wins'));
    }
    button('Career statistics',()=>renderMenu('stats'));
    break;
  }
  case 'wrestlers':
    profilePicker();
    button('View '+selection.name,()=>renderMenu('profile'),{parent:menuFooter,primary:true});
    break;
  case 'profile': {
    const data=wrestlerData(selection), level=levelOf(selection);
    line(selection.name+' · Level '+level,selection.style+' · '+selection.lore+' '+selection.perk);
    line('Experience',level===12?'Maximum level':(data.xp%80)+' / 80 XP until level '+(level+1));
    for(const [i,name] of attributes.entries()){
      const row=line(name+' '+stat(selection,i),['Damage','Kick-out and holds','Health and recovery','Crowd momentum'][i]);
      const price=65+data.mods[i]*35;
      button('Upgrade · '+price,()=>{if(spend(price,()=>data.mods[i]++)) renderMenu('profile');},
        {parent:row,disabled:profile.cash<price||data.mods[i]>=4||level<=data.mods[i]+1});
    }
    selectField('Signature slot',data.slots.map((id,i)=>[i,(i+1)+'. '+moves[id].name]),String(selectedSlot),
      value=>{selectedSlot=Number(value);renderMenu('profile');});
    const alternatives=Object.values(moves).filter(move=>
      profile.cards[move.id]&&(!move.only||move.only===selection.id)&&(!data.slots.includes(move.id)||data.slots[selectedSlot]===move.id));
    selectField('Equip move',alternatives.map(move=>[move.id,move.name]),data.slots[selectedSlot],id=>{
      data.slots[selectedSlot]=id;persist();renderMenu('profile');
    });
    const move=moves[data.slots[selectedSlot]];
    line(ICON[move.tile]+' '+move.name+' · Lv '+profile.cards[move.id],moveDescription(move));
    for(const key of ['attire','pose','celebration']){
      if(owns(key,selection)) button((data.look?.[key]?'Remove ':'Equip ')+cosmetics[key].name,()=>{
        data.look??={};data.look[key]=!data.look[key];persist();renderMenu('profile');
      });
    }
    break;
  }
  case 'shop':
    line(profile.cash+' cash');
    selectField('Shop department',[['moves','Move cards'],['look','Entrance, attire & arena'],['training','Wrestler upgrades']],
      shopCategory,value=>{shopCategory=value;renderMenu('shop');});
    if(shopCategory==='moves'){
      for(const move of Object.values(moves)){
        const level=profile.cards[move.id]||0;
        const row=line(ICON[move.tile]+' '+move.name+(level?' · Lv '+level:''),moveDescription(move));
        const cost=level?60+level*40:110;
        button(level>=3?'Max level':(level?'Upgrade':'Unlock')+' · '+cost,()=>{
          if(spend(cost,()=>profile.cards[move.id]=level+1)) renderMenu('shop');
        },{parent:row,disabled:level>=3||profile.cash<cost});
      }
    }else if(shopCategory==='look'){
      selectField('Wrestler',HEROES.map(w=>[w.id,w.name]),selection.id,id=>{selection=roster[id];renderMenu('shop');});
      for(const [id,item] of Object.entries(cosmetics)){
        const target=id==='arena'?null:selection,key=id+(target?'-'+target.id:'');
        const owned=owns(id,target), row=line(item.name,target?.name);
        button(owned?(id==='arena'?(profile.arena?'Remove':'Equip'):'Owned'):'Unlock · '+item.price,()=>{
          if(owned){profile.arena=!profile.arena;persist();}
          else spend(item.price,()=>{profile.cosmetics[key]=true;if(id==='arena')profile.arena=true;});
          renderMenu('shop');
        },{parent:row,disabled:owned?id!=='arena':profile.cash<item.price});
      }
    }else{
      selectField('Train wrestler',HEROES.map(w=>[w.id,w.name]),selection.id,id=>{selection=roster[id];});
      button('Open training',()=>renderMenu('profile'),{primary:true});
    }
    break;
  case 'daily': {
    events();
    const d=profile.daily;
    for(const [id,[label,goal,cash]] of Object.entries(dailyGoals)){
      const row=line(label,Math.min(goal,d.objectives[id])+' / '+goal);
      button(d.claimed[id]?'Claimed':'Claim '+cash+' cash',()=>{
        if(!d.claimed[id]&&d.objectives[id]>=goal){d.claimed[id]=true;profile.cash+=cash;persist();renderMenu('daily');}
      },{parent:row,disabled:!!d.claimed[id]||d.objectives[id]<goal});
    }
    break;
  }
  case 'weekly': {
    events();
    const cup=profile.weekly;
    line('Tournament bracket',cup.eliminated?'Eliminated for this week':cup.round===3?'Champion':'Win three rounds to earn 140 cash and unlock Lights Out.');
    cup.opponents.forEach((id,i)=>line(['Quarterfinal','Semifinal','Final'][i],roster[id].name+' · '+(i<cup.round?'Won':i===cup.round?(cup.eliminated?'Lost':'Next'):'Pending')));
    button('Enter '+['quarterfinal','semifinal','final'][cup.round],()=>setup('weekly',['standard','hardcore','cage'][cup.round]),
      {parent:menuFooter,primary:true,disabled:cup.eliminated||cup.round>=3}).hidden=cup.eliminated||cup.round>=3;
    break;
  }
  case 'badges':
    for(const [id,[label,,pay]] of Object.entries(badgeRules))line((profile.badges[id]?'🏅 ':'◇ ')+label,profile.badges[id]?'Earned':'Reward '+pay+' cash');
    break;
  case 'stats': {
    const c=profile.career,t=profile.stats;
    line('Match record',t.wins+' wins · '+t.losses+' losses · '+t.draws+' draws');
    line('Win streak',t.streak+' current · '+t.best+' best');
    for(const [id,r] of Object.entries(c.rivals)){
      if(roster[id]) line(roster[id].name,r.wins+' wins · '+r.losses+' losses · '+r.titles+' title wins · rivalry '+r.heat+'/10');
    }
    for(const record of c.history){
      if(championship[record.title]&&roster[record.opponent]) line(championship[record.title].name,record.result+' vs '+roster[record.opponent].name);
    }
    for(const record of profile.records.slice(0,12)){
      if(roster[record.wrestler]&&roster[record.opponent]&&rules[record.mode])
        line(roster[record.wrestler].name+' vs '+roster[record.opponent].name,rules[record.mode][0]+' · '+record.result);
    }
    break;
  }
  case 'settings':
    for(const [key,name] of [['music','Music volume'],['effects','Sound effects volume']]){
      const label=node('label',name,'field'), slider=node('input');
      slider.type='range';slider.min=0;slider.max=100;slider.value=profile.settings[key]*100;
      slider.oninput=()=>{profile.settings[key]=slider.value/100;sfx.sync();syncMusic();};
      slider.onchange=()=>{persist();if(key==='effects')sfx.select();};
      label.append(slider);menuContent.append(label);
    }
    for(const [key,name] of [['muted','Mute all sounds'],['motion','Animations'],['haptics','Haptics']]){
      const label=node('label',name,'field check'), control=node('input');control.type='checkbox';control.checked=profile.settings[key];
      control.onchange=()=>{
        profile.settings[key]=control.checked;persist();sfx.init();sfx.sync();syncMusic();
        document.documentElement.classList.toggle('reducedMotion',!profile.settings.motion);
      };
      label.append(control);menuContent.append(label);
    }
    break;
  }
}
function moveDescription(move){
  const effect=move.effect==='hold'?'damage and hold pressure':move.effect==='counter'?'damage and a counter guard':'damage';
  return move.category+' · '+move.rarity+' · '+move.strength+' '+effect+' · '+move.charge+' '+move.tile+' tiles · '+(move.only?roster[move.only].name:'All wrestlers');
}
$('menuBack').onclick=()=>renderMenu(screen==='profile'?'wrestlers':screen==='setup'&&queue==='career'?'career':screen==='setup'&&queue==='weekly'?'weekly':
  ['daily','weekly','badges','stats'].includes(screen)?'more':'home');
function beginMatch(){
  if($('entrance').hidden)return;
  clearTimeout(entranceTimer);$('entrance').hidden=true;start();
}
$('bellBtn').onclick=beginMatch;
$('moveBar').onclick=e=>{const move=e.target.closest('button')?.dataset.move;if(move)useSignature(move);};
$('tagBtn').onclick=()=>playerAction(()=>tagSide('p'));
$('teamBtn').onclick=()=>playerAction(()=>teamAttack('p'));
function openMenu(destination='home'){
  clearTimeout(entranceTimer);epoch++;paused=false;ended=true;busy=true;clearSel();down=null;hideHint();
  musicActive=false;syncMusic();sfx.sync();persist();
  for(const id of ['pauseMenu','entrance','between','pin'])$(id).hidden=true;
  $('menu').hidden=false;renderMenu(destination);
}
function pauseMatch(){
  if(!st||ended||overlayOpen())return;
  paused=true;clearSel();down=null;hideHint();syncMusic();sfx.sync();
  $('pauseRules').textContent=rules[st.mode][1];$('pauseMenu').hidden=false;
}
$('pauseBtn').onclick=pauseMatch;
$('resumeBtn').onclick=()=>{
  $('pauseMenu').hidden=true;paused=false;sfx.init();sfx.sync();syncMusic();ui();
  if(!busy)scheduleHint();
};
$('restartBtn').onclick=()=>{
  epoch++;paused=false;ended=true;clearSel();hideHint();$('pauseMenu').hidden=true;$('pin').hidden=true;
  $('entrance').hidden=false;musicActive=false;syncMusic();sfx.sync();entrance();
};
$('exitBtn').onclick=()=>openMenu();
$('bMenu').onclick=()=>openMenu();
$('bGo').onclick=()=>{
  if(queued.queue==='career'||queued.queue==='weekly') openMenu(queued.queue);
  else entrance();
};
document.addEventListener('visibilitychange',()=>{
  if(document.hidden){pauseMatch();if(st)persist();}
  sfx.sync();
});
