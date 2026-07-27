# CareGraph smoke suite — exercises every walker end-to-end on the embedded
# demo corpus, keyless (CAREGRAPH_MOCK_LLM=1). Run via scripts/run_tests.sh,
# which copies the project into a temp dir so the demo graph state is untouched.

include main;

import sys;

glob FAILS: list[str] = [];

def check(name: str, cond: bool) {
    if cond {
        print(f"PASS  {name}");
    } else {
        FAILS.append(name);
        print(f"FAIL  {name}");
    }
}

with entry {
    # ---- init: idempotent patient creation
    r1 = root spawn init_patient(name="Margaret");
    r1b = root spawn init_patient(name="Margaret");
    check("init_patient returns id", bool(r1.reports[0]["patient_id"]));
    check("init_patient idempotent", r1.reports[0]["patient_id"] == r1b.reports[0]["patient_id"]);

    # ---- seed: embedded corpus (no file dependency — the deploy-500 regression)
    r2 = root spawn seed_load();
    check("seed_load loads 22 entries", r2.reports[0]["loaded"] == 22);

    # ---- snapshot integrity
    snap = (root spawn graph_snapshot()).reports[0];
    check("snapshot has >70 nodes", len(snap["nodes"]) > 70);
    check("snapshot has >100 links", len(snap["links"]) > 100);

    # ---- timeline: full-content feed for the tiered UI
    tl = (root spawn timeline()).reports[0];
    check("timeline returns 22 entries", len(tl["entries"]) == 22);
    check("timeline text is untruncated", len(tl["entries"][0]["text"]) > 10);
    check("timeline knows the patient", tl["patient"] == "Margaret");

    # ---- server-side raw-data search
    se = (root spawn search_entries(query="tomatoes")).reports[0];
    check("search_entries finds tomato entries", len(se["matches"]) >= 2);

    # ---- ingest: merge, don't duplicate (Emma/Sunday already exist in seed)
    before = len(snap["nodes"]);
    r3 = root spawn ingest_batch(source="L2_caregiver",
                                 text="Emma will visit on Sunday.",
                                 ts="2026-07-26T09:00:00");
    snap2 = (root spawn graph_snapshot()).reports[0];
    check("ingest reports a trace", len(r3.reports[0]["trace"]) >= 1);
    check("ingest merges instead of duplicating", len(snap2["nodes"]) <= before + 4);

    # ---- ask: deterministic traversal, evidence-cited, ids consistent
    r4 = root spawn ask(question="Does she remember Emma is visiting?");
    a = r4.reports[0];
    check("ask produces an answer", len(a["answer"]) > 0);
    check("ask walks a path", len(a["path"]) > 0);
    check("ask cites evidence entries", len(a["evidence"]) > 0);
    ids = {n["id"] for n in snap2["nodes"]};
    all_in = True;
    for p in a["path"] {
        if p not in ids {
            all_in = False;
        }
    }
    check("ask path ids all appear in snapshot", all_in);

    # ---- drift: rate-based alerts, flat control stays silent
    d = (root spawn drift_scan()).reports[0];
    kinds = [x["kind"] for x in d["alerts"]];
    check("drift flags repeat_question", "repeat_question" in kinds);
    rq = [x for x in d["alerts"] if x["kind"] == "repeat_question"][0];
    check("drift detail speaks plain rates", "a day" in rq["detail"]);
    check("flat control (social_moment) never alerts", "social_moment" not in kinds);

    # ---- critique: adversarial verification with graph evidence
    c = (root spawn critique_alerts()).reports[0];
    check("critique attributed to CritiqueWalker", c["critiqued_by"] == "CritiqueWalker");
    crq = [x for x in c["alerts"] if x["kind"] == "repeat_question"][0];
    check("repeat_question confirmed with >=2 evidence",
          crq["verdict"] == "confirmed" and len(crq["evidence"]) >= 2);

    # ---- daily report persists
    dr = (root spawn daily_report(date="2026-07-25")).reports[0];
    check("daily report created", bool(dr["report_id"]));

    # ---- handoff: draft -> confirm -> cutoff honored on next draft
    h1 = (root spawn handoff_draft()).reports[0];
    check("handoff draft has items", len(h1["items"]) > 0);
    hc = (root spawn handoff_confirm(report_id=h1["report_id"],
                                     approved=[h1["items"][0]["id"]])).reports[0];
    check("handoff confirm flips status", hc["status"] == "confirmed");
    h2 = (root spawn handoff_draft()).reports[0];
    check("handoff cutoff honored", len(h2["items"]) <= len(h1["items"]));

    # ---- doctor report: per-day buckets + narrative
    doc = (root spawn doctor_report()).reports[0];
    check("doctor report has day buckets", len(doc["weekly"]) >= 7);
    check("doctor report has content", len(doc["content"]) > 0);

    print("");
    if FAILS {
        print(f"{len(FAILS)} FAILED: {FAILS}");
        sys.exit(1);
    } else {
        print("ALL PASS (23 checks)");
    }
}
