import { router, json, db, secrets, ai } from '@appdeploy/sdk';

type Sport = { label: string; key: string };
type Quote = { price: number; fair: number; book: string };
type Signal = {
  id: string; sport: string; sportKey: string; eventId: string; commence: string;
  event: string; home: string; away: string; market: string; selection: string;
  point: number | null; price: number; sportsbook: string; fairProbability: number;
  impliedProbability: number; edge: number; marketScore: number; books: number;
  capturedAt: string; status: string; model: string; unit: number;
};
type Board = { updatedAt: string; source: string; items: Signal[]; script: string; warning: string };
const SPORTS: Sport[] = [
  { label: 'NFL', key: 'americanfootball_nfl' },
  { label: 'NBA', key: 'basketball_nba' },
  { label: 'NHL', key: 'icehockey_nhl' },
  { label: 'MLB', key: 'baseball_mlb' },
  { label: 'NCAAF', key: 'americanfootball_ncaaf' },
  { label: 'NCAAB', key: 'basketball_ncaab' },
  { label: 'WNBA', key: 'basketball_wnba' },
];
const TABLE = 'clutch_capper_records';
const BOARD = 'clutch_capper_board';
const emptyBoard: Board = {
  updatedAt: '', source: 'The Odds API v4', items: [], script: '',
  warning: 'No verified market signals available. A licensed odds API key is required.'
};
const num = (n: unknown) => Number(n);
const prob = (odds: number) => odds > 0 ? 100 / (odds + 100) : Math.abs(odds) / (Math.abs(odds) + 100);
const median = (xs: number[]) => {
  const a = [...xs].sort((x, y) => x - y);
  return a.length % 2 ? a[(a.length - 1) / 2] : (a[a.length / 2 - 1] + a[a.length / 2]) / 2;
};
const percent = (n: number) => Math.round(n * 1000) / 10;
const safeKey = (x: string) => x.replace(/[^a-zA-Z0-9_-]/g, '_').slice(0, 110);
async function keyOrNull(): Promise<string | null> {
  if (!(await secrets.listSecretNames()).includes('THE_ODDS_API_KEY')) return null;
  return secrets.readSecret('THE_ODDS_API_KEY');
}
async function oddsGet(url: string, apiKey: string) {
  const join = url.includes('?') ? '&' : '?';
  const res = await fetch(url + join + 'apiKey=' + encodeURIComponent(apiKey), {
    headers: { 'Accept': 'application/json' }
  });
  if (!res.ok) throw new Error('Sports provider returned status ' + res.status);
  return res.json();
}
function candidates(event: any, sport: Sport, capturedAt: string): Signal[] {
  const groups = new Map<string, { market: string; selection: string; point: number | null; quotes: Quote[] }>();
  for (const b of Array.isArray(event.bookmakers) ? event.bookmakers : []) {
    for (const m of Array.isArray(b.markets) ? b.markets : []) {
      if (!['h2h', 'spreads', 'totals'].includes(m.key)) continue;
      const outs = Array.isArray(m.outcomes) ? m.outcomes : [];
      const total = outs.reduce((sum: number, o: any) => {
        const p = num(o.price);
        return sum + (Number.isFinite(p) && p !== 0 ? prob(p) : 0);
      }, 0);
      if (total <= 0) continue;
      for (const o of outs) {
        const price = num(o.price);
        const point = o.point === undefined ? null : num(o.point);
        if (!Number.isFinite(price) || price === 0 || (point !== null && !Number.isFinite(point))) continue;
        const selection = String(o.name || '');
        const groupId = m.key + '|' + selection + '|' + String(point);
        if (!groups.has(groupId)) groups.set(groupId, { market: m.key, selection, point, quotes: [] });
        groups.get(groupId)!.quotes.push({ price, fair: prob(price) / total, book: String(b.title || b.key) });
      }
    }
  }
  const out: Signal[] = [];
  for (const [groupId, group] of groups) {
    if (group.quotes.length < 3) continue;
    const best = [...group.quotes].sort((a, b) => prob(a.price) - prob(b.price))[0];
    const otherBooks = group.quotes.filter(q => q.book !== best.book);
    if (otherBooks.length < 2) continue;
    const estimated = median(otherBooks.map(q => q.fair));
    const edge = estimated - prob(best.price);
    if (edge < 0.025 || estimated <= 0 || estimated >= 1) continue;
    const score = Math.max(1, Math.min(100,
      Math.round(49 + edge * 500 + Math.min(otherBooks.length, 9) * 1.3)
    ));
    const eventName = String(event.away_team) + ' @ ' + String(event.home_team);
    out.push({
      id: safeKey(sport.key + '_' + event.id + '_' + groupId),
      sport: sport.label, sportKey: sport.key, eventId: String(event.id),
      commence: String(event.commence_time), event: eventName,
      home: String(event.home_team), away: String(event.away_team),
      market: group.market, selection: group.selection, point: group.point,
      price: best.price, sportsbook: best.book,
      fairProbability: percent(estimated), impliedProbability: percent(prob(best.price)),
      edge: percent(edge), marketScore: score, books: group.quotes.length,
      capturedAt, status: 'Open', model: 'Cross-book, vig-adjusted price signal; injuries and recent form not assessed',
      unit: 25
    });
  }
  return out;
}
async function boardRead(): Promise<Board> {
  const [row] = await db.get<Board>(BOARD, ['current']);
  return row || emptyBoard;
}
async function recordRead() {
  const page = await db.list<Signal>(TABLE, { limit: 100 });
  return page.items.sort((a, b) => String(b.capturedAt).localeCompare(String(a.capturedAt)));
}
function fallbackScript(signals: Signal[]): string {
  if (!signals.length) return 'Clutch Bets Capper is standing by. No qualified, sourced plays have cleared the market screen. We do not force picks.';
  const x = signals[0];
  return 'Welcome to Clutch Bets. Here is a market watchlist, not a guaranteed winner. ' +
    'In ' + x.sport + ', the model flags ' + x.selection + ' in ' + x.event + ', ' +
    x.market + (x.point === null ? '' : ' at ' + x.point) + ', at ' +
    (x.price > 0 ? '+' : '') + x.price + ' from ' + x.sportsbook + '. ' +
    'That price was captured ' + x.capturedAt + '. ' +
    'The screen compares available sportsbook prices; injury news and player form still require independent verification. ' +
    'Stake responsibly. One unit is twenty-five dollars. This is Clutch Bets.';
}
async function refresh() {
  const apiKey = await keyOrNull();
  if (!apiKey) return { skipped: 'THE_ODDS_API_KEY is not configured' };
  const capturedAt = new Date().toISOString();
  const found: Signal[] = [];
  const failures: string[] = [];
  for (const sport of SPORTS) {
    try {
      const url = 'https://api.the-odds-api.com/v4/sports/' + sport.key +
        '/odds?regions=us&markets=h2h,spreads,totals&oddsFormat=american';
      const events = await oddsGet(url, apiKey);
      if (!Array.isArray(events)) continue;
      for (const e of events) {
        if (Date.parse(String(e.commence_time)) < Date.now() + 15 * 60000) continue;
        found.push(...candidates(e, sport, capturedAt));
      }
    } catch (err) {
      failures.push(sport.label + ': ' + (err instanceof Error ? err.message : 'feed unavailable'));
    }
  }
  found.sort((a, b) => b.edge - a.edge);
  const filtered: Signal[] = [];
  const seen = new Set<string>();
  for (const x of found) {
    if (seen.has(x.eventId) || filtered.length >= 12) continue;
    seen.add(x.eventId);
    filtered.push(x);
  }
  const picked = filtered.slice(0, 5);
  const old = await boardRead();
  let script = fallbackScript(picked);
  if (picked.length > 0) {
    try {
      const generated = await ai.generate({
        system: 'Write a punchy 90-130 word spoken script for an original sports capper called Coach Clutch. Use ONLY the provided factual fields. Do not invent injuries, last-ten, opponent stats or probabilities. Call these market watchlist signals, never locks. Mention the source timestamp, $25 per unit, that bets are unplaced and that prices can change. No claims of guaranteed winning.',
        prompt: JSON.stringify(picked.slice(0, 3)),
        temperature: 0.35, maxTokens: 220, thinkingMode: 'NONE', cache: true
      });
      if (generated.text && generated.text.length < 1600) script = generated.text;
    } catch (err) {
      console.warn('Capper script generation not available:', err instanceof Error ? err.message : String(err));
    }
  }
  const board: Board = {
    updatedAt: capturedAt, source: 'The Odds API v4', items: picked,
    script, warning: failures.length ? 'Partial provider coverage: ' + failures.join('; ') : ''
  };
  const [current] = await db.get<Board>(BOARD, ['current'], { consistent: true });
  if (!current) {
    await db.tx.add(BOARD, [{ id: 'current', ...board }]);
  } else {
    await db.tx.update(BOARD, [{ id: 'current', record: board }]);
  }
  // A model signal is not an actual wager. Store the original odds + time before the event.
  for (const x of picked) {
    const [exists] = await db.get<Signal>(TABLE, [x.id], { consistent: true });
    if (!exists) await db.tx.add(TABLE, [x]);
  }
  return { signals: picked.length, failures, priorSignals: old.items.length };
}
async function grade() {
  const apiKey = await keyOrNull();
  if (!apiKey) return { skipped: 'missing provider key' };
  const open = (await recordRead()).filter(x => x.status === 'Open');
  let graded = 0;
  for (const sport of SPORTS) {
    const inSport = open.filter(x => x.sportKey === sport.key &&
      Date.parse(x.commence) <= Date.now());
    if (!inSport.length) continue;
    let events: any[] = [];
    try {
      const url = 'https://api.the-odds-api.com/v4/sports/' + sport.key + '/scores?daysFrom=3';
      const data = await oddsGet(url, apiKey);
      if (Array.isArray(data)) events = data;
    } catch (err) {
      console.warn('Results feed unavailable for ' + sport.label, err instanceof Error ? err.message : String(err));
      continue;
    }
    for (const x of inSport) {
      const match = events.find(e => String(e.id) === x.eventId && e.completed === true);
      if (!match || !Array.isArray(match.scores)) continue;
      const home = match.scores.find((s: any) => s.name === x.home);
      const away = match.scores.find((s: any) => s.name === x.away);
      if (!home || !away) continue;
      const hs = Number(home.score), as = Number(away.score);
      if (!Number.isFinite(hs) || !Number.isFinite(as)) continue;
      const mine = x.selection === x.home ? hs : as;
      const theirs = x.selection === x.home ? as : hs;
      let diff = 0;
      if (x.market === 'h2h') {
        if (x.selection !== x.home && x.selection !== x.away) continue;
        diff = mine - theirs;
      } else if (x.market === 'spreads') {
        if (x.point === null || (x.selection !== x.home && x.selection !== x.away)) continue;
        diff = mine + x.point - theirs;
      } else if (x.market === 'totals') {
        if (x.point === null || !['Over', 'Under'].includes(x.selection)) continue;
        diff = x.selection === 'Over' ? hs + as - x.point : x.point - hs - as;
      } else continue;
      const status = Math.abs(diff) < 0.00001 ? 'Push' : diff > 0 ? 'Won' : 'Lost';
      const [done] = await db.tx.update(TABLE, [{
        id: x.id, record: { status, finalScore: x.away + ' ' + as + ' — ' + x.home + ' ' + hs,
          gradedAt: new Date().toISOString(), resultSource: 'The Odds API v4 scores' },
        if: { status: 'Open' }
      }], { patch: true });
      if (done) graded++;
    }
  }
  return { graded };
}
export const refreshCapperBoard = async () => {
  try { await refresh(); } catch (e) { console.error('Board refresh failed', e); }
  return { statusCode: 200 };
};
export const gradeCapperResults = async () => {
  try { await grade(); } catch (e) { console.error('Grading failed', e); }
  return { statusCode: 200 };
};
export const handler = router({
  'GET /api/clutch-sports/health': [async () => {
    const names = await secrets.listSecretNames();
    if (!names.includes('CLUTCH_SPORTS_API_KEY')) return json({ configured: false, connected: false, reason: 'Key not stored' });
    try {
      const key = await secrets.readSecret('CLUTCH_SPORTS_API_KEY');
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 9000);
      let response: Response;
      try {
        response = await fetch('https://api.clutchbets.online/api/v1/nba/props', {
          headers: { Authorization: 'Bearer ' + key, Accept: 'application/json' },
          signal: controller.signal
        });
      } finally { clearTimeout(timer); }
      const status = response.status;
      return json({ configured: true, connected: response.ok, status,
        reason: response.ok ? 'Authenticated API request succeeded' :
          status === 402 ? 'API requires active subscription or internal entitlement' :
          status === 401 || status === 403 ? 'API rejected key or permissions' :
          status === 404 ? 'Documented endpoint unavailable' : 'Provider returned HTTP ' + status,
        endpoint: '/api/v1/nba/props', checkedAt: new Date().toISOString() });
    } catch (err) {
      return json({ configured: true, connected: false, reason: 'API connection failed or timed out', checkedAt: new Date().toISOString() });
    }
  }],
  'GET /api/clutch-sports/props': [async () => {
    if (!(await secrets.listSecretNames()).includes('CLUTCH_SPORTS_API_KEY')) return json({ connected: false, rows: [], reason: 'API key not configured' });
    try {
      const key = await secrets.readSecret('CLUTCH_SPORTS_API_KEY');
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 12000);
      let response: Response;
      try { response = await fetch('https://api.clutchbets.online/api/v1/nba/props', { headers: { Authorization: 'Bearer ' + key, Accept: 'application/json' }, signal: controller.signal }); }
      finally { clearTimeout(timer); }
      if (!response.ok) return json({ connected: false, rows: [], status: response.status, reason: 'Provider returned HTTP ' + response.status });
      const payload = await response.json();
      const entries = Array.isArray(payload) ? payload : Array.isArray(payload?.data) ? payload.data : Array.isArray(payload?.props) ? payload.props : Array.isArray(payload?.results) ? payload.results : [];
      const rows = entries.slice(0, 100).map((x: any) => ({
        player: String(x.player_name ?? x.player ?? x.participant_name ?? 'Unidentified player'),
        game: String(x.event ?? x.matchup ?? x.game ?? [x.away_team, x.home_team].filter(Boolean).join(' @ ') ?? ''),
        market: String(x.market_type ?? x.market ?? x.bet_type ?? 'Unspecified'),
        line: x.line ?? x.point ?? null,
        odds: x.odds_american ?? x.odds ?? x.price ?? null,
        book: String(x.sportsbook ?? x.bookmaker ?? x.book ?? 'Clutch Sports'),
        start: String(x.event_start_time ?? x.commence_time ?? x.start_time ?? ''),
      }));
      return json({ connected: true, rows, count: rows.length, source: 'Clutch Sports API', checkedAt: new Date().toISOString(), note: 'Research only: upstream player-game associations and line freshness have not been independently verified.', responseShape: Array.isArray(payload) ? 'array' : Object.keys(payload ?? {}).slice(0, 8) });
    } catch { return json({ connected: false, rows: [], reason: 'Provider request failed or timed out' }); }
  }],
  'GET /api/capper/status': [async () => {
    const configured = Boolean(await keyOrNull());
    return json({
      configured, source: 'The Odds API v4', unit: 25, refresh: '12:15 PM Eastern daily',
      grading: '9:05 AM Eastern daily',
      coverage: 'Game moneylines, spreads and totals; no live player-prop research yet'
    });
  }],
  'GET /api/capper/board': [async () => json(await boardRead())],
  'GET /api/capper/record': [async () => {
    const rows = await recordRead();
    const settled = rows.filter(x => x.status !== 'Open');
    const profit = settled.reduce((sum, x) => sum +
      (x.status === 'Won' ? (x.price > 0 ? x.price / 100 : 100 / Math.abs(x.price)) * 25 :
      x.status === 'Lost' ? -25 : 0), 0);
    const risked = settled.filter(x => x.status !== 'Push').length * 25;
    return json({ rows, total: rows.length, settled: settled.length,
      won: settled.filter(x => x.status === 'Won').length,
      lost: settled.filter(x => x.status === 'Lost').length,
      pushed: settled.filter(x => x.status === 'Push').length,
      profit: Math.round(profit * 100) / 100,
      roi: risked ? Math.round(profit / risked * 1000) / 10 : null,
      note: 'Recent 100 stored model signals, not placed wagers. Scores grade only completed events in the provider coverage window.' });
  }]
});