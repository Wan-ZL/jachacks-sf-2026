# CareGraph — Build Contract (single source of truth)

Every builder agent codes against THIS file. If recon cheatsheets (docs/recon/*.md) contradict
this file on Jac syntax, the cheatsheets win on syntax, this file wins on names/shapes.
One developer (Claude) + parallel agents. No renames without updating this file.

## Product in one line
Ambient memory graph for an Alzheimer's patient: wearable phone page auto-transcribes conversations
locally → batched byLLM extraction → persistent typed graph → walker team detects decline, drafts
reports → humans only confirm. Three layers: L1 patient wearable / L2 caregiver console / L3 doctor report.

## Repo layout
```
backend/
  main.jac          # ALL 10 walkers live HERE (served module). GOTCHA (verified): walkers
                    # pulled in via `include` lose their :pub tag under `jac start` and 401.
                    # Only type/def includes (schema, llm) survive include.
  schema.jac        # node/edge types (include'd by main.jac — types are safe to include)
  llm.jac           # byLLM Model config + typed extraction/drafting functions + obj types
  jac.toml          # required by `jac start` in this cwd
  seed_data.json    # 7-day simulated corpus (see SEED DATA); loaded by seed_load walker
frontend/
  dashboard.html    # caregiver console: D3 graph + spotlight replay + trends + alerts + handoff review
  patient.html      # wearable page: long-press record, Web Speech API, batch POST
  doctor.html       # doctor report: print-friendly read-only
  app.css           # shared minimal styles (dark-on-light, big touch targets)
scripts/
  run.sh            # start backend (+ static server if needed), env activation, ports
  demo_reset.sh     # wipe graph + reload seed
docs/               # design doc + recon cheatsheets (not part of app)
```

## Graph schema (Jac)
Node types (all `has ts: str` ISO-8601 where noted):
- `node Patient { has name: str; }`  — exactly one, child of root
- `node Person  { has name: str, relation: str; }`   # family/friend/caregiver mentioned in convos
- `node Fact    { has text: str, category: str; }`   # stable knowledge patient holds (category: person|place|routine|preference|other)
- `node Event   { has text: str, date: str; }`       # appointments/happenings (date ISO)
- `node Entry   { has text: str, source: str, ts: str; }`  # raw input; source: "L1_wearable" | "L2_caregiver"
- `node Signal  { has kind: str, detail: str, ts: str; }`  # kind: repeat_question | name_confusion | disorientation | positive_recall
- `node Report  { has kind: str, content: str, ts: str, status: str; }`  # kind: daily|handoff|doctor; status: draft|confirmed

Edge types:
- `edge remembers { has confidence: float, updated: str; }`  # Patient -> Person/Fact/Event
- `edge mentioned {}`                                        # Entry -> Person/Fact/Event/Signal it evidences
- `edge has_entry {}`                                        # Patient -> Entry
- `edge has_signal {}`                                       # Patient -> Signal
- `edge has_report {}`                                       # Patient -> Report

Provenance rule: every Entry carries source (L1/L2). Signal/Fact confidence starts 0.9 (L2 human)
or 0.7 (L1 wearable). DriftWalker decays `remembers.confidence` by 0.05/day without re-mention.

## Walkers (ALL exposed as REST; exact expose syntax per docs/recon/env-verified.md)
| walker | fields (request body) | behavior | returns (JSON) |
|---|---|---|---|
| `init_patient` | `name: str` | idempotent: ensure Patient under root | `{patient_id}` |
| `ingest_batch` | `source: str, text: str, ts: str` | create Entry; call `extract()` (llm.jac); create/merge Person/Fact/Event/Signal nodes + edges; merge = match by name/text case-insensitive | `{created: [...], trace: [node_ids in visit order]}` |
| `ask` | `question: str` | deterministic traversal: collect Persons/Facts/Events whose text/name overlaps question keywords (+1 hop via mentioned); then `phrase_answer()` | `{answer, path: [node_ids], evidence: [entry_ids]}` |
| `graph_snapshot` | — | full graph dump for D3 | `{nodes:[{id,type,label,confidence?}], links:[{source,target,type}]}` |
| `drift_scan` | — | window compare: Signals last 2 days vs previous 5; decay confidences; build alerts | `{alerts:[{kind, detail, now_count, base_count, severity}]}` |
| `daily_report` | `date: str` | compile that date's Entries+Signals → `draft_report()` → save Report(kind=daily, status=confirmed) | `{report_id, content}` |
| `handoff_draft` | — | items since last confirmed handoff → `draft_report()` | `{report_id, items:[{id,text}], content}` |
| `handoff_confirm` | `report_id: str, approved: list[str]` | keep approved items, mark confirmed | `{report_id, status}` |
| `doctor_report` | — | full timeline: weekly signal counts, confidence trends, key events | `{content, weekly:[{week, repeat_q, confusions}], generated: ts}` |
| `seed_load` | — | wipe non-Patient data, load seed_data.json through ingest pipeline WITHOUT llm (pre-extracted) | `{loaded: n}` |

`trace`/`path` node id lists power the frontend spotlight replay. Node ids: use the runtime's
native jid — snapshot must use the same ids.

## byLLM functions (llm.jac)
```
obj ExtractedPerson { has name: str, relation: str; }
obj ExtractedFact   { has text: str, category: str; }
obj ExtractedEvent  { has text: str, date: str; }
obj ExtractedSignal { has kind: str, detail: str; }
obj ExtractResult   { has persons: list[ExtractedPerson], facts: list[ExtractedFact],
                      events: list[ExtractedEvent], signals: list[ExtractedSignal]; }

def extract(batch_text: str, today: str) -> ExtractResult by llm();
def phrase_answer(question: str, facts: list[str]) -> str by llm();   # warm, short, cite facts given only
def draft_report(kind: str, items: list[str]) -> str by llm();        # markdown, <=10 bullets, plain language
```
Model: Anthropic claude sonnet via byllm Model (exact model_name per docs/recon/byllm-cheatsheet.md).
API key: env `ANTHROPIC_API_KEY` (run.sh exports from ~/Desktop/Keys/anthropic_key.txt).
FALLBACK (if byllm runtime breaks, per Persist precedent): llm.jac keeps same function signatures but
implements via direct `anthropic` python package call with JSON schema prompt — swap happens ONLY inside llm.jac.

## Frontend contract
- Backend base URL: `window.API = localStorage.getItem('api') || 'http://localhost:8000'` (override via ?api=)
- All calls: `POST ${API}/<walker-endpoint-per-recon>` JSON body = walker fields. If CORS blocks,
  run.sh serves frontend from same origin (recon decides; document in run.sh comments).
- dashboard.html: left = D3 force graph (color by node type: Patient gold, Person blue, Fact green,
  Event purple, Signal red, Entry gray small, Report orange). `ask` box top; on answer, spotlight
  replay: dim all, light `path` ids sequentially 400ms apart. Right column: alerts (drift_scan),
  trends (repeat_question count/day bar), handoff card (draft → checkboxes → confirm), daily report btn.
  Poll graph_snapshot every 5s (pause during replay).
- patient.html: full-screen single button. Long-press (600ms) toggles recording; state color
  (idle gray / recording soft green + pulsing). webkitSpeechRecognition, continuous, interim off,
  lang from ?lang= (default en-US). Buffer finals; every 10s (const BATCH_MS) or on stop → POST
  ingest_batch{source:"L1_wearable"}. Show last transcript line faintly (patient dignity: readable, calm).
- doctor.html: fetch doctor_report → render sections + a simple inline SVG line/bar for weekly counts. Print CSS.

## Seed data (seed_data.json)
7 days, ~20 entries, mixed source L1/L2, pre-extracted (each entry ships its persons/facts/events/signals
so seed_load skips the LLM). Story arc: Emma (granddaughter) visits Sunday; day1-3 stable (repeat_question
~2-3/day); day4 Lily/Emma name_confusion appears; day5-7 repeat_question climbs 5→8→11, disorientation x2,
one positive_recall (recognized old song). Include warm details (garden, jazz, Tuesday tea with Rosa).

## Hard rules (hackathon compliance)
- ≥40% of code lines in .jac files. Frontend stays lean vanilla HTML/JS to protect the ratio.
- All work committed to this repo (public) — commit early, commit often, message prefix `feat:/fix:/docs:`.
- No real patient data. Seed is labeled simulated in README and UI footer ("Demo data — simulated").
- Deploy target: jachammer.ai (per docs/recon/jachammer.md findings); local fallback documented in run.sh.

## Demo path (sacred — bugs here outrank everything)
patient.html long-press → say "Emma is coming on Sunday" → dashboard graph grows Emma+Event within 15s
→ ask "Does she remember Emma is visiting?" → spotlight replay → answer with evidence
→ alerts card shows repeat_question 3→11 → handoff draft → confirm 2 items → doctor.html trend page.
