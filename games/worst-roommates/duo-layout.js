/* Worst Roommates Ever: single-screen command dock + unfolded control room.
   Existing gameplay controls remain the source of truth; taps are forwarded to them.
   Mode changes never reload the game or reset saved progress. */
(function(){
  "use strict";
  const $ = s => document.querySelector(s);
  const controls = $(".controls");
  const gameplay = window.WorstRoommatesGameplay;
  if (!controls || !gameplay || !$("#playActions") || !$("#bGo")) return;
  controls.id = "duoControls";
  controls.setAttribute("aria-label","Worst Roommates control room");
  controls.dataset.pane = "play";
  const playPanel = controls.querySelector(".gameplay-panel");
  const filmPanels = [$("#chaos").closest(".panel"),$("#bGo").closest(".panel")];
  const castPanel = $("#cast").closest(".panel");
  const logPanel = $("#log").closest(".panel");
  if (!playPanel || filmPanels.some(p=>!p) || !castPanel || !logPanel) return;
  playPanel.dataset.consolePane = "play";
  filmPanels.forEach(p=>p.dataset.consolePane="film");
  castPanel.dataset.consolePane = "cast";
  logPanel.dataset.consolePane = "log";
  controls.insertAdjacentHTML("afterbegin",
    '<div class="console-top">' +
      '<div><strong class="console-title">🎬 CONTROL ROOM</strong>' +
      '<span class="console-sub">Worst Roommates Ever · Director\'s desk</span></div>' +
      '<button type="button" class="console-close" id="closeConsole" aria-label="Close control room">✕ Done</button>' +
    '</div>' +
    '<div class="console-tabs" role="tablist" aria-label="Control room views">' +
      '<button type="button" role="tab" data-console-tab="play" aria-selected="true">🎮 Play</button>' +
      '<button type="button" role="tab" data-console-tab="film" aria-selected="false">🎬 Film</button>' +
      '<button type="button" role="tab" data-console-tab="cast" aria-selected="false">👥 Cast</button>' +
      '<button type="button" role="tab" data-console-tab="log" aria-selected="false">📜 Log</button>' +
    '</div>');
  const backdrop = document.createElement("div");
  backdrop.className = "duo-backdrop";
  backdrop.id = "duoBackdrop";
  backdrop.setAttribute("aria-hidden","true");
  document.body.append(backdrop);
  const dock = document.createElement("nav");
  dock.id = "duoDock";
  dock.className = "duo-dock";
  dock.setAttribute("aria-label","Quick gameplay controls");
  dock.innerHTML =
    '<div class="dock-top">' +
      '<button type="button" id="dockMode">🏠 Story ▾</button>' +
      '<button type="button" id="dockSelected">🎯 Dex</button>' +
      '<span id="dockStats" aria-live="off">Day 1 · $75</span>' +
      '<button type="button" id="dockMenu" aria-label="Open all controls">☰</button>' +
    '</div>' +
    '<div class="dock-actions" id="dockActions"></div>' +
    '<div class="dock-director" id="dockDirector">' +
      '<button type="button" id="dockEpisode">🎬 Episode</button>' +
      '<label class="quick-chaos" for="dockChaos" aria-label="Chaos level">🔥' +
        '<input type="range" id="dockChaos" min="1" max="10" value="6" />' +
        '<output id="dockChaosVal">6</output></label>' +
      '<button type="button" id="dockWildcard">🎲 Wild</button>' +
    '</div>';
  document.body.append(dock);
  let currentMode = null;
  let lastPane = "play";
  const isCompact = () => window.matchMedia("(max-width:719px)").matches;
  function choosePane(pane){
    if (!["play","film","cast","log"].includes(pane)) return;
    if (pane==="film" && document.body.dataset.mode!=="director") gameplay.mode("director");
    controls.dataset.pane = pane;
    lastPane = pane;
    controls.querySelectorAll("[data-console-tab]").forEach(btn=>{
      const active=btn.dataset.consoleTab===pane;
      btn.setAttribute("aria-selected",String(active));
      btn.tabIndex=active?0:-1;
    });
    controls.scrollTop=0;
  }
  function openConsole(pane){
    choosePane(pane || lastPane);
    if (isCompact()){
      document.body.classList.add("duo-open");
      $("#dockMenu").setAttribute("aria-expanded","true");
      $("#closeConsole").focus({preventScroll:true});
    }
  }
  function closeConsole(){
    document.body.classList.remove("duo-open");
    $("#dockMenu").setAttribute("aria-expanded","false");
    if (isCompact()) $("#dockMenu").focus({preventScroll:true});
  }
  $("#closeConsole").addEventListener("click",closeConsole);
  backdrop.addEventListener("click",closeConsole);
  $("#dockMenu").setAttribute("aria-expanded","false");
  $("#dockMenu").setAttribute("aria-controls","duoControls");
  $("#dockMenu").addEventListener("click",()=>openConsole(lastPane));
  $("#dockMode").addEventListener("click",()=>openConsole("play"));
  $("#dockSelected").addEventListener("click",()=>openConsole("cast"));
  $("#dockEpisode").addEventListener("click",()=>openConsole("film"));
  $("#dockWildcard").addEventListener("click",()=>$("#bEvent").click());
  $("#dockChaos").addEventListener("input",e=>{
    const original=$("#chaos");
    original.value=e.target.value;
    original.dispatchEvent(new Event("input",{bubbles:true}));
    $("#dockChaosVal").textContent=e.target.value;
  });
  controls.querySelector(".console-tabs").addEventListener("click",e=>{
    const tab=e.target.closest("[data-console-tab]");
    if (tab) choosePane(tab.dataset.consoleTab);
  });
  document.addEventListener("keydown",e=>{
    if (e.key==="Escape" && document.body.classList.contains("duo-open")) closeConsole();
  });
  window.addEventListener("resize",()=>{
    if (!isCompact()) document.body.classList.remove("duo-open");
  });
  const labels = {
    work:"💼 Work",clean:"🧽 Clean",mediate:"🤝 Mediate",repair:"🔧 Repair",
    prank:"😈 Prank",instigate:"🥊 Beef",disaster:"💥 Disaster"
  };
  const actionsFor={story:["work","clean","mediate","repair"],chaos:["prank","instigate","disaster"]};
  function mountActions(mode){
    const items = actionsFor[mode] || [];
    const area = $("#dockActions");
    area.style.gridTemplateColumns="repeat("+Math.max(items.length,1)+",minmax(0,1fr))";
    area.innerHTML=items.map(action=>
      '<button type="button" data-dock-action="'+action+'">'+labels[action]+'</button>').join("");
  }
  // Gameplay mode buttons update synchronously; refresh quick actions before the next tap.
  playPanel.addEventListener("click",e=>{
    if(e.target.closest("button[data-mode]")) Promise.resolve().then(syncDock);
  });
  $("#dockActions").addEventListener("click",e=>{
    const button=e.target.closest("button[data-dock-action]");
    if (!button || button.disabled) return;
    const original=$("#playActions button[data-action='"+button.dataset.dockAction+"']");
    if (original && !original.disabled) original.click();
    syncDock();
  });
  function syncDock(){
    const state=gameplay.state(),mode=state.mode;
    if(mode!==currentMode){
      currentMode=mode;
      mountActions(mode);
      if(mode==="director") choosePane("film");
      else if(lastPane==="film") choosePane("play");
    }
    const modeName=mode==="story"?"🏠 Story":mode==="chaos"?"🔥 Chaos":"🎬 Director";
    $("#dockMode").textContent=modeName+" ▾";
    $("#dockSelected").textContent="🎯 "+state.selected;
    const intro=state.story,chaos=state.chaos;
    $("#dockStats").textContent=mode==="story"
      ?"Day "+intro.day+" · $"+Math.round(intro.cash)+" · "+Math.round(intro.order)+"% peace"
      :mode==="chaos"?"⏱ "+Math.ceil(chaos.remaining)+"s · "+Math.round(chaos.score)+" pts"
      :"S1 E"+($("#epPill").textContent.split("E").pop()||"1")+" · Chaos "+$("#chaos").value;
    if(mode==="director"){
      $("#dockChaos").value=$("#chaos").value;
      $("#dockChaosVal").textContent=$("#chaos").value;
    } else {
      $("#dockActions").querySelectorAll("[data-dock-action]").forEach(button=>{
        const action=button.dataset.dockAction;
        const original=$("#playActions button[data-action='"+action+"']");
        button.disabled=!original || original.disabled;
        const secs=original && original.textContent.match(/·\s*(\d+)s/);
        const label=labels[action]+(secs?" "+secs[1]+"s":"");
        if(button.textContent!==label)button.textContent=label;
      });
    }
  }
  syncDock();
  window.setInterval(syncDock,450);
  window.WorstRoommatesDuo={
    open:openConsole, close:closeConsole,
    status:()=>({mode:currentMode,pane:controls.dataset.pane,compact:isCompact(),drawerOpen:document.body.classList.contains("duo-open")})
  };
})();
