/* Worst Roommates Ever: playable Story, Chaos and Director modes.
   This file is embedded in src.html by build.py so the iPhone game works offline. */
(function () {
  "use strict";
  const STORAGE_KEY = "wre_play_v1";
  const $play = (selector) => document.querySelector(selector);
  const between = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
  const whole = (n) => Math.round(n);
  const defaultStory = () => ({
    day: 1, elapsed: 0, cash: 75, order: 78, mess: 20, score: 0,
    mission: 0, progress: 0, completed: 0, done: false, result: "",
    rentPaid: 0
  });
  const defaultChaos = (high) => ({
    remaining: 120, score: 0, combo: 1, lastHit: -100,
    done: false, result: "", high: high || 0
  });
  const missions = [
    { key: "work", name: "Everybody Pays Something", description: "Work 2 side hustles to cover the house bills.", target: 2, reward: 25 },
    { key: "clean", name: "The Health Inspector Is Coming", description: "Clean the apartment twice.", target: 2, reward: 20 },
    { key: "mediate", name: "Emergency House Meeting", description: "Resolve 2 roommate arguments.", target: 2, reward: 25 },
    { key: "work", name: "Rent Money, Not Vibes", description: "Finish 3 shifts before rent comes due.", target: 3, reward: 35 },
    { key: "clean", name: "Operation: No More Smell", description: "Clean the house 3 times.", target: 3, reward: 30 },
    { key: "mediate", name: "Nobody Gets Voted Out", description: "Settle 2 more disputes.", target: 2, reward: 30 }
  ];
  let saved = {};
  try { saved = JSON.parse(store.getItem(STORAGE_KEY) || "{}") || {}; } catch (_) {}
  const s = Object.assign(defaultStory(), saved.story || {});
  const hi = Number(saved.chaos && saved.chaos.high) || 0;
  const c = Object.assign(defaultChaos(hi), saved.chaos || {});
  const game = {
    mode: ["story", "chaos", "director"].includes(saved.mode) ? saved.mode : "story",
    selected: CAST.some(r => r.name === saved.selected) ? saved.selected : "Dex",
    story: s, chaos: c, sfx: saved.sfx !== false,
    cooldowns: Object.create(null), lastWrite: 0, lastUI: 0,
    message: "", messageUntil: 0
  };
  // Recover interrupted TestFlight play sessions without breaking older episode saves.
  if (!Number.isFinite(s.cash) || !Number.isFinite(s.day) || s.day < 1 || s.day > 7) game.story = defaultStory();
  if (!Number.isFinite(c.score) || !Number.isFinite(c.remaining)) game.chaos = defaultChaos(hi);

  const panel = document.createElement("div");
  panel.className = "panel gameplay-panel";
  panel.innerHTML =
    '<h3>Choose how to play</h3>' +
    '<div class="mode-buttons" role="group" aria-label="Game modes">' +
      '<button type="button" data-mode="story">🏠 Story</button>' +
      '<button type="button" data-mode="chaos">🔥 Chaos</button>' +
      '<button type="button" data-mode="director">🎬 Director</button>' +
    '</div>' +
    '<div id="playIntro" class="play-intro"></div>' +
    '<div id="playDash">' +
      '<div id="playStats" class="play-stats" aria-live="polite"></div>' +
      '<div id="playMission" class="play-mission"></div>' +
      '<div id="playStatus" class="play-status" role="status"></div>' +
      '<div id="playActions" class="play-actions"></div>' +
      '<div id="playEnding" class="play-ending" hidden></div>' +
      '<div class="play-footer"><span id="playSelected"></span><button type="button" id="playRestart">↻ New game</button></div>' +
    '</div>' +
    '<button type="button" class="play-sfx" id="playSfx"></button>';
  $play(".controls").prepend(panel);
  const episodePanel = $play("#bGo").closest(".panel");
  episodePanel.classList.add("director-panel");
  const hint = document.createElement("div");
  hint.className = "play-stage-hint";
  hint.id = "playStageHint";
  $play(".hud").append(hint);

  let audio = null;
  function sound(kind) {
    if (!game.sfx) return;
    const AudioClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioClass) return;
    try {
      if (!audio) audio = new AudioClass();
      if (audio.state === "suspended") audio.resume().catch(() => {});
      const base = kind === "win" ? 660 : kind === "bad" ? 190 : kind === "chaos" ? 310 : 470;
      const now = audio.currentTime;
      const notes = kind === "win" ? [1, 1.25, 1.5] : kind === "bad" ? [1, .75] : kind === "chaos" ? [1, 1.35] : [1, 1.2];
      notes.forEach((ratio, i) => {
        const osc = audio.createOscillator(), gain = audio.createGain();
        osc.type = kind === "chaos" ? "sawtooth" : "sine";
        osc.frequency.setValueAtTime(base * ratio, now + i * .085);
        gain.gain.setValueAtTime(.0001, now + i * .085);
        gain.gain.exponentialRampToValueAtTime(.055, now + i * .085 + .012);
        gain.gain.exponentialRampToValueAtTime(.0001, now + i * .085 + .14);
        osc.connect(gain); gain.connect(audio.destination);
        osc.start(now + i * .085); osc.stop(now + i * .085 + .16);
      });
    } catch (_) {}
  }
  function savePlay() {
    try {
      store.setItem(STORAGE_KEY, JSON.stringify({
        mode: game.mode, selected: game.selected, story: game.story,
        chaos: game.chaos, sfx: game.sfx
      }));
    } catch (_) {}
  }
  function message(text) {
    game.message = text; game.messageUntil = simTime + 5;
    $play("#playStatus").textContent = text;
    lowerThird(text);
  }
  function scoreChaos(points, reason) {
    const g = game.chaos;
    if (game.mode !== "chaos" || g.done) return;
    g.combo = simTime - g.lastHit < 9 ? between(g.combo + 1, 1, 5) : 1;
    g.lastHit = simTime;
    const earned = whole(points * g.combo);
    g.score += earned;
    if (g.score > g.high) g.high = g.score;
    message("🔥 " + reason + "  +" + earned + " (" + g.combo + "x combo)");
    sound("chaos");
    savePlay(); renderPlay();
  }
  function storyMissionProgress(key) {
    const g = game.story;
    if (game.mode !== "story" || g.done) return;
    const m = missions[g.mission % missions.length];
    if (key !== m.key) return;
    g.progress += 1;
    if (g.progress >= m.target) {
      g.completed += 1;
      g.cash += m.reward;
      g.score += 100;
      g.order = between(g.order + 8, 0, 100);
      g.mission += 1; g.progress = 0;
      showCard("MISSION COMPLETE", m.name, "+$" + m.reward + "  •  +100 points", 2000);
      message("✅ Mission cleared! +$" + m.reward);
      sound("win");
    }
    savePlay();
  }
  function storyFail(text) {
    const g = game.story;
    if (g.done) return;
    g.done = true; g.result = text;
    showCard("GAME OVER", "THE LEASE IS HISTORY", text, 5000);
    message("💔 " + text);
    sound("bad");
    savePlay(); renderPlay();
  }
  function storyWin() {
    const g = game.story;
    g.done = true;
    g.score += 1000 + whole(g.order) * 10;
    g.result = "You survived the full week and paid both rent bills!";
    showCard("YOU WIN!", "THE HOUSE SURVIVED", "Final score: " + g.score, 5000);
    message("🏆 A whole week without eviction. Legendary!");
    sound("win");
    savePlay(); renderPlay();
  }
  function startNextDay() {
    const g = game.story;
    if (g.done) return;
    g.day += 1; g.elapsed = 0;
    if (g.day === 4 || g.day === 7) {
      const rent = g.day === 4 ? 180 : 240;
      if (g.cash < rent) {
        storyFail("Rent was $" + rent + ", but you only had $" + g.cash + ". Evicted!");
        return;
      }
      g.cash -= rent; g.rentPaid += rent; g.score += 200;
      showCard("RENT PAID!", "$" + rent + " TO FENWICK", "The lease lives another day.", 2600);
      message("💸 Paid $" + rent + " rent. Keep hustling!");
    } else {
      showCard("NEXT DAY", "DAY " + g.day + " OF 7", "New day. Same impossible roommates.", 1800);
      message("🌅 Day " + g.day + " begins.");
    }
    if (g.day === 7 && g.order > 0) {
      storyWin();
    }
    savePlay(); renderPlay();
  }
  function handleWorldEvent(type) {
    if (game.mode === "story" && !game.story.done) {
      const g = game.story;
      g.mess = between(g.mess + (type === "flood" || type === "fire" ? 17 : 9), 0, 100);
      g.order = between(g.order - (type === "landlord" ? 10 : 7), 0, 100);
      if (g.order <= 0) storyFail("The house voted you out after too much drama.");
    } else if (game.mode === "chaos" && !game.chaos.done) {
      scoreChaos(type === "fire" || type === "flood" ? 140 : 100, type.toUpperCase() + " DISASTER");
    }
    savePlay();
  }
  function handleIncident() {
    if (game.mode === "story" && !game.story.done) {
      game.story.mess = between(game.story.mess + 2, 0, 100);
      game.story.order = between(game.story.order - 1, 0, 100);
      if (game.story.order <= 0) storyFail("Nobody can stand living here anymore.");
    } else if (game.mode === "chaos" && !game.chaos.done) {
      scoreChaos(12, "ROOMMATE DRAMA");
    }
  }
  // Preserve existing AI life simulation and scripted episode behavior.
  const oldTriggerEvent = triggerEvent;
  triggerEvent = function (type) {
    const happened = oldTriggerEvent(type);
    if (happened) handleWorldEvent(type);
    return happened;
  };
  const oldIncident = runIncident;
  runIncident = function () {
    oldIncident();
    handleIncident();
  };
  function selectedRoommate() {
    return find(game.selected) || roommates()[0];
  }
  function eligible(action) {
    return game.cooldowns[action] == null || simTime >= game.cooldowns[action];
  }
  function cooldown(action, secs) { game.cooldowns[action] = simTime + secs; }
  function doAction(action) {
    const mode = game.mode, g = game.story, c = selectedRoommate();
    if (!c || (mode === "story" && g.done) || (mode === "chaos" && game.chaos.done)) return;
    if (!eligible(action)) { message("⏳ That action needs a moment to recharge."); return; }
    if (mode === "story") {
      switch (action) {
        case "work": {
          g.cash += 35; g.score += 15;
          c.needs.energy = between(c.needs.energy - 18, 0, 100);
          say(c, pick(["I better get overtime for this.", "A paycheck? In this economy?!", "I literally work harder than Gary."]));
          cooldown(action, 9);
          message("💼 " + c.name + " earned $35!"); storyMissionProgress("work"); break;
        }
        case "clean": {
          g.mess = between(g.mess - 24, 0, 100);
          g.order = between(g.order + 5, 0, 100);
          g.score += 15;
          c.needs.energy = between(c.needs.energy - 8, 0, 100);
          say(c, pick(["Who left THIS on the floor?", "I'm charging a cleaning fee.", "I deserve my own bathroom."]));
          cooldown(action, 8);
          message("🧽 " + c.name + " cleaned up the apartment."); storyMissionProgress("clean"); break;
        }
        case "mediate": {
          g.order = between(g.order + 16, 0, 100);
          g.score += 20;
          Object.keys(c.grudge).forEach(name => { c.grudge[name] = Math.max(0, c.grudge[name] - 2); });
          roommates().forEach(r => { if (r !== c && r.grudge[c.name]) r.grudge[c.name] = Math.max(0, r.grudge[c.name] - 1); });
          say(c, pick(["Group hug? No? Fine.", "Nobody is getting kicked out TODAY.", "We are going to use our indoor voices."]));
          cooldown(action, 10);
          message("🤝 " + c.name + " calmed everyone down."); storyMissionProgress("mediate"); break;
        }
        case "repair": {
          let fixed = null;
          for (const type of ["fire", "flood", "outage", "party", "raccoon"]) {
            if (fx[type]) { fx[type] = null; fixed = type; break; }
          }
          if (!fixed) {
            g.mess = between(g.mess - 9, 0, 100);
            message("🔧 " + c.name + " fixed a few minor apartment problems.");
          } else {
            g.mess = between(g.mess - 17, 0, 100);
            g.order = between(g.order + 11, 0, 100);
            g.score += 70;
            message("🛠️ " + c.name + " fixed the " + fixed + " disaster!");
          }
          say(c, "I am NOT getting the security deposit back.");
          cooldown(action, 12);
          break;
        }
        default: return;
      }
      nativePost("haptic", {style: "light"});
      sound("tap");
    } else if (mode === "chaos") {
      switch (action) {
        case "prank": {
          const t = pick(others(c));
          say(c, "It was just a PRANK. Relax.");
          addGrudge(t, c, 2); addDrama(t.x, t.y, 3, "😈 " + c.name + " pranked " + t.name);
          log("😈 " + esc(c.name) + " unleashed a ridiculous prank on " + esc(t.name) + ".", "hd");
          cooldown(action, 5); scoreChaos(65, "PRANK ATTACK"); break;
        }
        case "instigate": {
          const t = pick(others(c));
          addGrudge(c, t, 3); addGrudge(t, c, 2);
          say(c, t.name + ", we need to talk about your attitude.");
          addDrama(c.x, c.y, 4, "🥊 " + c.name + " started serious beef");
          cooldown(action, 7); scoreChaos(80, "RIVALRY STARTED"); break;
        }
        case "disaster": {
          let result = false;
          for (const e of shuffle(EVENTS)) { if (triggerEvent(e)) { result = true; break; } }
          if (!result) { message("💤 Every disaster is already happening. Impressive."); return; }
          cooldown(action, 12); break;
        }
        default: return;
      }
      nativePost("haptic", {style: "heavy"});
    }
    savePlay(); renderPlay();
  }
  const baseUpdate = update;
  update = function (dt) {
    baseUpdate(dt);
    const mode = game.mode;
    if (mode === "story" && !game.story.done) {
      const g = game.story;
      g.elapsed += dt;
      if (g.mess > 70) g.order = between(g.order - dt * .08, 0, 100);
      if (g.order <= 0) storyFail("The roommates finally kicked you out.");
      if (g.elapsed >= 60 && !g.done) startNextDay();
    } else if (mode === "chaos" && !game.chaos.done) {
      const g = game.chaos;
      g.remaining = Math.max(0, g.remaining - dt);
      if (simTime - g.lastHit > 10) g.combo = 1;
      if (g.remaining <= 0) {
        g.done = true; g.result = "Final chaos score: " + g.score + " points";
        g.high = Math.max(g.high, g.score);
        showCard("CHAOS COMPLETE", "FINAL SCORE: " + g.score, "Best: " + g.high, 4500);
        message("🏆 Chaos round finished! Score: " + g.score);
        sound("win"); savePlay();
      }
    }
    game.lastWrite += dt; game.lastUI += dt;
    if (game.lastWrite >= 5) { game.lastWrite = 0; savePlay(); }
    if (game.lastUI >= .4) { game.lastUI = 0; renderPlay(); }
  };
  // A gold selection ring makes tapping individual roommates meaningful.
  const baseDraw = draw;
  draw = function () {
    baseDraw();
    if (game.mode === "director") return;
    const c = selectedRoommate();
    if (!c) return;
    ctx.save();
    ctx.strokeStyle = "#ffd84d"; ctx.lineWidth = 2.5;
    ctx.setLineDash([4, 3]); ctx.beginPath(); ctx.arc(c.x, c.y - 2, 15, 0, Math.PI * 2); ctx.stroke();
    ctx.restore();
  };

  function setSelected(name) {
    if (!CAST.some(c => c.name === name)) return;
    game.selected = name;
    message("🎯 " + name + " selected. Choose an action!");
    nativePost("haptic", {style: "light"});
    sound("tap"); renderPlay(); savePlay();
  }
  $play("#cast").addEventListener("click", e => {
    const item = e.target.closest(".cm");
    if (!item) return;
    const i = Array.prototype.indexOf.call(item.parentNode.children, item);
    const cast = roommates();
    if (cast[i]) setSelected(cast[i].name);
  });
  $play("#cv").addEventListener("click", e => {
    if (game.mode === "director") return;
    const rect = cv.getBoundingClientRect();
    const x = cam.x + ((e.clientX - rect.left) / rect.width - .5) * W / cam.z;
    const y = cam.y + ((e.clientY - rect.top) / rect.height - .5) * H / cam.z;
    let best = null, dist = 32;
    roommates().forEach(c => {
      const d = Math.hypot(c.x - x, c.y - y);
      if (d < dist) { best = c; dist = d; }
    });
    if (best) setSelected(best.name);
  });
  const summaries = {
    story: "Survive seven days, finish missions and pay rent on Days 4 and 7. Tap a roommate to give them a job.",
    chaos: "Two minutes. No rent. Unleash pranks, feuds and disasters to build an outrageous combo score.",
    director: "Create your own comedy episodes with the existing writer. Characters remember their grudges."
  };
  function switchMode(mode) {
    if (!summaries[mode]) return;
    game.mode = mode;
    // No reset on mode changes: ongoing story saves persist when filming an episode.
    document.body.dataset.mode = mode;
    game.message = "";
    game.cooldowns = Object.create(null);
    if (mode === "chaos" && game.chaos.done) game.chaos = defaultChaos(game.chaos.high);
    $play("#playIntro").textContent = summaries[mode];
    $play("#playDash").hidden = mode === "director";
    $play("#playSfx").textContent = game.sfx ? "🔊 SFX on" : "🔇 SFX off";
    $play("#playStageHint").textContent = mode === "story" ? "🏠 Survive the Lease" : mode === "chaos" ? "🔥 Chaos Challenge" : "🎬 Director Cam";
    $play("#playStageHint").style.display = mode === "director" ? "none" : "";
    panel.querySelectorAll("[data-mode]").forEach(b => {
      b.classList.toggle("on", b.dataset.mode === mode);
      b.setAttribute("aria-pressed", String(b.dataset.mode === mode));
    });
    savePlay(); renderPlay();
  }
  function stat(label, value) {
    return '<div class="play-stat"><span>' + label + '</span><b>' + value + '</b></div>';
  }
  function button(action, label, disabled) {
    const remaining = Math.ceil((game.cooldowns[action] || 0) - simTime);
    return '<button type="button" data-action="' + action + '"' +
      (disabled || remaining > 0 ? ' disabled' : '') +
      '>' + label + (remaining > 0 ? " · " + remaining + "s" : "") + '</button>';
  }
  function renderPlay() {
    const g = game.story, ch = game.chaos, mode = game.mode;
    document.body.dataset.mode = mode;
    if (mode === "story") {
      $play("#playStats").innerHTML = stat("DAY", g.day + " / 7") +
        stat("CASH", "$" + whole(g.cash)) + stat("HOUSE PEACE", whole(g.order) + "%") +
        stat("MESS", whole(g.mess) + "%");
      const m = missions[g.mission % missions.length];
      $play("#playMission").innerHTML = '<b>🎯 ' + m.name + '</b><span>' + m.description +
        '</span><div class="mission-track"><i style="width:' + (100 * g.progress / m.target) +
        '%"></i></div><small>' + g.progress + "/" + m.target + " · +$" + m.reward +
        " · Next rent: $" + (g.day < 4 ? 180 : 240) + " on Day " + (g.day < 4 ? 4 : 7) +
        " · " + Math.ceil(60 - g.elapsed) + 's to tomorrow</small>';
      $play("#playActions").innerHTML = button("work", "💼 Work +$35", g.done) +
        button("clean", "🧹 Clean", g.done) +
        button("mediate", "🤝 Mediate", g.done) +
        button("repair", "🔧 Fix disaster", g.done);
    } else if (mode === "chaos") {
      $play("#playStats").innerHTML = stat("TIME", Math.ceil(ch.remaining) + "s") +
        stat("CHAOS POINTS", whole(ch.score)) + stat("COMBO", ch.combo + "x") +
        stat("BEST", whole(ch.high));
      $play("#playMission").innerHTML =
        '<b>🔥 Cause absolute chaos</b><span>Prank the house, create feuds and set off disasters. Chain trouble within 9 seconds to increase your multiplier.</span>' +
        '<div class="mission-track"><i style="width:' + (100 * ch.remaining / 120) + '%"></i></div>' +
        '<small>Beat your personal high score before the clock runs out.</small>';
      $play("#playActions").innerHTML = button("prank", "😈 Prank", ch.done) +
        button("instigate", "🥊 Start beef", ch.done) +
        button("disaster", "💥 Disaster", ch.done);
    }
    const finished = mode === "story" ? g.done : mode === "chaos" && ch.done;
    $play("#playEnding").hidden = !finished;
    if (finished) {
      $play("#playEnding").textContent = mode === "story" ?
        (g.day === 7 && g.rentPaid >= 420 ? "🏆 YOU WIN! " : "💔 GAME OVER. ") + g.result + " · Score: " + g.score :
        "🏆 ROUND OVER. " + ch.result + " · Best: " + ch.high;
    }
    $play("#playSelected").textContent = mode === "chaos" ? "🎯 Instigator: " + game.selected : "🎯 Playing as: " + game.selected;
    $play("#playRestart").textContent = mode === "story" ? "↻ New lease" : "↻ New chaos round";
    if (game.messageUntil < simTime) { game.message = ""; }
    $play("#playStatus").textContent = game.message;
    Array.from($play("#cast").children).forEach((el, i) => {
      const r = roommates()[i];
      el.classList.toggle("selected-roommate", !!r && r.name === game.selected && mode !== "director");
      el.setAttribute("role", "button");
      el.setAttribute("tabindex", "0");
      el.setAttribute("aria-label", r ? "Select " + r.name : "Select roommate");
    });
  }
  panel.addEventListener("click", e => {
    const modeButton = e.target.closest("[data-mode]");
    if (modeButton) { sound("tap"); switchMode(modeButton.dataset.mode); return; }
    const actionButton = e.target.closest("[data-action]");
    if (actionButton) { doAction(actionButton.dataset.action); return; }
  });
  $play("#cast").addEventListener("keydown", e => {
    if ((e.key !== "Enter" && e.key !== " ") || !e.target.closest(".cm")) return;
    e.preventDefault(); e.target.click();
  });
  $play("#playRestart").addEventListener("click", () => {
    if (game.mode === "story") game.story = defaultStory();
    else if (game.mode === "chaos") game.chaos = defaultChaos(game.chaos.high);
    game.cooldowns = Object.create(null);
    message("🎮 Fresh game. Make some questionable decisions!");
    sound("win"); savePlay(); renderPlay();
  });
  $play("#playSfx").addEventListener("click", () => {
    game.sfx = !game.sfx;
    $play("#playSfx").textContent = game.sfx ? "🔊 SFX on" : "🔇 SFX off";
    if (game.sfx) sound("tap");
    savePlay();
  });
  switchMode(game.mode);
  // Public, read-only debug hook for TestFlight QA and automated browser tests.
  window.WorstRoommatesGameplay = {
    state: () => JSON.parse(JSON.stringify({mode: game.mode, story: game.story, chaos: game.chaos, selected: game.selected})),
    mode: switchMode
  };
})();