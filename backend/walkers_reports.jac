# CareGraph report/analysis walkers: drift_scan, daily_report, handoff_draft,
# handoff_confirm, doctor_report. Shapes per CONTRACT.md.
# "now" is always the newest ts in the graph (corpus time), never the wall clock,
# so the 7-day simulated seed behaves the same on any demo day.

import from datetime { datetime, timedelta }
import from schema { Patient, Entry, Signal, Report, Event, remembers, has_entry, has_signal, has_report }
import from llm { draft_report }


walker:pub drift_scan {
    has reports: list[dict] = [];

    can go with Root entry {
        visit [-->[?:Patient]] else {
            report {"alerts": []};
        }
    }

    can scan with Patient entry {
        signals = [here ->:has_signal:->[?:Signal]];
        if not signals {
            report {"alerts": []};
            disengage;
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
        for e in [edge here ->:remembers:->] {
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
                    alerts.append({
                        "kind": kind,
                        "detail": f"{kind}: {n} in the last 2 days vs {b} in the prior 5",
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
        report {"alerts": alerts};
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
