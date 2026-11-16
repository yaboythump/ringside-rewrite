#!/usr/bin/env python3
"""Browser smoke and combat integration checks. Requires Playwright and Chromium."""
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

from playwright.sync_api import sync_playwright

HERE = Path(__file__).resolve().parent
SIZES = [(320, 568), (375, 667), (390, 844), (430, 932)]
ROSTER = ("Brick Malone", "Raven Vega", "Dutch Harlan", "Kid Voltage")
QA = """
window.qa = {
  state:() => st, profile:() => profile, settings:() => profile.settings,
  clock:() => clockLeft, ready:() => !busy && !ended, music:() => sfx.musicPlaying || !!fallbackMusic && !fallbackMusic.paused,
  seed(initial) {
    Math.random=()=>{initial=(Math.imul(initial,1664525)+1013904223)>>>0;return initial/4294967296};
  },
  async autoplay(){
    let best=null,high=-Infinity;
    for(let r=0;r<N;r++) for(let c=0;c<N;c++) for(const [dr,dc] of [[1,0],[0,1]]){
      const r2=r+dr,c2=c+dc;
      if(r2>=N||c2>=N||!wouldMatch(r,c,r2,c2)) continue;
      const a=grid[r][c],b=grid[r2][c2];
      let score=27;
      if(a.type!=='fin'&&b.type!=='fin'){
        grid[r][c]=b;grid[r2][c2]=a;
        const weights={strike:4,grapple:5,kick:st.guard?6:3,show:2,heal:weak('p')?4:0.5,reversal:1.8};
        score=findRuns().reduce((total,run)=>{
          const [row,column]=run.cells[0], type=grid[row][column].type;
          return total+run.cells.length*(st.pin||st.kick?3:weights[type])+(run.cells.length>=4?6:0);
        },0);
        grid[r][c]=a;grid[r2][c2]=b;
      }
      if(score>high){high=score;best=[r,c,r2,c2];}
    }
    if(best) await tryMove(...best);
  },
  tilePoints:() => findMove().map(([r,c]) => {
    const box=grid[r][c].el.getBoundingClientRect();
    return [box.x+box.width/2,box.y+box.height/2];
  }),
  brief:() => ({rung, ended, turn:st?.turn, moves:st?.moves, hero:hero?.id}),
  mutate(fn) { fn(st,profile); ui(); },
  save() {return persist()},
  sessions() {events();return [profile.daily.id,profile.weekly.id]},
  async turn() {busy=true;return endPlayerTurn()},
  mixer:() => [sfx.musicPlaying, sfx.qaSamples, sfx.qaEffects, sfx.qaMusicGain],
  startPin, startKickout, beginRecovery, resolveKickout, scoreFall, ironExpired, damage,
  async countPin() {return pinTick()},
  async tally(type,n,who='p') {
    const t=Object.fromEntries([...TYPES,'weapon'].map(key=>[key,key===type?n:0]));
    applyTally(t,1,0,0,who);ui();
  },
  async use(id) {
    st.charge[hero.id]={[id]:moves[id].charge};
    wrestlerData(hero).slots[0]=id;ui();useSignature(id);
  },
  replay() {queued={...queued};hero=queued.starter;start()},
};
"""

def open_play(page, wrestler=ROSTER[0], mode="ladder"):
    page.locator("#menuContent button").first.tap()
    page.locator("#menuContent select").first.select_option(mode)
    page.get_by_role("button", name=wrestler).tap()
    start = page.get_by_role("button", name="Start Match", exact=True)
    rect = start.bounding_box()
    assert rect and rect["y"] >= 0 and rect["y"] + rect["height"] <= page.viewport_size["height"]
    start.tap()
    page.locator("#entrance").wait_for(state="hidden")
    assert page.locator("#pName").inner_text() == wrestler
    assert page.locator(".tile").count() == 49
    board = page.locator("#board").bounding_box()
    assert board["x"] >= 0 and board["y"] >= 0
    assert board["x"] + board["width"] <= page.viewport_size["width"]
    assert board["y"] + board["height"] <= page.viewport_size["height"]


def home(page):
    if page.locator("#between").is_visible():
        page.locator("#bMenu").tap()
    else:
        page.locator("#pauseBtn").tap()
        page.locator("#exitBtn").tap()
    assert page.locator("#menu").is_visible()


def quick_checks(page, plain):
    for (width, height), wrestler in zip(SIZES, ROSTER):
        page.set_viewport_size({"width":width, "height":height})
        page.goto(plain)
        open_play(page, wrestler, "tag" if width == 320 else "ladder")
        page.locator("#pauseBtn").tap()
        assert page.locator("#pauseMenu").is_visible()
        page.locator("#resumeBtn").tap()
        page.locator("#pauseBtn").tap()
        page.locator("#restartBtn").tap()
        page.locator("#entrance").wait_for(state="hidden")
        assert page.locator("#pName").inner_text() == wrestler
        home(page)
    print("PASS four roster starts at 320×568 through 430×932, pause/resume/restart, safe exit")


def combat(page, fixture):
    page.set_viewport_size({"width":375,"height":667})
    page.goto(fixture)
    open_play(page)
    # A real pair of touch inputs runs the original swap, cascade, and AI turn.
    for x, y in page.evaluate("qa.tilePoints()"):
        page.touchscreen.tap(x, y)
    page.wait_for_function("qa.brief().moves===1 && qa.ready()")
    page.wait_for_function("qa.mixer()[0] && qa.mixer()[1]===11")
    original = page.evaluate("qa.mixer()")
    page.evaluate("qa.mutate((s,p)=>p.settings.music=0)")
    assert not page.evaluate("qa.music()")
    assert page.evaluate("qa.mixer()[2]") == original[2]
    page.evaluate("qa.mutate((s,p)=>p.settings.music=0.38)")
    clock = page.evaluate("qa.clock()")
    page.locator("#pauseBtn").tap()
    page.wait_for_timeout(250)
    assert abs(page.evaluate("qa.clock()") - clock) < .25
    assert not page.evaluate("qa.music()")
    page.locator("#resumeBtn").tap()
    page.wait_for_function("qa.music()")
    # Outcomes are set up as deterministic fixtures to cover late-match branches.
    page.evaluate("""async () => {
      qa.state().ohp=0;qa.startPin();qa.state().pin.got=99;
      await qa.countPin();await qa.countPin();await qa.countPin();
    }""")
    assert "You win" in page.locator("#bTitle").inner_text()
    assert page.evaluate("qa.profile().stats.wins") == 1
    assert page.evaluate("window.qaHaptics") > 0
    home(page)
    open_play(page)
    page.evaluate("async () => {qa.startKickout();await qa.resolveKickout();await qa.resolveKickout()}")
    assert "wins" in page.locator("#bTitle").inner_text()
    home(page)
    open_play(page)
    page.evaluate("""async () => {
      qa.startPin();await qa.countPin();await qa.countPin();await qa.countPin();
      qa.startKickout();qa.state().kick.got=99;await qa.resolveKickout();await qa.resolveKickout();
    }""")
    assert page.evaluate("qa.state().kickouts") == 1
    page.evaluate("async () => {await qa.tally('reversal',3);qa.damage('p',30,'finish')}")
    assert page.evaluate("qa.state().reversal.p") == 0
    home(page)
    print("PASS real touch swap and AI turn, music pause/resume, music gain, all embedded samples, haptic callback, three-counts, loss, near fall, kick-out, finisher counter")


def full_match(page):
    page.evaluate("qa.seed(1443)")
    open_play(page)
    for _ in range(110):
        if page.locator("#between").is_visible():
            break
        page.evaluate("qa.autoplay()")
    assert page.locator("#between").is_visible(), page.evaluate("qa.brief()")
    assert "You win" in page.locator("#bTitle").inner_text(), page.locator("#bTitle").inner_text()
    assert page.evaluate("qa.brief().moves") > 5
    home(page)
    print("PASS complete game from opening bell to winning pin using legal board swaps")


def stipulations(page):
    open_play(page, mode="cage")
    page.evaluate("""async () => {
      qa.mutate(s=>{s.ohp=25;s.climb.p=90});await qa.tally('show',3);await qa.turn();
    }""")
    assert "Escaped the Steel Cage" in page.locator("#bText").inner_text()
    home(page)
    open_play(page, mode="hardcore")
    assert page.locator(".t-weapon").count() > 0
    page.evaluate("""async () => {
      await qa.tally('weapon',3); if(qa.state().ohp>72) throw Error('weapon damage');
      qa.startPin();qa.state().pin.got=99;await qa.countPin();await qa.countPin();await qa.countPin();
    }""")
    assert "Pinfall" in page.locator("#bText").inner_text()
    home(page)
    open_play(page, mode="submission")
    page.evaluate("""async () => {
      qa.beginRecovery('p',true);await qa.tally('heal',6);await qa.turn();
      if(qa.state().recovery)throw Error('escape');qa.beginRecovery('p',true);qa.state().recovery.turns=1;await qa.turn();
    }""")
    assert "Submission" in page.locator("#bText").inner_text()
    home(page)
    open_play(page, mode="iron")
    page.evaluate("""() => {
      qa.scoreFall('p');qa.mutate(s=>s.remaining=0);qa.ironExpired();
    }""")
    assert "1–0" in page.locator("#bText").inner_text()
    home(page)
    open_play(page, mode="last")
    page.evaluate("""async () => {
      qa.beginRecovery('p',false);await qa.tally('reversal',12);await qa.turn();
      if(qa.state().downed)throw Error('recovery');qa.beginRecovery('p',false);
      qa.mutate(s=>s.downed.time=0);
    }""")
    page.locator("#between").wait_for(state="visible")
    assert "Ten-count knockout" in page.locator("#bText").inner_text()
    home(page)
    open_play(page, mode="tag")
    page.locator("#tagBtn").tap()
    page.wait_for_function("qa.ready()")
    assert page.locator("#pName").inner_text() != ROSTER[0]
    page.evaluate("qa.mutate(s=>s.teamMomentum.p=100)")
    page.locator("#teamBtn").tap()
    page.wait_for_function("qa.ready()")
    assert page.evaluate("qa.state().teamMomentum.p") == 0
    page.evaluate("qa.scoreFall('p')")
    home(page)
    print("PASS Steel Cage escape, Hardcore weapons/pinfall, Submission escape/finish, Iron Man scoring, LMS recovery/KO, Tag switch/finisher")


def progression(page):
    page.evaluate("qa.mutate((s,p)=>{p.cash=2000});qa.save()")
    page.locator("#menuContent button").nth(3).tap()
    row = page.locator(".menuRow").filter(has_text="Crossface Lock")
    row.get_by_role("button", name="Unlock").tap()
    assert page.evaluate("qa.profile().cards.lock") == 1
    row.get_by_role("button", name="Upgrade").tap()
    assert page.evaluate("qa.profile().cards.lock") == 2
    page.locator("#menuBack").tap()
    page.locator("#menuContent button").nth(2).tap()
    page.get_by_role("button", name="View Brick Malone").tap()
    page.get_by_label("Equip move").select_option("lock")
    assert page.evaluate("qa.profile().wrestlers.brick.slots[0]") == "lock"
    row = page.locator(".menuRow").filter(has_text="Power")
    row.get_by_role("button").tap()
    assert page.evaluate("qa.profile().wrestlers.brick.mods[0]") == 1
    page.reload()
    assert page.evaluate("qa.profile().cards.lock") == 2
    assert page.evaluate("qa.profile().wrestlers.brick.slots[0]") == "lock"
    open_play(page)
    for move in ("jab","slam","lock","counter","power","flight","bridge","surge","cutter","drop","lariat"):
        page.evaluate("""async id => {
          qa.mutate((s,p)=>{s.php=s.pmax;s.ohp=s.omax;p.cards[id]??=1});
          await qa.use(id);
        }""", move)
        page.wait_for_function("qa.ready()")
    assert page.evaluate("qa.state().signatureUses") == 11
    home(page)
    print("PASS earn/spend, buy/upgrade/equip/reload, and all move effects")


def career_tournament(page):
    page.locator("#menuContent button").nth(1).tap()
    for button in ["Make your debut", "Challenge for Prospect Championship"]:
        page.get_by_role("button", name=button).tap()
        page.locator("#menuFooter button").tap()
        page.locator("#entrance").wait_for(state="hidden")
        page.evaluate("qa.scoreFall('p')")
        page.locator("#bGo").tap()
    assert page.evaluate("qa.profile().career.titles.prospect.holder") == "brick"
    page.get_by_role("button", name="Fight for your title").tap()
    page.locator("#menuFooter button").tap()
    page.locator("#entrance").wait_for(state="hidden")
    page.evaluate("qa.scoreFall('p');qa.mutate(s=>s.remaining=0);qa.ironExpired()")
    page.locator("#bGo").tap()
    assert page.evaluate("qa.profile().career.titles.prospect.defenses") == 1
    page.locator("#menuBack").tap()
    page.get_by_role("button", name="More").tap()
    page.get_by_role("button", name="Weekly tournament").tap()
    for stage in ["quarterfinal", "semifinal", "final"]:
        page.get_by_role("button", name="Enter "+stage).tap()
        page.locator("#menuFooter button").tap()
        page.locator("#entrance").wait_for(state="hidden")
        if stage == "final":
            page.evaluate("async () => {qa.mutate(s=>{s.ohp=20;s.climb.p=100});await qa.turn()}")
        else:
            page.evaluate("qa.scoreFall('p')")
        page.locator("#bGo").tap()
    assert page.evaluate("qa.profile().weekly.round") == 3
    assert page.evaluate("qa.profile().stats.cups") == 1
    page.locator("#menuBack").tap()
    page.get_by_role("button", name="Daily challenges").tap()
    button = page.get_by_role("button", name="Claim 50 cash")
    button.tap()
    assert page.evaluate("qa.profile().daily.claimed.wins")
    assert page.locator(".menuRow").filter(has_text="Win two matches").get_by_role("button").is_disabled()
    ids = page.evaluate("qa.sessions()")
    page.evaluate("Date.now = () => 1")
    assert page.evaluate("qa.sessions()") == ids
    page.evaluate("Date.now = () => 9000000000000")
    assert page.evaluate("qa.sessions()") == ids
    page.evaluate("localStorage.setItem('ringcombo-profile','broken')")
    page.reload()
    assert "Recovered" in page.locator("#saveNotice").inner_text()
    print("PASS debut, contender title, title defense, three tournament rounds, daily claim, rollback/future clock and save recovery")


def main():
    with TemporaryDirectory() as directory, sync_playwright() as playwright:
        path = Path(directory) / "Ringside-Combo.html"
        subprocess.run([sys.executable, str(HERE / "build.py"), str(path)], check=True)
        content = path.read_text(encoding="utf-8")
        fixture = Path(directory) / "fixture.html"
        fixture.write_text(
            content.replace("async function sleep(ms){", "async function sleep(ms){ms=Math.min(8,ms);")
            .replace("setTimeout(beginMatch,1550)","setTimeout(beginMatch,80)")
            .replace("get musicPlaying()", "get qaSamples(){return Object.keys(voice).length},"
                "get qaEffects(){return master?.gain.value},get qaMusicGain(){return trackGain?.gain.value},"
                "get musicPlaying()")
            .replace("\n})();\n</script>", "\n" + QA + "\n})();\n</script>"),
            encoding="utf-8",
        )
        executable = os.environ.get("COMBO_CHROMIUM")
        browser = playwright.chromium.launch(
            executable_path=executable,
            args=["--no-sandbox", "--single-process", "--no-zygote"] if executable else [],
        )
        context = browser.new_context(viewport={"width":375,"height":667}, is_mobile=True, has_touch=True, offline=True)
        context.add_init_script("""
            window.qaHaptics=0;
            Object.defineProperty(navigator,'vibrate',{value:()=>{window.qaHaptics++;return true}});
        """)
        page = context.new_page()
        page.set_default_timeout(10000)
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.on("console", lambda msg: errors.append(msg.text) if msg.type=="error" else None)
        quick_checks(page,path.as_uri())
        combat(page,fixture.as_uri())
        full_match(page)
        stipulations(page)
        progression(page)
        career_tournament(page)
        assert not errors, errors
        browser.close()

if __name__ == "__main__":
    main()
