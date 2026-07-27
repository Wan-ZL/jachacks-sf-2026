# Memory Book

**See what she still remembers — and know the moment it starts to fade.**

An ambient memory companion for people living with memory loss and the people who care for them.
Built in **Jac** (Jaseci object-spatial stack) at JacHacks SF 2026.

> **All demo data is simulated.** No real patient data is used anywhere in this repository.

---

## Inspiration

Linda cares for her mother, Margaret, who has Alzheimer's.

Every appointment opens with the same question — *is she worse than last month?* — and Linda has
no way to answer it. "She seems about the same" is not a clinical observation. So Linda started
keeping a tally on a notepad: how many times today did Mum ask what day it is. She keeps it there
because there is nowhere else to put it.

6.9 million Americans live with Alzheimer's and 11 million family members care for them. Almost
all of that observation lives on notepads, in group chats, and in memory. **The decline is
measurable. Nobody is measuring it.**

Memory Book is Linda's notepad, turned into a graph that can be traversed, measured, and handed
to a doctor.

---

## What it does

Three ends, one graph, escalating tiers of data quality.

- **L1 — Patient companion** (`assets/patient.html`): an old phone on a lanyard. One button:
  long-press to start, long-press to stop — the patient always holds the off switch. The
  browser's speech engine transcribes and the text batches into the graph every few seconds.
  **The system never records or stores audio; only the recognized text is kept.**
- **L2 — Caregiver console** (`assets/dashboard.html`): people, facts and events grow into a
  living graph. Named walkers patrol it — detect decline signals, raise alerts, auto-write the
  daily log, draft the shift handoff. The caregiver reviews and confirms; they never write the
  log themselves.
- **L3 — Doctor report** (Doctor column in the caregiver console): one click before an
  appointment produces a clinical timeline card — signal trends by day, memory-confidence decay,
  key events, each traceable to the entry that produced it. Opens full-screen; printable from
  there. (There is no separate doctor page — two surfaces total.)

Every node carries its provenance — `L1_wearable` contributes 0.7 confidence, `L2_caregiver` 0.9
— so data quality is part of the graph model rather than a disclaimer.

**Nothing in the system is Alzheimer's-specific.** The graph measures *whether recall is
degrading*, not *why*. The same walkers apply to post-stroke and TBI recovery, post-surgical
delirium monitoring, and the much larger group of families who simply suspect a parent is
slipping and have no way to check.

---

## Where Jac runs — point at it, don't take our word for it

**Everything that thinks is Jac.** The graph schema, all thirteen walkers, and every line of
decline logic live in the root `*.jac` files. The frontend is dependency-free vanilla JS whose
only job is to render what walkers return. This repo contains **no ORM, no database code, no API
routing layer and no server framework** — Jac provides all four. That is not a stylistic choice;
it is why two people shipped three surfaces in one day.

| Jac capability | How Memory Book depends on it | Code |
|---|---|---|
| Typed node/edge graph | The memory graph **is** the domain model: 7 node types, 5 edge types | [`schema.jac:3-52`](schema.jac) |
| Named walkers as agents | **14 walkers**, each with one job (list below) | [`main.jac`](main.jac) |
| Graph traversal + type filters | `[here ->:remembers:->[?:Person]]` — recall is a walk, not a vector search | [`main.jac:277`](main.jac#L277) |
| Edge objects carry state | `[edge patient ->:remembers:-> target]` reads and writes per-memory confidence | [`main.jac:107`](main.jac#L107) |
| `visit … else` get-or-create | Every walker bootstraps the patient only when absent | [`main.jac:322`](main.jac#L322) |
| `with Root exit` | `ask` accumulates hits during the walk and reports **once** at the end | [`main.jac:255`](main.jac#L255) |
| **Language-level persistence** | The graph survives process restarts with **zero lines of database code** — no schema, no migrations, no ORM | (everywhere) |
| **`walker:pub` → auto REST** | All 14 endpoints exist because the walkers are public. **We wrote no routing code.** | [`main.jac:172`](main.jac#L172) onward |
| byLLM typed returns | `-> ExtractResult by llm()` — the return type *is* the output schema | [`llm.jac:55`](llm.jac#L55) |
| `sem` prompt wiring | Field-level prompt semantics keep extraction typed and honest | [`llm.jac:18`](llm.jac#L18) |

### The 14 walkers

The UI labels walkers by role (`RecallWalker`, `DriftWalker`, `CritiqueWalker`); the identifiers
below are what you `grep` for in `main.jac` and what the REST routes are named.

| Walker | Shown in UI as | Job | Line |
|---|---|---|---|
| `init_patient` | — | Create or find the patient root | [172](main.jac#L172) |
| `ingest_batch` | IngestWalker | Transcript batch → typed LLM extraction → merge into the graph, returning the visit trace | [187](main.jac#L187) |
| `ask` | RecallWalker | **Deterministic** keyword walk over the memory graph; returns the answer *plus its graph path and the source entries that justify it* | [208](main.jac#L208) |
| `graph_snapshot` | — | Nodes and links for the D3 view — the same native ids the walkers emit, so spotlight replay lines up | [265](main.jac#L265) |
| `search_entries` | — | Free-text search across raw entries | [317](main.jac#L317) |
| `timeline` | — | Chronological entry + report feed | [342](main.jac#L342) |
| `seed_load` | — | Wipe and load the simulated corpus | [379](main.jac#L379) |
| `drift_scan` | DriftWalker | Decline detection: recent-window vs baseline-window comparison, plus confidence decay on links that were not refreshed | [533](main.jac#L533) |
| **`critique_alerts`** | **CritiqueWalker** | **Adversarial second pass** — an alert keeps its severity only if its signals span ≥2 distinct days **and** ≥2 distinct evidence entries; a spike packed into one afternoon is downgraded, with the graph evidence attached | [554](main.jac#L554) |
| `daily_report` | — | Auto-written, auto-filed | [599](main.jac#L599) |
| `handoff_draft` | HandoffWalker | Everything since the last confirmed handoff, drafted | [629](main.jac#L629) |
| `handoff_confirm` | — | The one human step in the whole loop: the caregiver approves | [679](main.jac#L679) |
| `doctor_report` | — | Clinical timeline + per-day trend buckets | [704](main.jac#L704) |
| `diag` | — | Ops probe: replica identity + graph counts (deploy sync debugging) | [769](main.jac#L769) |

### Four things Jac gave us that we would otherwise have had to build

1. **Persistence is the language.** Kill the server, restart it, the memory is still there. No
   schema, no migrations, no ORM, no database file we manage.
2. **`walker:pub` is the API.** Fourteen REST endpoints exist because the walkers are public.
   No routing, no controllers, no serializers.
3. **Traversal is the query language.** `[here ->:remembers:->[?:Person]]`. Recall is a walk over
   typed edges — which is exactly why every answer can cite its path.
4. **`by llm()` types the LLM.** The return type *is* the output schema, with `sem` annotations
   wiring per-field prompt semantics. No JSON parsing, no retry-until-it-validates loop.

### The line we hold: the LLM never makes the medical judgement

Decline detection is arithmetic on the graph — count signals in the recent window, compare
against the baseline window, decay confidence on links that were not refreshed
([`main.jac:454-531`](main.jac#L454)). Deterministic, reproducible, and able to name the exact
signals and entries behind every alert.

byLLM is used at exactly two boundaries: **text in** (transcript → typed `ExtractResult`) and
**words out** (facts → a warm sentence, items → a plain-language report). **It labels; the graph
decides.** `CAREGRAPH_MOCK_LLM=1` runs the whole product with zero API calls
([`llm.jac:71`](llm.jac#L71)) — the demo path never depends on a network.

That is also our answer to *"what if the AI is wrong about my mother?"* — **we do not diagnose.**
We make what the caregiver already observed countable, and every alert opens to show the records
that produced it.

---

## What the demo shows

Simulated 7-day corpus, 22 entries across both sources (`seed_data.json`):

| | Baseline (prior 5 days) | Recent (last 2 days) |
|---|---|---|
| Repeated questions | **3.0 / day** | **9.5 / day — a 3.2× rise** |
| Peak | — | **11 in a single day** |

Crucially, **not every signal rises.** `social_moment` stays flat across the same period. So the
finding is not "she talked more this week" — it is specifically orientation and person-recall
that degraded, and `positive_recall` still marks what is intact. That flat control is the
difference between a metric and a finding.

Then the part a single confidence score can never tell you: the graph localizes *which* memories
are going. Name confusion and disorientation land on specific people and specific days, and every
alert is one click from the raw record that triggered it.

Every seeded fact is recallable, and every answer arrives with a citable path back to the entry
that produced it — traceability is a property of the traversal, not an accuracy score we tuned.

---

## Run

```bash
./scripts/run.sh          # one server on :8000 — walkers AND static frontend
./scripts/demo_reset.sh   # wipe .jac/, restart, reload the simulated corpus
./scripts/run_tests.sh    # 3 Jac suites, 41 checks, keyless
```

Then open <http://localhost:8000/static/home.html> (not `file://`).
`CAREGRAPH_MOCK_LLM=1` runs everything without an API key.

> The companion page needs a **secure context** for the browser speech engine — `localhost`
> works; a phone on the LAN over plain HTTP does not. Use the deployed URL or an HTTPS tunnel.

---

## Challenges we ran into

- **Walkers pulled in via `include` silently lose their `:pub` tag** under `jac start` and return
  401; type and `def` includes are unaffected. We found this empirically and restructured so
  every walker is declared in the served module.
- **The persistent root graph is persistent across runs** — which is the feature, but during
  development every re-run stacked another copy of the corpus into the graph. We spent real time
  chasing a de-duplication bug that did not exist before realising the data was simply loading
  twice. `demo_reset.sh` now wipes `.jac/` deliberately.
- **The hosted runtime and local jaclang disagree about byLLM packaging** — the hosted runtime
  bundles byLLM inside jaclang core and cannot parse the legacy pip package. Model loading is now
  runtime-adaptive (`llm_backend.py`).
- **Static file serving differs across runtimes.** We read the runtime source, found the
  `/static/` gateway path that works on both, and monkey-patched the older server's
  unimplemented `send_static_file` (`static_patch.py`).
- **Deploy packaging drops loose data files** — the demo corpus is now compiled into a Jac module
  (`seed_corpus.jac`).
- **Chrome's SpeechRecognition self-stops on silence** — the companion page runs an auto-restart
  loop, and it requires a secure context, which nearly cost us the live demo.
- **Our first alert wording compared raw counts across unequal windows** ("19 in the last 2 days
  vs 15 in the prior 5"), which made a 3.2× rise read like a rounding error. It reports rates now.

## Accomplishments we're proud of

**`critique_alerts`.** Most projects stop at "the agent found something." We added an adversarial
walker whose only job is to attack the first walker's conclusions and downgrade the ones that
cannot survive — a spike packed into a single afternoon is not a trend. Every alert that survives
carries its own proof. When you are telling a family their mother is getting worse, **an alert
you can argue with is worth more than an alert that is merely confident.**

**A flat control in our own data.** It would have been easier to make every signal climb. Holding
one flat is what lets us say the finding is specific rather than "she talked more this week."

**No database, no backend framework, no build step.** Fourteen REST endpoints, a persistent
graph, three working surfaces, and a 41-check test suite — in one day, by two people.

## What we learned

Object-spatial programming changed *what we modelled*. Our first instinct was rows of
observations with a decline score on top. Putting the **relationships** first — a memory as an
edge with confidence, a signal as a node with provenance — meant decline detection stopped being
a statistics problem and became a traversal. And because it is a traversal, it can always show
its work, which for this particular product is not a nice-to-have; it is the entire basis for
trusting it.

We also learned to keep the LLM at the boundary on purpose. Every time we were tempted to let it
judge, the feature got less explainable and no more accurate.

## What's next

On-device transcription (whisper.cpp) so recognition never leaves the phone; guardian-managed
consent profiles; longitudinal per-person baselines; clinician input as a fourth data tier.

---

## Ethics and consent

- **Simulated data only.** No real patient data anywhere in this repository, and every page
  carries a "Demo data — simulated" footer.
- **No audio is stored** — the browser's speech engine produces text and only text is kept.
- **Guardian (POA) authorization**, plus a visible indicator that the companion is listening.
  The long-press off switch is a dignity affordance, not our consent mechanism — for someone with
  cognitive impairment, guardian authorization is.
- **AI drafts, humans confirm.** Alerts are advisory, never a diagnosis, and never change who
  signs the record.

## Scope

Built in one day. Deliberately **not** included, and not claimed anywhere: camera or photo
capture, background or locked-screen recording, native apps, multi-tenancy, and clinician data
entry.

## Stack

Jac (graph, walkers, REST) · byLLM (typed extraction and phrasing) · vanilla JS + D3 force graph
with spotlight traversal replay · Web Speech API (browser transcription; no audio stored).

Build contract: [`CONTRACT.md`](CONTRACT.md) · Decision log: [`docs/DECISIONS.md`](docs/DECISIONS.md) ·
Verified Jac/byLLM findings from today: [`docs/recon/`](docs/recon/)

---

*Built at JacHacks SF — Founders Inc, July 26, 2026.*
