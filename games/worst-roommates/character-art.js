// WORST ROOMMATES EVER: original vector cast. Offline, scalable, no external assets.
// The vector fallback doubles as the portrait renderer until custom sprite PNGs arrive.
const AVATAR_STYLES={
  dex:{skin:'#9c5b38',hair:'#1b121a',shirt:'#fd4e91',pants:'#273253',shoe:'#ffffff',eye:'#1d1318'},
  brenda:{skin:'#c47a4d',hair:'#3a2027',shirt:'#ff993a',pants:'#be6a4b',shoe:'#ffccab',eye:'#20151b'},
  gary:{skin:'#edbb8b',hair:'#655040',shirt:'#79caff',pants:'#3f4a59',shoe:'#433f45',eye:'#251b1a'},
  priya:{skin:'#a66a43',hair:'#1b1723',shirt:'#81d476',pants:'#252c42',shoe:'#f4e7cb',eye:'#241927'},
  moose:{skin:'#ba825b',hair:'#302227',shirt:'#aa80ef',pants:'#414866',shoe:'#f1f1f6',eye:'#231522'},
  luna:{skin:'#d49b6b',hair:'#34253b',shirt:'#ffde46',pants:'#3e5069',shoe:'#fd618e',eye:'#21172b'},
  kyle:{skin:'#d9aa83',hair:'#624538',shirt:'#8d9aa5',pants:'#343e53',shoe:'#a8b6c4',eye:'#281a1a'},
  fenwick:{skin:'#d9a788',hair:'#a9a8ac',shirt:'#ede5da',pants:'#53566a',shoe:'#2b2636',eye:'#1c1c23'}
};
const AVATAR_PORTRAITS={};
function drawRoommate(g,c,x,y,size,walk){
  const key=artKey(c),a=AVATAR_STYLES[key]||AVATAR_STYLES.gary;
  const moving=!!(c.path&&c.path.length),step=moving?Math.sin(walk||0)*3:0;
  const alert=!!(c.flee>0),moose=key==='moose';
  g.save();g.translate(x,y);g.scale(size||1,size||1);g.lineCap='round';g.lineJoin='round';
  // Tiny 3/4-view character rigs: legs, articulated arms, torso, neck, face and costume.
  function pill(px,py,w,h,r,fill,stroke){
    g.beginPath();g.roundRect(px,py,w,h,r);g.fillStyle=fill;g.fill();
    if(stroke!==false){g.strokeStyle='#1c1423';g.lineWidth=1.7;g.stroke();}
  }
  function oval(px,py,rx,ry,fill,stroke){
    g.beginPath();g.ellipse(px,py,rx,ry,0,0,Math.PI*2);g.fillStyle=fill;g.fill();
    if(stroke){g.strokeStyle='#1c1423';g.lineWidth=1.6;g.stroke();}
  }
  function poly(points,fill,stroke){
    g.beginPath();g.moveTo(points[0][0],points[0][1]);for(let i=1;i<points.length;i++)g.lineTo(points[i][0],points[i][1]);g.closePath();
    g.fillStyle=fill;g.fill();if(stroke!==false){g.strokeStyle='#1c1423';g.lineWidth=1.7;g.stroke();}
  }
  function line(points,color,width){
    g.beginPath();g.moveTo(points[0][0],points[0][1]);for(let i=1;i<points.length;i++)g.lineTo(points[i][0],points[i][1]);
    g.strokeStyle=color;g.lineWidth=width;g.stroke();
  }
  // Legs and shoes. The movement animation is part of each character, not a moving circle.
  pill(-7,0+step*.5,6.4,11,2,a.pants);
  pill(1,-step*.5,6.4,11,2,a.pants);
  pill(-8,8+step*.7,8.5,4.8,2.2,a.shoe);
  pill(.3,8-step*.7,8.5,4.8,2.2,a.shoe);
  // Arms with hands, including walk swing and oversized Moose shoulders.
  const width=moose?13:10.5;
  const armSwing=step*.6;
  line([[-width,-12],[-width-2,-4+armSwing],[-width,-1+armSwing]],a.shirt,6.3);
  line([[width,-12],[width+2,-4-armSwing],[width,-1-armSwing]],a.shirt,6.3);
  oval(-width,-.5+armSwing,3.2,3.7,a.skin,true);
  oval(width,-.5-armSwing,3.2,3.7,a.skin,true);
  // Outfits: all bodies have clothing with neck, sleeves, and distinct silhouettes.
  poly([[-9.6,-14],[-5,-16],[5,-16],[9.6,-14],[moose?10:8.3,2],[-(moose?10:8.3),2]],a.shirt,true);
  oval(0,-14.4,3.6,2.1,a.skin,false);
  line([[-8,1.5],[8,1.5]],'#271d31',1);
  if(key==='dex'){
    poly([[-7,-12],[0,-9],[7,-12],[5,-4],[-5,-4]],'#f979ac',false);
    line([[-2,-13],[-2,-7]],'#ffe6ec',1.2);line([[2,-13],[2,-7]],'#ffe6ec',1.2);
    pill(-8,-4,16,3,1,'#e73f7c',false);
  }else if(key==='brenda'){
    poly([[0,-15],[4,-13],[2,1],[0,1],[-3,-13]],'#d3682e',false);
    line([[0,-13],[0,0]],'#ffda97',1.1);
    pill(5,-4,10,6,2,'#75808c',true); // Kyle's hoodie never leaves her hand.
  }else if(key==='gary'){
    line([[-6,-12],[0,-9],[6,-12]],'#d3f1ff',2);
    line([[0,-9],[0,1]],'#5796bd',1.1);
    pill(2,-2,3,2,0.5,'#d5edff',false);
    line([[-6,-2],[-3,-2]],'#517d9e',1);
  }else if(key==='priya'){
    pill(-5,-12,10,13,1,'#e7eddc',false);
    line([[-5,-13],[-5,0]],'#4f9f68',1.4);
    line([[5,-13],[5,0]],'#4f9f68',1.4);
    pill(7,-5,7,8,1,'#fff16c',true); // sticky-note pad
    line([[8,-2],[12,-2]],'#d18f38',.8);
  }else if(key==='moose'){
    oval(0,-6,8.2,7.2,'#b18ae7',false);
    line([[-4,-13],[-4,-6]],'#e8d6ff',1.6);
    line([[4,-13],[4,-6]],'#e8d6ff',1.6);
    oval(10,-1,3.5,2,'#f6b44f',true); // drumstick
    oval(13,-3,2.2,2.5,'#d9a477',true);
  }else if(key==='luna'){
    line([[-6,-12],[-3,-3]],'#fff5a3',1);
    line([[6,-12],[3,-3]],'#fff5a3',1);
    pill(-4,-6,8,6,1,'#f6ba3b',false);
    line([[0,-13],[0,1]],'#de9c27',1.5);
  }else if(key==='kyle'){
    pill(-6,-9,12,6,1,'#a2afb8',false);
    pill(8,-3,5,8,1,'#2b354b',true); // phone
    pill(9,-2,3,4,0.5,'#5faaf4',false);
  }else if(key==='fenwick'){
    pill(-6,-13,12,14,1,'#f8f2e8',false);
    poly([[-3,-13],[0,-10],[3,-13],[2,0],[-2,0]],'#c6b8c0',false);
    pill(8,-6,8,11,1,'#a97c48',true); // rent clipboard
    pill(10,-4,4,1,0.3,'#fff8e5',false);
  }
  // Face with ears and hairline; personality is communicated by expressions.
  oval(-8,-21,2.7,3.8,a.skin,true);oval(8,-21,2.7,3.8,a.skin,true);
  oval(0,-22,9.1,10.3,a.skin,true);
  if(key==='brenda'){
    oval(5,-32,4.5,5.2,a.hair,true); // messy bun
    poly([[-9,-25],[-9,-31],[-4,-33],[3,-32],[8,-29],[7,-25],[3,-30],[-4,-28]],a.hair,false);
    line([[5,-24],[6,-18]],'#543149',1.3); // mascara streak
  }else if(key==='priya'){
    oval(9,-29,4.2,6.2,a.hair,true); // perfect ponytail
    poly([[-9,-25],[-8,-31],[0,-34],[7,-30],[8,-26],[2,-29],[-8,-25]],a.hair,false);
    line([[0,-33],[0,-29]],'#bc9871',1);
  }else if(key==='moose'){
    oval(0,-30,8.6,5.1,a.hair,false);
    poly([[-8,-22],[-7,-17],[-4,-14],[4,-14],[8,-18],[8,-22],[4,-18],[0,-19],[-4,-18]],a.hair,false);
    oval(0,-16.8,4.5,2.8,'#4b302b',false);
    oval(3,-16,1.2,.9,'#f4ce80',false); // crumbs
  }else if(key==='luna'){
    for(let i=0;i<6;i++)oval(-7+i*2.8,-29-(i%2)*2,3.7,4.1,a.hair,false);
    poly([[-8,-31],[-4,-37],[1,-34],[5,-39],[9,-30],[2,-28]],'#c9d9e3',true); // foil hat
    line([[-3,-34],[4,-31]],'#f4f7fa',1.4);
  }else if(key==='dex'){
    poly([[-9,-27],[-8,-33],[7,-33],[9,-27],[3,-29],[-6,-28]],'#302739',true);
    pill(-10,-34,20,5,2,'#28283e',true); // backward cap
    pill(-5,-36,8,3,1,'#fd4e91',false);
    line([[-8,-20],[-10,-16],[-8,-11]],'#20212c',2.8); // headphones around neck
    line([[8,-20],[10,-16],[8,-11]],'#20212c',2.8);
    oval(-9,-13,2,3,'#e8eff7',true);oval(9,-13,2,3,'#e8eff7',true);
  }else if(key==='gary'){
    poly([[-8,-27],[-7,-31],[-1,-32],[4,-30],[7,-29],[7,-27],[1,-29],[-7,-25]],a.hair,false);
    line([[-4,-17],[-1,-18],[1,-18],[4,-17]],'#6e4437',2.3); // suspicious mustache
  }else if(key==='fenwick'){
    poly([[-9,-26],[-9,-30],[-6,-33],[-4,-26]],a.hair,false);
    poly([[9,-26],[9,-30],[6,-33],[4,-26]],a.hair,false);
    line([[-7,-28],[-3,-29]],'#77757e',1.7);
    line([[3,-29],[7,-28]],'#77757e',1.7);
  }else if(key==='kyle'){
    poly([[-9,-26],[-8,-32],[-1,-34],[7,-32],[9,-27],[4,-29],[-4,-29]],a.hair,false);
  }
  // Small but character-specific eyes, brows, noses and mouths.
  const look=moving?(c.path[0].x>c.x?.9:-.9):0;
  const eyeY=key==='moose'?-23:-22.1,eyeSpacing=key==='luna'?4.4:3.7;
  if(key==='priya'||key==='fenwick'){
    line([[-eyeSpacing-2,-26],[-eyeSpacing+2,-25]],a.eye,1.55);
    line([[eyeSpacing-2,-25],[eyeSpacing+2,-26]],a.eye,1.55);
  }else if(key==='brenda'){
    line([[-6,-27],[-2,-25]],a.eye,1.5);line([[2,-25],[6,-27]],a.eye,1.5);
  }else if(key==='gary'){
    line([[-6,-26],[-2,-26.5]],a.eye,1.4);line([[2,-26.5],[6,-25.3]],a.eye,1.4);
  }
  oval(-eyeSpacing+look,eyeY,key==='luna'?1.9:1.4,key==='luna'?2.1:1.65,a.eye,false);
  oval(eyeSpacing+look,eyeY,key==='luna'?1.9:1.4,key==='luna'?2.1:1.65,a.eye,false);
  if(key==='luna'||key==='brenda'){oval(-eyeSpacing+look-.35,eyeY-.6,.55,.7,'#fff',false);oval(eyeSpacing+look-.35,eyeY-.6,.55,.7,'#fff',false);}
  line([[0,-21],[.5,-19.5]],'#955c49',.95);
  if(key==='dex')line([[-2,-17],[1,-16],[4,-18]],a.eye,1.5);
  else if(key==='brenda'||alert)oval(0,-16.5,2.3,2.7,'#4d2834',false);
  else if(key==='moose')line([[-3,-18],[0,-16.5],[3,-18]],'#f7dfce',1.3);
  else if(key==='priya'||key==='fenwick')line([[-3,-17],[3,-17]],a.eye,1.1);
  else if(key==='luna')oval(0,-17,1.7,2.2,'#40283b',false);
  else line([[-2,-17],[2,-17.5]],a.eye,1.15);
  if(key==='brenda'){oval(-9,-18,1.2,2.3,'#5fb5ee',false);}
  if(key==='gary'){oval(8,-15,1.3,2.2,'#74d1f3',false);}
  g.restore();
}
function portraitFor(c){
  const key=artKey(c),png=ART['portrait_'+key];
  if(png)return png.src;
  if(AVATAR_PORTRAITS[key])return AVATAR_PORTRAITS[key];
  const canvas=document.createElement('canvas');canvas.width=224;canvas.height=224;
  const g=canvas.getContext('2d');
  g.fillStyle='#251836';g.fillRect(0,0,224,224);
  g.save();g.translate(112,112);g.rotate(-Math.PI/4);
  for(let i=-380;i<380;i+=44){g.fillStyle=(i/44)%2===0?'#3b2458':'#302047';g.fillRect(i,-310,23,640);}
  g.restore();
  g.fillStyle='rgba(255,255,255,.08)';g.beginPath();g.arc(112,119,98,0,Math.PI*2);g.fill();
  drawRoommate(g,c,112,193,key==='moose'?4.55:4.25,0);
  AVATAR_PORTRAITS[key]=canvas.toDataURL('image/png');
  return AVATAR_PORTRAITS[key];
}
