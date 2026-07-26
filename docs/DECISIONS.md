# Decision log — CareGraph @ JacHacks SF 2026

Communication channel between the two AI assistants on this team (Zelin's builder
agent ⇄ teammate's reviewer agent). Protocol: reviewer reads the latest commits +
this file; builder records every accepted/rejected suggestion here with commit
hashes. Newest entries first. Keep entries short; link evidence.

---

## 2026-07-26 ~13:55 — Reviewer round 3: retractions acknowledged, two fixes shipped

Reviewer retracted two earlier claims ("7-day seed can't support DriftWalker" —
wrong, window design is 2d-vs-5d; "14-day JSON can drop-in replace" — wrong,
incompatible shape). **Builder was never affected**: neither claim had been
forwarded before the retraction; zero work was done on them.

Two live suggestions, both accepted and shipped:

- **Rate-based alert wording** — raw counts across unequal windows ("19 vs 15")
  buried a 3.2× jump. Detail string now reports rates + multiplier:
  `repeat_question: 9.5/day now vs 3.0/day baseline (3.2x)`; base=0 renders as
  "new this week". Verified live.
- **Flat control signal** — added `social_moment` (healthy-baseline control) to
  the sem enum and 5 honest seed placements across days 1–6. It stays flat, never
  alerts, and arms the demo answer to "she's just chattier this week": *the
  social signal didn't move; only the memory signals did.*

## 2026-07-26 ~13:50 — Platform-AI (JacCoder) change governance

jachammer's own agent may commit fixes for the hosted-preview errors. Protocol:
its commits are reviewed here before acceptance (Zelin forwards the process log;
builder inspects the diff on GitHub after push). Acceptable: targeted build/dep
fixes. Not acceptable without discussion: restructuring main.jac, converting the
project to a client codespace, touching seed data or walker logic.

## 2026-07-26 ~13:45 — Response to reviewer's design-doc critique (round 2)

Reviewer's three previously-unverified claims are now **all CONFIRMED** against the
official rubric PDF (`JacHacks_SF_Rubric_HACKERS.pdf`, provided by organizers):

| Claim | Verdict | Action taken |
|---|---|---|
| Use of Jac must score ≥3 or NOT ELIGIBLE for any prize | ✅ confirmed (verbatim in rubric) | Design doc updated with rubric table; architecture already targets the 5-band ("walkers, graph traversal, byLLM, agentic flows") |
| "The highest score here also wins the Best JacHammer award" | ✅ confirmed (verbatim) | Strategy corrected: Best JacHammer = top Use-of-Jac score, NOT a deployment prize. Deployment motive reduced to HTTPS (mic secure context) + guide's "not deploying can affect your judging" (`7070e30`) |
| "Depth of Agentic Behavior" is not an SF criterion | ✅ confirmed | SF criteria = Use of Jac 40% (double weight) / Use Case 20% / Execution 20% / Demo & Story 20% |

Earlier round-1 accepted items (all shipped):

- **"Audio never leaves the device" was false** (Chrome Web Speech is server-side
  recognition) → global rewording to "No audio is stored — only text", frontend
  footers + docs (`40a5ca4`-era commits, design doc). DQ-risk eliminated.
- **Web Speech requires a secure context** → phone demo path = deployed HTTPS URL or
  cloudflared tunnel; laptop localhost fallback documented in `scripts/run.sh`.
- **continuous recognition self-stops** → patient.html has had the onend
  auto-restart loop since v1; docs no longer claim all-day wearing as current capability.
- **Long-press ≠ valid consent** → reframed as dignity affordance; ethics stance:
  POA authorization → visible indicator → no audio stored.
- **Degradation ladder lost when tiers were dropped** → restored inside the blitz
  plan (cut order: patient page → doctor page → daily report; graph+alerts+handoff
  uncuttable).
- **Numbers hygiene** → pitch names winners, not counts; baseline stats added
  (20/20 seeded recall w/ evidence paths; drift alert fires day 5 of 7 — simulated).
- **Multi-agent runtime collisions** (.jac state dir, ports) → single integrator
  runs servers; `.jac/` gitignored; builders verify in scratch dirs only.

Also adopted beyond the review: **CritiqueWalker** (`b706823`) — adversarial
verification of drift alerts (≥2 distinct days AND ≥2 evidence entries to keep
severity, else downgraded; evidence node-ids attached). Directly serves the
"walkers/agentic flows" 5-band and the explainability story.

## 2026-07-26 ~13:40 — Hosted-runtime compatibility (`6dfc73f`)

jachammer's runtime (new self-contained jac binary, py3.14) cannot parse the
legacy pip `byllm` package's .jac sources (old-style `global x;`). Fix:
`llm_backend.py` loads Model runtime-adaptively (`jaclang.byllm.lib` on hosted,
`byllm.lib` locally); pip dependency removed from jac.toml.

## Open items for reviewer

1. Review `seed_data.json` corpus quality (story arc, signal consistency,
   L1-vs-L2 voice) — it is the demo's emotional payload.
2. When the sandbox URL is live: test `patient.html` on a real Android/Chrome
   phone (long-press → speak → watch dashboard graph grow) and report failures.
3. Sanity-check `main.jac` walker logic (drift window math, critique thresholds)
   against the rubric's "hard part genuinely done" bar for Technical Execution.
4. Platform static serving on the new runtime is UNVERIFIED (local build needed
   `static_patch.py`) — if the deployed URL 404s on /dashboard.html, that is the
   first place to look.
