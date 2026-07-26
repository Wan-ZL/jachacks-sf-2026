# JacHammer (jachammer.ai) recon — 2026-07-26

## TL;DR
JacHammer is **Jaseci Labs' browser-based vibe-coding IDE for Jac** ("Build Jac apps in your browser. No install needed" — its own meta description). It is the hosted product name for **jacBuilder**. It is BOTH:
- a build-IN-it IDE (AI chat build flow, file editor, live preview, versioning), AND
- capable of taking an **existing app**: project creation accepts a **jacpack** (`jacpack_url` / `jacpack_content_base64`) and there are **git/GitHub import-export walkers** (`git_ops`, `github_ops` with GitHub App `installation_id`, `repo_name`).

It has a real deploy path: `deploy_ops` walker (`action=deploy`, `deploy_mode=permanent`, `subdomain`/`domain`, cert-manager email) → app gets a stable URL on the platform (jac-scale HTTP scale-to-zero: a stable URL wakes a zero-replica k8s Deployment).

There is **no public documentation** for JacHammer itself (docs.jaseci.org never mentions it; homepage is a JS app with no marketing copy). Everything below was reverse-engineered from its live OpenAPI spec — confirm the intended judging flow with an on-site mentor.

## Why it matters today (JacHacks SF)
From jachacks.org/sf-guide:
- "Deployed on jachammer.ai" is on the **submission checklist** and "can affect your judging."
- **Best JacHammer special award: $400** — "Use jachammer.ai to build and ship a working application." (The $500 award is "AI for Defense"; must use Jac. The prize amounts may be per-guide — recheck the guide.)
- Other checklist items: public GitHub repo, code ≥40% Jac, working 4-minute demo.

## Platform facts (from https://jachammer.ai/openapi.json — "Jac Microservice Gateway")
Two services: `builder_sv` (the IDE platform) and `jac_coder_sv` (the AI coding agent: `run_turn`, `stream_events`, sessions, clarifications).

### Auth / account
- Self-serve **registration API**: `POST /api/builder_sv/user/register` with `identities` (email or username) + `credential` (password). Email verification endpoints exist (`send-verification`, `verify-identity`) — may be required.
- SSO endpoints exist incl. **Firebase token** (`/sso/firebase/token`) — the web UI likely offers Google sign-in.
- **API keys**: `POST /api/builder_sv/api-key/create`, list, delete → headless automation is possible after login.

### Key walkers (all `POST /api/builder_sv/walker/<name>`, JWT/API-key auth)
- `project_ops` — action default `list`; create supports `template_id` (default "empty"), `jacpack_url`, `jacpack_content_base64` → **import an existing app as a .jacpack**.
- `ide_file_ops` — file CRUD in a project.
- `git_ops`, `github_ops` — GitHub App OAuth flow (code/state/installation_id), repo name/private → push/pull project to GitHub (satisfies the "public repo" checklist item too).
- `preview_control`, `preview_screenshot`, `preview_auth_ops` — live preview sandbox.
- `deploy_ops` — `action=deploy`, `project_id`, `deploy_mode` (default `permanent`), `subdomain`, `domain`, `cert_manager_email`; plus `deploy_monitoring`.
- `version_ops`, `template_ops`, `ai_chat`, `env_ops` (secrets/env vars), `billing_ops`/`stripe_webhook` (there is billing — hackathon accounts presumably free-tier).

### Jacpack (the import format)
From jaseci-labs/jacpacks README: a `.jacpack` is a self-contained project archive (source + config + setup hooks). Local CLI usage: `jac create my-app --use <url>.jacpack`, `jac install`, `jac start main.jac`. Docs don't show an official "jac pack" export command — the .jacpack format may need to be assembled by hand or the project rebuilt inside JacHammer; ask a mentor.

## Answers to the key questions
1. **Vibe-coding IDE or push-existing?** Primarily an in-browser AI-builder IDE, but existing code can enter via jacpack upload or GitHub import (`github_ops`). Worst case: create empty project + push files through `ide_file_ops`.
2. **Account?** Yes — email/username+password self-registration (or Google/Firebase SSO in the UI). No sign of hackathon-specific gating.
3. **CLI?** No JacHammer CLI. The `jac` CLI deploys to your own k8s (`jac start --scale`), not to jachammer.ai. Automation path is the REST/walker API with an API key.
4. **Human vs automatable?** Human: create the account in the browser (email verify / SSO / possible captcha), authorize the GitHub App if importing from a repo, eyeball the deployed URL. Automatable after that: API-key creation, project create (jacpack base64), file upload, `deploy_ops` deploy, screenshot via `preview_screenshot`.

## Recommended flow for the team
1. One teammate registers at https://jachammer.ai in a browser now (early — before wifi/queue crunch).
2. Build locally with normal `jac` tooling; keep the repo GitHub-public (checklist).
3. To deploy: import the project into JacHammer (GitHub import in the UI is likely the easiest), then hit Deploy in the UI (backed by `deploy_ops`, `deploy_mode=permanent`, pick a subdomain).
4. If the UI import fights back, fall back to API: login → create API key → `project_ops` create with `jacpack_content_base64` (or empty + `ide_file_ops`) → `deploy_ops`.
5. Confirm with an on-site mentor: intended import path, whether the AI-built-in-JacHammer flow is required for the Best JacHammer award (its wording is "build and ship" ON jachammer.ai), and any account/quota gotchas.

## Sources
- https://jachammer.ai (meta: "web-based IDE for the Jac language. Build, preview, and version your projects in the browser", author Jaseci Labs)
- https://jachammer.ai/openapi.json (live gateway spec, fetched 2026-07-26)
- https://jachacks.org/sf-guide (judging + prize)
- https://github.com/jaseci-labs/jacpacks (jacpack format)
- https://docs.jaseci.org/reference/plugins/jac-scale/ and /reference/cli/ (no jachammer mention; self-hosted deploy only)
