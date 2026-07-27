# Devpost submission copy — paste into jachacks-sf.devpost.com

**Track**: Social Impact. **Special awards**: Best Use of Jac (+ Best JacHammer rides on it per rubric).
**Video**: [ADD LINK — ≤90s]. **Deployed**: [ADD sandbox/production URL] (open `/static/home.html` — two ends: wearable + console).

---

## Project name

Memory Book — see what she still remembers

## Elevator pitch (one-liner)

An ambient memory graph for Alzheimer's care: a wearable phone listens, Jac walkers
turn conversations into a living memory graph, detect decline before families do,
and write the reports caregivers only have to confirm.

## Inspiration

6.9 million Americans live with Alzheimer's; 11+ million family members care for
them. Caregivers already write shift notes — then the notes die in a notebook.
Nobody can answer the question that matters: *is Mom forgetting faster than last
month?* Families usually find out half a year too late.

## What it does

Three ends, one graph, escalating data tiers:

- **L1 — Patient wearable** (`/static/patient.html`): an old phone on a lanyard. One
  button: long-press to listen, long-press to stop — the patient always holds the
  off switch. The browser transcribes speech; **no audio is ever stored — only
  text**. Batches flow into the graph every few seconds.
- **L2 — Caregiver console** (`/static/dashboard.html`): the memory graph grows live
  (people, facts, events as typed nodes). Named walkers patrol it: **DriftWalker**
  compares time windows and raises decline alerts ("repeat_question: 9.5/day now vs
  3.0/day baseline — 3.2×"); **CritiqueWalker** adversarially re-checks every alert
  against graph evidence (≥2 days AND ≥2 independent entries, else downgraded) —
  every surviving alert carries its own proof; **HandoffWalker** drafts the shift
  report and the caregiver only reviews and confirms. A flat control signal
  (social_moment) stays quiet — she isn't "just chattier this week."
- **L3 — Doctor reports** (Doctor column in the console): one click before an
  appointment produces a clinical timeline card — per-day signal trends,
  memory-confidence decay, key events. Opens full-screen; printable from there.

Ask anything — "Does she remember Emma is visiting?" — and **RecallWalker** answers
by deterministic graph traversal with a spotlight replay of the exact path it
walked, plus the evidence entries behind it. On the simulated 7-day corpus every
seeded fact is recallable, and every answer arrives with a citable path back to the
entry that produced it — traceability is a property of the traversal, not an
accuracy score we tuned.

## How we built it — where Jac runs (rubric: walkers, graph traversal, byLLM, agentic flows)

Everything that thinks is Jac -- the graph schema, all 14 walkers, and every line of decline logic live in the root `*.jac` files. No ORM, no database code, no API routing layer, no server framework:

- **Object-spatial core**: the patient's world IS the graph — `Patient`, `Person`,
  `Fact`, `Event`, `Entry`, `Signal`, `Report` nodes; typed `remembers` edges carry
  confidence + provenance (L1 wearable 0.7 / L2 human 0.9) that **decays 0.05/day**
  unless re-mentioned.
- **14 walkers as the agent team** (`main.jac`): init_patient, ingest_batch, ask,
  graph_snapshot, search_entries, timeline, seed_load, drift_scan,
  **critique_alerts** (the devil's-advocate pass), daily_report,
  handoff_draft/confirm, doctor_report, diag (ops probe). Walkers ARE our REST API
  (`walker:pub` → POST /walker/<name>) — we wrote zero routing code.
- **byLLM at the boundary only** (`llm.jac`): typed `by llm()` functions —
  `extract(batch) -> ExtractResult` with sem-constrained signal kinds,
  `phrase_answer`, `draft_report`. Claude does language; **the graph does the
  reasoning** — every alert and answer cites the nodes that produced it.
- **Deterministic + explainable by construction**: decline detection is edge-counting
  and window math on the graph, not an LLM vibe. That's the difference between an
  alert a family can act on and a hallucination.

## Challenges we ran into

- The hosted runtime and local jaclang disagree about byLLM packaging — solved with
  a runtime-adaptive loader (`llm_backend.py`).
- Static HTML serving differs across runtimes — we read the runtime source and
  found the `/static/` gateway path that works on both, plus a monkey-patch for the
  older server's unimplemented `send_static_file`.
- Deploy packaging drops loose data files — the demo corpus is now compiled into
  a Jac module (`seed_corpus.jac`).
- Chrome's SpeechRecognition self-stops on silence — auto-restart loop in the
  wearable page.

## Accomplishments / What we learned

A one-day build where the language's paradigm did real work: modeling care as a
persistent typed graph made provenance, decay, evidence-cited alerts, and a
three-tier reporting pipeline almost free. Walker-as-agent is a genuinely better
mental model for this domain than services + ORM.

## What's next

On-device transcription (whisper.cpp) so recognition never leaves the phone;
guardian-managed consent profiles; longitudinal baselines per patient; clinician
input as a fourth data tier.

## Ethics

Simulated data only. Guardian (POA) authorization model; visible wear indicator;
no audio stored — only text; AI drafts, humans confirm; alerts are advisory, not
diagnosis.

---

### 4-minute live demo script (rubric prescription)

1. (30s) Who it's for + what breaks: Margaret, her granddaughter Emma, caregiver
   Maria. Shift notes die in notebooks; decline is invisible until it's late.
2. (2m) LIVE: long-press the wearable → say "Emma is coming on Sunday afternoon" →
   graph grows on the big screen → Ask "Does she remember Emma is visiting?" →
   spotlight traversal + evidence → Alerts strip: 3.2× repeat-question, ✓
   CritiqueWalker verified · social control flat → Draft handoff → review & confirm in the overlay
   → doctor report card → print.
3. (60s) WHERE JAC RUNS: open main.jac on screen — 14 walkers, typed edges with
   decaying confidence; point at the footer walker roster and the ✓ CritiqueWalker
   badge; "the graph is the database — no ORM, no SQL, walkers are the API."
4. (30s) Numbers + close: repeat questions 3.0/day baseline -> 9.5/day now (3.2x,
   peak 11), while the social control stayed flat. "See what she still remembers — and know the moment it starts
   to fade."
