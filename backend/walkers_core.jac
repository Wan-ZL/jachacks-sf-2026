# Core walkers: init_patient, ingest_batch, ask, graph_snapshot, seed_load.
# llm.jac provides extract/phrase_answer/draft_report + Extracted* objs (CONTRACT signatures).

include schema;
include llm;

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

def seed_path() -> str {
    for p in ["seed_data.json", "backend/seed_data.json", "../backend/seed_data.json"] {
        if os.path.exists(p) {
            return p;
        }
    }
    return "seed_data.json";
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
        data = json.loads(open(seed_path()).read());
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
