# CareGraph backend entry - ALL walkers live in this served module.
# (Walkers pulled in via `include` lose their :pub access tag under `jac start`
#  and return 401 - verified empirically; type/def includes are unaffected.)
# Serve from repo root: jac start main.jac --no_client -p 8000 (static frontend in assets/)

import static_patch;  # fills jaclang 0.16.7 send_static_file gap (see file header)
import seed_corpus;  # demo corpus compiled into code — deploy packaging drops loose data files

include schema;
include llm;

# Core walkers: init_patient, ingest_batch, ask, graph_snapshot, seed_load.
# llm.jac provides extract/phrase_answer/draft_report + Extracted* objs (CONTRACT signatures).


import re;
import os;
import json;

glob STOPWORDS: list[str] = [
    "the", "a", "an", "is", "are", "was", "were", "does", "do", "did", "she", "he",
    "her", "his", "it", "its", "of", "to", "in", "on", "at", "and", "or", "what",
    "when", "who", "where", "how", "why", "that", "this", "you", "your", "my", "me",
    "we", "they", "them", "about", "remember", "remembers", "will", "for", "with",
    "has", "have", "had", "still", "know", "knows"
];

def kw_split(question: str) -> list[str] {
    words = re.sub(r"[^a-z]", " ", question.lower()).split();
    return [w for w in words if w not in STOPWORDS and len(w) > 2];
}

def kw_match(kws: list[str], text: str) -> bool {
    tl = text.lower();
    for k in kws {
        if k in tl {
            return True;
        }
    }
    return False;
}

def label_of(text: str) -> str {
    return text if len(text) <= 40 else text[:40];
}

# Provenance rule (CONTRACT): L2 human = 0.9, L1 wearable = 0.7.
def source_conf(source: str) -> float {
    return 0.9 if source == "L2_caregiver" else 0.7;
}

def find_person(patient: Patient, name: str) -> Person | None {
    for n in [patient ->:remembers:->[?:Person]] {
        if n.name.lower() == name.lower() {
            return n;
        }
    }
    return None;
}

def find_fact(patient: Patient, text: str) -> Fact | None {
    for n in [patient ->:remembers:->[?:Fact]] {
        if n.text.lower() == text.lower() {
            return n;
        }
    }
    return None;
}

def find_event(patient: Patient, text: str) -> Event | None {
    for n in [patient ->:remembers:->[?:Event]] {
        if n.text.lower() == text.lower() {
            return n;
        }
    }
    return None;
}

# Refresh the remembers edge on re-mention: bump `updated`, never lower confidence.
def ensure_remembers(patient: Patient, target: Person | Fact | Event, conf: float, ts: str) {
    es = [edge patient ->:remembers:-> target];
    if es {
        es[0].updated = ts;
        if conf > es[0].confidence {
            es[0].confidence = conf;
        }
    } else {
        patient +>:remembers(confidence=conf, updated=ts):+> target;
    }
}

def remembers_conf(patient: Patient, target: Person | Fact | Event) -> float {
    es = [edge patient ->:remembers:-> target];
    return es[0].confidence if es else 0.0;
}

# Shared merge pipeline: used by ingest_batch (LLM output) and seed_load (pre-extracted).
# Appends created node ids into `created` and all touched ids into `trace` (visit order).
def apply_extract(patient: Patient, entry_node: Entry, res: ExtractResult,
                  conf: float, ts: str, created: list[str], trace: list[str]) {
    for p in res.persons {
        person = find_person(patient, p.name);
        if person is None {
            person = (patient +>:remembers(confidence=conf, updated=ts):+>
                      Person(name=p.name, relation=p.relation))[0] as Person;
            created.append(jid(person));
        } else {
            ensure_remembers(patient, person, conf, ts);
        }
        entry_node +>:mentioned():+> person;
        trace.append(jid(person));
    }
    for f in res.facts {
        fact = find_fact(patient, f.text);
        if fact is None {
            fact = (patient +>:remembers(confidence=conf, updated=ts):+>
                    Fact(text=f.text, category=f.category))[0] as Fact;
            created.append(jid(fact));
        } else {
            ensure_remembers(patient, fact, conf, ts);
        }
        entry_node +>:mentioned():+> fact;
        trace.append(jid(fact));
    }
    for ev in res.events {
        event = find_event(patient, ev.text);
        if event is None {
            event = (patient +>:remembers(confidence=conf, updated=ts):+>
                     Event(text=ev.text, date=ev.date))[0] as Event;
            created.append(jid(event));
        } else {
            ensure_remembers(patient, event, conf, ts);
        }
        entry_node +>:mentioned():+> event;
        trace.append(jid(event));
    }
    for s in res.signals {
        # Signals are point-in-time observations — never merged, always new.
        sig = (patient +>:has_signal():+> Signal(kind=s.kind, detail=s.detail, ts=ts))[0] as Signal;
        entry_node +>:mentioned():+> sig;
        created.append(jid(sig));
        trace.append(jid(sig));
    }
}

walker:pub init_patient {
    has name: str;
    has reports: list[dict] = [];

    can ensure with Root entry {
        existing = [here -->[?:Patient]];
        if existing {
            report {"patient_id": jid(existing[0])};
        } else {
            patient = (here ++> Patient(name=self.name))[0] as Patient;
            report {"patient_id": jid(patient)};
        }
    }
}

walker:pub ingest_batch {
    has source: str,
        text: str,
        ts: str;
    has reports: list[dict] = [];

    can go with Root entry {
        visit [-->[?:Patient]];
    }

    can process with Patient entry {
        entry_node = (here +>:has_entry():+>
                      Entry(text=self.text, source=self.source, ts=self.ts))[0] as Entry;
        created: list[str] = [jid(entry_node)];
        trace: list[str] = [jid(entry_node)];
        res = extract(self.text, self.ts[:10]);
        apply_extract(here, entry_node, res, source_conf(self.source), self.ts, created, trace);
        report {"created": created, "trace": trace};
    }
}

walker:pub ask {
    has question: str;
    has keywords: list[str] = [],
        path: list[str] = [],
        evidence: list[str] = [],
        facts_found: list[str] = [];
    has reports: list[dict] = [];

    can go with Root entry {
        self.keywords = kw_split(self.question);
        visit [-->[?:Patient]];
    }

    can scan with Patient entry {
        visit [->:remembers:->];
    }

    can check_person with Person entry {
        if kw_match(self.keywords, here.name) {
            self.hit(here, f"{here.name} ({here.relation})");
        }
    }

    can check_fact with Fact entry {
        if kw_match(self.keywords, here.text) {
            self.hit(here, here.text);
        }
    }

    can check_event with Event entry {
        if kw_match(self.keywords, here.text) {
            self.hit(here, f"{here.text} on {here.date}");
        }
    }

    def hit(matched: Person | Fact | Event, text: str) {
        self.path.append(jid(matched));
        self.facts_found.append(text);
        # 1 hop back through mentioned = the raw Entries evidencing this memory.
        for e in [matched <-:mentioned:<-[?:Entry]] {
            eid = jid(e);
            if eid not in self.evidence {
                self.evidence.append(eid);
            }
        }
    }

    can answer with Root exit {
        if self.facts_found {
            ans = phrase_answer(self.question, self.facts_found);
        } else {
            ans = "I couldn't find anything about that in the memory graph yet.";
        }
        report {"answer": ans, "path": self.path, "evidence": self.evidence};
    }
}

walker:pub graph_snapshot {
    has reports: list[dict] = [];

    can go with Root entry {
        visit [-->[?:Patient]];
    }

    can dump with Patient entry {
        nodes: list[dict] = [];
        links: list[dict] = [];
        pid = jid(here);
        nodes.append({"id": pid, "type": "Patient", "label": here.name});
        for p in [here ->:remembers:->[?:Person]] {
            nodes.append({"id": jid(p), "type": "Person", "label": p.name,
                          "confidence": remembers_conf(here, p)});
            links.append({"source": pid, "target": jid(p), "type": "remembers"});
        }
        for f in [here ->:remembers:->[?:Fact]] {
            nodes.append({"id": jid(f), "type": "Fact", "label": label_of(f.text),
                          "confidence": remembers_conf(here, f)});
            links.append({"source": pid, "target": jid(f), "type": "remembers"});
        }
        for ev in [here ->:remembers:->[?:Event]] {
            nodes.append({"id": jid(ev), "type": "Event", "label": label_of(ev.text),
                          "confidence": remembers_conf(here, ev)});
            links.append({"source": pid, "target": jid(ev), "type": "remembers"});
        }
        for s in [here ->:has_signal:->[?:Signal]] {
            # kind + ts kept: dashboard trend charts bucket signals by kind per day.
            nodes.append({"id": jid(s), "type": "Signal", "label": label_of(s.detail),
                          "kind": s.kind, "ts": s.ts});
            links.append({"source": pid, "target": jid(s), "type": "has_signal"});
        }
        for en in [here ->:has_entry:->[?:Entry]] {
            nodes.append({"id": jid(en), "type": "Entry", "label": label_of(en.text),
                          "ts": en.ts});
            links.append({"source": pid, "target": jid(en), "type": "has_entry"});
            for m in [en ->:mentioned:->] {
                links.append({"source": jid(en), "target": jid(m), "type": "mentioned"});
            }
        }
        for r in [here ->:has_report:->[?:Report]] {
            nodes.append({"id": jid(r), "type": "Report", "label": label_of(r.content),
                          "kind": r.kind, "status": r.status, "ts": r.ts});
            links.append({"source": pid, "target": jid(r), "type": "has_report"});
        }
        report {"nodes": nodes, "links": links};
    }
}

# Server-side raw-data search (the napkin spec's "raw data search" column):
# keyword match over Entry text, same stopword pipeline as ask.
walker:pub search_entries {
    has query: str;
    has reports: list[dict] = [];

    can go with Root entry {
        visit [-->[?:Patient]] else {
            report {"matches": []};
        }
    }

    can find with Patient entry {
        kws = kw_split(self.query);
        matches = [];
        for e in [here ->:has_entry:->[?:Entry]] {
            if kw_match(kws, e.text) {
                matches.append({"id": jid(e), "ts": e.ts, "source": e.source, "text": e.text});
            }
        }
        report {"matches": matches};
    }
}


# Full-content feed for the tiered-column UI: raw entries + all reports with
# complete text (graph_snapshot labels are truncated to 40 chars by design).
walker:pub timeline {
    has reports: list[dict] = [];

    can go with Root entry {
        visit [-->[?:Patient]] else {
            report {"entries": [], "reports": [], "patient": ""};
        }
    }

    can collect with Patient entry {
        entries = [];
        for e in [here ->:has_entry:->[?:Entry]] {
            entries.append({"id": jid(e), "ts": e.ts, "source": e.source, "text": e.text});
        }
        reps = [];
        for r in [here ->:has_report:->[?:Report]] {
            reps.append({"id": jid(r), "kind": r.kind, "status": r.status, "ts": r.ts, "content": r.content});
        }
        report {"entries": entries, "reports": reps, "patient": here.name};
    }
}


def seed_path() -> str {
    # Absolute path first: the hosted sandbox's cwd is NOT the project root.
    candidates = [
        os.path.join(static_patch.PROJECT_ROOT, "seed_data.json"),
        "seed_data.json", "backend/seed_data.json", "../backend/seed_data.json"
    ];
    for p in candidates {
        if os.path.exists(p) {
            return p;
        }
    }
    return candidates[0];
}

walker:pub seed_load {
    has reports: list[dict] = [];

    can go with Root entry {
        visit [-->[?:Patient]] else {
            patient = (here ++> Patient(name="Margaret"))[0] as Patient;
            visit patient;
        }
    }

    can load with Patient entry {
        # Wipe: every non-Patient node is exactly 1 hop out from Patient.
        for n in [here -->] {
            del n;
        }
        data = seed_corpus.get_data();
        sp = seed_path();
        if os.path.exists(sp) {
            try {
                data = json.loads(open(sp).read());
            } except Exception {
                data = seed_corpus.get_data();
            }
        }
        here.name = str(data.get("patient", here.name));
        count = 0;
        for e in data["entries"] {
            ts = str(e["ts"]);
            src = str(e["source"]);
            entry_node = (here +>:has_entry():+>
                          Entry(text=str(e["text"]), source=src, ts=ts))[0] as Entry;
            ex = e["extracted"];
            res = ExtractResult(
                persons=[ExtractedPerson(name=str(p["name"]), relation=str(p["relation"]))
                         for p in ex["persons"]],
                facts=[ExtractedFact(text=str(f["text"]), category=str(f["category"]))
                       for f in ex["facts"]],
                events=[ExtractedEvent(text=str(ev["text"]), date=str(ev["date"]))
                        for ev in ex["events"]],
                signals=[ExtractedSignal(kind=str(s["kind"]), detail=str(s["detail"]))
                         for s in ex["signals"]]
            );
            created: list[str] = [];
            trace: list[str] = [];
            apply_extract(here, entry_node, res, source_conf(src), ts, created, trace);
            count += 1;
        }
        report {"loaded": count};
    }
}

# ============ report / analysis walkers ============
# CareGraph report/analysis walkers: drift_scan, daily_report, handoff_draft,
# handoff_confirm, doctor_report. Shapes per CONTRACT.md.
# "now" is always the newest ts in the graph (corpus time), never the wall clock,
# so the 7-day simulated seed behaves the same on any demo day.

import from datetime { datetime, timedelta }


# Shared drift analysis: window compare + confidence decay. Used by DriftWalker
# (raw alerts) and CritiqueWalker (verified alerts) without nested walker spawns —
# a spawned walker's report{} would leak into the outer HTTP response.
def drift_alerts(patient: Patient) -> list[dict] {
    signals = [patient ->:has_signal:->[?:Signal]];
    if not signals {
        return [];
    }
        now_dt = datetime.fromisoformat(max([s.ts for s in signals]));
        now_start = now_dt - timedelta(days=2);
        base_start = now_dt - timedelta(days=7);

        now_counts: dict[str, int] = {};
        base_counts: dict[str, int] = {};
        for s in signals {
            ts_dt = datetime.fromisoformat(s.ts);
            if ts_dt > now_start {
                now_counts[s.kind] = now_counts.get(s.kind, 0) + 1;
            } elif ts_dt > base_start {
                base_counts[s.kind] = base_counts.get(s.kind, 0) + 1;
            }
        }

        # confidence decay: -0.05 per day since last update, floor 0.1;
        # `updated` is bumped to corpus-now so repeated scans don't compound.
        for e in [edge patient ->:remembers:->] {
            days = (now_dt - datetime.fromisoformat(e.updated)).days;
            if days > 0 {
                e.confidence = max(0.1, e.confidence - 0.05 * days);
                e.updated = now_dt.isoformat();
            }
        }

        alerts = [];
        for kind in now_counts.keys() {
            if kind != "positive_recall" {
                n = now_counts[kind];
                b = base_counts.get(kind, 0);
                now_rate = n / 2.0;
                base_rate = b / 5.0;
                if now_rate > base_rate * 1.5 {
                    sev = "high" if now_rate > base_rate * 2.0 else "medium";
                    # rates, not raw counts — unequal windows (2d vs 5d) make
                    # "19 vs 15" read flat when the real jump is 3.2x
                    if b == 0 {
                        trend = f"{kind}: {now_rate:.1f}/day — new this week";
                    } else {
                        trend = f"{kind}: {now_rate:.1f}/day now vs {base_rate:.1f}/day baseline ({now_rate / max(base_rate, 0.1):.1f}x)";
                    }
                    alerts.append({
                        "kind": kind,
                        "detail": trend,
                        "now_count": n,
                        "base_count": b,
                        "severity": sev
                    });
                }
            }
        }

        latest_positive = "";
        for s in signals {
            if s.kind == "positive_recall" {
                if not latest_positive or s.ts > latest_positive {
                    latest_positive = s.ts;
                }
            }
        }
        if latest_positive {
            detail = [s.detail for s in signals if s.ts == latest_positive and s.kind == "positive_recall"][0];
            alerts.append({
                "kind": "positive_recall",
                "detail": detail,
                "now_count": now_counts.get("positive_recall", 0),
                "base_count": base_counts.get("positive_recall", 0),
                "severity": "low"
            });
        }
        return alerts;
}


walker:pub drift_scan {
    has reports: list[dict] = [];

    can go with Root entry {
        visit [-->[?:Patient]] else {
            report {"alerts": []};
        }
    }

    can scan with Patient entry {
        report {"alerts": drift_alerts(here)};
    }
}


# CritiqueWalker: adversarial second pass over DriftWalker's alerts (the
# devil's-advocate pattern). An alert keeps its severity only when its signals
# spread across >=2 distinct days AND >=2 distinct evidence entries; a spike
# packed into one afternoon is downgraded, with the graph evidence attached so
# the caregiver can click through to WHY. This is the human-trust layer: every
# alert that survives critique carries its own proof.
walker:pub critique_alerts {
    has reports: list[dict] = [];

    can go with Root entry {
        visit [-->[?:Patient]] else {
            report {"alerts": [], "critiqued_by": "CritiqueWalker"};
        }
    }

    can verify with Patient entry {
        raw = drift_alerts(here);
        signals = [here ->:has_signal:->[?:Signal]];
        out = [];
        for a in raw {
            if a["kind"] == "positive_recall" {
                a["verdict"] = "noted";
                a["evidence"] = [];
                out.append(a);
                continue;
            }
            kind_sigs = [s for s in signals if s.kind == a["kind"]];
            days = len({s.ts[:10] for s in kind_sigs});
            ev_ids = [];
            for s in kind_sigs {
                for ent in [s <-:mentioned:<-[?:Entry]] {
                    eid = jid(ent);
                    if eid not in ev_ids {
                        ev_ids.append(eid);
                    }
                }
            }
            if days >= 2 and len(ev_ids) >= 2 {
                a["verdict"] = "confirmed";
            } else {
                a["severity"] = "medium" if a["severity"] == "high" else "low";
                a["verdict"] = "downgraded: single-day spike or thin evidence";
            }
            a["evidence"] = ev_ids[:5];
            out.append(a);
        }
        report {"alerts": out, "critiqued_by": "CritiqueWalker"};
    }
}


walker:pub daily_report {
    has date: str;
    has reports: list[dict] = [];

    can go with Root entry {
        visit [-->[?:Patient]] else {
            report {"report_id": "", "content": ""};
        }
    }

    can compile with Patient entry {
        items = [];
        for en in [here ->:has_entry:->[?:Entry]] {
            if en.ts.startswith(self.date) {
                items.append(f"[{en.source}] {en.text}");
            }
        }
        for s in [here ->:has_signal:->[?:Signal]] {
            if s.ts.startswith(self.date) {
                items.append(f"[signal:{s.kind}] {s.detail}");
            }
        }
        content = draft_report("daily", items) if items else "No entries recorded for this date.";
        rep = Report(kind="daily", content=content, ts=f"{self.date}T23:59:59", status="confirmed");
        here +>:has_report():+> rep;
        report {"report_id": jid(rep), "content": content};
    }
}


walker:pub handoff_draft {
    has reports: list[dict] = [];

    can go with Root entry {
        visit [-->[?:Patient]] else {
            report {"report_id": "", "items": [], "content": ""};
        }
    }

    can draft with Patient entry {
        entries = [here ->:has_entry:->[?:Entry]];
        signals = [here ->:has_signal:->[?:Signal]];
        all_ts = [n.ts for n in entries] + [n.ts for n in signals];
        if not all_ts {
            report {"report_id": "", "items": [], "content": ""};
            disengage;
        }
        corpus_now = max(all_ts);

        confirmed = [r.ts for r in [here ->:has_report:->[?:Report]]
                     if r.kind == "handoff" and r.status == "confirmed"];
        if confirmed {
            cutoff = max(confirmed);
        } else {
            cutoff = (datetime.fromisoformat(corpus_now) - timedelta(hours=24)).isoformat();
        }

        pending = [];  # (ts, id, text) so one sort orders items chronologically
        for en in entries {
            if en.ts > cutoff {
                pending.append((en.ts, jid(en), f"[{en.source}] {en.text}"));
            }
        }
        for s in signals {
            if s.ts > cutoff {
                pending.append((s.ts, jid(s), f"[signal:{s.kind}] {s.detail}"));
            }
        }
        pending.sort();
        items = [{"id": p[1], "text": p[2]} for p in pending];

        content = draft_report("handoff", [p[2] for p in pending]) if pending
                  else "No new items since the last confirmed handoff.";
        rep = Report(kind="handoff", content=content, ts=corpus_now, status="draft");
        here +>:has_report():+> rep;
        report {"report_id": jid(rep), "items": items, "content": content};
    }
}


walker:pub handoff_confirm {
    has report_id: str;
    has approved: list[str] = [];
    has reports: list[dict] = [];

    can go with Root entry {
        visit [-->[?:Patient]] else {
            report {"report_id": self.report_id, "status": "not_found"};
        }
    }

    can confirm with Patient entry {
        for r in [here ->:has_report:->[?:Report]] {
            if jid(r) == self.report_id {
                r.content = f"{r.content}\n\nConfirmed items: {len(self.approved)}";
                r.status = "confirmed";
                report {"report_id": self.report_id, "status": "confirmed"};
                disengage;
            }
        }
        report {"report_id": self.report_id, "status": "not_found"};
    }
}


walker:pub doctor_report {
    has reports: list[dict] = [];

    can go with Root entry {
        visit [-->[?:Patient]] else {
            report {"content": "", "weekly": [], "generated": datetime.now().isoformat()};
        }
    }

    can compile with Patient entry {
        signals = [here ->:has_signal:->[?:Signal]];

        # per-day buckets; dashboard/doctor chart treats each as one trend bucket
        buckets: dict[str, dict[str, int]] = {};
        for s in signals {
            day = s.ts[:10];
            if day not in buckets {
                buckets[day] = {"repeat_q": 0, "confusions": 0};
            }
            if s.kind == "repeat_question" {
                buckets[day]["repeat_q"] += 1;
            } elif s.kind in ["name_confusion", "disorientation"] {
                buckets[day]["confusions"] += 1;
            }
        }
        weekly = [];
        for day in sorted(buckets.keys()) {
            weekly.append({
                "week": datetime.fromisoformat(day).strftime("%b %d"),
                "repeat_q": buckets[day]["repeat_q"],
                "confusions": buckets[day]["confusions"]
            });
        }

        items = [];
        if weekly {
            trend = ", ".join([f"{w['week']}: {w['repeat_q']} repeated questions / {w['confusions']} confusions" for w in weekly]);
            items.append(f"Signal trend by day — {trend}");
        }
        confs: list[float] = [e.confidence for e in [edge here ->:remembers:->]];
        if confs {
            avg = sum(confs) / len(confs);
            items.append(f"Average memory-link confidence: {avg:.2f} across {len(confs)} remembered people/facts/events");
        }
        for ev in [here ->:remembers:->[?:Event]] {
            items.append(f"Key event: {ev.text} ({ev.date})");
        }
        for s in signals {
            if s.kind == "positive_recall" {
                items.append(f"Positive moment: {s.detail}");
            } elif s.kind == "name_confusion" {
                items.append(f"Observed confusion: {s.detail}");
            }
        }

        content = draft_report("doctor", items) if items else "No clinical observations recorded yet.";
        report {"content": content, "weekly": weekly, "generated": datetime.now().isoformat()};
    }
}


# Client entry — the hosted dev preview's client pipeline requires a def:pub
# app export. The real UI is the static trio in assets/, served by BOTH
# runtimes under /static/ (verified: old runtime's is_static_path branch +
# new runtime gateway's serve_project_static both resolve assets/<file>).
cl {
    def:pub app() -> JsxElement {
        window.location.replace("/static/home.html");
        return <div style={{"fontFamily": "sans-serif", "padding": "2rem", "color": "#555"}}>Loading CareGraph…</div>;
    }
}
