# Provenance & decay suite — verifies the graph's trust model end-to-end:
# L1 wearable mentions carry 0.7 confidence, L2 human observations 0.9,
# re-mention bumps but never lowers, and DriftWalker's decay is idempotent
# within one corpus day. Run via scripts/run_tests.sh (isolated temp dir).

include main;

import sys;

glob P_FAILS: list[str] = [];

def pcheck(name: str, cond: bool) {
    if cond {
        print(f"PASS  {name}");
    } else {
        P_FAILS.append(name);
        print(f"FAIL  {name}");
    }
}

def conf_of(snapshot: dict, label: str) -> float {
    for n in snapshot["nodes"] {
        if n.get("label") == label and "confidence" in n {
            return n["confidence"];
        }
    }
    return -1.0;
}

with entry {
    root spawn init_patient(name="Margaret");
    root spawn seed_load();
    snap = (root spawn graph_snapshot()).reports[0];

    # ---- source provenance: L2-touched memories outrank L1-only ones
    pcheck("Emma (L2-mentioned) carries 0.9", conf_of(snap, "Emma") == 0.9);
    pcheck("Harold (L1-only) carries 0.7", conf_of(snap, "Harold") == 0.7);
    ok_range = True;
    for n in snap["nodes"] {
        if "confidence" in n and (n["confidence"] > 0.9 or n["confidence"] < 0.1) {
            ok_range = False;
        }
    }
    pcheck("all confidences within [0.1, 0.9]", ok_range);

    # ---- re-mention semantics, proven by the seed's own mixed-source history:
    # the Sunday-lunch event is FIRST created by an L1 transcript (0.7) and later
    # mentioned in L2 notes — it must end at 0.9 (bump up), while Emma (0.9 from
    # L2) keeps 0.9 despite later L1 mentions (never lowered).
    pcheck("L1-born event bumped to 0.9 by later human mention",
           conf_of(snap, "Emma visiting for Sunday lunch") == 0.9);
    pcheck("later L1 mentions never lower an L2 memory",
           conf_of(snap, "Emma likes the yellow cherry tomatoes") == 0.9);

    # ---- decay: drift_scan ages unmentioned edges, and is idempotent per day
    root spawn drift_scan();
    snap3 = (root spawn graph_snapshot()).reports[0];
    rosa1 = conf_of(snap3, "Has tea with Rosa every Tuesday");
    pcheck("old fact decayed below its source confidence", rosa1 < 0.9 and rosa1 >= 0.1);
    root spawn drift_scan();
    snap4 = (root spawn graph_snapshot()).reports[0];
    pcheck("decay does not compound within one corpus day",
           conf_of(snap4, "Has tea with Rosa every Tuesday") == rosa1);

    print("");
    if P_FAILS {
        print(f"{len(P_FAILS)} FAILED: {P_FAILS}");
        sys.exit(1);
    } else {
        print("ALL PASS (7 checks)");
    }
}
