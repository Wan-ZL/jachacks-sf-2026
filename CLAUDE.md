# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

CareGraph — a JacHacks SF 2026 hackathon project (built July 26, 2026, during the 10:45–19:15
hacking window). An ambient memory-graph companion for an Alzheimer's patient: a wearable phone
page transcribes conversations on-device, batched text is extracted by LLM into a persistent Jac
graph, named walkers detect decline and draft reports, humans only confirm.

**`CONTRACT.md` is the single source of truth** for the graph schema, walker names/shapes, REST
API, byLLM function signatures, seed-data format, and file layout. Read it before touching
anything. If you rename anything, update CONTRACT.md in the same commit.
`docs/recon/*.md` holds verified Jac/byLLM syntax and platform findings — trust `env-verified.md`
over memory or general docs; only its patterns are confirmed to run on this machine.

## Environment & commands

- Python env: conda env `jachacks` (`conda activate jachacks`). Jac toolchain + byllm installed there.
- LLM key: `export ANTHROPIC_API_KEY=$(cat ~/Desktop/Keys/anthropic_key.txt)` (scripts/run.sh does this).
- Run everything: `./scripts/run.sh` (backend via jac serve + frontend static; ports in script header).
- Reset demo state: `./scripts/demo_reset.sh` (wipes graph, reloads `backend/seed_data.json`).
- Frontend is plain HTML/JS — open `frontend/dashboard.html` via the static server, not file://
  (Web Speech + fetch need http origin). Pages accept `?api=http://host:port` to point at the backend.

## Architecture (why it's shaped this way)

- **All domain logic lives in Jac** (`backend/*.jac`): typed nodes/edges + four named walkers
  (ingest / recall / drift / handoff-report). Hackathon rule: ≥40% of repo code must be Jac —
  keep the frontend lean vanilla JS, put logic in walkers.
- **LLM only at the boundary** (`backend/llm.jac`): typed `by llm()` functions for extract-in /
  phrase-out. Core reasoning (decline detection, recall) is deterministic graph traversal so every
  alert/answer can cite its graph path. If byLLM runtime breaks, swap to a direct Anthropic API
  call **inside llm.jac only** — signatures stay stable.
- **Walker `trace`/`path` node-id lists power the dashboard's spotlight replay** — snapshot and
  walkers must emit the same native node ids or the demo's key visual breaks.
- Three frontends, one backend: `dashboard.html` (caregiver console), `patient.html` (wearable,
  long-press + Web Speech, batches every 10s), `doctor.html` (read-only clinical report).

## Hard constraints (hackathon + owner)

- The demo path in CONTRACT.md ("Demo path (sacred)") outranks all other work; a bug there is P0.
- Commit early and often to this public repo; commits use the personal identity already set in
  local git config (`Zelin Wan <…Wan-ZL@users.noreply.github.com>`). **Do not add Claude/AI
  attribution lines (e.g. Co-Authored-By) to commit messages in this repo.**
- All demo data is simulated — never add real patient data; keep the "Demo data — simulated"
  footer on every page.
- Deploy target: jachammer.ai (see `docs/recon/jachammer.md`); local run is the fallback.
- Do not add: camera/photo capture, native app, auth/multi-tenant, doctor data-entry. These are
  explicitly out of scope (roadmap-only) per team decision.
