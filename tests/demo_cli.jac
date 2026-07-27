# Memory Book terminal demo — the full product story without a browser.
# For judges and reviewers: scripts/demo_cli.sh runs this in an isolated temp
# dir (keyless by default via the deterministic byLLM fallback; export
# ANTHROPIC_API_KEY and unset CAREGRAPH_MOCK_LLM for live LLM phrasing).

include main;

def banner(title: str) {
    print("");
    print("============================================================");
    print(f"  {title}");
    print("============================================================");
}

with entry {
    banner("Memory Book — ambient memory graph for Alzheimer's care");
    print("Margaret, 78. Her granddaughter Emma visits Sunday.");
    print("A worn phone listens; walkers turn talk into a memory graph.");

    root spawn init_patient(name="Margaret");
    seeded = (root spawn seed_load()).reports[0];
    snap = (root spawn graph_snapshot()).reports[0];
    print(f"Seeded {seeded['loaded']} conversation entries -> "
          f"{len(snap['nodes'])} nodes / {len(snap['links'])} edges.");

    banner("RecallWalker — evidence-cited memory recall");
    for q in ["Does she remember Emma is visiting?",
              "What does she do with Rosa?",
              "What music does she love?"] {
        a = (root spawn ask(question=q)).reports[0];
        print(f"Q: {q}");
        print(f"A: {a['answer']}");
        print(f"   ({len(a['path'])}-node traversal, {len(a['evidence'])} evidence entries)");
    }

    banner("DriftWalker + CritiqueWalker — decline detection, verified");
    c = (root spawn critique_alerts()).reports[0];
    for al in c["alerts"] {
        mark = "OK " if al["verdict"] == "confirmed" else "~~ ";
        print(f"{mark}[{al['severity']:6}] {al['detail']}");
        print(f"      verdict: {al['verdict']}, evidence entries: {len(al.get('evidence', []))}");
    }
    print("(social_moment — the flat control — raised no alert: she isn't");
    print(" 'just chattier this week'; only the memory signals moved.)");

    banner("HandoffWalker — AI drafts, the human confirms");
    h = (root spawn handoff_draft()).reports[0];
    print(f"Draft with {len(h['items'])} observations since last confirmed handoff.");
    keep = [i["id"] for i in h["items"][:3]];
    hc = (root spawn handoff_confirm(report_id=h["report_id"], approved=keep)).reports[0];
    print(f"Caregiver approved {len(keep)} items -> status: {hc['status']}.");

    banner("Doctor report — the clinical timeline");
    doc = (root spawn doctor_report()).reports[0];
    print(f"{len(doc['weekly'])} day-buckets of signal trends. Headline:");
    for line in str(doc["content"]).split("\n")[:6] {
        print(f"  {line}");
    }

    banner("Where Jac ran just now");
    print("11 walker:pub endpoints; typed nodes/edges with decaying confidence;");
    print("byLLM only at the language boundary; the graph is the database.");
}
