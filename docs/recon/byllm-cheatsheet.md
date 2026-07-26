# byLLM Cheatsheet (Jac / Jaseci) — for builder agents

Recon date: 2026-07-26. Sources: jaseci-labs/jaseci monorepo @ main (`jac/jaclang/byllm/`, incl. the official `jac-by-llm` CLI skill doc and `docs/docs/reference/plugins/byllm.md`), docs.jaseci.org tutorial + reference pages. Everything without a tag is confirmed from source/docs; unconfirmed items marked [UNVERIFIED].

---

## 0. Version gotcha — TWO import styles exist (check yours FIRST)

byLLM was **folded into jaclang core** (breaking change, ~2026). The old standalone `byllm` pip package (latest 0.6.19) still exists for older jaclang.

| Setup | Install | Import |
|---|---|---|
| **Current** (jac binary / monorepo, recommended) | `jac install byllm` | `import from jaclang.byllm.lib { Model }` |
| **Legacy** (pip `byllm` + older jaclang) | `pip install byllm` | `import from byllm { Model }` or `import from byllm.lib { Model }` |

Quick detect: if `import from byllm { Model }` fails with module-not-found, switch to `jaclang.byllm.lib`. All syntax below is the **current** style; for legacy just swap the import path.

```bash
# current-style install (one-line jac installer, then plugin)
curl -fsSL https://raw.githubusercontent.com/jaseci-labs/jaseci/main/scripts/install.sh | bash
jac install byllm
```

---

## 1. Hello world — `by llm()`

```jac
def translate_to(language: str, phrase: str) -> str by llm();

with entry {
    print(translate_to(language="Welsh", phrase="Hello world"));
}
```

- `llm` is an **ambient builtin** — works with NO imports and NO `glob llm` declaration; it uses the project default model from `jac.toml` (default `gpt-4o-mini`).
- `by llm(...)` **replaces** the function body. Never write both `{ body }` and `by llm(...)`.
- Inline expressions (`x = "prompt" by llm;`) DO NOT exist — passes `jac check`, raises `NotImplementedError` at runtime. Always declare a function.

## 2. Choosing a model — `Model` + Anthropic Claude

```jac
import from jaclang.byllm.lib { Model }

glob llm = Model(model_name="claude-sonnet-4-6");
```

Model names are **LiteLLM identifiers**:

| Provider | `model_name` | Auth (env var, takes precedence over `api_key` arg/toml) |
|---|---|---|
| Anthropic | `claude-sonnet-4-6` (bare `claude-*` works; `anthropic/claude-sonnet-4-6` also seen in official docs/examples) | `ANTHROPIC_API_KEY="sk-ant-..."` |
| OpenAI | `gpt-4o`, `gpt-4o-mini` | `OPENAI_API_KEY` |
| Google | `gemini/gemini-2.0-flash` | `GOOGLE_API_KEY` |
| Ollama (local) | `ollama/llama3:70b` | none (daemon) |
| In-process local | `local:gemma-4-e4b` | none; `jac install 'byllm[local]'` + `jac model pull ...` |
| HuggingFace | `huggingface/meta-llama/Llama-3.3-70B-Instruct` | `HUGGINGFACE_API_KEY` |

Full provider list = LiteLLM's: https://docs.litellm.ai/docs/providers

`Model` constructor:

```jac
glob llm = Model(
    model_name="claude-sonnet-4-6",   # required
    api_key="sk-ant-...",             # optional; ENV VAR OVERRIDES THIS
    config={                          # optional advanced
        "api_base": "https://your-endpoint/v1/chat/completions",
        "http_client": True,          # raw HTTP mode for custom endpoints
        # "proxy": True, "ca_bundle": ..., "verbose": False
    },
    # call_params={...}  # default per-call params on this model [UNVERIFIED exact merge order vs by llm() args]
);
```

- The glob needn't be named `llm`: `glob fast = Model(model_name="gpt-4o-mini"); def label(t: str) -> str by fast();`
- Multiple models per file are fine (one glob per model).
- `BYLLM_DEFAULT_MODEL=...` env var overrides project default for one shell.

Project-wide config (`jac.toml`):

```toml
[plugins.byllm]            # declares the plugin (then `jac install`)

[byllm]
system_prompt = "You are a helpful assistant..."

[byllm.model]
default_model = "claude-sonnet-4-6"

[byllm.call_params]
temperature = 0.7
```

## 3. Typed returns — obj / enum / list / optional

The LLM's output is validated against the declared return type. Malformed output auto-retries with corrective feedback.

```jac
obj Person {
    has name: str;
    has birth_year: int;
    has description: str;
}

def extract_person(text: str) -> Person by llm();
def extract_tasks(notes: str) -> list[Task] by llm();   # lists & nested objs work
def get_count(text: str) -> int by llm();
def maybe_date(text: str) -> str | None by llm();       # -> T | None lets LLM say "not found"

enum Priority { LOW, MEDIUM, HIGH }
def classify(ticket: str) -> Priority by llm();          # constrained to enum members
```

- LLM return types are `obj`s, **never `node`s** — fill an `obj`, then copy fields into a `node` to persist.

## 4. `sem` semstrings — the prompt IS your annotations

`sem` (not docstrings!) is what the LLM sees. Attach to functions, params, obj fields, enum members:

```jac
obj Summary {
    has title: str;
    has bullets: list[str];
}
sem Summary         = "Structured summary of a text.";
sem Summary.title   = "A short, specific title capturing the text's topic.";
sem Summary.bullets = "Key points - each a single concise sentence.";

def summarize(text: str) -> Summary by llm(temperature=0.2);
sem summarize      = "Extract a structured Summary from the given text.";
sem summarize.text = "The text to summarize.";

sem Priority.HIGH = "Urgent: requires immediate attention.";  # enum members too
```

- Docstrings are for humans only (and triple-quoted strings inside a `by llm` body fail with W0060 in current jac). Note: older docs/README show docstrings feeding the prompt — in the current version use `sem` exclusively.

## 5. Agentic calls — `tools=[...]` (ReAct)

Passing `tools=[...]` automatically turns on a ReAct tool-calling loop. Tools are **function references, not strings**; give each tool (and its args) `sem`.

```jac
def word_count(text: str) -> int {
    return len(text.split());
}
sem word_count      = "Count whitespace-separated words in text.";
sem word_count.text = "The text to count words in.";

def analyze(question: str) -> str by llm(
    tools=[word_count],
    temperature=0.2,
    max_react_iterations=5
);
```

- `method="ReAct"` is **deprecated and never worked** — don't use it; just pass `tools`.
- `parallelize=True` runs multiple tool calls concurrently.
- `on_iteration=callback` fires between ReAct iterations; receives `IterationContext`, returns `IterationAction` (`CONTINUE` / `ABORT` / `ABORT_WITH_SUMMARY`) — stop buttons, token budgets, doom-loop detection.
- MCP tools exist: `import from jaclang.byllm.lib { McpClient, McpTool }` (needs `llm.mcp` capability). [UNVERIFIED exact usage — see `jaclang/byllm/mcp.jac`]

## 6. Method-style `by llm` on obj methods (incl. bound-method tools)

```jac
obj Account {
    has owner: str;
    has balance: float = 0.0;

    def deposit(amount: float) -> float {
        self.balance += amount; return self.balance;
    }
    def advise(question: str) -> str by llm(tools=[self.deposit]);  # bound methods work as tools
}
```

- **Method-level `by llm` automatically includes the object's `has` fields as context** — no need to pass `self.owner` etc. as arguments.
- Works on walker abilities too (byLLM examples use `by llm()` functions called from walker abilities; a walker's own ability declared `by llm` follows the same method rules [UNVERIFIED — examples call plain `by llm` functions from abilities rather than declaring abilities `by llm`]).

## 7. Extra context — `incl_info`

```jac
def get_recommendation(query: str) -> str by llm(
    incl_info={
        "current_time": datetime.now().isoformat(),
        "location": "NYC",
        "trending": get_trending_topics()
    }
);
```

Dict keys+values are injected into the prompt as additional context — use for dynamic per-call info.

## 8. Multi-turn chat, streaming

```jac
glob history: list[dict] = [];
def chat(message: str) -> str by llm(
    conversation=history,                        # caller-owned list; byLLM appends turns IN PLACE as plain dicts (JSON-serializable)
    system_prompt="You are a terse assistant."   # EXTENDS the base system prompt, never replaces it
);

def stream_story(topic: str) -> str by llm(stream=True);
# stream=True returns a GENERATOR: for token in stream_story("space") { print(token, end=""); }
# str returns only — any other return type raises ConfigurationError.
# stream=True + logging=True yields StreamEvent objects (tool calls, thoughts) instead of raw tokens.
```

## 9. Full `by llm(...)` parameter table

| Param | Type | Default | Notes |
|---|---|---|---|
| `temperature` | float | unset (provider default) | Anthropic max 1.0, OpenAI max 2.0 |
| `max_tokens` | int | 0 = no limit | |
| `max_output_retries` | int | 3 | typed-output re-asks; `0` disables |
| `tools` | list | `[]` | function refs; enables ReAct |
| `max_react_iterations` | int | — | forces final answer after N loops |
| `incl_info` | dict | `{}` | extra prompt context |
| `stream` | bool | False | str-only generator |
| `logging` | bool | False | with stream: StreamEvent objects |
| `conversation` | list | None | in-place multi-turn history |
| `system_prompt` | str | "" | extends jac.toml system prompt |
| `parallelize` | bool | global | concurrent tool calls |
| `on_iteration` | callable | None | ReAct loop control |
| `max_tool_result_length` | int | 500 | truncation in StreamEvent only |
| `compaction_enabled` / `threshold_ratio` / `keep_recent_iterations` / `ctx_window` / `compaction_model` / `on_compaction` | — | 0.80 / 3 / auto | auto-compaction of long histories |

WARNING: `jac check` does NOT validate `by llm` keyword names — a typo'd option surfaces only at runtime.

## 10. Errors & retry behavior

All exceptions inherit `ByLLMError`, importable from `jaclang.byllm.lib`:
`AuthenticationError`, `RateLimitError`, `ModelNotFoundError`, `OutputConversionError`, `ConfigurationError`, `FinishToolError`, `McpError`, plus `CompactionNotEffectiveError`.

- **Typed (non-str) returns auto-retry** malformed/empty output with corrective feedback fed back to the model — up to `max_output_retries` (default 3), then raises `OutputConversionError`. `str` returns are never retried.
- Rejected text: read with `getattr(e, "raw_output", "")` (direct `e.raw_output` fails `jac check` E1030 — dynamic attribute).
- Missing key/model config → `ConfigurationError`; bad key → `AuthenticationError`; 429s → `RateLimitError` (LiteLLM-mapped).

```jac
import from jaclang.byllm.lib { OutputConversionError }
try { result = extract_person(text); }
catch e: OutputConversionError { print(getattr(e, "raw_output", "")); }
```

## 11. Testing without keys — MockLLM

```jac
import from jaclang.byllm.lib { MockLLM }
glob llm = MockLLM(model_name="mockllm", config={"outputs": ["Bonjour", "Salut"]});
def translate(text: str) -> str by llm();
test "in order" { assert translate("Hello") == "Bonjour"; }
```

Outputs consumed sequentially, one per `by` call; for typed returns put pre-built instances in `outputs` (e.g. `Priority.HIGH`, `Person(...)`). Run: `jac test file.jac`.

## 12. Python interface (byLLM from plain Python)

```python
from jaclang.byllm.lib import Model, by   # legacy: from byllm.lib import Model, by

llm = Model(model_name="claude-sonnet-4-6")

@by(llm)
def get_person_info(text: str) -> Person: ...   # body is literal `...`
```

Dataclasses work as typed returns. Same `by(llm)` decorator pattern with Image inputs etc.

## 13. Multimodal (bonus)

```jac
import from jaclang.byllm.lib { Image, Video }
def parse_receipt(img: Image) -> Receipt by llm();   # Image("f.jpg") | URL | bytes | PIL
def describe_clip(v: Video) -> str by llm();          # Video(path="c.mp4", fps=1); needs byllm[video]
```

Needs a vision model (`gpt-4o`, `claude-sonnet-4-6`).

## 14. ModelPool (fallback / load balancing)

```jac
import from jaclang.byllm.lib { ModelPool }
glob llm = ModelPool(models=[
    Model(model_name="gpt-4o-mini"),
    Model(model_name="anthropic/claude-sonnet-4-6"),  # last resort
]);
```
`strategy`, `num_retries`, `timeout` fields exist on ModelPool. [UNVERIFIED strategy values — see reference doc "ModelPool"]

---

## Top 8 pitfalls (memorize)

1. Import path depends on version: `jaclang.byllm.lib` (current) vs `byllm` / `byllm.lib` (legacy pip).
2. No inline `by llm` expressions — functions only.
3. `sem`, not docstrings, is the prompt; docstrings inside `by llm` context can even warn/fail.
4. `tools=[fn_ref]` never `tools=["name"]`; `method="ReAct"` is dead — tools alone enables ReAct.
5. Env var (`ANTHROPIC_API_KEY`) beats `api_key=` argument.
6. `stream=True` only with `-> str`.
7. `by llm` kwargs are unvalidated at check time — typos fail silently until runtime.
8. Return `obj`, not `node`; copy into nodes to persist.

Local clone for deeper digging: `/Users/zelin/.claude/jobs/6aa83096/tmp/jaseci/jac/jaclang/byllm/` (see `README.md`, `examples/agentic_ai/`, `tests/fixtures/`, and the excellent skill doc `jac/jaclang/cli/skills/jac-by-llm.md`).
