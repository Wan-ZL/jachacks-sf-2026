# Jac Language Cheatsheet — for builder agents (graph + walker apps)

Recon date: 2026-07-26. Sources (verified against the live repo, cloned at HEAD):
- `jaseci-labs/jac` repo: `docs/docs/reference/language/syntax-cheatsheet.md` (official "Learn Jac in Y Minutes"; live at https://docs.jaseci.org/reference/language/syntax-cheatsheet/ — confirmed 200)
- Real example apps in-repo: `jac/examples/mini_todo/main.jac`, `jac/examples/todo_app/main.jac`, `jac/examples/littleX/` (social network — best real-world graph+walker code)
- `docs/docs/reference/language/walker-responses.md`, `docs/docs/reference/persistence.md`, repo `README.md`, repo `SKILL.md` (agent-oriented setup doc at repo root — read it, it's written for us)

NOTE on old docs URLs: the `docs.jaseci.org/jac_book/chapter_NN/` pages are the LEGACY doc structure; the current docs tree in the repo has no `jac_book/` — use `reference/language/*` and `tutorials/language/{basics,osp}` instead. Old chapter pages may still be served but can be stale [UNVERIFIED which are stale].

Big picture: Jac ≈ Python semantics with braces + semicolons, compiled to Python bytecode. Adds graph-native archetypes (`node`/`edge`/`walker`), automatic persistence of everything reachable from `root`, walkers-as-REST-endpoints, and (optionally) React-compiled client code in the same file. One binary does everything.

---

## 0. Install / run / serve

```bash
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash   # installs ~/.local/bin/jac
jac --version
jac run main.jac        # run a program
jac start main.jac      # serve: REST API + auth + Swagger + frontend (if JSX present)
jac create <name>       # scaffold project
jac dev                 # hot-reload dev loop
jac check <file>        # type-check   |  jac fmt <file>  |  jac test <path>
jac guide               # curated docs in terminal
claude mcp add jac -- jac mcp    # optional: Jac MCP server (validate/format/docs)
```
(Source: repo `SKILL.md`, `README.md`.)

Persistence is automatic: **whatever is reachable from `root` persists** between `jac run` invocations (local store `.jac/data/<app>.db`) and across server requests. Each served user gets their own `root`. (Source: `reference/persistence.md`.)

Project config lives in `jac.toml` (`[project] entry-point = "main.jac"`, `[dependencies]` = PyPI, `[dependencies.npm]` = npm, `[byllm.model]`, `[serve]`). Add deps with `jac install <pkg>`.

---

## 1. Basics: entry, variables, functions, control flow

```jac
with entry {                      # program entry point; multiple allowed, run in order
    print("Hello, world!");
}
with entry:__main__ { print("Only when run directly"); }

with entry {
    x: int = 42;                  # typed
    name = "Jac";                 # inferred
    maybe: str | None = None;     # union
    msg = f"Value: {x}";          # f-strings work
}

def greet(name: str) -> str {     # braces + semicolons; type annotations mandatory
    return f"Hello, {name}!";
}

def:pub health_check() -> dict {  # :pub function => REST endpoint under `jac start`
    return {"status": "ok"};
}

if x < 5 { print("low"); } elif x < 10 { print("medium"); } else { print("high"); }
for item in ["a", "b", "c"] { print(item); }
for i = 0 while i < 10 with i += 2 { print(i); }   # C-style loop
while n > 0 { n -= 1; }
label = "high" if x > 5 else "low";                 # ternary
try { r = 10 // 0; } except ZeroDivisionError as e { print(e); } finally { print("done"); }
```

Lists/dicts/strings are Python's, with `;`:

```jac
fruits = ["apple", "banana", "cherry"];
print(fruits[0]); print(fruits[1:3]); print(fruits[-1]);
person = {"name": "Alice", "age": 25};
squares = [i ** 2 for i in range(5)];
evens = [i for i in range(10) if i % 2 == 0];
name_map = {name: len(name) for name in ["alice", "bob"]};
s = "hello".upper(); parts = "a,b".split(","); joined = ",".join(["a","b"]);
```

Lambdas are parenthesized-params + braced-body (last expression is implicit return):

```jac
add = lambda (x: int, y: int) { x + y; };
handler = lambda -> None { print("clicked"); };
tweets.sort(key=lambda (t: Tweet) { t.created_at; }, reverse=True);   # littleX, verbatim
```

## 2. Imports & globals

```jac
import os;
import datetime as dt;
import from math { sqrt, pi, log as logarithm }
import from .sibling { helper_func }               # relative
import from dateutil.parser { parse }              # PyPI (mini_todo, verbatim)
import from "canvas-confetti" { default as confetti }   # npm string import (mini_todo)
include random;                                    # merge namespace

glob MAX_SIZE: int = 100;                          # module-level global
glob greeting: str = "Hello";
def use_global() { greeting = "Hola"; }            # bare assignment rebinds the glob
```

## 3. obj / class / enums

```jac
obj Pet {                          # like a Python dataclass: auto __init__/__eq__/__repr__
    has name: str = "Unnamed",
        age: int = 0;              # note: one `has` can declare several fields, comma-separated
    def bark() { print(f"{self.name} says Woof!"); }
    static def make(name: str) -> Pet { return Pet(name=name); }
}
obj Puppy(Pet) { has parent_name: str = "Unknown"; }   # inheritance = parens

obj Example {
    has computed: int postinit;    # deferred init
    def postinit() { self.computed = 2; }
}
# ALL instance fields must be declared with `has`; dynamic attr assignment is an anti-pattern.

enum Category: int { WORK, PERSONAL, SHOPPING, HEALTH, OTHER }   # mini_todo, verbatim
enum Color { RED = "red", GREEN = "green", BLUE = "blue" }
```

Decl/impl split (bodies can live in a `.impl.jac` file):

```jac
obj Calculator { has value: int = 0; def add(n: int) -> int; }
impl Calculator.add(n: int) -> int { self.value += n; return self.value; }
```

Tests:

```jac
test "walker test" {
    root ++> Person(name="Alice", age=30);
    result = root spawn Greeter();
    assert len(result.reports) > 0;
}
```

---

## 4. Nodes & edges (the data model)

```jac
node Todo {                        # todo_app/main.jac, verbatim
    has text: str,
        done: bool = False;
}

edge Friendship { has since: int = 0; }    # edges carry fields too
edge Follow {}                             # empty edge classes are fine (littleX)
edge Post {}

node Employee(Person) { has department: str; }   # node inheritance

node SecureRoom {                  # nodes can have abilities triggered by walkers
    has name: str, clearance: int = 0;
    can on_enter with Visitor entry { print(f"Welcome to {self.name}"); }
    can on_exit  with Visitor exit  { print(f"Leaving {self.name}"); }
    # inside node abilities: `self` = this node, `visitor` = the walker
}
```

## 5. Creating nodes/edges — connect operators (EXACT)

```jac
root ++> a;                                  # untyped edge root -> a
a ++> b;                                     # a -> b
c <++ a;                                     # a -> c (backward form)
a <++> b;                                    # bidirectional
root ++> a ++> b ++> c;                      # chained

a +>: Friendship(since=2020) :+> b;          # typed edge with constructor
a +>: Friendship : since=2018 :+> b;         # typed edge, field-assignment form
me +>:Follow():+> here;                      # littleX real usage (no spaces variant)
new = here +>:Post():+> Tweet(content=self.content, created_at=_now());  # create+connect+capture

new_todo = here ++> Todo(text=self.text);    # ++> returns the target; capture it (todo_app)

a del --> b;                                 # delete edge between a and b
del c;                                       # delete node
edges = [edge me->:Follow:->here]; if edges { del edges[0]; }   # delete typed edge (littleX)
```

## 6. Traversal & filtering (EXACT syntax)

```jac
[root -->]                          # all nodes via outgoing edges
[root <--]                          # incoming
[root <-->]                         # both directions
[-->]                               # from current node (inside ability) / from `here`

[root ->:Friendship:->]             # filter by EDGE type
[root ->:Friendship:since > 2018:->]  # filter by edge field value
[root -->][?:Person]                # filter by NODE type
[root -->][?age >= 18]              # filter by node attribute
[root -->][?:Person, age > 25]      # type + attribute combined
[root-->][?:Todo]                   # real usage, mini_todo (spaces optional)
[-->[?:Profile]]                    # nested form: outgoing, only Profile nodes (littleX — very common)

[edge root -->]                     # the EDGE objects themselves (not target nodes)
[edge me->:Member:->here]           # typed edge objects between two known nodes (littleX)

[root ->:Friendship:-> ->:Friendship:->]        # multi-hop chain
[me->:Follow:->[?:Profile]-->[?:Tweet]]         # littleX: my follows' tweets, verbatim
[self<-:Follow:<-[?:Profile]]                   # incoming typed edges (followers), verbatim

[root -->][?age >= 18](=verified=True);         # assign-comprehension: bulk update in place
```

Careful: edge-type filter inside traversal is `->:Type:->` (arrows OUTSIDE colons); node-type filter is a separate `[?:Type]` suffix or nested `[-->[?:Type]]`. There is no `[-->:MyEdge:-->]` — it's `[->:MyEdge:->]`.

---

## 7. Walkers (the compute)

```jac
walker Greeter {                                # syntax-cheatsheet, verbatim
    has greeting: str = "Hello";

    can greet_root with Root entry {            # ability fires when walker enters a Root node
        print(f"{self.greeting} from root!");
        visit [-->];                            # enqueue connected nodes
    }

    can greet_person with Person entry {        # fires on every Person node visited
        # `here` = current node, `self` = the walker
        print(f"{self.greeting}, {here.name}!");
        report here.name;                       # push a value onto the response
        visit [-->];
    }
}

with entry {
    root ++> Person(name="Alice", age=25);
    result = root spawn Greeter();              # spawn walker at root
    print(result.reports);                      # ["Alice"] — list of reported values
}
```

Spawn variants: `root spawn w;` / `root spawn Greeter(greeting="Hey");` / `w spawn root;` (reversed). Walker fields (`has`) are constructor params — and become the JSON request body when served.

Control flow inside walkers:

```jac
disengage;                          # stop traversal immediately (like return from the walk)
visit [-->] else { print("dead end"); }   # else runs if visit enqueued NOTHING
visit : 0 : [-->];                  # first outgoing node only
visit here;                         # re-visit current node
skip;                               # early-exit current ability (like bare return)
can done with Root exit { report self.results; }   # exit ability: fires when walk ends
can with entry { ... }              # anonymous ability (no name needed)
```

Find-or-create — the canonical `visit ... else` idiom (littleX, verbatim):

```jac
walker setup_profile {
    has username: str = "", bio: str = "",
        reports: list[ProfileBundle] = [];
    can run with Root entry {
        visit [-->[?:Profile]] else {
            fresh = here ++> Profile(created_at=_now());
            visit fresh;
        }
    }
    can apply with Profile entry {
        if self.username { here.username = self.username; }
        report here.to_bundle();
    }
}
```

Accumulator pattern — gather during traversal, report once at exit (littleX, verbatim):

```jac
walker:pub get_all_profiles {
    has results: list[Profile] = [],
        reports: list[list[Profile]] = [];      # typed report channel (recommended, see below)
    can run with Root entry {
        for r in allroots() { visit [r-->[?:Profile]]; }   # allroots() = every user's root
    }
    can gather with Profile entry { self.results.append(here); }
    can deliver with Root exit { report self.results; }
}
```

Walker inheritance for shared navigation (littleX): `walker follow_user(find_profile) { can act with Profile entry {...} }` — base walker resolves the target, subclasses react on entry.

### report / reports — get data OUT

- Each `report X;` appends X to the response's `.reports` list. `result = root spawn W(); result.reports[0]`.
- **Declare `has reports: list[T] = [];` on every walker** — it types the report channel end-to-end (`jac check` verifies both sides). Reporting a list once makes it `list[list[T]]`. The `= []` default is required. (Source: `reference/language/walker-responses.md`.)
- `report` also prints each value to stdout as a side effect.
- Useful builtins (no import): `jid(node)` — stable unique id (use as JSX key / API id); `jobj(id)` — resolve id back to the object; `save(n)`, `commit()`, `printgraph(root)` (debug), `allroots()`, `grant(node, level=ConnectPerm|WritePerm)` (multi-user perms, littleX).

---

## 8. REST API: `:pub` + `jac start`

```jac
walker:pub create_todo {            # todo_app, verbatim — becomes POST /walker/create_todo
    has text: str;                  # request body: {"text": "..."}
    can create with Root entry {
        new_todo = here ++> Todo(text=self.text);
        report new_todo;            # response body (in .reports)
    }
}
```

- `walker:pub` / `def:pub` = public endpoint, no auth. `walker:priv` = requires per-user token (each user gets own root). Anything not `:pub` requires auth.
- `jac start main.jac` serves it with Swagger docs and auth built in.
- Custom method/path: `@restspec(method=HTTPMethod.GET, path="/items/{item_id}")` on a `walker:pub` (needs `import from http { HTTPMethod }`).
- Client auth helpers: `import from "@jac/runtime" { jacLogin, jacSignup, jacLogout, jacIsLoggedIn }` (littleX, verbatim).

---

## 9. Frontend in Jac (client codespace) — WORKS, use it

Maturity: **real but young.** This is the current-gen system (compiles to React via vite; npm deps in `jac.toml [dependencies.npm]`). The in-repo examples (mini_todo ~90 lines full-stack, todo_app, littleX with a full component library `components/ui/*.jac`) all use it and are actively maintained. For a hackathon: the happy path (one file, `def:pub app -> JsxElement`, `jac start`) is well-trodden; deep npm interop beyond what examples show is [UNVERIFIED]. `.cl.jac` files exist mostly inside the runtime itself; app code usually relies on **inference** instead.

Codespace rules (from official cheatsheet):
- Code is **server by default**. A function returning JSX or an npm string-import is **inferred client** — no marker needed (mini_todo/todo_app are markerless single files).
- Explicit overrides: `cl { ... }` block, `sv { ... }`, or single-statement `cl import from react { useState }` / `sv import from ...main { MyWalker }` (import server walkers into client code).
- File-extension pins: `.cl.jac` = client-only file, `.sv.jac` = server-only, `.impl.jac` = method bodies, `.test.jac` = tests, `<Comp>.style.css` = auto-scoped CSS.
- `walker`/`def:pub` always stay server; client calls to them become RPC automatically (`root spawn MyWalker()` in client code = HTTP call).

Minimal full-stack component (mini_todo/main.jac, verbatim, trimmed):

```jac
def:pub app -> JsxElement {
    has todos: list[Todo] = [],        # `has` in a client component = React useState
        text: str = "";

    async can with entry {             # mount effect (useEffect on mount)
        todos = await get_todos();     # calling a server def:pub — auto RPC
    }

    async def add {
        if text.strip() {
            todo = await add_todo(text.strip());
            todos = todos + [todo];    # reassignment triggers re-render (don't mutate in place)
            text = "";
        }
    }

    return
        <div>
            <input value={text}
                onChange={lambda (e: ChangeEvent) { text = e.target.value; }}
                onKeyPress={lambda (e: KeyboardEvent) { if e.key == "Enter" { add(); }}} />
            <button onClick={lambda { add(); }}>Add</button>
            {for t in todos {
                <p key={jid(t)}>[{t.priority}]{t.title}</p>
            }}
        </div>;
}
```

Spawning a server walker from the client (todo_app, verbatim):

```jac
async can with entry {
    result = root spawn read_todos();
    todos = result.reports;
}
# note todo_app reads response.reports[0][0] after create_todo — reported `here ++> Todo(...)`
# comes back as a 1-element list; prefer capturing the node and reporting it directly.
```

JSX notes: `className` not `class`; `style={{"color": "red"}}` (dict); `{expression}` slots; `{for x in xs { <li/> }}` and `{if cond { <p/> }}` statement slots; `key={jid(node)}`; effects: `async can with entry {}` (mount), `can with [dep] entry {}` (dep change), `can with exit {}` (cleanup). File-based routing under `pages/` (`pages/index.jac` → `/`, `pages/users/[id].jac` → `/users/:id`) returning `JsxPage` — documented but not used by the small examples [UNVERIFIED in practice].

---

## 10. AI bonus (one-liner LLM calls)

```jac
enum Category: int { WORK, PERSONAL, SHOPPING, HEALTH, OTHER }
def categorize(title: str) -> Category by llm();     # mini_todo, verbatim — return type = output schema
sem categorize.title = "The todo item text";          # sem strings feed the prompt
def answer(q: str) -> str by llm(tools=[get_weather]);  # ReAct tool loop
```
Needs `jac install byllm` + `[byllm.model] default_model = "..."` in `jac.toml`.

---

## 11. Special variables & gotchas

| var | meaning |
|---|---|
| `self` | current walker (in walker abilities) / current object |
| `here` | current node (in walker abilities) |
| `visitor` | the visiting walker (in node/edge abilities) |
| `root` | the graph root (per-user when served); `Root` is its type in `with Root entry` |

Gotchas for Python-brained agents:
1. Every statement ends with `;`, every block uses `{}` — including `if`/`for` one-liners.
2. Type annotations are mandatory on `def` params/returns and `has` fields.
3. Fields: `has a: str, b: int = 0;` — comma-continues, one semicolon at the end.
4. Ability trigger type is the NODE type the walker lands on: `can x with Person entry`, root is `with Root entry` (capital R).
5. Edge filter is `->:Type:->`, node filter is `[?:Type]` / `[?attr > 5]` — don't mix them up.
6. `visit` ENQUEUES; ability keeps executing after it. `disengage` stops the whole walk.
7. `report`, not `return`, gets data out of walkers; read `.reports` on the spawn result.
8. No manual DB: attach to `root` (`root ++> node`) and it persists. Detached nodes don't.
9. Lambda: `lambda (x: int) { x + 1; }` — parens + braces, not Python's `lambda x:`.
10. Docstrings go BEFORE the declaration. Comments `#` and `#* ... *#`.
11. Client state updates by REASSIGNMENT (`todos = todos + [t]`), like React setState.
12. Run `jac check` before `jac run` — the type checker catches most of the above.
