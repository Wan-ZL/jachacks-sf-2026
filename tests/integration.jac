# Full-pipeline integration: RAW TEXT in, VERIFIED ALERT out — no seed corpus,
# no API key. Seven simulated days stream through ingest_batch (keyless
# heuristic extraction), then DriftWalker must fire on the spike and
# CritiqueWalker must confirm it with graph evidence, while the social
# control signal stays quiet. Run via scripts/run_tests.sh.

include main;

import sys;

glob I_FAILS: list[str] = [];

def icheck(name: str, cond: bool) {
    if cond {
        print(f"PASS  {name}");
    } else {
        I_FAILS.append(name);
        print(f"FAIL  {name}");
    }
}

def day(n: int, hh: str) -> str {
    return f"2026-07-{18 + n}T{hh}:00";
}

with entry {
    root spawn init_patient(name="Margaret");

    # ---- baseline week: warm days, occasional repeat
    root spawn ingest_batch(source="L1_wearable", ts=day(1, "10:00"),
        text="Rosa came by for tea and everyone laughed at the garden story.");
    root spawn ingest_batch(source="L1_wearable", ts=day(2, "09:00"),
        text="asked what day is it this morning, then settled down happily.");
    root spawn ingest_batch(source="L1_wearable", ts=day(3, "15:00"),
        text="she sang along with the record and smiled the whole afternoon.");
    root spawn ingest_batch(source="L2_caregiver", ts=day(4, "18:00"),
        text="Emma called to say she will visit; a calm and happy evening.");
    root spawn ingest_batch(source="L1_wearable", ts=day(5, "11:00"),
        text="asked what day is it before lunch, once.");

    # ---- the spike: days 6-7
    root spawn ingest_batch(source="L1_wearable", ts=day(6, "08:30"),
        text="asked what day is it, and asked again twice before breakfast.");
    root spawn ingest_batch(source="L2_caregiver", ts=day(6, "13:00"),
        text="asked about lunch three times within the hour.");
    root spawn ingest_batch(source="L1_wearable", ts=day(6, "17:00"),
        text="she laughed at the radio show after dinner.");
    root spawn ingest_batch(source="L1_wearable", ts=day(7, "09:00"),
        text="asked what day is it four times before ten.");
    root spawn ingest_batch(source="L2_caregiver", ts=day(7, "12:30"),
        text="asked when lunch would be, twice, right after eating.");
    root spawn ingest_batch(source="L1_wearable", ts=day(7, "16:00"),
        text="found her looking for the bus stop to the old school again.");

    # ---- graph grew from raw text alone
    snap = (root spawn graph_snapshot()).reports[0];
    icheck("raw ingest built a graph (>14 nodes)", len(snap["nodes"]) > 14);
    labels = [n["label"] for n in snap["nodes"]];
    icheck("heuristics extracted Emma from raw text", "Emma" in labels);

    # ---- ask works over heuristically-built memories
    a = (root spawn ask(question="Did Emma call about visiting?")).reports[0];
    icheck("ask finds Emma with evidence", len(a["path"]) > 0 and len(a["evidence"]) > 0);

    # ---- drift fires on the spike, in rates
    d = (root spawn drift_scan()).reports[0];
    kinds = [x["kind"] for x in d["alerts"]];
    icheck("spike raises repeat_question alert", "repeat_question" in kinds);
    rq = [x for x in d["alerts"] if x["kind"] == "repeat_question"][0];
    icheck("alert severity is high", rq["severity"] == "high");
    icheck("alert speaks in rates", "/day" in rq["detail"]);
    icheck("disorientation reported as new this week",
           "disorientation" in kinds
           and "new this week" in [x for x in d["alerts"] if x["kind"] == "disorientation"][0]["detail"]);
    icheck("social control stays quiet", "social_moment" not in kinds);

    # ---- critique confirms with evidence from >=2 days and >=2 entries
    c = (root spawn critique_alerts()).reports[0];
    crq = [x for x in c["alerts"] if x["kind"] == "repeat_question"][0];
    icheck("critique confirms the spike", crq["verdict"] == "confirmed");
    icheck("confirmed alert carries >=2 evidence entries", len(crq["evidence"]) >= 2);

    # ---- handoff sees the week
    h = (root spawn handoff_draft()).reports[0];
    icheck("handoff draft has items", len(h["items"]) > 0);

    print("");
    if I_FAILS {
        print(f"{len(I_FAILS)} FAILED: {I_FAILS}");
        sys.exit(1);
    } else {
        print("ALL PASS (11 checks)");
    }
}
