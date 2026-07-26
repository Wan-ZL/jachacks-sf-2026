# JacHacks winner code recon — what ACTUALLY works in practice

Recon date: 2026-07-26. Source clones under `/Users/zelin/.claude/jobs/6aa83096/tmp/`.

## Status of the two targets

| Repo | Result |
|---|---|
| `chinnuteja/CONSILIUM` (multi-agent diagnosis council) | **NOT AVAILABLE.** 404 on clone; not in chinnuteja's ~50 public repos (checked via GitHub API, both pages); no match in GitHub repo search for `consilium` + jac/jaseci/diagnosis. Deleted or made private. No trace/replay JSON shape could be extracted. |
| `nishantr14/jac` (PharmaGraph, Best Demo + Best Use of Jac) | Cloned OK → `/Users/zelin/.claude/jobs/6aa83096/tmp/nishantr14-jac`. Everything below is from this repo. |

Note: `/Users/zelin/.claude/jobs/6aa83096/tmp/jac` is an unrelated pre-existing clone of `jaseci-labs/jac` (the language repo itself) — useful as a reference for language internals but not a winner project.

---

## 1. Versions they pin (and the version story is messy — instructive)

There is **no requirements.txt and no pyproject** in the repo. Pins live in the README install command only:

```bash
# README.md (Quick Start)
pip install jaclang==0.9.0 jac-cloud==0.2.11 byllm==0.4.7 python-dotenv
```

README tech-stack table: `jaclang 0.9.0`, `jac-cloud 0.2.11` ("auto FastAPI from walkers"), `byLLM 0.4.7 → claude-sonnet-4-20250514`.

But their internal design doc (`docs/superpowers/plans/2026-05-19-pharmagraph.md`) says `jaclang 0.15.2, jac-scale, jac-byllm (mtllm)` and `pip install mtllm`. So they **changed jaclang major-ish versions and the byllm package name mid-hackathon** and the docs disagree with each other. Takeaway: pin exact versions in a requirements file on day 0 and smoke-test `jac serve` immediately; the ecosystem's package naming (mtllm vs byllm, jac-scale vs jac-cloud) churns.

`jac.toml` (project manifest — note it also carries npm deps and plugin config):

```toml
[project]
name = "pharmagraph"

[dependencies.npm]
react = "^18.2.0"
react-dom = "^18.2.0"
d3 = "^7.8.5"

[dependencies.npm.dev]
vite = "^6.4.1"
"@vitejs/plugin-react" = "^4.2.1"

[plugins.scale]

[plugins.byllm]
default_model = "claude-sonnet-4-20250514"
```

## 2. Project layout (748 total lines of backend code — small!)

```
jac/
├── main.jac                  # 13 lines: includes + seed-on-startup
├── jac.toml
├── graph/
│   ├── nodes.jac             # 26 lines: Drug, Condition, MedProfile, RiskReport
│   └── edges.jac             # 6 lines: one Interaction edge type
├── llm/functions.jac         # 6 lines (see byllm section — it's a shim)
├── walkers/                  # 7 walkers, one file each, 44–149 lines
│   ├── seed_graph.jac        # 62
│   ├── get_graph_data.jac    # 46   (feeds D3)
│   ├── parse_rx.jac          # 75
│   ├── interaction_walk.jac  # 71
│   ├── condition_walk.jac    # 44
│   ├── report_walker.jac     # 149  (full pipeline, the demo endpoint)
│   └── drug_stats.jac        # 48
├── llm_config.py             # 10 lines: byllm Model instance (mostly vestigial)
├── pharma_nlp.py             # 150 lines: pure-Python regex/alias NLP — the ACTUAL "LLM"
├── data_loader.py            # 42 lines: lru_cache JSON loader
├── data/interactions.json    # 49 drugs, 50 interactions, 8 conditions
├── frontend/                 # React 18 + Vite 6 + D3 v7 (plain JS, no TS)
│   └── src/{api.js, App.jsx, components/{DrugGraph,PrescriptionInput,RiskReport}.jsx}
└── tests/                    # e2e_test.py hits the live server with requests
```

`main.jac` verbatim — entry point is just includes + seeding:

```jac
include graph.nodes;
include graph.edges;
include walkers.seed_graph;
include walkers.get_graph_data;
include walkers.parse_rx;
include walkers.interaction_walk;
include walkers.condition_walk;
include walkers.report_walker;
include walkers.drug_stats;

with entry {
    root spawn seed_graph();
}
```

Pattern: `include` for other .jac modules; `import from python_module { fn }` for Python helpers (e.g. `import from data_loader { get_all_drugs, ... }`, `import from datetime { datetime }`). Python files sit next to the .jac files at repo root and are importable directly.

## 3. Frontend ↔ Jac backend wiring

Backend: `jac serve main.jac --host 0.0.0.0 --port 8000` (jac-cloud auto-exposes every walker as `POST /walker/<name>`). Frontend: `npm run dev` (Vite on 5173). Two processes; on Windows a `start.bat` launches both.

**CORS is avoided entirely via a Vite dev proxy** — the frontend fetches relative URLs; Vite forwards `/walker/*` to :8000. `frontend/vite.config.js` verbatim:

```js
export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/walker': {
        target: 'http://localhost:8000',
        changeOrigin: true,
      }
    }
  }
})
```

The **entire** API layer, `frontend/src/api.js` verbatim (note the `data.reports?.[0]` unwrap — jac-cloud wraps walker `report {...}` output in a `{"reports": [...]}` envelope):

```js
const BASE = ''

async function post(path, body = {}) {
  const res = await fetch(`${BASE}/walker/${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  if (!res.ok) throw new Error(`HTTP ${res.status}: ${await res.text()}`)
  const data = await res.json()
  return data.reports?.[0] ?? data
}

export const getGraphData = () => post('get_graph_data')
export const analyseRx = (rawText) => post('report_walker', { raw_text: rawText })
```

Walker `has` fields = the JSON request body (`{ raw_text: rawText }` → `has raw_text: str = "";`).

**Auth bypass — every single walker carries this** (jac-cloud endpoints require auth by default; this is how you make them public for a demo):

```jac
class __specs__ {
    has auth: bool = False;
}
```

Serving: pure localhost dev servers, no deployment (no vercel/static hosting anywhere in the repo). Demo = two terminals + browser at :5173.

## 4. The "walker traversal replay with spotlight" pattern (PharmaGraph's version)

CONSILIUM is gone, but PharmaGraph has the same trick and it's fully readable. **The walker does NOT stream its trace — it builds a `traversal_log` list while it runs and returns it in one response; the frontend replays it with setTimeout.** This is dead simple and demo-robust (no websockets, no SSE).

Trace shape emitted by `report_walker` (`walkers/report_walker.jac`) — one entry per graph edge examined:

```json
{
  "flagged_pairs":    [ {"drug_a", "drug_b", "severity", "mechanism", "clinical_effect", "evidence_level"} ],
  "traversal_log":    [ {"drug_a", "drug_b", "severity", "mechanism", "clinical_effect", "flagged": true} ],
  "contraindications":[ {"condition", "drug", "icd_code", "reason"} ],
  "severity_max": 5,
  "matched_drugs": ["warfarin", "..."],
  "unrecognised_drugs": [],
  "summary": "plain-English report...",
  "generated_at": "ISO timestamp"
}
```

Replay in `frontend/src/components/DrugGraph.jsx` (verbatim core): each log step flashes its edge cyan ("scan"), then 220ms later settles to red+glow if flagged or back to rest color; steps are staggered 330ms apart:

```js
log.forEach((step, i) => {
  const key = [step.drug_a, step.drug_b].sort().join('|')
  const isFlagged = flagged.has(key)

  const t1 = setTimeout(() => {
    linkEls.current.filter(d => { /* match edge by sorted name pair */ })
      .attr('stroke', SCAN)                 // SCAN = '#7dd3fc' cyan
      .attr('stroke-opacity', 0.9)
      .attr('stroke-width', 3)

    const t2 = setTimeout(() => {
      linkEls.current.filter(/* same edge */)
        .attr('stroke', isFlagged ? FLAGGED : SEV_REST[step.severity])  // FLAGGED = '#ef4444'
        .attr('stroke-width', isFlagged ? 3.5 : Math.max(1, step.severity*0.7))
        .attr('filter', isFlagged ? 'url(#glow)' : null)   // SVG feGaussianBlur glow
        .each(d => { if (isFlagged) d._flagged = true })
    }, 220)
    timers.current.push(t2)
  }, i * 330)
  timers.current.push(t1)
})
```

Supporting details that make it look good: timers stored in a ref and cleared on re-run (`clearTimers()`); user's matched drug nodes get brighter fill/stroke; flagged edges become clickable with a red tooltip showing mechanism/effect; `<defs><filter id="glow">` feGaussianBlur for the spotlight glow.

## 5. D3 force-graph data shape + physics

Walker `get_graph_data` reports the exact `{nodes, links}` shape D3's forceLink expects — **string IDs on links, resolved by `.id(d=>d.id)`**:

```json
{
  "nodes": [ {"id": "warfarin", "name": "warfarin", "generic_name": "...",
              "drug_class": "anticoagulant", "cyp_pathway": ["CYP2C9"], "half_life_hours": 40.0} ],
  "links": [ {"source": "warfarin", "target": "fluconazole", "severity": 5,
              "mechanism": "...", "clinical_effect": "...", "evidence_level": "established"} ]
}
```

Note: **links come from the raw JSON data layer, not from graph-edge traversal** — the walker only traverses `[-->(`?Drug)]` for nodes, then iterates `get_all_interactions()` for links, deduping with a sorted `"a|b"` pair key. (Edges in the Jac graph were created plain `da ++> db; db ++> da;` — they didn't even attach the Interaction edge attributes when seeding.)

Simulation setup (DrugGraph.jsx):

```js
const sim = d3.forceSimulation(nodes)
  .force('link', d3.forceLink(links).id(d=>d.id).distance(90))
  .force('charge', d3.forceManyBody().strength(-200))
  .force('center', d3.forceCenter(W/2, H/2))
  .force('collision', d3.forceCollide().radius(d=>9+(deg[d.id]||0)*1.4))
```

Plus: node radius scaled by degree (`4 + deg*1.4`), zoom via `d3.zoom()` on a `<g>` wrapper, drag with `fx/fy` pinning, labels as separate `<text>` selection updated on every tick, severity-coded rest colors (dim navy → dark red) with active colors only during replay. Data is defensively copied (`nodes.map(d=>({...d}))`) because forceSimulation mutates.

## 6. byLLM reality check — **they quietly removed byllm from the runtime path**

This is the biggest finding. The README markets "`parse_prescription() by llm()`" and "byLLM 0.4.7 → Claude", but the shipped code has **zero `by llm()` calls**. `llm/functions.jac` verbatim, all 6 lines:

```jac
import from pharma_nlp { parse_prescription, generate_risk_summary }

obj ExtractedDrugs {
    has drug_names: list[str];
    has conditions_mentioned: list[str];
}
```

Both "LLM" functions are plain Python in `pharma_nlp.py` (header comment: *"Drug extraction + report generation - no API key required. Uses keyword/regex matching against the drug database."*): `parse_prescription` = brand-name alias dict (advil→ibuprofen, coumadin→warfarin, ~40 entries) + word-boundary regex against the drug DB; `generate_risk_summary` = f-string template. `llm_config.py` still instantiates `Model("gemini/gemini-2.0-flash")` but nothing imports it. `.env.example` tells users to grab a free Gemini or Groq key — also unused at runtime.

Their design doc preserved the escape hatch they planned if byllm's magic broke (plans/2026-05-19-pharmagraph.md):

> **`by llm()` without explicit model reference** — relies on `[plugins.byllm]` in jac.toml; if it errors, add `import:py from mtllm.llms { Anthropic }; glob model = Anthropic(model_name="claude-sonnet-4-20250514");` and change `by llm()` to `by model()`

Lesson for us: a Best Demo winner made the demo path **deterministic** (regex + templates), kept the byllm scaffolding for the judging narrative, and never let an API call sit between click and animation. If we do use byllm live, have the `by model()` explicit-model fallback and a deterministic offline fallback ready.

## 7. Seed / demo data approach

- One JSON file, `data/interactions.json`: `{"drugs": [...49], "interactions": [...50], "conditions": [...8]}`. Handcrafted, medically plausible, sized so the force graph looks dense but readable.
- Loaded via `data_loader.py` with `@lru_cache(maxsize=1)`; walkers import these Python functions directly.
- **Auto-seed on server start** via `with entry { root spawn seed_graph(); }` in main.jac; `seed_graph` is idempotent — it checks `[-->(`?Drug)]` count and reports `{"status": "already_seeded"}` unless `force_reseed`. Seeding: `here ++> Drug(...)` off root, bidirectional `da ++> db; db ++> da;` for interactions.
- **Demo scenarios scripted in the README** ("The Pharmacist's Nightmare": warfarin + fluconazole + aspirin + ibuprofen → guaranteed Severity-5 hit) and **asserted in `tests/e2e_test.py`**, which posts to the live server (`requests.post(f"{BASE}/walker/{walker}")`, unwraps `data.get("reports",[data])[0]`) and checks the exact demo outputs. Their last commit is literally `feat: video-ready UI — typewriter demo animation, scan-line, visual polish`.

## 8. Misc jac idioms worth copying verbatim

- Node filter traversal: `[-->(`?Drug)]`, scoped: `[profile-->(`?Drug)]`, from root inside a non-root ability: `[root-->(`?Condition)]`.
- Delete an edge: `profile del--> old_drug;`.
- Two-entry walker pattern for "operate on profile if it exists": a `can walk with MedProfile entry` doing the work + a `can walk with `root entry` that finds/creates the profile and `visit profiles[0];` — else reports empty and `disengage`s.
- Early-exit input validation: `if not self.raw_text { report {"error": ...}; disengage; }`.
- Singleton state node (MedProfile) found-or-created on root; results persisted as a `RiskReport` node linked to the profile — cheap "persistence" story for judges.
- Walker HTTP contract: request body = `has` fields; response = `report {...}` dicts collected into `{"reports": [...]}`.

## 9. Blockers / cautions for our build

1. CONSILIUM is unrecoverable — if we want its council-replay pattern we must design our own trace format; PharmaGraph's `traversal_log` + staggered-setTimeout replay is a proven substitute.
2. Version pins are hearsay (README-only, contradicts their own design doc). Verify `jaclang==0.9.0 jac-cloud==0.2.11 byllm==0.4.7` actually coexist before building on them.
3. jac-cloud walkers are auth-gated by default — forget `class __specs__ { has auth: bool = False; }` and every fetch 401s.
4. jac-cloud wraps responses in `{"reports": [...]}` — unwrap in the API layer once, like their `data.reports?.[0] ?? data`.
5. `by llm()` was abandoned by this winner; treat byllm as demo-risk and keep a deterministic fallback path.
