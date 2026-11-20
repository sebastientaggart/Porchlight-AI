# Setup

## 1. First boot

```bash
cp .env.example .env
# fill in WEBUI_SECRET_KEY, LITELLM_MASTER_KEY (must start with sk-), POSTGRES_PASSWORD,
# ADMIN_UI_USERNAME, ADMIN_UI_PASSWORD, ANTHROPIC_API_KEY
# (and OPENROUTER_API_KEY if you want non-Anthropic models; see openrouter.md)
docker compose up -d --wait   # returns once everything is healthy
```

Open `http://<host>:3000`. **The first account created becomes the admin.** Make it yours, immediately.

LiteLLM takes up to about 30 seconds to start (it runs database migrations first). `--wait` covers that; without it, the scripts below fail with `Connection refused` until LiteLLM shows as healthy in `docker compose ps`.

**Where settings live.** Open WebUI's admin settings (connections, features, default permissions) are set in `docker-compose.yml` and `.env`, and re-applied on every start. Changes in the admin UI work until the next restart, then revert, so make lasting changes in the files. Users, groups, group permissions, model presets, and functions are the exception: they live in Open WebUI's database and are managed in the UI. Details: [features.md](features.md).

## 2. Your own connection

Open WebUI only sees models through a connection, and every connection carries a LiteLLM key. Until you add one, the model list is empty, even for you.

```bash
./scripts/create-parent-key.sh parent 10
```

Arguments: name (default `parent`), monthly budget in USD (default 10). The key can use every model and gets no age prompt. Don't paste the master key instead: anyone who got into your Open WebUI admin account would then control LiteLLM too, audit log included.

Put the key in `.env` as the first connection (the template already has the URL and prefix):

```bash
OPENAI_API_BASE_URLS=http://litellm:4000/v1
OPENAI_API_KEYS=sk-...the key from the script...
OPENAI_API_CONFIGS='{"0":{"prefix_id":"parent"}}'
```

The URL is LiteLLM's Docker service name, not localhost. Then `docker compose up -d --wait`. You should now see `parent.claude-kids` and the other models. Base models are admin-only by default, so kids won't see these. Chat with each one, then check the whole path made it to the audit log:

```bash
./scripts/review-logs.sh 5 parent
```

### Parent models and the other parent

The parent key can use every model in `litellm/config.yaml`: the kid models, plus a parents section (`claude-sonnet`, `claude-opus`; add your own there). Kids can't reach the parent models because each kid key carries a fixed list of models, and parent models are never on it.

- **Separate provider keys.** Parent models use `ANTHROPIC_API_KEY_PARENTS` and `OPENROUTER_API_KEY_PARENTS`, so parent spend gets its own limits (an Anthropic Console workspace, an OpenRouter key limit) and the kids' OpenRouter allowlist stays kid-only. Set them to the kid values if you don't care. Restart LiteLLM after changing `.env`.
- **Budget.** The parent key's LiteLLM budget (default $10/month) should sit above your provider limits, or it becomes the real cap. Change it in the LiteLLM admin UI (`http://localhost:4000/ui`, Keys).
- **The other parent.** Create their Open WebUI account as an **admin** and share the one `parent` connection. As an admin they can read the kids' chats, and the alert filter skips them. A connection per parent works too, but every admin sees every connection's models, so the list doubles.
- **Who said what.** Each request is tagged with the Open WebUI user's email, so the `who` column in `review-logs.sh` tells parents (and kids) apart on a shared key.
- **Privacy between parents.** Parents' chats go into the same audit log, and admins can read each other's chats in Open WebUI. Agree on that up front.
- **Never make a parent model public** in Admin > Settings > Models. It would run on the parent key (every model, no age prompt), and kid key restrictions can't stop it.

## 3. Create a LiteLLM key per kid

Each kid gets their own key so budgets and audit logs are per kid.

**Shortcut:** `make add-kid` (or `./scripts/add-kid.sh`) does this step and the next one in one go: it asks for name, birthdate, budget, and models, creates the key, adds the connection to `.env`, restarts, checks it, and prints the Open WebUI steps (5 and 6) with the exact values. The manual steps below are what it does.

```bash
./scripts/create-kid-key.sh alex 2016-04-02 5 claude-kids
./scripts/create-kid-key.sh sam 2012-09-30 5 claude-kids,claude-kids-plus
```

Arguments: name, birthdate, monthly budget in USD, allowed models. Save the returned `key` values. To change an existing kid's models later: `./scripts/set-kid-models.sh alex claude-kids,claude-kids-plus`; their budget: `./scripts/set-kid-budget.sh alex 10`. Non-Anthropic models need OpenRouter; see [openrouter.md](openrouter.md).

The name and birthdate are stored on the key. LiteLLM's `age_prompt` hook uses them to pick the prompt from `prompts/` for the kid's age on each request and fill in the name and age. Brackets move on birthdays without you doing anything. Keys without a birthdate, like yours, pass through untouched.

The age prompt always goes first in the system message. Anything else there (mostly Open WebUI's own: memories, tool instructions, dates) follows below a line saying the age rules win. Kids can't write system prompts through the UI (step 5); anything they sneak in another way sits below your rules and shows up in the audit log.

## 4. One Open WebUI connection per kid

Open WebUI uses one API key per connection, so each kid gets a connection, added to the three lists in `.env` in the same position:

```bash
OPENAI_API_BASE_URLS=http://litellm:4000/v1;http://litellm:4000/v1;http://litellm:4000/v1
OPENAI_API_KEYS=sk-parent...;sk-alex...;sk-sam...
OPENAI_API_CONFIGS='{"0":{"prefix_id":"parent"},"1":{"prefix_id":"alex"},"2":{"prefix_id":"sam"}}'
```

The prefix keeps model IDs from colliding (`alex.claude-kids`). Then `docker compose up -d --wait`.

## 5. Accounts and groups

Admin > Users:
1. Create a user per kid (you set the password; signup is disabled).
2. Create a group per kid (`alex`, `sam`). Put each kid in their own group.

**Default permissions are what every kid gets**, and they're set in `docker-compose.yml` (the `USER_PERMISSIONS_*` block): no deleting or editing chats or messages, no temporary chats, no kid-written system prompts, no voice, no memories, no notes, no folders, no URL fetching; file upload and the in-browser code interpreter on; web search and image generation off until configured. The reasons for each are in [features.md](features.md).

Group permissions can only **add** to the defaults (the most permissive wins), so use a kid's group to grant extras deliberately, e.g. web search for a teenager. Don't turn the locked-down items back on in a group.

## 6. Model presets

Open WebUI calls these "Models"; these docs say preset to tell them apart from the base models LiteLLM provides ([admin.md](admin.md#the-words)).

Workspace > Models > create one preset per kid:
- **Base model:** that kid's prefixed model (e.g. `alex.claude-kids`)
- **Name:** something friendly ("Alex's Helper")
- **System prompt:** leave empty. LiteLLM injects it from `prompts/` (step 3).
- **Prompt suggestions:** custom, pitched at the kid. The defaults are for adults.
- **Access:** that kid's group only. With no access entry, only admins see it.

Then set it as the **Default Model** on the kid's group (Admin Panel > Users > Groups).

Then in Admin > Settings > Models, hide the raw base models to tidy the list. Hiding is cosmetic; what actually protects them is access. Base models are admin-only by default, so leave their access private and never make one public, or any kid could call another kid's model (and key) by ID.

## 7. Verify as a kid

First `make doctor` (or `./scripts/doctor.sh`): it catches the common mistakes, like a preset with no access entry or shared with the wrong kid. Then log in as each kid (private window). Confirm:
- Only their preset is visible.
- No delete or temporary chat option, and no system prompt field in chat Controls or Settings > General.
- No microphone or voice-call button, and no Memories, Notes, or Folders.
- A test chat shows up in Admin > Users > (kid) > chats.
- Asking "what's my name and how old am I?" gets the right answer (proves the age prompt is injected).
- `./scripts/review-logs.sh 5 alex` shows the same exchange.

## 8. Parent alerts (optional)

`openwebui/functions/parent_alert.py` sends a webhook when a kid's chat looks like it needs you. What it checks and why: [monitoring.md](monitoring.md#3-alerts-optional).

1. Admin > Functions > Create. Replace the template with the contents of `parent_alert.py` and save.
2. In the functions list, switch it on, then use its menu to make it **Global** so it runs on every model.
3. Open its valves (gear icon) and set:

| Valve | Laptop testing | At home |
|---|---|---|
| `webhook_url` | `http://host.docker.internal:9999` (see below) | `https://homeassistant.home.lan/api/webhook/family_ai_alert` |
| `webui_url` | `http://localhost:3000` | `https://chat.home.lan` |
| `llama_guard_url` | `http://ollama:11434` (optional, see below) | same |

The two URLs are used from different places:
- **`webui_url`** only builds the link inside the alert, which you open on your phone. It's the address your phone uses: `chat.home.lan` works at home and over Tailscale.
- **`webhook_url`** is called by the Open WebUI container. The container has to resolve the name and trust the certificate, not just your browser.

Alerts skip admin accounts, so make the other parent an admin too, or their chats will page you.

**Home Assistant side:** hand an agent with Home Assistant access the [setup prompt](home-assistant-alerts.md), or build it from the [YAML example](monitoring.md#home-assistant-example).

**Test without Home Assistant:** run `nc -l 9999` on the laptop, then as a kid send "honestly i just wanna kms". The alert's JSON body prints in the terminal. `nc` never replies, so the filter logs a timeout a minute later; that's expected.

**Optional local classifier.** A small Llama Guard model (CPU is fine, about 2 GB of RAM) classifies each message alongside the keyword patterns and catches things no keyword list will. It only adds alerts; it never blocks or slows a chat, and kids never see it. Set `COMPOSE_PROFILES=guard` in `.env` so it starts with the stack, then:

```bash
docker compose up -d --wait
docker compose exec ollama ollama pull llama-guard3:1b          # once, about 1.6 GB
docker compose exec ollama ollama run llama-guard3:1b "how do i make a pipe bomb"   # expect: unsafe, S9
```

Then set `llama_guard_url` to `http://ollama:11434`. Like every other check, it only runs when `webhook_url` is set. Details and categories: [monitoring.md](monitoring.md#llama-guard).

## 9. Web search for parents (optional)

A small SearXNG instance in the stack, with strict safe search locked on, gives the parents web search. Kids don't get it: their `USER_PERMISSIONS_FEATURES_WEB_SEARCH` stays off, and Open WebUI checks that permission on the server for every search path. Why kids are left out, and what it would take: [plans/web-search.md](plans/web-search.md).

In `.env`:

```bash
COMPOSE_PROFILES=guard,search      # add "search" to whatever is there
ENABLE_WEB_SEARCH=true
SEARXNG_SECRET=                    # openssl rand -hex 32
```

Then `docker compose up -d --wait`. Check it as a parent:
- Search is per chat: switch on Web Search in the chat box's Integrations menu first. Without it, the model says it can't search.
- Ask something that needs today's information ("what's the weather in Boston this weekend?"). The model should search, and the answer should cite sources with working links.
- `./scripts/review-logs.sh 3 parent` shows the search query and results inside the exchange.

As a kid (private window): no web search option in the chat box, and asking for a search gets an answer from the model's own knowledge instead.

**Engines break.** Search engines block self-hosted instances, so results come almost entirely from Bing (`searxng/settings.yml` lists what worked when last tested). If searches start coming back empty, check `docker compose logs searxng`. The fallback is the Brave Search API (plan, "Fallback").

## 10. Upgrades and backups

Image tags in `docker-compose.yml` are pinned. Upgrade deliberately, one service at a time, and re-run step 7 afterwards: permission defaults and LiteLLM's log format have both changed between releases before.

Back up before upgrading, and on a schedule:

```bash
./scripts/backup.sh     # writes backups/<timestamp>/{litellm.sql.gz,webui.db.gz}
```

Suggested cron: `0 3 * * * /path/to/Porchlight-AI/scripts/backup.sh`. It doesn't prune old backups.
