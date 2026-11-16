// Stable IDs and lore are portable to other Ringside games.
const roster = {
  brick:{name:'Brick Malone',style:'Powerhouse',perk:'Grapples hit 50% harder',mod:{grapple:1.5},stats:[5,2,4,2],lore:'A blue-collar brawler who makes the ring shake.'},
  raven:{name:'Raven Vega',style:'High-Flyer',perk:'Clotheslines deal +8 damage',mod:{line:8},stats:[2,4,3,4],lore:'A fearless aerial specialist who lives for the top rope.'},
  dutch:{name:'Dutch Harlan',style:'Technician',perk:'Can pin below 40% health',mod:{pinAt:0.4},stats:[3,5,3,2],lore:'The veteran who can turn any opening into a wrestling hold.'},
  kid:{name:'Kid Voltage',style:'Showman',perk:'Crowd builds 50% faster',mod:{crowd:1.5},stats:[2,3,3,5],lore:'An arena favorite who gets stronger when the crowd gets loud.'},
  jett:{name:'Jett Romano',hp:90,power:0.8,smart:0.35,tricks:['guard'],trickEvery:4,clock:15,lore:'A quick-footed prospect who hides behind a tight guard.'},
  tank:{name:'Tank Ferro',hp:110,power:1,smart:0.6,tricks:['chair'],trickEvery:3,clock:13,lore:'The big hitter who keeps a chair within arm’s reach.'},
  ox:{name:'Big Ox Duggan',hp:130,power:1.25,smart:0.8,tricks:['guard','chair'],trickEvery:3,clock:12,lore:'A veteran enforcer who wears down every challenger.'},
  silas:{name:'Silas Crowe',hp:150,power:1.15,smart:1,tricks:['knux','guard','chair'],trickEvery:2,clock:10,lore:'A calculating champion with a reputation for dirty finishes.'},
};
for (const [id, wrestler] of Object.entries(roster)) Object.assign(wrestler,{id,img:id+'.jpg'});
const HEROES = Object.values(roster).filter(wrestler => wrestler.stats);
const LADDER = Object.values(roster).filter(wrestler => wrestler.tricks);
const championship = {
  prospect:{name:'Prospect Championship',wins:2},
  arena:{name:'Arena Championship',wins:4},
  world:{name:'Ringside World Championship',wins:7},
  tag:{name:'Ringside Tag Team Championship',wins:3},
};
