# Memory Book

**See what she still remembers — and know the moment it starts to fade.**

An ambient memory companion for Alzheimer's patients and the people who care for them.
Built in **Jac** (Jaseci object-spatial stack) at JacHacks SF 2026.

---

## Who this is for

Linda cares for her mother, Margaret. Every doctor's appointment opens with the same question —
*is she worse than last month?* — and Linda has no way to answer it. She has started keeping a
tally on a notepad of how many times a day her mother asks what day it is, because there is
nowhere else to put it.

Memory Book is that notepad, turned into a graph that can be traversed, measured, and handed to a
doctor.

## What it does

- **L1 — Patient wearable** (`assets/patient.html`): an old phone on a lanyard. One button:
  long-press to start, long-press to stop — the patient always holds the off switch. Speech is
  transcribed by the browser's speech engine and batched every ~10s. **The system never records
  or stores audio; only the recognized text is kept.**
- **L2 — Caregiver console** (`assets/dashboard.html`): memories grow into a living graph of
  people, facts and events. Named walkers patrol it — detect decline signals, raise alerts,
  auto-write the daily report, draft the shift handoff. The caregiver only reviews and confirms.
- **L3 — Doctor report** (Doctor column in the console): one click before an appointment produces a
  clinical timeline — signal trends by day, memory-confidence decay, key events.

Every node carries its provenance (`L1_wearable` = 0.7 confidence, `L2_caregiver` = 0.9), so
data quality is part of the graph model rather than a footnote.

---

## Where Jac runs — point at it, don't take our word for it

**All domain logic is Jac.** The frontend is dependency-free vanilla JS whose only job is to
render what walkers return. There is no ORM, no database code, no API routing layer, and no
server framework in this repo — Jac provides all four.

| Jac capability | How Memory Book depends on it | Code |
|---|---|---|
| Typed node/edge graph | The memory graph **is** the domain model: 7 node types, 5 edge types | [`schema.jac:3-52`](schema.jac) |
| Named walkers as agents | **11 walkers**, each with one job (list below) | [`main.jac`](main.jac) |
| Graph traversal + type filters | `[here ->:remembers:->[?:Person]]` — recall is a walk, not a vector search | [`main.jac:250`](main.jac#L250) |
| Edge objects carry state | `[edge patient ->:remembers:-> target]` reads/writes per-memory confidence | [`main.jac:80`](main.jac#L80), [`:374`](main.jac#L374) |
| `visit … else` get-or-create | Seed loader creates the patient only when absent | [`main.jac:301`](main.jac#L301) |
| `with Root exit` | `ask` accumulates hits during the walk, reports **once** at the end | [`main.jac:228`](main.jac#L228) |
| **Language-level persistence** | The graph survives process restarts with **zero lines of database code** — no schema, no migrations, no ORM | (everything) |
| **`walker:pub` → auto REST** | All 11 endpoints exist because the walkers are public. **We wrote no routing code.** | [`main.jac:145`](main.jac#L145) onward |
| byLLM typed returns | `-> ExtractResult by llm()` — the return type *is* the output schema | [`llm.jac:54`](llm.jac#L54) |
| `sem` prompt wiring | Field-level prompt semantics keep extraction honest and typed | [`llm.jac:17-67`](llm.jac) |

### The 11 walkers

The UI labels walkers by role (`RecallWalker`, `DriftWalker`, `CritiqueWalker`); the identifiers
below are what you `grep` for in `main.jac` and what the REST routes are named.

| Walker | Shown in UI as | Job | Line |
|---|---|---|---|
| `init_patient` | — | Create/find the patient root | [145](main.jac#L145) |
| `ingest_batch` | IngestWalker | Transcript batch → LLM extract → merge into graph, return the visit trace | [160](main.jac#L160) |
| `ask` | RecallWalker | **Deterministic** keyword walk over the memory graph; returns the answer *plus its graph path and source entries* | [181](main.jac#L181) |
| `graph_snapshot` | — | Nodes + links for the D3 view (same native ids the walkers emit, so spotlight replay lines up) | [238](main.jac#L238) |
| `seed_load` | — | Wipe and load the simulated corpus | [297](main.jac#L297) |
| `drift_scan` | DriftWalker | Decline detection: window comparison + confidence decay | [431](main.jac#L431) |
| **`critique_alerts`** | **CritiqueWalker** | **Adversarial second pass** — an alert keeps its severity only if its signals span ≥2 distinct days **and** ≥2 distinct evidence entries; a spike packed into one afternoon is downgraded, with graph evidence attached | [452](main.jac#L452) |
| `daily_report` | — | Auto-written, auto-filed | [497](main.jac#L497) |
| `handoff_draft` | HandoffWalker | Everything since the last confirmed handoff, drafted | [527](main.jac#L527) |
| `handoff_confirm` | — | The one human step: the caregiver approves | [577](main.jac#L577) |
| `doctor_report` | — | Clinical timeline + trend buckets | [602](main.jac#L602) |

### The line we hold: the LLM never makes the medical judgement

Decline detection is arithmetic on the graph — count signals in a recent window, compare with the
baseline window, decay confidence on links that have not been refreshed
([`main.jac:352-428`](main.jac#L352)). It is deterministic, reproducible, and can name the exact
signals and entries behind every alert.

byLLM is used at exactly two boundaries: **text in** (transcript → typed `ExtractResult`) and
**words out** (facts → a warm sentence, items → a plain-language report). It labels; the graph
decides. `CAREGRAPH_MOCK_LLM=1` runs the whole product with zero API calls
([`llm.jac:70-102`](llm.jac#L70)) — the demo path never depends on a network.

That is also the answer to *"what if the AI is wrong about my mother?"* — **we do not diagnose.**
We make what the caregiver already observed countable, and every alert opens to show which
records produced it.

---

## What the demo shows

Simulated 7-day corpus, 22 entries across both sources (`seed_data.json`):

| | Baseline (prior 5 days) | Recent (last 2 days) |
|---|---|---|
| Repeated questions | **3.0 / day** | **9.5 / day** — a 3.2× rise |
| Peak | — | **11 in a single day** |

Crucially, **not every signal rises**: `social_moment` stays flat across the same period. So the
finding is not "she talked more this week" — it is specifically orientation and person-recall
that degraded, and `positive_recall` signals still mark what is intact.

Then the part a single score cannot tell you: the graph localizes *which* memories are going.
Name confusion and disorientation land on specific people and specific days, and every alert
carries the entries that triggered it — one click from the alert to the raw record.

**All demo data is simulated.** No real patient data is used anywhere in this repository.

---

## Run

```bash
./scripts/run.sh          # one server on :8000 — walkers AND static frontend
./scripts/demo_reset.sh   # wipe .jac/, restart, reload the simulated corpus
```

Then open <http://localhost:8000/dashboard.html> (not `file://`).
`CAREGRAPH_MOCK_LLM=1` runs everything without an API key.

> The wearable page needs a **secure context** for the browser speech engine — `localhost` works;
> a phone on the LAN over plain HTTP does not. Use the deployed URL or an HTTPS tunnel.

## Stack

Jac (graph, walkers, REST) · byLLM (typed extraction and phrasing) · vanilla JS + D3 force graph
(spotlight traversal replay) · Web Speech API (browser transcription; no audio stored).

Build contract: [`CONTRACT.md`](CONTRACT.md) · Design doc: [`docs/caregraph-design.html`](docs/caregraph-design.html) ·
Verified Jac/byLLM findings from today: [`docs/recon/`](docs/recon/)

## Scope

Built in one day. Deliberately **not** included, and not claimed anywhere: camera or photo
capture, background/locked-screen recording, native apps, authentication or multi-tenancy, and
any clinician data entry.

---

*Built at JacHacks SF — Founders Inc, July 26, 2026.*
