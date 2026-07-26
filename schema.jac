# CareGraph graph schema — node/edge types exactly per CONTRACT.md.

node Patient {
    has name: str;
}

node Person {
    has name: str,
        relation: str;
}

node Fact {
    has text: str,
        category: str;
}

node Event {
    has text: str,
        date: str;
}

node Entry {
    has text: str,
        source: str,
        ts: str;
}

node Signal {
    has kind: str,
        detail: str,
        ts: str;
}

node Report {
    has kind: str,
        content: str,
        ts: str,
        status: str;
}

edge remembers {
    has confidence: float,
        updated: str;
}

edge mentioned {}

edge has_entry {}

edge has_signal {}

edge has_report {}
