const {chromium,devices}=require("playwright");
const assert=require("node:assert/strict");
const base=process.env.RCC_URL||"http://127.0.0.1:8765/ringside-rewrite/preview/";
const isPreview=new URL(base).pathname.includes("/preview");
const key=isPreview?"rcc-preview-career":"rcc-career";
const mode=process.env.RCC_SMOKE_ONLY;
const legacy={
  wid:"raven",champ:"silas",contenders:["dutch","raven","kid","brick","tank","jett","ox"],
  booked:{id:"dutch",title:false,stip:null},news:["Prior show"],week:13,w:8,l:4,fame:65,align:2,hypeBonus:0,hpMod:0,
  segDone:false,peak:0,defenses:3,reigns:1,best:4,
  deck:["chop","chop","dropkick","clothesline","suplex","headlock","block","block","reversal","secondwind","taunt","crowdpop","springboard","moonsault","springboard"]
};
(async()=>{
  const browser=await chromium.launch();
  try{
    for(const [label,device] of Object.entries({
      desktop:{viewport:{width:1440,height:950}},
      iPhone:devices["iPhone 13"],
      Android:devices["Pixel 7"]
    })){
      const ctx=await browser.newContext({...device,reducedMotion:"reduce"});
      const p=await ctx.newPage();
      p.setDefaultTimeout(8500);
      const errors=[];
      p.on("pageerror",e=>errors.push(e.message));
      p.on("console",m=>{if(m.type()==="error")errors.push(m.text());});
      await p.goto(base,{waitUntil:"load"});
      const button=id=>p.locator(id);
      const click=async id=>button(id).click();
      const visible=async id=>button(id).waitFor({state:"visible"});
      const noOverflow=async()=>assert.equal(await p.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,label);
      const menu=async()=>{await p.goto(base,{waitUntil:"load"});await visible("#m-career");};
      const ring=async()=>{
        const skip=button(".overlay .skip");
        if(await skip.count()) await skip.click({timeout:750}).catch(()=>{});
        await p.waitForFunction(()=>G?.p&&!G.busy);
        await noOverflow();
      };
      const complete=async()=>{
        for(let turns=0;turns<35;turns++){
          await p.waitForFunction(()=>G?.over||!G?.busy);
          if(await p.evaluate(()=>G.over))return p.locator(".result h2").textContent();
          const action=await p.evaluate(()=>{
            const {p,o,intent}=G;
            if(p.hype===10)return "#fin";
            const cards=p.hand.map((id,i)=>({c:CARDS[id],i})).filter(({c})=>c.cost<=p.energy);
            const score=c=>{
              if(c.dmg&&c.dmg>=(o.hp+(c.pierce?0:o.block))&&!p.weak)return 60;
              if(c.reversal&&intent.type==="grapple"&&!p.reversal)return 30;
              if(c.strikeCounter&&intent.type==="strike"&&!p.strikeCounter)return 26;
              if(c.heal&&p.hp+8<p.max&&p.hp<18)return 17;
              if(c.block&&intent.dmg&&p.block<5&&p.hp<=intent.dmg+5)return 15;
              if(c.hypeGain||c.energy)return c.cost===0?27:(c.hypeGain>3?9:5);
              if(c.dmg)return Math.max(0,cardDmg(c)-o.block)/(c.cost||1)+(c.pierce?1:0);
              return 0;
            };
            const usable=cards.map(x=>({...x,score:score(x.c)})).sort((a,b)=>b.score-a.score)[0];
            return usable?.score>0?`.hand [data-i="${usable.i}"]`:"#end";
          });
          await click(action);
        }
        for(let i=0;i<100;i++){
          await p.waitForFunction(()=>G?.over||!G?.busy);
          if(await p.evaluate(()=>G.over))return p.locator(".result h2").textContent();
          const attack=p.locator(".hand .card:not([disabled]):has(.big:text('DMG'))").first();
          if(await attack.count()) await attack.click();
          else await click("#end");
        }
        throw Error("Bout exceeded QA action limit");
      };
      await visible("#m-career");
      await noOverflow();
      assert.equal(await p.locator(".mode").evaluateAll(tiles=>tiles.every(tile=>tile.scrollWidth<=tile.clientWidth)),true,label+" title menu fit");
      await p.evaluate(data=>localStorage.setItem("rcc-career",JSON.stringify(data)),legacy);
      await menu();
      assert.equal(await button("#m-cont").count(),isPreview?0:1);
      if(!isPreview){
        await click("#m-cont");
        await click("#fight-camp");
        assert.match(await button(".camp-summary").textContent(),/Equipped 15/);
        await click("#camp-back");await click("#quit");
      }
      await click("#m-career");
      assert.equal(await p.locator(".pick").count(),16);
      assert.equal(await p.locator(".pick img").count(),16);
      await p.waitForFunction(()=>[...document.querySelectorAll(".pick img")].every(img=>img.complete&&img.naturalWidth>0));
      await click('[data-division="women"]');
      assert.equal(await p.locator(".pick").count(),8);
      assert.equal(await p.locator(".pick img").count(),8);
      await p.waitForFunction(()=>[...document.querySelectorAll(".pick img")].every(img=>img.complete&&img.naturalWidth>0));
      await click("#create-wrestler");
      await button('[name="name"]').fill("Rose & Thorn");
      await button('[name="look"]').selectOption("mask");
      await button('[name="gear"]').selectOption("elite");
      await button('[name="palette"]').selectOption("jade");
      await button('[name="move"]').selectOption("haymaker");
      if(!isPreview)p.once("dialog",d=>d.accept());
      await click("#creation [type=submit]");
      await visible("#fight-camp");
      await click("#career-office");
      await click('[data-contract="wins"]');
      await p.getByText(/Win Streak · 0\/2 · due week 4/).waitFor();
      await click("#back");
      await click("#s-train");
      const learned=await p.locator("[data-add]").first().getAttribute("data-add");
      await click(`[data-add="${learned}"]`);
      await click("#fight-camp");
      await click(`[data-unequip="${learned}"]`);
      await click(`[data-equip="${learned}"]`);
      await click("#camp-back");
      await click("#journal");
      await p.getByRole("heading",{name:"Event calendar"}).waitFor();
      await click("#back");
      await menu();
      await click("#m-cont");
      assert.match(await p.locator(".hubtop").textContent(),/Rose & Thorn/);
      const save=await p.evaluate(key=>JSON.parse(localStorage.getItem(key)),key);
      assert.equal(save.profile.look,"mask");
      assert.ok(save.collection.includes(learned));
      if(isPreview)assert.equal(await p.evaluate(()=>JSON.parse(localStorage.getItem("rcc-career")).week),13);
      await click("#fight");
      await ring();
      if(label==="iPhone"&&!mode){
        const original=p.viewportSize();
        const positions=()=>p.evaluate(()=>{
          const bounds=selector=>document.querySelector(selector).getBoundingClientRect();
          const hud=bounds(".battle-hud"),hand=bounds(".battle-hand");
          return {split:hud.right<=hand.left,atTop:scrollY===0,
            controls:["#end",".ticker","#f-p","#f-o"].every(selector=>{
              const {top,bottom,left,right}=bounds(selector);
              return top>=0&&left>=0&&right<=innerWidth&&bottom<=innerHeight+1;
            })};
        });
        const turnState=()=>p.evaluate(()=>({
          turn:G.turn,hp:[G.p.hp,G.o.hp],energy:G.p.energy,hand:[...G.p.hand],message:G.log[0]
        }));
        await p.setViewportSize({width:466,height:678});
        assert.deepEqual(await positions(),{split:false,atTop:true,controls:true},"Duo closed");
        assert.equal(await button(".live-ring").isVisible(),false);
        const before=await turnState();
        for(const viewport of [{width:890,height:626},{width:626,height:890}]){
          await p.setViewportSize(viewport);
          assert.deepEqual(await positions(),{split:true,atTop:true,controls:true},"Duo open");
          await visible(".live-ring");
          assert.equal(await p.locator(".live-ring .ring-actor").count(),2);
          assert.equal(await p.locator('.live-ring .ring-actor[data-wrestler="custom"]').count(),1);
          assert.deepEqual(await turnState(),before,"Unfolding or rotating preserves the live turn");
          await noOverflow();
        }
        // Set up a known strike within the live match, then use the real card click.
        await p.evaluate(()=>{G.p.hand[0]="chop";G.o.block=0;render();});
        await click('.hand [data-i="0"]');
        await visible('.ring-actor.player[data-action="strike"]');
        await visible('.ring-actor.opponent[data-reaction="hit"]');
        assert.match(await button(".ring-call").textContent(),/Rose & Thorn · Chop/);
        const after=await turnState();
        assert.ok(after.hp[1]<before.hp[1]);
        assert.match(after.message,new RegExp("for "+(before.hp[1]-after.hp[1])));
        await p.setViewportSize({width:466,height:678});
        assert.deepEqual(await positions(),{split:false,atTop:true,controls:true},"Duo refolded");
        assert.equal(await button(".live-ring").isVisible(),false);
        assert.deepEqual(await turnState(),after,"Refolding preserves damage and the remaining cards");
        assert.match(await button(".ticker .now").textContent(),/for [1-9]/);
        await p.setViewportSize(original);
        console.log("iPhone Duo closed/open/rotated/refolded: live wrestlers react to a card, controls and damage stay visible");
      }
      const career=await complete();
      const result=await p.evaluate(key=>JSON.parse(localStorage.getItem(key)),key);
      assert.equal(result.week,2);
      assert.equal(result.w+result.l,1);
      assert.equal(result.office.active.id,"wins");
      assert.equal(result.office.active.progress,result.w);
      console.log(label,"career",career,"saved week",result.week);
      if(label==="desktop"&&!mode){
        for(const stip of ["cage","street","submission","lastman"]){
          await menu();await click("#m-exhibition");await click('[data-w="raven"]');
          await button('[name="opponent"]').selectOption("tank");
          await button('[name="stip"]').selectOption(stip);
          await click("#bout [type=submit]");await ring();
          console.log(label,stip,await complete());
        }
        await menu();await click("#m-quick");await click('[data-w="raven"]');await ring();
        console.log(label,"ladder",await complete());
        await menu();await click("#m-tournament");await click('[data-division="women"]');await click('[data-w="nova"]');
        assert.equal(await p.locator(".bracket li").count(),7);
        const bracket=await button(".bracket").textContent();
        await menu();await click("#m-tournament");
        assert.equal(await button(".bracket").textContent(),bracket);
        await click("#cup-fight");await ring();
        console.log(label,"cup",await complete());
        await menu();await click("#m-tournament");
        await p.locator(".bracket strong").first().waitFor();
        console.log(label,"cup resumed after reload");
        await menu();await click("#m-tag");await click('[data-w="raven"]');
        await button('[name="stakes"]').selectOption("title");
        await click("#tag-bout [type=submit]");await ring();
        const partner=await p.evaluate(()=>G.pBench.w.id);
        await click("#tag");
        await p.waitForFunction(id=>!G.busy&&G.p.w.id===id,partner);
        console.log(label,"tag",await complete());
        const tag=await p.evaluate(key=>JSON.parse(localStorage.getItem(key)),isPreview?"rcc-preview-tag":"rcc-tag");
        assert.equal(tag.champions.length,2);
        assert.equal(tag.history.length,1);
        await click("#event-next");
        await click("summary");
        await p.getByText(/won the belts|retained the belts/).waitFor();

        await p.evaluate(key=>{
          const saved=JSON.parse(localStorage.getItem(key));
          saved.week=4;
          saved.arc.ally="nyx";
          saved.arc.faction="lights";
          saved.tag.partners.nyx={wins:2,losses:0};
          localStorage.setItem(key,JSON.stringify(saved));
        },key);
        await menu();await click("#m-cont");
        await p.getByRole("heading",{name:"Career Tag Team"}).waitFor();
        await click("#career-tag");await ring();
        console.log(label,"career tag title",await complete());
        await click("#event-next");
        await visible("#fight");
        assert.equal(await button("#career-tag").count(),0);
        await click("#journal");
        await p.locator("section").filter({has:p.getByRole("heading",{name:"Career tag title history"})})
          .getByText(/Week 4.* the belts/).waitFor();
      }
      assert.deepEqual(errors,[],label+" runtime errors");
      await ctx.close();
    }
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
