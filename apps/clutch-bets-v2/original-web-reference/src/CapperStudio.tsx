import { useEffect, useState } from 'react';
import { api } from '@appdeploy/client';
import { Activity, CalendarClock, CheckCircle2, Clapperboard, Copy, Database, ShieldCheck, Target, TrendingUp } from 'lucide-react';
import './capper.css';

type Signal = {
  id: string; sport: string; event: string; market: string; selection: string; point: number | null;
  price: number; sportsbook: string; edge: number; marketScore: number;
  fairProbability: number; impliedProbability: number; books: number; capturedAt: string;
  model: string; status: string; finalScore?: string;
};
type Board = { updatedAt: string; source: string; items: Signal[]; script: string; warning: string };
type RecordView = { rows: Signal[]; total: number; settled: number; won: number; lost: number; pushed: number; profit: number; roi: number | null; note: string };
type Status = { configured: boolean; source: string; unit: number; refresh: string; grading: string; coverage: string };
const odds = (n: number) => n > 0 ? '+' + n : String(n);
const when = (x: string) => x ? new Date(x).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short', timeZone: 'America/New_York' }) + ' ET' : 'Not yet synchronized';
export default function CapperStudio() {
  const [status, setStatus] = useState<Status | null>(null);
  const [board, setBoard] = useState<Board | null>(null);
  const [record, setRecord] = useState<RecordView | null>(null);
  const [section, setSection] = useState<'board' | 'record' | 'presenter'>('board');
  const [loading, setLoading] = useState(true);
  const [failure, setFailure] = useState('');
  const [copied, setCopied] = useState(false);
  const [clutch, setClutch] = useState<{ connected: boolean; rows: { player: string; game: string; market: string; line: string | number | null; odds: string | number | null; book: string; start: string }[]; count?: number; note?: string; reason?: string; responseShape?: string[] } | null>(null);
  const reload = async () => {
    setLoading(true);
    setFailure('');
    try {
      const [s, b, r] = await Promise.all([
        api.get('/api/capper/status'), api.get('/api/capper/board'), api.get('/api/capper/record')
      ]);
      setStatus(s.data as Status);
      setBoard(b.data as Board);
      setRecord(r.data as RecordView);
      try { const p = await api.get('/api/clutch-sports/props'); setClutch(p.data); } catch { setClutch({ connected: false, rows: [], reason: 'Clutch Sports props unavailable' }); }
    } catch {
      setFailure('The capper service could not be loaded. Retry to check the backend connection.');
    } finally {
      setLoading(false);
    }
  };
  useEffect(() => { void reload(); }, []);
  const script = board?.script || (board?.items?.length
    ? 'Welcome to Clutch Bets. Today we have market watchlist signals, not locks. Check the source, game time and current price. Every unit is $25. Never bet more than you can afford to lose.'
    : 'Welcome to Clutch Bets. Coach Clutch here. The board is clear right now: no sourced, qualified picks. We never force a play. Check back after the next data refresh.');
  return (
    <div className="capper">
      <div className="capperTitle">
        <div><span className="capperEyebrow">CLUTCH BETS / THE RESEARCH DESK</span><h2>AI Capper Command Center</h2><p>Real source snapshots. Market-first analysis. A record that earns its credibility.</p></div>
        <button className="capperBtn ghost" onClick={reload} disabled={loading}>{loading ? 'Checking…' : 'Reload board'}</button>
      </div>
      <div className="capperPills">
        <span className={clutch?.connected ? 'capperGood' : 'capperAlert'}>{clutch?.connected ? '● Clutch Sports API connected' : '● Clutch Sports API not connected'}</span>
        <span><Database size={14} /> {status?.source || 'The Odds API v4'}</span>
        <span><CalendarClock size={14} /> {when(board?.updatedAt || '')}</span>
        <span><ShieldCheck size={14} /> 1 unit = $25</span>
      </div>
      {failure && <div role="alert" className="capperCallout danger">{failure}</div>}
      {clutch?.connected && <div className="capperCallout"><strong>Clutch Sports API — live connection</strong><p>NBA player props returned: {clutch.count ?? 0}. This is an unverified research feed, not a list of approved picks.</p>{clutch.rows.length > 0 && <div style={{overflowX:'auto'}}><table style={{width:'100%',textAlign:'left'}}><thead><tr><th>Player</th><th>Game</th><th>Market</th><th>Line</th><th>Odds</th><th>Book</th></tr></thead><tbody>{clutch.rows.slice(0,30).map((x,i)=><tr key={i}><td>{x.player}</td><td>{x.game}</td><td>{x.market}</td><td>{x.line ?? '—'}</td><td>{x.odds ?? '—'}</td><td>{x.book}</td></tr>)}</tbody></table></div>}{clutch.note && <small>{clutch.note}</small>}</div>}
      {clutch && !clutch.connected && <div className="capperCallout">Clutch Sports connection: {clutch.reason || 'Unavailable'}</div>}
      {!loading && status && !status.configured && (
        <div className="capperCallout">
          <strong>Legacy market signal engine is not configured</strong>
          <p>The legacy cross-book model uses a different provider and is not yet configured. Your connected Clutch Sports NBA props feed is shown separately above. No simulated picks will be substituted.</p>
        </div>
      )}
      {board?.warning && status?.configured && <div className="capperCallout">{board.warning}</div>}
      <div className="capperStats">
        <div><span>CURRENT QUALIFIED SIGNALS</span><b>{board?.items?.length || 0}</b><small>Market screen only</small></div>
        <div><span>RECENT VERIFIED RESULTS</span><b>{record?.settled || 0}</b><small>Provider-scored outcomes</small></div>
        <div><span>WIN / LOSS / PUSH</span><b>{record ? record.won + ' / ' + record.lost + ' / ' + record.pushed : '—'}</b><small>Recent tracked model signals</small></div>
        <div><span>MODEL ROI</span><b>{record?.roi === null || record?.roi === undefined ? '—' : record.roi.toFixed(1) + '%'}</b><small>Hypothetical $25 per settled signal</small></div>
      </div>
      <div className="capperTabs" role="tablist">
        <button className={section === 'board' ? 'active' : ''} onClick={() => setSection('board')}><Target size={17} /> Research Board</button>
        <button className={section === 'record' ? 'active' : ''} onClick={() => setSection('record')}><TrendingUp size={17} /> Verified Record</button>
        <button className={section === 'presenter' ? 'active' : ''} onClick={() => setSection('presenter')}><Clapperboard size={17} /> Coach Clutch Studio</button>
      </div>
      {section === 'board' && <div className="capperPanel">
        <div className="capperPanelTitle"><h3>Qualified market signals</h3><span>Updated {when(board?.updatedAt || '')}</span></div>
        {!board?.items?.length ? <div className="capperEmpty"><Activity size={30} /><strong>No sourced picks on the board</strong><p>Nothing will be displayed until the connected data feed produces qualifying results. This is not a betting recommendation.</p></div> :
        <div className="capperCards">{board.items.map((x) => <div className="capperCard" key={x.id}>
          <div className="capperCardHead"><b>{x.sport}</b><span>MARKET SCORE {x.marketScore}/100</span></div>
          <h4>{x.selection}{x.point !== null ? ' ' + x.point : ''}</h4>
          <p>{x.event} · {x.market.toUpperCase()}</p>
          <div className="capperLine"><strong>{odds(x.price)}</strong><span>{x.sportsbook}</span><span>{x.books} quoted books</span></div>
          <div className="capperDetails"><span>Cross-book edge <b>{x.edge.toFixed(1)} pts</b></span><span>Fair estimate <b>{x.fairProbability.toFixed(1)}%</b></span><span>Quoted implied <b>{x.impliedProbability.toFixed(1)}%</b></span></div>
          <small>Captured {when(x.capturedAt)}. {x.model}. Prices may have moved.</small>
        </div>)}</div>}
        <div className="capperCaution">Market Score is an evidence grade, not win probability. A listed edge is a cross-book estimate, not a guarantee. Injury news, lineup confirmation, opponent tendencies and last-10 player stats are not yet supplied by this feed. Model signals are automatically logged, not wagers placed on your behalf.</div>
      </div>}
      {section === 'record' && <div className="capperPanel">
        <div className="capperPanelTitle"><h3>Score-verified model record</h3><span>{record?.total || 0} most recent signals</span></div>
        <p className="capperFine">{record?.note || 'Not yet graded. No historical results have been invented.'}</p>
        {!record?.rows?.length ? <div className="capperEmpty"><CheckCircle2 size={30}/><strong>Track record starts at zero</strong><p>Only timestamped selections from future data refreshes enter the record.</p></div> :
        <div className="capperRecord">{record.rows.map(x => <div className="capperResult" key={x.id}><div><b>{x.selection}{x.point !== null ? ' ' + x.point : ''}</b><small>{x.sport} · {x.event} · {x.market} · {odds(x.price)}</small><small>{when(x.capturedAt)} · {x.sportsbook}</small>{x.finalScore && <small>{x.finalScore}</small>}</div><span className={'result-' + x.status.toLowerCase()}>{x.status}</span></div>)}</div>}
        <p className="capperFine">Profit/ROI is a hypothetical 1-unit model ledger, not a claim about anyone's sportsbook account, and excludes open/push stakes. Results outside the provider's recent-score coverage remain open rather than being guessed.</p>
      </div>}
      {section === 'presenter' && <div className="capperPanel">
        <div className="capperPanelTitle"><h3>Coach Clutch • Presenter Desk</h3><span>Video script prep</span></div>
        <div className="capperPresenter"><div className="capperCharacter"><div className="capperMonogram">CC</div><h4>COACH CLUTCH</h4><p>Original AI sports analyst persona</p><small>One locked identity · one consistent voice · 9:16 primary</small></div>
        <div className="capperScript"><span className="capperEyebrow">APPROVAL-READY NARRATION DRAFT</span><p>{script}</p><button className="capperBtn" onClick={async () => { try { await navigator.clipboard.writeText(script); setCopied(true); } catch { setCopied(false); } }}><Copy size={15}/>{copied ? 'Copied to clipboard' : 'Copy presenter script'}</button><small>Script is generated from captured market data when available; generic intro shown otherwise. Video rendering and publishing are separate approval steps.</small></div></div>
      </div>}
      <div className="capperFooter"><strong>Locked guardrails</strong><span>No manufactured stats · No guaranteed returns · No auto-betting · No unapproved publishing</span><span>Refresh: {status?.refresh || '12:15 PM ET'} · Grading: {status?.grading || '9:05 AM ET'}</span></div>
    </div>
  );
}