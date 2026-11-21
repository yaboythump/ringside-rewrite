import { useEffect, useMemo, useState } from 'react';
import CapperStudio from './CapperStudio';
import {
  Activity,
  BarChart3,
  Bookmark,
  ChevronDown,
  CircleDollarSign,
  ExternalLink,
  LayoutDashboard,
  Search,
  ShieldCheck,
  Target,
  Trash2,
  TrendingUp,
} from 'lucide-react';

type Pick = {
  id: number;
  event: string;
  market: string;
  side: string;
  odds: number;
  stake: number;
  status: string;
};
const games = [
  {
    sport: 'NFL',
    league: 'NFL',
    away: 'Dallas Cowboys',
    home: 'Philadelphia Eagles',
    time: 'Sun • 4:25 PM',
    market: 'Moneyline',
    a: -110,
    b: -105,
  },
  {
    sport: 'NBA',
    league: 'NBA',
    away: 'Boston Celtics',
    home: 'New York Knicks',
    time: 'Tonight • 7:30 PM',
    market: 'Moneyline',
    a: -125,
    b: +105,
  },
  {
    sport: 'NBA',
    league: 'NBA',
    away: 'Los Angeles Lakers',
    home: 'Golden State Warriors',
    time: 'Tonight • 10:00 PM',
    market: 'Moneyline',
    a: +115,
    b: -135,
  },
  {
    sport: 'NHL',
    league: 'NHL',
    away: 'New York Rangers',
    home: 'Boston Bruins',
    time: 'Tomorrow • 7:00 PM',
    market: 'Moneyline',
    a: +120,
    b: -140,
  },
  {
    sport: 'MLB',
    league: 'MLB',
    away: 'New York Yankees',
    home: 'Los Angeles Dodgers',
    time: 'Example matchup',
    market: 'Moneyline',
    a: -115,
    b: +100,
  },
  {
    sport: 'NCAAF',
    league: 'NCAAF',
    away: 'Michigan',
    home: 'Ohio State',
    time: 'Example matchup',
    market: 'Moneyline',
    a: +145,
    b: -165,
  },
];
const props = [
  {
    sport: 'NBA',
    name: 'Jayson Tatum',
    team: 'BOS',
    market: 'Points',
    line: 27.5,
    avg: '29.1',
    hit: '7/10',
    over: -110,
    under: -110,
  },
  {
    sport: 'NBA',
    name: 'Stephen Curry',
    team: 'GSW',
    market: '3-Pointers Made',
    line: 4.5,
    avg: '4.2',
    hit: '5/10',
    over: +115,
    under: -135,
  },
  {
    sport: 'NFL',
    name: 'Jalen Hurts',
    team: 'PHI',
    market: 'Passing Yards',
    line: 224.5,
    avg: '238.0',
    hit: '6/10',
    over: -115,
    under: -105,
  },
  {
    sport: 'NFL',
    name: 'CeeDee Lamb',
    team: 'DAL',
    market: 'Receiving Yards',
    line: 79.5,
    avg: '82.3',
    hit: '6/10',
    over: -110,
    under: -110,
  },
  {
    sport: 'NHL',
    name: 'David Pastrnak',
    team: 'BOS',
    market: 'Shots on Goal',
    line: 3.5,
    avg: '4.1',
    hit: '7/10',
    over: -120,
    under: +100,
  },
];
const books = [
  ['FanDuel', 'https://sportsbook.fanduel.com/'],
  ['DraftKings', 'https://sportsbook.draftkings.com/'],
  ['BetMGM', 'https://sports.betmgm.com/'],
  ['Caesars', 'https://www.caesars.com/sportsbook-and-casino'],
  ['Fanatics', 'https://sportsbook.fanatics.com/'],
];
const fmt = (n: number) => (n > 0 ? '+' + n : String(n));
const key = 'clutch-bets-picks-v1';
function App() {
  const [tab, setTab] = useState('Dashboard'),
    [sport, setSport] = useState('All Sports'),
    [query, setQuery] = useState(''),
    [slip, setSlip] = useState<Pick[]>(() => {
      try {
        return JSON.parse(localStorage.getItem(key) || '[]');
      } catch {
        return [];
      }
    }),
    [stake, setStake] = useState('25'),
    [book, setBook] = useState('FanDuel'),
    [notice, setNotice] = useState(''),
    [slipOpen, setSlipOpen] = useState(false);
  useEffect(() => localStorage.setItem(key, JSON.stringify(slip)), [slip]);
  const add = (event: string, market: string, side: string, odds: number) => {
    if (
      slip.some(
        p => p.event === event && p.market === market && p.side === side
      )
    ) {
      setNotice('That selection is already in your picks.');
      return;
    }
    setSlip(s => [
      ...s,
      {
        id: Date.now() + Math.random(),
        event,
        market,
        side,
        odds,
        stake: Number(stake) || 0,
        status: 'Draft',
      },
    ]);
    setNotice('Selection added to your bet slip.');
    setSlipOpen(true);
  };
  const filteredGames = games.filter(
    g =>
      (sport === 'All Sports' || g.sport === sport) &&
      [g.away, g.home].join(' ').toLowerCase().includes(query.toLowerCase())
  );
  const filteredProps = props.filter(
    p =>
      (sport === 'All Sports' || p.sport === sport) &&
      [p.name, p.market, p.team]
        .join(' ')
        .toLowerCase()
        .includes(query.toLowerCase())
  );
  const decimal = (o: number) => (o > 0 ? 1 + o / 100 : 1 + 100 / Math.abs(o));
  const combined = slip
    .filter(p => p.status === 'Draft')
    .reduce((v, p) => v * decimal(p.odds), 1);
  const drafts = slip.filter(p => p.status === 'Draft');
  const payout = Number(stake || 0) * combined;
  const links = books.find(b => b[0] === book)?.[1] || books[0][1];
  const tabs = [
    ['Dashboard', LayoutDashboard],
    ['Games', Activity],
    ['Player Props', BarChart3],
    ['My Picks', Bookmark],
    ['Capper Studio', Target],
  ];
  return (
    <div className="shell">
      <aside className="sidebar">
        <div className="brand">
          <div className="brandIcon">
            C<span>B</span>
          </div>
          <div>
            <strong>
              CLUTCH<span>BETS</span>
            </strong>
            <small>THE EDGE IS YOURS</small>
          </div>
        </div>
        <div className="navLabel">WORKSPACE</div>
        {tabs.map(([name, Icon]) => (
          <button
            key={name as string}
            className={'nav ' + (tab === name ? 'active' : '')}
            onClick={() => setTab(name as string)}
          >
            <Icon size={19} />
            {name as string}
            {name === 'My Picks' && slip.length > 0 && (
              <b className="count">{slip.length}</b>
            )}
          </button>
        ))}
        <div className="sideBottom">
          <ShieldCheck size={17} /> Personal workspace{' '}
          <small>Research & pick tracking</small>
        </div>
      </aside>
      <main className="main">
        <header>
          <div className="mobileBrand">
            ⚡ CLUTCH<span>BETS</span>
          </div>
          <div className="crumb">
            YOUR COMMAND CENTER <span>/ {tab.toUpperCase()}</span>
          </div>
          <div className="headerRight">
            <span className="demoDot" /> DEMO DATA{' '}
            <button
              onClick={() => setSlipOpen(v => !v)}
              className="slipTrigger"
            >
              <Bookmark size={16} /> Bet Slip <b>{drafts.length}</b>
            </button>
          </div>
        </header>
        <div className="content">
          <div className="hero">
            <div className="eyebrow">YOUR PERSONAL BETTING INTELLIGENCE</div>
            <h1>{tab === 'Dashboard' ? 'Every edge. One place.' : tab}</h1>
            <p>
              Analyze matchups, compare selections, and build your next slip.
            </p>
            <div className="heroGlow" />
          </div>
          <div className="warning">
            <ShieldCheck size={18} />
            <div>
              <strong>Legacy dashboard is illustrative; Capper Studio is source-gated.</strong> Scores,
              matchups, odds, player statistics and trends below are sample
              content, not live or verified. Never use these prices to wager.
              The separate Capper Studio uses a credential-gated source and never repurposes these samples as verified picks.
            </div>
          </div>
          <div className="statGrid">
            <div className="stat">
              <span>SPORTS COVERED</span>
              <strong>5+</strong>
              <small>Major leagues</small>
              <Activity />
            </div>
            <div className="stat">
              <span>MY SELECTIONS</span>
              <strong>{slip.length}</strong>
              <small>Saved locally</small>
              <Bookmark />
            </div>
            <div className="stat">
              <span>DRAFT PICKS</span>
              <strong>{drafts.length}</strong>
              <small>In your slip</small>
              <Target />
            </div>
            <div className="stat">
              <span>TRACKED BETS</span>
              <strong>{slip.filter(p => p.status !== 'Draft').length}</strong>
              <small>Manual results</small>
              <TrendingUp />
            </div>
          </div>
          {tab !== 'My Picks' && tab !== 'Capper Studio' && (
            <>
              <div className="toolbar">
                <div className="sports">
                  {['All Sports', 'NFL', 'NBA', 'MLB', 'NHL', 'NCAAF'].map(
                    s => (
                      <button
                        className={sport === s ? 'selected' : ''}
                        onClick={() => setSport(s)}
                        key={s}
                      >
                        {s}
                      </button>
                    )
                  )}
                </div>
                <label className="search">
                  <Search size={17} />
                  <input
                    placeholder="Search teams, players..."
                    value={query}
                    onChange={e => setQuery(e.target.value)}
                  />
                </label>
              </div>
              {(tab === 'Dashboard' || tab === 'Games') && (
                <section>
                  <div className="sectionHeading">
                    <div>
                      <span className="sectionAccent" /> <h2>Game Lines</h2>
                      <span className="tag">SAMPLE</span>
                    </div>
                    <button className="textBtn" onClick={() => setTab('Games')}>
                      View all games →
                    </button>
                  </div>
                  <div className="gameGrid">
                    {filteredGames.length === 0 ? (
                      <div className="empty">No games match your filters.</div>
                    ) : (
                      filteredGames
                        .slice(0, tab === 'Dashboard' ? 4 : 20)
                        .map(g => (
                          <div className="gameCard" key={g.away}>
                            <div className="cardTop">
                              <span className="league">{g.league}</span>
                              <span>{g.time}</span>
                            </div>
                            <div className="teamRow">
                              <div>
                                <div className="teamIcon">
                                  {g.away
                                    .split(' ')
                                    .map(x => x[0])
                                    .slice(-2)
                                    .join('')}
                                </div>
                                <strong>{g.away}</strong>
                              </div>
                              <button
                                onClick={() =>
                                  add(
                                    g.away + ' @ ' + g.home,
                                    'Moneyline',
                                    g.away,
                                    g.a
                                  )
                                }
                              >
                                {fmt(g.a)} <span>ADD</span>
                              </button>
                            </div>
                            <div className="teamRow">
                              <div>
                                <div className="teamIcon">
                                  {g.home
                                    .split(' ')
                                    .map(x => x[0])
                                    .slice(-2)
                                    .join('')}
                                </div>
                                <strong>{g.home}</strong>
                              </div>
                              <button
                                onClick={() =>
                                  add(
                                    g.away + ' @ ' + g.home,
                                    'Moneyline',
                                    g.home,
                                    g.b
                                  )
                                }
                              >
                                {fmt(g.b)} <span>ADD</span>
                              </button>
                            </div>
                            <div className="cardFoot">
                              Moneyline · Illustrative odds
                            </div>
                          </div>
                        ))
                    )}
                  </div>
                </section>
              )}
              {(tab === 'Dashboard' || tab === 'Player Props') && (
                <section>
                  <div className="sectionHeading">
                    <div>
                      <span className="sectionAccent" /> <h2>Player Props</h2>
                      <span className="tag">SAMPLE</span>
                    </div>
                    <button
                      className="textBtn"
                      onClick={() => setTab('Player Props')}
                    >
                      Explore props →
                    </button>
                  </div>
                  <div className="propTable">
                    <div className="tableHead">
                      <span>PLAYER / MARKET</span>
                      <span>LINE</span>
                      <span>AVG*</span>
                      <span>HIT RATE*</span>
                      <span>OVER</span>
                      <span>UNDER</span>
                    </div>
                    {filteredProps.length === 0 ? (
                      <div className="empty">
                        No player props match your filters.
                      </div>
                    ) : (
                      filteredProps.map(p => (
                        <div className="propRow" key={p.name}>
                          <div className="player">
                            <div className="avatar">
                              {p.name
                                .split(' ')
                                .map(x => x[0])
                                .join('')}
                            </div>
                            <div>
                              <strong>{p.name}</strong>
                              <small>
                                {p.team} · {p.market}
                              </small>
                            </div>
                          </div>
                          <strong>{p.line}</strong>
                          <span>{p.avg}</span>
                          <span className="hit">{p.hit}</span>
                          <button
                            onClick={() =>
                              add(
                                p.name,
                                p.market + ' ' + p.line,
                                'Over',
                                p.over
                              )
                            }
                          >
                            O {fmt(p.over)}
                          </button>
                          <button
                            onClick={() =>
                              add(
                                p.name,
                                p.market + ' ' + p.line,
                                'Under',
                                p.under
                              )
                            }
                          >
                            U {fmt(p.under)}
                          </button>
                        </div>
                      ))
                    )}
                  </div>
                  <div className="footnote">
                    * Illustrative statistics, not actual recent performance.
                  </div>
                </section>
              )}
            </>
          )}
          {tab === 'Capper Studio' && <CapperStudio />}
          {tab === 'My Picks' && (
            <section>
              <div className="sectionHeading">
                <div>
                  <span className="sectionAccent" />
                  <h2>My Saved Picks</h2>
                </div>
              </div>
              <div className="saved">
                {slip.length === 0 ? (
                  <div className="empty">
                    No picks saved yet. Add a selection from Games or Player
                    Props.
                  </div>
                ) : (
                  slip.map(p => (
                    <div className="savedRow" key={p.id}>
                      <div>
                        <strong>
                          {p.side} · {p.event}
                        </strong>
                        <small>
                          {p.market} · {fmt(p.odds)}
                        </small>
                      </div>
                      <select
                        aria-label={'Result for ' + p.event}
                        value={p.status}
                        onChange={e =>
                          setSlip(s =>
                            s.map(x =>
                              x.id === p.id
                                ? { ...x, status: e.target.value }
                                : x
                            )
                          )
                        }
                      >
                        <option>Draft</option>
                        <option>Placed</option>
                        <option>Won</option>
                        <option>Lost</option>
                        <option>Void</option>
                      </select>
                      <button
                        aria-label={'Remove ' + p.event}
                        onClick={() =>
                          setSlip(s => s.filter(x => x.id !== p.id))
                        }
                      >
                        <Trash2 size={18} />
                      </button>
                    </div>
                  ))
                )}
              </div>
            </section>
          )}
          <footer>
            CLUTCH BETS © 2026 · Private research dashboard · No wagers
            processed here
          </footer>
        </div>
      </main>
      <aside className={'betslip ' + (slipOpen ? 'open' : '')}>
        <div className="slipHead">
          <div>
            <CircleDollarSign size={21} />
            <strong>MY BET SLIP</strong>
          </div>
          <button onClick={() => setSlipOpen(false)}>✕</button>
        </div>
        <div className="slipContent">
          <div className="slipTitle">
            Your selections <span>{drafts.length} picks</span>
          </div>
          {drafts.length === 0 ? (
            <div className="slipEmpty">
              <Target size={34} />
              <strong>Your slip is empty</strong>
              <p>Select any odds to add a pick.</p>
            </div>
          ) : (
            drafts.map(p => (
              <div className="slipPick" key={p.id}>
                <div>
                  <span className="selection">{p.side}</span>
                  <button
                    aria-label="Remove selection"
                    onClick={() => setSlip(s => s.filter(x => x.id !== p.id))}
                  >
                    ✕
                  </button>
                </div>
                <strong>{p.event}</strong>
                <small>{p.market}</small>
                <b>{fmt(p.odds)}</b>
              </div>
            ))
          )}
          <div className="slipControls">
            <label>
              SPORTSBOOK{' '}
              <span>
                Choose a provider <ChevronDown size={12} />
              </span>
            </label>
            <select value={book} onChange={e => setBook(e.target.value)}>
              {books.map(b => (
                <option key={b[0]}>{b[0]}</option>
              ))}
            </select>
            <label>STAKE ($)</label>
            <input
              type="number"
              min="0"
              value={stake}
              onChange={e => setStake(e.target.value)}
            />
            <div className="calculation">
              <span>Combined odds (decimal)</span>
              <strong>{drafts.length ? combined.toFixed(2) : '—'}</strong>
            </div>
            <div className="calculation">
              <span>Illustrative return</span>
              <strong>{drafts.length ? payout.toFixed(2) : '—'}</strong>
            </div>
            <a className="placeBtn" href="https://sportsbook.fanduel.com/" target="_blank" rel="noopener noreferrer">OPEN FANDUEL <ExternalLink size={16} /></a>
            <a className="placeBtn" href="https://sportsbook.draftkings.com/" target="_blank" rel="noopener noreferrer">OPEN DRAFTKINGS <ExternalLink size={16} /></a>
            <p className="disclaimer">
              Both buttons open the official sportsbooks. These are not bet-slip deep links: automatic pick transfer is unavailable until supported market-specific links and real odds data are connected. Verify all selections, prices and eligibility before placing a wager.
            </p>
          </div>
        </div>
      </aside>
      {slipOpen && <div className="scrim" onClick={() => setSlipOpen(false)} />}
      {notice && (
        <div className="toast" role="status" onClick={() => setNotice('')}>
          {notice} ✕
        </div>
      )}
    </div>
  );
}
export default App;
