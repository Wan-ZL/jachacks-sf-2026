# CareGraph byLLM layer — typed extraction + phrasing + report drafting.
# Safety fuse: set env CAREGRAPH_MOCK_LLM=1 to run all three functions with
# deterministic plain-Jac logic (zero API calls). Public wrappers extract /
# phrase_answer / draft_report dispatch on that env var; the by-llm versions
# live in the _llm_* private functions below.

import os;
import re;
import llm_backend;

glob llm = llm_backend.get_model();


obj ExtractedPerson {
    has name: str,
        relation: str;
}
sem ExtractedPerson = "A person mentioned in the conversation, other than the patient.";
sem ExtractedPerson.name = "The person's name exactly as spoken (e.g. 'Emma').";
sem ExtractedPerson.relation = "Short relation to the patient: granddaughter, neighbor, caregiver, late sister, friend, doctor... One or two words.";

obj ExtractedFact {
    has text: str,
        category: str;
}
sem ExtractedFact = "A stable piece of knowledge the patient holds or that is true about their life.";
sem ExtractedFact.text = "The fact as one short plain sentence.";
sem ExtractedFact.category = "Exactly one of: person | place | routine | preference | other.";

obj ExtractedEvent {
    has text: str,
        date: str;
}
sem ExtractedEvent = "An appointment or happening, past or upcoming.";
sem ExtractedEvent.text = "The event as one short plain sentence.";
sem ExtractedEvent.date = "ISO-8601 date (YYYY-MM-DD) if it can be inferred from the text using the provided 'today' date (e.g. 'Sunday' -> the next Sunday on or after today); empty string if no date is inferable.";

obj ExtractedSignal {
    has kind: str,
        detail: str;
}
sem ExtractedSignal = "A cognitive-health signal observed in the conversation of an Alzheimer's patient.";
sem ExtractedSignal.kind = "Exactly one of: repeat_question (patient asked the same question more than once) | name_confusion (patient mixed up or forgot a name) | disorientation (confused about time, place, or situation) | positive_recall (patient correctly remembered something noteworthy) | social_moment (patient engaged normally and warmly in conversation or activity — the healthy-baseline control signal).";
sem ExtractedSignal.detail = "One short sentence describing the observation, including counts if present (e.g. 'asked what day it is three times').";

obj ExtractResult {
    has persons: list[ExtractedPerson],
        facts: list[ExtractedFact],
        events: list[ExtractedEvent],
        signals: list[ExtractedSignal];
}
sem ExtractResult = "Everything extracted from a batch of transcribed patient conversation. Empty lists when a category has no items — never invent.";


def _llm_extract(batch_text: str, today: str) -> ExtractResult by llm();
sem _llm_extract = "Extract persons, stable facts, dated events, and cognitive-health signals from a transcribed conversation involving an Alzheimer's patient. Only extract what is explicitly evidenced in the text.";
sem _llm_extract.batch_text = "Raw transcribed conversation text, possibly several utterances.";
sem _llm_extract.today = "Today's date in ISO-8601, for resolving relative dates like 'Sunday' or 'tomorrow'.";

def _llm_phrase_answer(question: str, facts: list[str]) -> str by llm();
sem _llm_phrase_answer = "Answer the caregiver's question warmly in ONE short, very simple sentence a 10-year-old could read at a glance. Everyday words only — no medical or technical terms. Use ONLY the facts provided; if they don't answer it, say so gently. Never invent information.";
sem _llm_phrase_answer.question = "The caregiver's question about the patient.";
sem _llm_phrase_answer.facts = "The only facts you may use in the answer.";

def _llm_draft_report(kind: str, items: list[str]) -> str by llm();
sem _llm_draft_report = "Write a very simple report from the given items for a family with no medical background: first line = one short plain sentence on how the day went; then at most 8 short bullets, each under 12 words, everyday language a child could read. No jargon, no abbreviations, no underscores, nothing beyond the items.";
sem _llm_draft_report.kind = "Report kind: daily | handoff | doctor.";
sem _llm_draft_report.items = "The observations/items to summarize into the report.";


def _mock_on() -> bool {
    return os.environ.get("CAREGRAPH_MOCK_LLM", "") == "1";
}


# Keyless fallback: deterministic heuristic extraction so the full ingest →
# graph → alert pipeline works with zero API calls (demo insurance — the same
# trade the Best Demo winner PharmaGraph made). Coarse by design; the live
# byLLM path is strictly better, this only has to keep the demo standing.
def _heuristic_extract(batch_text: str) -> ExtractResult {
    low = batch_text.lower();
    persons: list[ExtractedPerson] = [];
    signals: list[ExtractedSignal] = [];
    seen: list[str] = [];
    skip_words = ["margaret", "sunday", "monday", "tuesday", "wednesday", "thursday",
            "friday", "saturday", "i", "she", "he", "the", "a", "is", "it",
            "oh", "and", "but", "that", "this", "duke", "ellington",
            "they", "asked", "found", "when", "did", "everyone", "after",
            "before", "right", "within", "her", "his", "we", "you"];
    for w in re.findall(r"[A-Z][a-z]+", batch_text) {
        ws = str(w);
        if ws.lower() not in skip_words and ws.lower() not in seen {
            seen.append(ws.lower());
            persons.append(ExtractedPerson(name=ws, relation="mentioned"));
        }
    }
    if (re.search(r"(asked|asks|asking).*(again|twice|three times|\d+ times)", low)
        or re.search(r"what day is it|is it (sunday|monday|tuesday)|did we (already|just)", low)) {
        signals.append(ExtractedSignal(kind="repeat_question",
                                       detail=batch_text[:80]));
    }
    if re.search(r"bus stop|need to be at|looking for the|where am i|wrong (house|door)", low) {
        signals.append(ExtractedSignal(kind="disorientation", detail=batch_text[:80]));
    }
    if re.search(r"sang|laughed|smiled|recognized|remembered the", low) {
        signals.append(ExtractedSignal(kind="social_moment", detail=batch_text[:80]));
    }
    return ExtractResult(persons=persons, facts=[], events=[], signals=signals);
}

def extract(batch_text: str, today: str) -> ExtractResult {
    if _mock_on() {
        return _heuristic_extract(batch_text);
    }
    try {
        return _llm_extract(batch_text, today);
    } except Exception {
        # live LLM unavailable (no key / outage) — demo must not 500
        return _heuristic_extract(batch_text);
    }
}

def phrase_answer(question: str, facts: list[str]) -> str {
    if _mock_on() {
        if not facts {
            return "I don't have any notes about that yet.";
        }
        return "Here is what I know: " + "; ".join(facts) + ".";
    }
    try {
        return _llm_phrase_answer(question, facts);
    } except Exception {
        return "Here is what I know: " + "; ".join(facts) + ".";
    }
}

def draft_report(kind: str, items: list[str]) -> str {
    if _mock_on() {
        lines = [f"{kind} report — {len(items)} items."];
        for it in items[:10] {
            lines.append(f"- {it}");
        }
        return "\n".join(lines);
    }
    try {
        return _llm_draft_report(kind, items);
    } except Exception {
        lines = [f"{kind} report — {len(items)} items."];
        for it in items[:10] {
            lines.append(f"- {it}");
        }
        return "\n".join(lines);
    }
}
