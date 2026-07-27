const API = new URLSearchParams(location.search).get('api') || ((location.protocol.startsWith('http') && location.port !== '8080') ? location.origin : null) || localStorage.getItem('api') || 'http://localhost:8000';
const WALKER = n => API + '/walker/' + n;
const CG_IDENT = { type: 'username', value: 'caregraph-demo' };
const CG_CRED = { type: 'password', password: 'caregraph-demo-2026' };
const CG_TKEY = 'cg_token:' + API;
async function cgToken(force) {
  if (!force) { const t = localStorage.getItem(CG_TKEY); if (t) return t; }
  try {
    await fetch(API + '/user/register', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ identities: [CG_IDENT], credential: CG_CRED }) });
  } catch (e) {}
  try {
    const r = await fetch(API + '/user/login', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ identity: CG_IDENT, credential: CG_CRED }) });
    const j = await r.json();
    const t = (j.data && j.data.token) || j.token || '';
    if (t) { localStorage.setItem(CG_TKEY, t); return t; }
  } catch (e) {}
  return '';
}
function cgHeaders(tok) {
  return Object.assign({ 'Content-Type': 'application/json' }, tok ? { 'Authorization': 'Bearer ' + tok } : {});
}
async function callWalker(name, body = {}) {
  // Authenticated by default: the hosted sandbox rejects anonymous graph
  // writes; a per-device auto-registered demo user gives every page (and the
  // phone) the same server-side root. 401 = stale token -> re-auth once.
  let tok = await cgToken(false);
  let r = await fetch(WALKER(name), { method: 'POST', headers: cgHeaders(tok), body: JSON.stringify(body) });
  if (r.status === 401) {
    tok = await cgToken(true);
    r = await fetch(WALKER(name), { method: 'POST', headers: cgHeaders(tok), body: JSON.stringify(body) });
  }
  if (!r.ok) throw new Error(name + ' ' + r.status);
  const j = await r.json();
  const rep=(j.data&&j.data.reports)||j.reports; return rep?(rep[0]??j):j;
}
const sleep = ms => new Promise(res => setTimeout(res, ms));
let lastDayCount = 0;
function setPatient(name, days) {
  if (!name) return;
  if (days) lastDayCount = days;          // graph poll passes no days — keep the last known
  document.getElementById('patientName').textContent =
    '— ' + name + (lastDayCount ? ' · day ' + lastDayCount : '');
  document.getElementById('askInput').placeholder =
    'Ask about ' + name + '’s memory…';
}
const esc = s => String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
function mdish(s) {
  return esc(s).split('\n').map(line => {
    if (/^#{1,4}\s/.test(line)) return '<strong>' + line.replace(/^#{1,4}\s/, '') + '</strong>';
    return line.replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>');
  }).join('<br>');
}
const MONTHS = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
function fmtTs(ts) {
  const d = new Date(ts);
  if (isNaN(d)) return String(ts || '').slice(0, 16);
  return MONTHS[d.getMonth()] + ' ' + d.getDate() + ' · '
    + String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
}
function fmtDay(ts) {
  const d = new Date(ts);
  if (isNaN(d)) return String(ts || '').slice(0, 10);
  return MONTHS[d.getMonth()] + ' ' + d.getDate();
}

/* ---------- Plain-English humanizer ----------
   Every user-visible string that might carry technical tokens goes through
   this before rendering (cards, checklists, modal, alert chips).           */
const KIND_LABELS = {
  repeat_question: 'Repeated question',
  name_confusion: 'Mixed up a name',
  disorientation: 'Got disoriented',
  positive_recall: 'A bright moment',
  social_moment: 'Good social time'
};
const kindLabel = k => KIND_LABELS[String(k || '').toLowerCase()] || String(k || '').replace(/_/g, ' ');
function humanize(s) {
  let t = String(s ?? '');
  t = t.replace(/\[signal:\s*([a-z_]+)\s*\]\s*/gi, (m, k) => kindLabel(k) + ' — ');
  t = t.replace(/\[L1_wearable\]\s*/gi, 'Heard — ');
  t = t.replace(/\[L2_caregiver\]\s*/gi, 'Caregiver note — ');
  t = t.replace(/\bL1_wearable\b/gi, 'heard by the wearable');
  t = t.replace(/\bL2_caregiver\b/gi, 'caregiver note');
  for (const k of Object.keys(KIND_LABELS)) t = t.replace(new RegExp('\\b' + k + '\\b', 'g'), KIND_LABELS[k]);
  return t;
}

/* ---------- Persistent card dismissals ---------- */
const DISMISS_KEY = 'mb_dismissed';
let dismissed = new Set();
try { dismissed = new Set(JSON.parse(localStorage.getItem(DISMISS_KEY) || '[]')); } catch (e) {}
function saveDismissed() {
  try { localStorage.setItem(DISMISS_KEY, JSON.stringify([...dismissed])); } catch (e) {}
}

/* ---------- D3 graph ---------- */
// Morning Light data palette (PR #1). Validated (OKLab dE + CVD sim + WCAG)
// against the cream surface. Semantics: red = trouble, jade = intact,
// blue = people, gold = her. Entry/Report are deliberately neutral.
const COLORS = { Patient: '#A87A10', Person: '#2A6FA8', Fact: '#2FA37A', Event: '#2FA37A',
                 Signal: '#C0392B', Entry: '#746D69', Report: '#746D69' };

// Positive signals must not wear the alarm red — positive_recall is the one
// node proving this isn't a doom meter. Reuses the jade, no new hue.
const SIGNAL_COLOR = { positive_recall: '#2FA37A', social_moment: '#2FA37A' };
const nodeColor = d =>
  (d.type === 'Signal' && SIGNAL_COLOR[d.kind]) || COLORS[d.type] || '#746D69';

// Most Signals are repeat_question; rendered full-size they drown the graph.
// Only the signals worth looking at individually stay loud; the repeats
// recede into a faint ring — which reads as "she is stuck on the same
// question" without hiding the genuinely new events.
const LOUD_KINDS = new Set(['name_confusion', 'disorientation', 'positive_recall']);
const isLoud = d => d.type !== 'Signal' || LOUD_KINDS.has(d.kind);

const RADIUS = d => {
  if (d.type === 'Patient') return 22;
  if (d.type === 'Entry')   return 3;
  if (d.type === 'Report')  return 8;
  if (d.type === 'Signal')  return isLoud(d) ? 13 : 4;
  return 10;
};
const NODE_OPACITY = d =>
  d.type === 'Entry' ? 0.22 :
  (d.type === 'Signal' && !isLoud(d)) ? 0.32 : 1;
const SHOW_LABEL = d => !(d.type === 'Entry' || (d.type === 'Signal' && !isLoud(d)));

// Legend follows the semantics, not the seven raw node types.
document.getElementById('legend').innerHTML = [
  ['Margaret', '#A87A10'], ['People', '#2A6FA8'], ['What she knows', '#2FA37A'],
  ['Warning signs', '#C0392B'], ['Raw records', '#746D69']
].map(([t, c]) => `<span class="lg"><i style="background:${c}"></i>${t}</span>`).join('');

const svg = d3.select('#graph');
const zoomG = svg.append('g');
const gLink = zoomG.append('g');
const gNode = zoomG.append('g');
svg.call(d3.zoom().scaleExtent([0.25, 4]).on('zoom', e => zoomG.attr('transform', e.transform)));

const pane = document.getElementById('graphPane');
let W = pane.clientWidth || 800, H = pane.clientHeight || 600;
const sim = d3.forceSimulation()
  .force('charge', d3.forceManyBody().strength(-260))
  .force('link', d3.forceLink().id(d => d.id).distance(84))
  .force('collide', d3.forceCollide().radius(d => RADIUS(d) + 9))
  .force('center', d3.forceCenter(W / 2, H / 2))
  .on('tick', () => {
    gLink.selectAll('path').attr('d', linkArc);
    gNode.selectAll('g.node').attr('transform', d => `translate(${d.x},${d.y})`);
  });

// Gentle arc between nodes (the design mock's soft curves — straight spokes
// read as a wiring diagram, curves read as something organic).
function linkArc(d) {
  const sx = d.source.x, sy = d.source.y, tx = d.target.x, ty = d.target.y;
  const dx = tx - sx, dy = ty - sy;
  const dr = Math.sqrt(dx * dx + dy * dy) * 2.1;
  if (!dr) return `M${sx},${sy}L${tx},${ty}`;
  return `M${sx},${sy}A${dr},${dr} 0 0,1 ${tx},${ty}`;
}
window.addEventListener('resize', () => {
  W = pane.clientWidth; H = pane.clientHeight;
  sim.force('center', d3.forceCenter(W / 2, H / 2)).alpha(0.3).restart();
});

let nodesById = new Map();
let knownIds = new Set();
let latestSnapshot = null;
let replaying = false, dragging = false;
let tlDebounce = null;

// Links are context, not content: warm-toned and faint (the design mock's
// graph reads clean because edges nearly vanish). `mentioned` edges are the
// hairball-makers — they drop to a whisper.
const LINK_COLOR = '#c2a983';
const linkBaseOpacity = d =>
  d.type === 'mentioned' ? 0.16 :
  d.type === 'remembers' && d.confidence != null
    ? Math.max(0.25, Math.min(0.95, +d.confidence)) * 0.8 : 0.35;

function drag() {
  return d3.drag()
    .on('start', (e, d) => { dragging = true; if (!e.active) sim.alphaTarget(0.3).restart(); d.fx = d.x; d.fy = d.y; })
    .on('drag', (e, d) => { d.fx = e.x; d.fy = e.y; })
    .on('end', (e, d) => { dragging = false; if (!e.active) sim.alphaTarget(0); d.fx = null; d.fy = null; });
}

function updateGraph(data) {
  if (!data || !Array.isArray(data.nodes)) return;
  latestSnapshot = data;
  const nodes = data.nodes.map(n => Object.assign(nodesById.get(n.id) || {}, n));
  nodesById = new Map(nodes.map(n => [n.id, n]));
  const links = (data.links || [])
    .filter(l => nodesById.has(l.source?.id ?? l.source) && nodesById.has(l.target?.id ?? l.target))
    .map(l => ({ source: l.source?.id ?? l.source, target: l.target?.id ?? l.target,
                 type: l.type, confidence: l.confidence }));

  const fresh = knownIds.size ? nodes.filter(n => !knownIds.has(n.id)) : [];
  knownIds = new Set(nodes.map(n => n.id));

  gLink.selectAll('path')
    .data(links, d => (d.source.id ?? d.source) + '|' + (d.target.id ?? d.target) + '|' + d.type)
    .join('path')
    .attr('fill', 'none')
    .attr('stroke', LINK_COLOR).attr('stroke-width', 1)
    .attr('opacity', linkBaseOpacity);

  const nodeSel = gNode.selectAll('g.node').data(nodes, d => d.id)
    .join(enter => {
      const g = enter.append('g').attr('class', 'node').style('cursor', 'pointer').call(drag());
      g.append('circle')
        .attr('r', RADIUS)
        .attr('fill', nodeColor)
        .attr('stroke', '#fffdfa').attr('stroke-width', 1.5);
      g.append('text')
        .attr('dy', d => RADIUS(d) + 12).attr('text-anchor', 'middle')
        .attr('font-size', 10).attr('fill', '#7A6A5C')
        .style('pointer-events', 'none');
      g.append('title');
      return g;
    });
  nodeSel.attr('opacity', NODE_OPACITY);
  nodeSel.select('circle').attr('r', RADIUS).attr('fill', nodeColor);
  nodeSel.select('text')
    .attr('display', d => SHOW_LABEL(d) ? null : 'none')
    .attr('dy', d => RADIUS(d) + 12)
    .text(d => {
      const l = d.label || d.name || '';
      return l.length > 18 ? l.slice(0, 17) + '…' : l;
    });
  nodeSel.select('title').text(d => (d.type || '') + ': ' + (d.label || ''));

  const changed = fresh.length > 0 ||
    nodes.length !== sim.nodes().length ||
    links.length !== sim.force('link').links().length;
  sim.nodes(nodes);
  sim.force('link').links(links);
  if (changed) sim.alpha(0.6).restart();   // only reheat when the graph actually grew/shrank

  fresh.forEach(n => flashNode(n.id));
  if (fresh.length) {                      // graph grew — refresh the tier columns too
    clearTimeout(tlDebounce);
    tlDebounce = setTimeout(loadTimeline, 800);
  }

  const p = nodes.find(n => n.type === 'Patient');
  if (p) setPatient(p.label || p.name || '');
}

function flashNode(id) {
  const sel = gNode.selectAll('g.node').filter(d => d.id === id).select('circle');
  if (sel.empty()) return;
  const r0 = +sel.attr('r');
  sel.transition().duration(350).attr('r', r0 * 2.2).attr('stroke', '#dd8a4e').attr('stroke-width', 4)
     .transition().duration(350).attr('r', r0)
     .transition().duration(350).attr('r', r0 * 1.8)
     .transition().duration(400).attr('r', r0).attr('stroke', '#fffdfa').attr('stroke-width', 1.5);
}

async function pollGraph() {
  if (replaying || dragging) return;
  try { updateGraph(await callWalker('graph_snapshot')); }
  catch (e) { console.warn('snapshot failed:', e.message); }
}
pollGraph();
setInterval(pollGraph, 5000);

/* ---------- Ask + spotlight replay ---------- */
async function runReplay(path) {
  replaying = true;
  const nodeSel = gNode.selectAll('g.node');
  const linkSel = gLink.selectAll('path');
  nodeSel.attr('opacity', 0.15);
  linkSel.attr('opacity', 0.05);
  let prev = null;
  for (const id of path) {
    const hit = nodeSel.filter(d => d.id === id);
    if (hit.empty()) continue;               // id not in current graph — skip gracefully
    hit.attr('opacity', 1);
    const c = hit.select('circle');
    const r0 = RADIUS(hit.datum());
    c.transition().duration(250).attr('r', r0 * 1.9).attr('stroke', '#4a3f33').attr('stroke-width', 3);
    if (prev !== null) {
      linkSel.filter(d => {
        const s = d.source.id ?? d.source, t = d.target.id ?? d.target;
        return (s === prev && t === id) || (s === id && t === prev);
      }).attr('opacity', 0.9).attr('stroke', '#a5732f');
    }
    prev = id;
    await sleep(400);
  }
  await sleep(1400);
  // restore the degraded state, not a flat opacity:1 — otherwise every question
  // permanently un-dims the repeat_question dots and the graph drowns again
  nodeSel.attr('opacity', NODE_OPACITY);
  nodeSel.select('circle').transition().duration(400)
    .attr('r', RADIUS).attr('stroke', '#fffdfa').attr('stroke-width', 1.5);
  linkSel.attr('stroke', LINK_COLOR).attr('opacity', linkBaseOpacity);
  replaying = false;
}

async function doAsk() {
  const q = document.getElementById('askInput').value.trim();
  if (!q) return;
  const btn = document.getElementById('askBtn');
  btn.disabled = true; btn.textContent = '…';
  try {
    const ans = await callWalker('ask', { question: q });
    const card = document.getElementById('answerCard');
    card.style.display = 'block';
    const n = Array.isArray(ans.evidence) ? ans.evidence.length : 0;
    const hops = Array.isArray(ans.path) ? ans.path.length : 0;
    document.getElementById('answerText').textContent = (!hops && !n)
      ? "Nothing in the memory graph matches that. Try naming a person or thing — e.g. 'Does she remember Emma?'"
      : (ans.answer || '(no answer)');
    document.getElementById('answerEvidence').textContent =
      'traced ' + hops + ' nodes · ' + n + ' ' + (n === 1 ? 'entry' : 'entries') + ' · RecallWalker';
    if (Array.isArray(ans.path) && ans.path.length) await runReplay(ans.path);
  } catch (e) {
    document.getElementById('answerCard').style.display = 'block';
    document.getElementById('answerText').textContent = 'Could not reach the memory graph. Is the backend running?';
    document.getElementById('answerEvidence').textContent = '';
  } finally {
    btn.disabled = false; btn.textContent = 'Ask';
  }
}
document.getElementById('askBtn').addEventListener('click', doAsk);
document.getElementById('askInput').addEventListener('keydown', e => { if (e.key === 'Enter') doAsk(); });
document.querySelectorAll('.asksugg .sg').forEach(b =>
  b.addEventListener('click', () => {
    document.getElementById('askInput').value = b.textContent;
    doAsk();
  }));
document.getElementById('answerClose').addEventListener('click', () => {
  document.getElementById('answerCard').style.display = 'none';
});

/* ---------- Alerts strip ---------- */
// Status colours are reserved, never reused as categorical hues. `low` covers
// positive_recall / social_moment, so it must not read as an alarm — jade.
const SEV_COLOR = s => {
  s = String(s || '').toLowerCase();
  if (s === 'high' || s === 'critical' || s === 'severe') return '#C0392B';
  if (s === 'medium' || s === 'moderate' || s === 'warn') return '#B4762A';
  return '#2FA37A';
};
async function loadAlerts() {
  const box = document.getElementById('alertsBody');
  try {
    const r = await callWalker('critique_alerts');
    const alerts = Array.isArray(r?.alerts) ? r.alerts : Array.isArray(r) ? r : [];
    if (!alerts.length) { box.innerHTML = '<span class="chip-none">No alerts — all steady.</span>'; return; }
    box.innerHTML = alerts.map(a => {
      // The chip already shows the kind in bold — strip it from the detail,
      // whether the backend sent the raw kind or the plain-English label.
      let rate = String(a.detail || '');
      const kind = kindLabel(a.kind || 'alert');
      if (a.kind && rate.startsWith(a.kind + ':')) rate = rate.slice(a.kind.length + 1).trim();
      if (rate.startsWith(kind + ':')) rate = rate.slice(kind.length + 1).trim();
      if (rate.startsWith(kind + ' —')) rate = rate.slice(kind.length + 2).trim();
      if (rate.length > 48) rate = rate.slice(0, 47) + '…';   // chips stay short; full text in the tooltip
      const verdict = a.verdict === 'confirmed'
        ? `<span class="vok">✓ verified · ${a.evidence?.length || 0} evidence</span>`
        : a.verdict ? `<span class="vplain">${esc(a.verdict)}</span>` : '';
      return `<span class="achip" title="CritiqueWalker · ${esc(a.detail || '')}">
        <span class="sev" style="background:${SEV_COLOR(a.severity)}"></span>
        <strong>${esc(kind)}</strong>
        <span class="rate">${esc(rate)}</span>
        ${verdict}
      </span>`;
    }).join('');
  } catch (e) { box.innerHTML = '<span class="chip-none">Alerts unavailable.</span>'; }
}
loadAlerts();
setInterval(loadAlerts, 30000);

/* ---------- Tier columns: state ---------- */
let timelineData = { entries: [], reports: [], patient: null };
let rawQuery = '';
let handoffDraft = null;          // {report_id, items, content} — reviewed in the modal
let doctorCards = [];             // client-side only: doctor_report does not persist
let modalOpen = false;
const expandedKeys = new Set();
const CARD_REG = new Map();       // key -> {title, text, md} for the modal

function setCount(col, n) {
  document.getElementById('cnt-' + col).textContent = n;
  document.getElementById('railcnt-' + col).textContent = n;
}

function tcard(key, mtitle, headHTML, text, md, tagsHTML) {
  text = humanize(text);
  CARD_REG.set(key, { title: mtitle, text: String(text || ''), md: !!md });
  const open = expandedKeys.has(key);
  const inner = md ? mdish(text) : esc(text).replace(/\n/g, '<br>');
  return `<div class="tcard" data-key="${esc(key)}">
    <div class="thead">${headHTML}<button class="xbtn" title="Hide card">&#10005;</button></div>
    <div class="tbody${open ? '' : (key.startsWith('entry:') ? ' clamp2' : ' clamp3')}">${inner}</div>
    ${tagsHTML || ''}
  </div>`;
}
const statusChip = s => s === 'confirmed'
  ? '<span class="chip green">confirmed</span>'
  : `<span class="chip amber">${esc(s || 'draft')}</span>`;
const byTsDesc = (a, b) => String(b.ts || '').localeCompare(String(a.ts || ''));

/* ---------- Column ①: Raw data ---------- */
// "→ Person · Emma"-style pills under each moment, derived from the graph's
// `mentioned` edges — no extra backend call, the snapshot already has them.
function entryTags(id) {
  if (!latestSnapshot) return '';
  const labels = [];
  for (const l of (latestSnapshot.links || [])) {
    if (l.type !== 'mentioned' || l.source !== id) continue;
    const n = nodesById.get(l.target);
    if (!n) continue;
    if (n.type === 'Person') labels.push('Person · ' + (n.label || ''));
    else if (n.type === 'Signal') labels.push(kindLabel(n.kind));
    else if (n.type === 'Fact' || n.type === 'Event') labels.push(n.label || '');
    if (labels.length >= 3) break;
  }
  return labels.length
    ? '<div class="tags">' + labels.map(t => `<span class="tag">&rarr; ${esc(t)}</span>`).join('') + '</div>'
    : '';
}
let knownEntryIds = null;   // null until first render: seed data never flashes
function renderRaw() {
  const box = document.getElementById('body-raw');
  const fetched = (timelineData.entries || []).slice().sort(byTsDesc);
  const fresh = new Set();
  if (knownEntryIds !== null) {
    for (const en of fetched) { if (!knownEntryIds.has(en.id)) fresh.add(en.id); }
  }
  knownEntryIds = new Set(fetched.map(en => en.id));
  const all = fetched.filter(en => !dismissed.has('entry:' + en.id));
  setCount('raw', all.length);
  const shown = rawQuery
    ? all.filter(en => (String(en.text || '') + ' ' + fmtTs(en.ts)).toLowerCase().includes(rawQuery))
    : all;
  if (!shown.length) {
    box.innerHTML = `<div class="empty">${rawQuery ? 'No matches.' : 'Nothing here yet.'}</div>`;
    return;
  }
  box.innerHTML = shown.map(en => {
    const isNote = String(en.source || '') === 'L2_caregiver';
    const srcChip = isNote
      ? '<span class="chip green">note</span>'
      : '<span class="chip amber">heard</span>';
    const head = srcChip + '<span class="spacer"></span>'
      + `<span class="time">${esc(fmtTs(en.ts))}</span>`;
    const text = isNote ? (en.text || '') : '“' + (en.text || '') + '”';
    const card = tcard('entry:' + en.id, 'Moment — ' + fmtTs(en.ts), head, text, false,
                       entryTags(en.id));
    return fresh.has(en.id) ? card.replace('class="tcard"', 'class="tcard fresh"') : card;
  }).join('');
}
document.getElementById('rawSearch').addEventListener('input', e => {
  rawQuery = e.target.value.trim().toLowerCase();
  renderRaw();
});

/* ---------- Column ②: Daily reports ---------- */
function renderDaily() {
  const box = document.getElementById('body-daily');
  const reps = (timelineData.reports || [])
    .filter(r => r.kind === 'daily' && !dismissed.has('report:' + r.id)).sort(byTsDesc);
  setCount('daily', reps.length);
  if (!reps.length) { box.innerHTML = '<div class="empty">Nothing here yet.</div>'; return; }
  box.innerHTML = reps.map(r => {
    const head = `<span class="rtitle">${esc(fmtDay(r.ts))}</span>` + statusChip(r.status)
      + '<span class="spacer"></span>';
    return tcard('report:' + r.id, 'Daily note — ' + fmtDay(r.ts), head, r.content || '', true);
  }).join('');
}
function newestEntryDate() {
  let m = '';
  (timelineData.entries || []).forEach(en => {
    const d = String(en.ts || '').slice(0, 10);
    if (d > m) m = d;
  });
  return m || new Date().toISOString().slice(0, 10);
}
document.getElementById('dailyBtn').addEventListener('click', async () => {
  const btn = document.getElementById('dailyBtn');
  btn.disabled = true; btn.textContent = 'Writing…';
  try {
    await callWalker('daily_report', { date: newestEntryDate() });
    await loadTimeline();
  } catch (e) { alert('Could not write the note: ' + e.message); }
  finally { btn.disabled = false; btn.textContent = 'Write today’s note'; }
});

/* ---------- Column ③: Handoff ---------- */
/* Draft flow: one compact card in the column; the actual checklist review
   happens in the fullscreen modal (openReviewModal). */
function draftCardHTML() {
  const d = handoffDraft;
  if (!d || dismissed.has('draft:' + d.report_id)) return '';
  const n = d.items.length;
  return `<div class="tcard draft" data-review="1" data-key="${esc('draft:' + d.report_id)}">
    <div class="thead"><span class="rtitle">Draft</span><span class="chip amber">needs review</span>
      <span class="spacer"></span><button class="xbtn" title="Hide card">&#10005;</button></div>
    <div class="tbody">${n} item${n === 1 ? '' : 's'} to check — tap to review &amp; confirm</div>
  </div>`;
}
function renderHandoff() {
  const box = document.getElementById('body-handoff');
  const past = (timelineData.reports || [])
    .filter(r => r.kind === 'handoff'
      && !(handoffDraft && r.id === handoffDraft.report_id)
      && !dismissed.has('report:' + r.id))
    .sort(byTsDesc);
  const draftHTML = draftCardHTML();
  setCount('handoff', past.length + (draftHTML ? 1 : 0));
  const pastHTML = past.map(r => {
    const head = `<span class="rtitle">${esc(fmtTs(r.ts))}</span>` + statusChip(r.status)
      + '<span class="spacer"></span>';
    return tcard('report:' + r.id, 'Handoff — ' + fmtTs(r.ts), head, r.content || '', true);
  }).join('');
  box.innerHTML = (draftHTML + pastHTML) || '<div class="empty">Nothing here yet — tap “Draft handoff”.</div>';
}
function openReviewModal() {
  const d = handoffDraft;
  if (!d) return;
  modalOpen = true;
  document.getElementById('modalTitle').textContent = 'Review handoff — uncheck anything not to pass on';
  const list = d.items.length
    ? d.items.map(it =>
        `<label class="item"><input type="checkbox" checked value="${esc(it.id)}"><span>${esc(humanize(it.text))}</span></label>`
      ).join('')
    : '<div class="muted">No new items since the last handoff.</div>';
  document.getElementById('modalBody').innerHTML = list
    + (d.content ? `<div class="preview" style="max-height:none">${mdish(humanize(d.content))}</div>` : '')
    + `<button id="reviewConfirm" style="margin-top:14px;width:100%">Confirm handoff</button>`;
  document.getElementById('modalOverlay').classList.add('show');
  document.getElementById('reviewConfirm').addEventListener('click', async ev => {
    ev.target.disabled = true; ev.target.textContent = 'Confirming…';
    const approved = [...document.querySelectorAll('#modalBody input:checked')].map(el => el.value);
    try {
      await callWalker('handoff_confirm', { report_id: d.report_id, approved });
      handoffDraft = null;         // draft is done — the confirmed card comes from the timeline
      closeModal();
      await loadTimeline();
      loadAlerts();
    } catch (e) {
      ev.target.disabled = false; ev.target.textContent = 'Confirm handoff';
      alert('Confirm failed: ' + e.message);
    }
  });
}
/* ---------- Caregiver observation input (feeds the graph as L2) ---------- */
const obsInput = document.getElementById('obsInput');
const obsLive = document.getElementById('obsLive');
async function submitObservation() {
  const text = obsInput.value.trim();
  if (!text) return;
  obsInput.disabled = true;
  try {
    await callWalker('ingest_batch', { source: 'L2_caregiver', text, ts: new Date().toISOString() });
    obsInput.value = ''; obsLive.textContent = '';
    loadTimeline(); pollGraph(); loadAlerts();
  } catch (e) { alert('Could not save observation: ' + e.message); }
  finally { obsInput.disabled = false; obsInput.focus(); }
}
obsInput.addEventListener('keydown', e => { if (e.key === 'Enter') submitObservation(); });
const obsMicBtn = document.getElementById('obsMic');
let obsRec = null, obsRecOn = false;
obsMicBtn.addEventListener('click', () => {
  const SR = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SR) { alert('Voice input needs Chrome.'); return; }
  if (obsRecOn) { obsRecOn = false; try { obsRec.stop(); } catch (e) {} obsMicBtn.classList.remove('rec'); obsLive.textContent = ''; return; }
  obsRec = new SR();
  obsRec.continuous = true; obsRec.interimResults = true; obsRec.lang = 'en-US';
  obsRec.onresult = ev => {
    let interim = '';
    for (let i = ev.resultIndex; i < ev.results.length; i++) {
      const t = ev.results[i][0].transcript;
      if (ev.results[i].isFinal) { obsInput.value = (obsInput.value + ' ' + t).trim(); }
      else interim += t;
    }
    obsLive.textContent = interim.trim();
  };
  obsRec.onend = () => { if (obsRecOn) { try { obsRec.start(); } catch (e) {} } };
  obsRecOn = true; obsMicBtn.classList.add('rec');
  try { obsRec.start(); } catch (e) {}
});

document.getElementById('handoffBtn').addEventListener('click', async () => {
  const btn = document.getElementById('handoffBtn');
  btn.disabled = true; btn.textContent = 'Drafting…';
  try {
    const d = await callWalker('handoff_draft');
    handoffDraft = {
      report_id: d.report_id,
      items: Array.isArray(d.items) ? d.items : [],
      content: d.content || ''
    };
    dismissed.delete('draft:' + handoffDraft.report_id);   // a fresh draft always shows
    renderHandoff();
  } catch (e) { alert('Could not draft handoff: ' + e.message); }
  finally { btn.disabled = false; btn.textContent = 'Draft handoff'; }
});

/* ---------- Column ④: Doctor (self-contained — no separate page) ---------- */
function renderDoctor() {
  const box = document.getElementById('body-doctor');
  const shown = doctorCards.filter(c => !dismissed.has('doctor:' + c.id));
  setCount('doctor', shown.length);
  if (!shown.length) { box.innerHTML = '<div class="empty">Nothing here yet.</div>'; return; }
  box.innerHTML = shown.map(c => `<div class="tcard" data-doctor="${esc(c.id)}" data-key="${esc('doctor:' + c.id)}">
    <div class="thead"><span class="rtitle">Doctor report</span><span class="spacer"></span>
      <span class="time">${esc(c.ts)}</span>
      <button class="xbtn" title="Hide card">&#10005;</button></div>
    <div class="tbody clamp3">${mdish(humanize(c.content))}</div>
  </div>`).join('');
}
function dayWords(w) {
  const rq = +w.repeat_q || 0, cf = +w.confusions || 0;
  if (!rq && !cf) return 'a calm day';
  const parts = [];
  if (rq) parts.push(rq + (rq === 1 ? ' repeated question' : ' repeated questions'));
  if (cf) parts.push(cf + (cf === 1 ? ' time confused' : ' times confused'));
  return parts.join(' · ');
}
function openDoctorModal(c) {
  modalOpen = true;
  document.getElementById('modalTitle').textContent = 'Doctor report — ' + c.ts;
  const rows = (c.weekly || []).map(w =>
    `<tr><td>${esc(w.week)}</td><td>${esc(dayWords(w))}</td></tr>`).join('');
  const table = rows
    ? `<table class="daytable"><thead><tr><th>Day</th><th>What we counted</th></tr></thead><tbody>${rows}</tbody></table>`
    : '';
  document.getElementById('modalBody').innerHTML =
    `<div id="doctorPrintable"><div>${mdish(humanize(c.content))}</div>${table}</div>
     <button id="printDoctor" class="ghost" style="margin-top:14px;width:100%">Print</button>`;
  document.getElementById('modalOverlay').classList.add('show');
  document.getElementById('printDoctor').addEventListener('click', () => {
    // Print ONLY the report: copy it into #printArea (the sole element
    // visible under @media print), then print.
    const pa = document.getElementById('printArea');
    pa.innerHTML = '<h2>Memory Book — Doctor report</h2>'
      + '<div class="muted">' + esc(c.ts) + '</div>'
      + document.getElementById('doctorPrintable').innerHTML;
    window.print();
  });
}
document.getElementById('doctorBtn').addEventListener('click', async () => {
  const btn = document.getElementById('doctorBtn');
  btn.disabled = true; btn.textContent = 'Writing…';
  try {
    const r = await callWalker('doctor_report');
    doctorCards.unshift({
      id: 'd' + Date.now(),
      content: r.content || '(empty report)',
      weekly: Array.isArray(r.weekly) ? r.weekly : [],
      ts: fmtTs(new Date().toISOString())
    });
    renderDoctor();
    loadTimeline();
  } catch (e) { alert('Report failed: ' + e.message); }
  finally { btn.disabled = false; btn.textContent = 'Make doctor report'; }
});

/* ---------- Timeline load + poll ---------- */
function renderAll() { renderRaw(); renderDaily(); renderHandoff(); renderDoctor(); }
async function loadTimeline() {
  if (modalOpen) return;   // paused while a modal is open
  try {
    const t = await callWalker('timeline');
    timelineData = {
      entries: Array.isArray(t?.entries) ? t.entries : [],
      reports: Array.isArray(t?.reports) ? t.reports : [],
      patient: t?.patient ?? null
    };
    const p = timelineData.patient;
    const pn = typeof p === 'string' ? p : (p && (p.name || p.label));
    const days = new Set(timelineData.entries.map(e => String(e.ts || '').slice(0, 10))).size;
    if (pn) setPatient(pn, days);
    renderAll();
  } catch (e) { console.warn('timeline failed:', e.message); }
}
loadTimeline();
setInterval(loadTimeline, 5000);

/* ---------- Card interactions: expand / modal / hide ---------- */
const tiersEl = document.getElementById('tiers');
let clickTimer = null;
tiersEl.addEventListener('click', e => {
  const xb = e.target.closest('.xbtn');
  if (xb) {                        // persistent dismiss: survives every refresh
    const c = xb.closest('.tcard');
    if (c) {
      if (c.dataset.key) { dismissed.add(c.dataset.key); saveDismissed(); }
      c.remove();
      renderAll();                 // recount badges + restore empty states
    }
    return;
  }
  if (e.target.closest('button, a, input, label')) return;
  const card = e.target.closest('.tcard');
  if (!card || card.dataset.static) return;
  if (card.dataset.review) { openReviewModal(); return; }        // handoff draft review
  if (card.dataset.doctor) {                                     // doctor report + table + print
    const c = doctorCards.find(x => x.id === card.dataset.doctor);
    if (c) openDoctorModal(c);
    return;
  }
  if (!card.dataset.key) return;
  // Unified: every card opens the fullscreen modal — columns stay compact,
  // detail lives in the overlay.
  const reg = CARD_REG.get(card.dataset.key);
  if (reg) openModal(reg.title, reg.text, reg.md);
});

function openModal(title, text, md) {
  modalOpen = true;
  text = humanize(text);
  document.getElementById('modalTitle').textContent = title || '';
  document.getElementById('modalBody').innerHTML = md ? mdish(text) : esc(text).replace(/\n/g, '<br>');
  document.getElementById('modalOverlay').classList.add('show');
}
function closeModal() {
  modalOpen = false;
  document.getElementById('modalOverlay').classList.remove('show');
}
document.getElementById('modalClose').addEventListener('click', closeModal);
document.getElementById('modalOverlay').addEventListener('click', e => {
  if (e.target === e.currentTarget) closeModal();
});
document.addEventListener('keydown', e => { if (e.key === 'Escape' && modalOpen) closeModal(); });

/* ---------- Column collapse (persisted) ---------- */
const COLS = ['raw', 'daily', 'handoff', 'doctor'];
function setCollapsed(col, v) {
  document.getElementById('tier-' + col).classList.toggle('collapsed', v);
  try { localStorage.setItem('cg_collapse_' + col, v ? '1' : '0'); } catch (e) {}
}
COLS.forEach(col => {
  let saved = null;
  try { saved = localStorage.getItem('cg_collapse_' + col); } catch (e) {}
  // Doctor starts tucked away (as in the design mock) until opened once.
  // Legacy builds stored '' instead of '0' — treat '' as "never touched".
  if (saved === '1' || (!saved && col === 'doctor')) setCollapsed(col, true);
});
document.querySelectorAll('.collapse-btn').forEach(b =>
  b.addEventListener('click', e => { e.stopPropagation(); setCollapsed(b.dataset.col, true); }));
document.querySelectorAll('.tier .rail').forEach(r =>
  r.addEventListener('click', () => setCollapsed(r.dataset.col, false)));

/* ---------- diag probe: phone-vs-laptop sync debugging ----------
   Shows which server replica this browser is talking to and how many
   moments that replica can see. If two devices show different pods or
   counts, the platform split storage across replicas.                  */
async function pollDiag() {
  try {
    const d = await callWalker('diag');
    document.getElementById('diagLine').textContent =
      ' · ' + (d.entries ?? '?') + ' moments @ ' + (d.pod || '?');
  } catch (e) {
    document.getElementById('diagLine').textContent = ' · probe unreachable';
  }
}
pollDiag();
setInterval(pollDiag, 15000);

/* ---------- Reset demo ---------- */
document.getElementById('resetBtn').addEventListener('click', async () => {
  const btn = document.getElementById('resetBtn');
  btn.disabled = true; btn.textContent = 'Resetting…';
  try {
    await callWalker('seed_load');
    knownIds = new Set();            // avoid a full-graph flash storm
    handoffDraft = null;
    doctorCards = [];
    expandedKeys.clear();
    dismissed.clear();               // dismissed cards come back on reset
    saveDismissed();
    await pollGraph();
    loadAlerts();
    await loadTimeline();
  } catch (e) { alert('Reset failed: ' + e.message); }
  finally { btn.disabled = false; btn.textContent = 'Reset demo'; }
});
