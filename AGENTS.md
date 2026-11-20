# AGENTS.md

Self-hosted, parent-monitored AI chat for kids. Open WebUI (UI, per-kid accounts) -> LiteLLM (per-kid keys, budgets, age prompt hook, audit log in Postgres) -> Anthropic API, plus optional OpenRouter models. Optional Ollama + Llama Guard (compose profile `guard`) used only by the alert filter.

## Layout
- `docker-compose.yml`: the stack. Image tags are pinned; upgrade deliberately.
- `litellm/config.yaml`, `litellm/age_prompt.py`: models, audit logging, and the pre-call hook that injects `prompts/*.md` for keys with a `birthdate` in metadata.
- `prompts/`: system prompts by age bracket. Text after the first `---` line is the prompt; `NAME` and `AGE` are filled in by the hook.
- `searxng/settings.yml`: web search backend (compose profile `search`), strict safe search locked. Parents only; kids' web search permission stays off.
- `openwebui/presets.md`: source text for the Workspace > Models presets (helper, modes). Pasted into the UI; edit here first.
- `openwebui/functions/parent_alert.py`: Open WebUI filter, pasted into the admin UI (not mounted). Alerts only, never blocks.
- `Makefile`: front door (`make help`). Every target is a one-line wrapper around `scripts/`; logic goes in the scripts, which must keep working without `make` (Unraid doesn't ship it).
- `scripts/`: operator scripts, run from the host against the running stack. They ask for missing arguments (`scripts/lib.sh`) and stay bash 3.2 compatible (macOS). `doctor.sh` is read-only; add a check there when a new misconfiguration bites.
- `docs/`: operator docs. Keep them in sync with behavior changes. `docs/plans/`: plans for work not started. `TODO.md`: backlog.
- `obsidian-notes/`, if present: the maintainer's private notes (family details, decisions, personal backlog). A git-ignored symlink into an Obsidian vault, so repo-wide search skips it: read it directly, or search that path explicitly. Before writing there, read the vault's `AGENTS.md` (vault root, `~/notes/AGENTS.md`).

## Rules
- Tracked files are meant to be publishable: no family-specific details (kids' names, ages, home hostnames) outside generic examples. Those go in `obsidian-notes/`.
- The safety model is visibility plus conversation, not blocking. Don't add filters that block a kid's message about self-harm; alert instead.
- Controls kids could touch (Open WebUI settings) are convenience; controls that matter live in LiteLLM.
- Open WebUI runs with `ENABLE_PERSISTENT_CONFIG=false`: `docker-compose.yml` and `.env` are the source of truth for its admin settings (connections, features, default permissions), re-applied every start. UI changes revert on restart. Users, groups, group permissions, model presets, and functions live in its database. Change settings in the files, never by telling someone to click.
- Kids get the default permissions; groups can only add (permissions are OR'd). Parents are admins.
- The age prompt hook prepends; it never drops Open WebUI's system content (memories, tool instructions, dates depend on it). Document context stays in the user message (`RAG_SYSTEM_CONTEXT=false`).
- Kid models only from providers whose terms allow minors. Google's Gemini API terms forbid it; Anthropic explicitly allows it with safeguards.
- The LiteLLM image has python3 but no curl or wget. Scripts that call LiteLLM run python inside the container.

- Model access is per LiteLLM key: kid keys list their models; the parent key (no list) gets everything. Parent models use the `*_PARENTS` provider keys and must never be on a kid key or made public in Open WebUI.
- OpenRouter entries in `litellm/config.yaml` always carry `extra_body.provider: {data_collection: deny, zdr: true}` and fallback `model_info` prices. The model list must match the guardrail allowlist on the OpenRouter key (docs/openrouter.md).

## Gotchas
- LiteLLM spend logs: the prompt is in `proxy_server_request` (the `messages` column is `{}`), stored after the pre-call hook runs. Long strings are middle-truncated past `MAX_STRING_LENGTH_PROMPT_IN_DB`.
- Open WebUI group permissions are additive with Default permissions; lock things down in Default permissions.
- Docker Desktop on macOS doesn't share `/private/tmp`; bind mounts from there show up as empty directories.
- LiteLLM keys SpendLogs rows on the upstream response `id`. A test stub must return unique ids, or rows silently go missing.
- `general_settings.user_header_mappings` maps Open WebUI's forwarded `X-OpenWebUI-User-Email` to LiteLLM's `end_user` (role `customer`); `review-logs.sh` shows it as `who`.
- LiteLLM has no built-in prices for OpenRouter models; cost comes from OpenRouter's `usage.cost` (requested automatically), with `model_info` prices as the fallback.
