# Memory Book regression suite — the contracts the other three suites assume
# but never pin down. Where smoke.jac proves every walker answers and
# integration.jac proves the alert pipeline fires, this suite proves the
# PROMISES each answer makes: referential integrity of the graph snapshot,
# the plain-English guarantee on every human-facing string, exact handoff
# cutoff semantics, per-day trend bucketing, unicode round-trips, and
# case-insensitive search. Runs keyless (CAREGRAPH_MOCK_LLM=1) on its own
# controlled mini-corpus — the demo seed data is never touched, so this file
# can grow without changing what the judges see on screen.
#
# Run via scripts/run_tests.sh (fresh temp dir, fresh graph state).

include main;

import sys;

glob R_FAILS: list[str] = [];

def rcheck(name: str, cond: bool) {
    if cond {
        print(f"PASS  {name}");
    } else {
        R_FAILS.append(name);
        print(f"FAIL  {name}");
    }
}

# The five signal kinds the whole system speaks — extraction, drift rates,
# chart bucketing and the dashboard legend all assume this exact taxonomy.
glob KNOWN_KINDS: list[str] = ["repeat_question", "name_confusion",
                               "disorientation", "positive_recall", "social_moment"];
glob KNOWN_TYPES: list[str] = ["Patient", "Person", "Fact", "Event",
                               "Signal", "Entry", "Report"];

# Any raw identifier leaking into caregiver-facing text shows up as an
# underscore (repeat_question, L1_wearable...). The plain-English pass made
# that a hard promise; this helper enforces it on every surface we render.
def plain(s: str) -> bool {
    return "_" not in s;
}

with entry {
    root spawn init_patient(name="Margaret");

    # ---- controlled mini-corpus (heuristic-extraction path, no API key).
    # Texts start lowercase on purpose: the keyless extractor reads capitals
    # as names, so sentence case here would invent people.
    root spawn ingest_batch(source="L1_wearable", ts="2026-07-19T09:00:00",
        text="asked what day is it this morning, then settled in by the window.");
    root spawn ingest_batch(source="L1_wearable", ts="2026-07-19T15:00:00",
        text="she sang along with the record all afternoon, word for word.");
    # ingested twice on purpose — the merge test below
    root spawn ingest_batch(source="L2_caregiver", ts="2026-07-20T10:00:00",
        text="Rosa dropped off soup and they laughed together in the kitchen.");
    root spawn ingest_batch(source="L2_caregiver", ts="2026-07-20T10:00:00",
        text="Rosa dropped off soup and they laughed together in the kitchen.");
    # unicode round-trip payload: accents, emoji, em dash
    root spawn ingest_batch(source="L1_wearable", ts="2026-07-20T17:00:00",
        text="the café radio played her song and she smiled at the tune — ☕ a good afternoon.");
    root spawn ingest_batch(source="L1_wearable", ts="2026-07-21T08:30:00",
        text="asked what day is it, and asked again twice before breakfast was done.");
    root spawn ingest_batch(source="L1_wearable", ts="2026-07-21T12:00:00",
        text="found her looking for the bus stop to the old school at midday.");
    root spawn ingest_batch(source="L2_caregiver", ts="2026-07-21T13:00:00",
        text="a long slow lunch today; she asked about lunch three times after eating, "
             "settled each time with the answer, kept folding and refolding the same napkin, "
             "and wanted the radio on for the whole meal from the first course to the last cup of tea.");
    root spawn ingest_batch(source="L1_wearable", ts="2026-07-21T18:00:00",
        text="Emma called to say she will visit on sunday evening after supper.");

    # ---- snapshot: referential integrity ------------------------------
    snap = (root spawn graph_snapshot()).reports[0];
    ids = [n["id"] for n in snap["nodes"]];
    rcheck("snapshot node ids are unique", len(ids) == len(set(ids)));
    rcheck("snapshot has exactly one Patient",
           len([n for n in snap["nodes"] if n["type"] == "Patient"]) == 1);
    bad_types = [n["type"] for n in snap["nodes"] if n["type"] not in KNOWN_TYPES];
    rcheck("every node type is a known type", len(bad_types) == 0);
    bad_kinds = [n["kind"] for n in snap["nodes"]
                 if n["type"] == "Signal" and n["kind"] not in KNOWN_KINDS];
    rcheck("every Signal kind is in the taxonomy", len(bad_kinds) == 0);
    idset = set(ids);
    dangling = [l for l in snap["links"]
                if l["source"] not in idset or l["target"] not in idset];
    rcheck("no link points at a missing node", len(dangling) == 0);
    # `mentioned` edges are the provenance spine the UI tags ride on:
    # they must always start at a raw Entry, never at derived knowledge.
    typeof = {};
    for n in snap["nodes"] { typeof[n["id"]] = n["type"]; }
    bad_mentions = [l for l in snap["links"]
                    if l["type"] == "mentioned" and typeof[l["source"]] != "Entry"];
    rcheck("every mentioned edge starts at an Entry", len(bad_mentions) == 0);

    # ---- merge, don't duplicate ---------------------------------------
    persons = [n["label"] for n in snap["nodes"] if n["type"] == "Person"];
    rcheck("same person ingested twice becomes ONE node", persons.count("Rosa") == 1);
    rcheck("distinct people stay distinct", "Emma" in persons);

    # ---- timeline: the raw feed is lossless ---------------------------
    tl = (root spawn timeline()).reports[0];
    rcheck("timeline returns all 9 ingested entries", len(tl["entries"]) == 9);
    cafe = [e for e in tl["entries"] if "café" in e["text"]];
    rcheck("unicode text round-trips exactly (accents, ☕, em dash)",
           len(cafe) == 1 and "☕ a good afternoon." in cafe[0]["text"]);
    longest = max([len(e["text"]) for e in tl["entries"]]);
    rcheck("long entries are stored untruncated (>200 chars)", longest > 200);

    # ---- search: case-insensitive, no false positives -----------------
    s1 = (root spawn search_entries(query="soup")).reports[0];
    rcheck("search finds both soup entries", len(s1["matches"]) == 2);
    s2 = (root spawn search_entries(query="SOUP KITCHEN")).reports[0];
    rcheck("search is case-insensitive", len(s2["matches"]) >= 2);
    s3 = (root spawn search_entries(query="zzzunfindable")).reports[0];
    rcheck("search returns nothing for nonsense", len(s3["matches"]) == 0);

    # ---- ask: answers carry their evidence ----------------------------
    a = (root spawn ask(question="Did Emma call about visiting?")).reports[0];
    rcheck("ask answers with a non-empty sentence", len(a["answer"]) > 0);
    rcheck("ask walks a real path", len(a["path"]) > 0);
    rcheck("ask cites at least one raw entry", len(a["evidence"]) > 0);
    path_ok = [p for p in a["path"] if p in idset];
    rcheck("every path hop exists in the snapshot", len(path_ok) == len(a["path"]));

    # ---- daily report: exact empty-day contract ------------------------
    d0 = (root spawn daily_report(date="2025-01-01")).reports[0];
    rcheck("empty day says so in one plain sentence",
           d0["content"] == "No entries recorded for this date.");
    d1 = (root spawn daily_report(date="2026-07-21")).reports[0];
    rcheck("daily report covers the day's moments", "lunch" in d1["content"]);
    rcheck("daily report is plain English (no raw tokens)", plain(d1["content"]));
    rcheck("daily report is persisted with an id", len(d1["report_id"]) > 0);

    # ---- handoff: cutoff semantics, confirm loop -----------------------
    h1 = (root spawn handoff_draft()).reports[0];
    rcheck("handoff drafts the last 24h of moments", len(h1["items"]) >= 4);
    with_ids = [i for i in h1["items"] if len(i["id"]) > 0];
    rcheck("every checklist item is individually addressable",
           len(with_ids) == len(h1["items"]));
    unplain = [i for i in h1["items"] if not plain(i["text"])];
    rcheck("every checklist item is plain English", len(unplain) == 0);

    miss = (root spawn handoff_confirm(report_id="not-a-real-id", approved=[])).reports[0];
    rcheck("confirming a bogus id reports not_found", miss["status"] == "not_found");

    ok = (root spawn handoff_confirm(report_id=h1["report_id"],
                                     approved=[h1["items"][0]["id"]])).reports[0];
    rcheck("confirming the draft flips it to confirmed", ok["status"] == "confirmed");

    h2 = (root spawn handoff_draft()).reports[0];
    rcheck("nothing new after a confirm -> empty checklist", len(h2["items"]) == 0);
    rcheck("and it says so gently",
           h2["content"] == "No new items since the last confirmed handoff.");

    # one new moment after the confirm — the next draft must contain
    # EXACTLY that moment, nothing recycled from before the cutoff
    root spawn ingest_batch(source="L2_caregiver", ts="2026-07-21T19:00:00",
        text="she watered the plants before tea and picked out two ripe ones.");
    h3 = (root spawn handoff_draft()).reports[0];
    rcheck("next draft contains exactly the one new moment", len(h3["items"]) == 1);
    rcheck("and it is the right one", "watered the plants" in h3["items"][0]["text"]);

    # ---- doctor report: per-day buckets the chart depends on -----------
    doc = (root spawn doctor_report()).reports[0];
    rcheck("doctor report buckets by distinct signal days", len(doc["weekly"]) == 3);
    w_last = doc["weekly"][-1];
    rcheck("chart buckets are chronological (last = Jul 21)", w_last["week"] == "Jul 21");
    rcheck("Jul 21 counted both repeated questions", w_last["repeat_q"] == 2);
    rcheck("Jul 21 counted the disorientation", w_last["confusions"] == 1);
    w_first = doc["weekly"][0];
    rcheck("a social day is NOT a confusion day",
           w_first["repeat_q"] == 1 and w_first["confusions"] == 0);
    rcheck("doctor report reads plain", plain(doc["content"]));

    # ---- drift + critique: alert shape contract -------------------------
    dr = (root spawn drift_scan()).reports[0];
    shaped = [x for x in dr["alerts"]
              if "kind" in x and "severity" in x and "detail" in x];
    rcheck("every drift alert carries kind/severity/detail",
           len(shaped) == len(dr["alerts"]));
    unplain_alerts = [x for x in dr["alerts"] if not plain(x["detail"])];
    rcheck("every alert detail is plain English", len(unplain_alerts) == 0);
    cr = (root spawn critique_alerts()).reports[0];
    with_verdict = [x for x in cr["alerts"] if "verdict" in x];
    rcheck("critique attaches a verdict to every alert",
           len(with_verdict) == len(cr["alerts"]));

    # ---- diag: the probe tells the truth --------------------------------
    tl2 = (root spawn timeline()).reports[0];
    dg = (root spawn diag()).reports[0];
    rcheck("diag entry count matches the timeline", dg["entries"] == len(tl2["entries"]));
    rcheck("diag knows the patient", dg["patient"] == "Margaret");
    rcheck("diag names its replica as host:pid", ":" in dg["pod"]);
    latest = max([e["ts"] for e in tl2["entries"]]);
    rcheck("diag tracks the newest moment", dg["latest_entry_ts"] == latest);
    rcheck("diag reports the mock fuse honestly", dg["llm"]["mock_fuse"] == True);

    # ---- verdict --------------------------------------------------------
    print("");
    if R_FAILS {
        print(f"REGRESSION SUITE: {len(R_FAILS)} FAILED");
        for f in R_FAILS { print(f"  - {f}"); }
        sys.exit(1);
    }
    print("REGRESSION SUITE: all checks passed");
}
