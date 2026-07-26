# Jac toolchain — VERIFIED ground truth (2026-07-26, macOS arm64)

Everything below was actually run and confirmed on this machine. Do not trust older
jac-cloud-era blog posts / tutorials — the stack changed significantly at jaclang 0.16.x.

## Versions installed (conda env `jachacks`, Python 3.12.13)

| package | version |
|---|---|
| jaclang | 0.16.7 |
| byllm   | 0.6.19 |
| litellm | 1.82.6 (byllm dep) |
| fastapi | 0.115.11 |

**jac-cloud is NOT installed and must NOT be installed.** See Gotcha #1.

## Activate

```bash
source ~/miniconda3/etc/profile.d/conda.sh
conda activate jachacks
jac --version   # shows 0.16.7 + "Plugins Detected: byllm==0.6.19"
```

## The single most useful discovery: `jac guide`

`jac guide` (no args) lists curated, current, offline reference guides bundled with the
compiler — they are much more accurate than web docs. Read these before writing code:

```bash
jac guide jac-core-cheatsheet     # baseline syntax
jac guide jac-node-edge-patterns  # nodes, edges, graph queries
jac guide jac-walker-patterns     # walkers, visit/report/spawn
jac guide jac-sv-endpoints        # REST endpoints
jac guide jac-by-llm              # LLM-powered functions
jac guide jac-sv-persistence      # server-side graph persistence
```

---

## Smoke test 1 — hello-graph (`jac run`, persistence)

File `hello.jac` (ran successfully, twice):

```jac
node City {
    has name: str;
    has pop: int = 0;
}

edge Road: City --> City {
    has km: int = 1;
}

walker Tour {
    has reports: list[str] = [];

    can start with Root entry {
        existing = [here -->[?:City]];
        if not existing {
            sf = (here ++> City(name="SF", pop=800000))[0] as City;
            oak = (here ++> City(name="Oakland", pop=440000))[0] as City;
            sf +>:Road(km=13):+> oak;
            print("created 2 cities + 1 Road edge");
        } else {
            print(f"found {len(existing)} existing cities (persistence!)");
        }
        visit [-->];
    }

    can see with City entry {
        for e in [edge here ->:Road:->] {
            print(f"{here.name} --Road({e.km}km)--> connects onward");
        }
        report f"{here.name} pop={here.pop}";
        visit [->:Road:->];
    }
}

with entry {
    result = root spawn Tour();
    print("reports:", result.reports);
}
```

Run: `jac run hello.jac`

**Verified output** — Run 1 prints `created 2 cities + 1 Road edge`; Run 2 prints
`found 2 existing cities (persistence!)`. **Persistence works with plain `jac run`**:
state is written to `./.jac/data/` (SQLite) in the cwd. `jac serve` does not exist;
the server command is `jac start` (see test 2), and it shares the same `./.jac/data/`.

Reset state: `rm -rf .jac/` (or `jac clean --all` if you have a jac.toml).

## Smoke test 2 — REST server (`jac start`)

Files in one dir. **`jac start` REQUIRES a `jac.toml` in the cwd** — minimal one works:

```toml
[project]
name = "apismoke"
version = "0.1.0"
```

`api.jac` (ran successfully):

```jac
node Task {
    has title: str;
    has done: bool = False;
}

walker:pub add_task {
    has title: str;

    can create with Root entry {
        task = (root ++> Task(title=self.title))[0] as Task;
        report {"id": jid(task), "title": task.title, "done": task.done};
    }
}

walker:pub list_tasks {
    has reports: list[dict] = [];

    can collect with Root entry {
        for t in [root -->[?:Task]] {
            report {"title": t.title, "done": t.done};
        }
    }
}
```

Start (API only, no frontend bundling):

```bash
jac start api.jac --no_client -p 8722    # underscore flag! --no-client is INVALID
```

Takes ~10 s to be ready; prints `🚀 Server ready (no client)`.

### URL pattern (verified by curl)

- **`POST /walker/<walker_name>`** — JSON body keys map 1:1 onto the walker's `has`
  fields. Walker spawns at the caller's root, runs, response = its `report` values.
- `POST /function/<name>` also exists for `def:pub` functions (body = parameters).
- `walker:pub` = anonymous access (runs on shared guest graph). Plain `walker` /
  `walker:priv` = requires JWT (register/login endpoints — see `jac guide jac-sv-auth`).

```bash
curl -X POST http://localhost:8722/walker/add_task \
  -H "Content-Type: application/json" -d '{"title": "Write docs"}'
```

**Verified response envelope** (every endpoint wraps like this):

```json
{"ok": true, "type": "response",
 "data": {"result": {"_jac_type": "add_task", "_jac_id": "...", "_jac_archetype": "walker",
                     "reports": [{"id": "...", "title": "Write docs", "done": false}],
                     "title": "Write docs"},
          "reports": [{"id": "...", "title": "Write docs", "done": false}]},
 "error": null, "meta": {"extra": {"http_status": 200}}}
```

Read `data.reports` (list, one item per `report` statement). Ignore `_jac_*` keys.
Errors flip `ok:false` and fill `error: {code, message}`.

### CORS (verified by OPTIONS preflight)

Single-process `jac start` **hardwires `Access-Control-Allow-Origin: *`** — nothing to
configure, browser frontends on any port just work. (Not lockable in single-process
mode; only the k8s microservice gateway has CORS config.)

### Server persistence (verified)

Added a task, killed the server, restarted — `list_tasks` still returned it. Data lives
in `./.jac/data/*.db` (SQLite) next to the jac.toml.

### Custom routes

`@restspec(method=HTTPMethod.GET, path="/users/{user_id}")` on a walker/def gives custom
method + path; GET params become query/path params. `import from http { HTTPMethod }`.
See `jac guide jac-sv-endpoints`.

## Smoke test 3 — byllm typed extraction (Anthropic)

`extract.jac` (ran successfully — printed `name=Maria Chen city=Oakland`, asserts passed):

```jac
import from byllm.lib { Model }

glob llm: Model = Model(model_name="claude-sonnet-4-6");

obj Contact {
    has name: str;
    has city: str;
}
sem Contact.name = "The person's full name as mentioned in the text.";
sem Contact.city = "The city where the person lives.";

def extract(text: str) -> Contact by llm();
sem extract = "Extract the contact info from the given text.";
sem extract.text = "Free-form text mentioning a person and where they live.";

with entry {
    c = extract("Yesterday I had coffee with Maria Chen, who just moved to Oakland.");
    print(f"name={c.name} city={c.city}");
}
```

Run:

```bash
export ANTHROPIC_API_KEY=$(cat ~/Desktop/Keys/anthropic_key.txt)
jac run extract.jac
```

- **Model name syntax: plain `claude-sonnet-4-6`** (no `anthropic/` prefix needed —
  byllm routes via litellm and this exact name worked). OpenAI: `gpt-4o`. Ollama:
  `ollama/llama3`. Auth comes from `ANTHROPIC_API_KEY` env var.
- Return value is a real typed instance (`<class '__main__.Contact'>`), dot access works.
- Typed (non-str) returns auto-retry malformed LLM output up to 3 times.
- Use `sem` statements for prompts/descriptions, NOT docstrings.
- `MockLLM` (also in `byllm.lib`) runs tests without API keys.

---

## Gotchas (all hit or verified on this machine)

1. **DO NOT `pip install jac-cloud`.** jac-cloud 0.2.11 force-downgrades jaclang to
   0.9.0, which then crashes on import (`ModuleNotFoundError: No module named
   'byllm.plugin'`) because byllm 0.6.19 needs modern jaclang. jac-cloud is the
   legacy serving stack; in 0.16.x serving is built into jaclang as `jac start`.
   If someone breaks the env: `pip uninstall -y jac-cloud && pip install -U jaclang==0.16.7`.
2. **There is no `jac serve`.** The command is `jac start`. Flags use underscores:
   `--no_client`, not `--no-client`.
3. **`jac start` errors without a `jac.toml`** in the cwd (minimal `[project]` block ok).
4. **`++>` returns a LIST, not the node.** `(root ++> Task(...))[0]` — indexing first
   is mandatory; `new.title` right after connect is the classic bug.
5. **`report` also echoes each value to stdout** (why output looks doubled in `jac run`).
6. Walker report channel must be typed AND defaulted: `has reports: list[T] = [];` —
   omitting `= []` makes it a required spawn/API parameter and every call fails.
7. Typed edge creation is `a +>:Road(km=13):+> b` (plus signs both sides); typed
   traversal uses SINGLE arrows `[n ->:Road:->]`; `[n -->:Road:-->]` is a parse error.
8. Re-running `jac run` in the same dir REUSES `./.jac/` graph state — guard node
   creation with an existence check (as in hello.jac) or your nodes duplicate.
   Changing node schemas between runs ⇒ `Invalid anchor id` / `NodeAnchor ... not a
   valid reference` errors — fix with `rm -rf .jac/` (script dir) or `rm -rf .jac/data/`
   (server) and restart.
9. In walker abilities: `self` = walker, `here` = current node. In node abilities:
   `self` = node, `visitor` = walker. Mixing these is the #1 bug per the official guide.
10. Entry points are `can foo with NodeType entry { ... }` — `can` not `def`, and the
    `with ... entry` clause is mandatory.
11. `/docs`, `/openapi.json`, `/graph` returned **404** on this build in
    `--no_client` single-file mode — don't promise Swagger UI in the demo; the
    `POST /walker/<name>` endpoints themselves work fine.
12. Official web docs at docs.jaseci.org recommend a standalone `jac` binary
    (`curl ... install.sh | bash`). We deliberately used pip-in-conda instead — same
    0.16.x stack, and Python interop (`import` of pip packages) is guaranteed to use
    the jachacks env. Do not mix the two installs (a binary `jac` earlier in PATH would
    shadow the conda one).

## Scratch tests live at

`/Users/zelin/.claude/jobs/6aa83096/tmp/jacsmoke/{hellograph,api,byllm}` — all runnable as-is.
