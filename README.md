# CareGraph

**See what she still remembers — and know the moment it starts to fade.**

An ambient memory companion for Alzheimer's patients and the people who care for them,
built in **Jac** (Jaseci object-spatial stack) for JacHacks SF 2026.

## What it does

- **L1 — Patient wearable** (`frontend/patient.html`): an old phone on a lanyard. One button:
  long-press to start/stop listening — the patient always holds the off switch. Speech is
  transcribed by the browser's speech engine; **the system never records or stores audio — only
  the recognized text is kept**. Text batches flow to the graph.
- **L2 — Caregiver console** (`frontend/dashboard.html`): the patient's memories grow as a living
  graph (people, facts, events). Walker agents patrol it: detect decline signals (repeat
  questions, name confusion), raise alerts, auto-write the daily report, and draft the shift
  handoff — the caregiver only reviews and confirms.
- **L3 — Doctor report** (`frontend/doctor.html`): one click before an appointment produces a
  clinical timeline: weekly signal trends, confidence decay, key events.

All core reasoning is **deterministic graph traversal** by named Jac walkers
(IngestWalker / RecallWalker / DriftWalker / HandoffWalker); the LLM (byLLM) is used only at the
boundary — parsing conversation text in, phrasing warm answers and reports out. Every alert and
answer cites the graph path that produced it.

## Run

```bash
./scripts/run.sh          # starts Jac backend + serves frontend; see script header for ports
./scripts/demo_reset.sh   # reset graph and load the 7-day simulated demo corpus
```

**All demo data is simulated.** No real patient data is used anywhere.

## Stack

Jac (graph schema, walkers, REST) · byLLM (typed LLM extraction) · vanilla JS + D3 force graph
(spotlight traversal replay) · Web Speech API (browser transcription; no audio stored).

Design doc: `docs/caregraph-design.html`. Build contract: `CONTRACT.md`.

*Built at JacHacks SF, July 26, 2026, during the hacking window.*
