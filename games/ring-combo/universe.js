// Combo combat rules layered over the shared Ringside identities.
const universe = /*__UNIVERSE_DATA__*/;
const roster = {
  brick:{style:'Powerhouse',perk:'Grapples hit 50% harder',mod:{grapple:1.5},stats:[5,2,4,2]},
  raven:{style:'High-Flyer',perk:'Clotheslines deal +8 damage',mod:{line:8},stats:[2,4,3,4]},
  dutch:{style:'Technician',perk:'Can pin below 40% health',mod:{pinAt:0.4},stats:[3,5,3,2]},
  kid:{style:'Showman',perk:'Crowd builds 50% faster',mod:{crowd:1.5},stats:[2,3,3,5]},
  jett:{hp:90,power:0.8,smart:0.35,tricks:['guard'],trickEvery:4,clock:15},
  tank:{hp:110,power:1,smart:0.6,tricks:['chair'],trickEvery:3,clock:13},
  ox:{hp:130,power:1.25,smart:0.8,tricks:['guard','chair'],trickEvery:3,clock:12},
  silas:{hp:150,power:1.15,smart:1,tricks:['knux','guard','chair'],trickEvery:2,clock:10},
};
for (const [id, wrestler] of Object.entries(roster)) Object.assign(wrestler,universe.characters[id],{id,img:id+'.jpg'});
const HEROES = Object.values(roster).filter(wrestler => wrestler.stats);
const LADDER = Object.values(roster).filter(wrestler => wrestler.tricks);
const championship = {
  prospect:{...universe.championships.prospect,wins:2},
  arena:{...universe.championships.arena,wins:4},
  world:{...universe.championships.world,wins:7},
  tag:{...universe.championships.tag,wins:3},
};
