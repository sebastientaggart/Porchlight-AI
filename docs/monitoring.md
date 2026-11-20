# Monitoring

There are three layers. Use the first routinely, keep the second as a backstop, and add the third if you want to be nudged.

## 1. Reading chats (Open WebUI)

Admin > Users > select a kid > chats. This is the everyday view: readable, threaded, searchable.

Admin > Settings > Database also offers an export of all chats if you'd rather skim offline.

Note: Open WebUI creates some "internal" chats on a user's behalf (sub-agents, timers, notes) that are excluded from normal admin listings. Another reason for layer 2, and another reason to disable tools you don't need.

## 2. The audit log (LiteLLM)

Every request and response through LiteLLM is stored in Postgres with `store_prompts_in_spend_logs: true`. Kids have no access to it. Strings up to 100k characters are stored whole (`MAX_STRING_LENGTH_PROMPT_IN_DB`); beyond that LiteLLM cuts out the middle.

```bash
./scripts/review-logs.sh 20          # last 20 exchanges, all kids
./scripts/review-logs.sh 50 alex     # last 50 for one kid
```

Use this when the UI and the log disagree, or to spot-check periodically. If a chat is missing from the UI but present here, that's a conversation worth having.

LiteLLM also has its own admin UI with keys, spend per key, and request logs. It listens on the host's loopback only:

- On the machine running the stack: `http://localhost:4000/ui`
- From another machine: `ssh -L 4000:localhost:4000 <server>`, then the same URL

Log in with `ADMIN_UI_USERNAME` and `ADMIN_UI_PASSWORD` from `.env`. It's full admin access, including deleting keys, so use a strong password and treat it like the master key.

## 3. Alerts (optional)

`openwebui/functions/parent_alert.py` is an Open WebUI filter that POSTs to a webhook when an exchange looks like it needs a parent. It never blocks or slows a chat.

- **Kid's messages** are checked against `kid_patterns` (wellbeing, secrecy and grooming signals, personal info, jailbreak attempts).
- **AI replies** are checked against `reply_patterns`, which look for the AI pointing to help (988, a crisis line, a trusted adult). That usually means the kid said something serious.
- **Optional Llama Guard** (local, via Ollama) classifies both sides as well. It catches things no keyword list will (weapons, sexual content, phrasing you didn't think of). The regexes catch slang and grooming signals it misses. Use both.

Install and valve setup: [setup.md step 8](setup.md#8-parent-alerts-optional). The valves:

| Valve | Value |
|---|---|
| `webhook_url` | e.g. `https://homeassistant.home.lan/api/webhook/family_ai_alert`. Called from inside the Open WebUI container: `.local` (mDNS) names don't resolve there, and an internal-CA certificate won't be trusted by default. |
| `webui_url` | e.g. `https://chat.home.lan`, the address your phone uses, so alerts include a link to the chat |
| `llama_guard_url` | `http://ollama:11434` if you run the guard profile, else empty |

Your own chats are skipped (admin role).

### Llama Guard

```bash
# COMPOSE_PROFILES=guard in .env, or add --profile guard to every compose command
docker compose up -d --wait
docker compose exec ollama ollama pull llama-guard3:1b
```

The 1B model is about 1.6 GB and runs fine on CPU. Checks run in the background, so speed only affects how fast the alert arrives. `llama_guard_categories` picks which hazard categories alert; the default skips ones that don't matter for kids (defamation, IP, elections).

### Home Assistant example

Easiest: give an AI agent with access to your Home Assistant the [setup prompt](home-assistant-alerts.md). It checks your instance, builds the automation, and walks you through testing it. By hand:

```yaml
alias: Family AI alert
mode: queued                       # two alerts close together both arrive
triggers:
  - trigger: webhook
    webhook_id: family_ai_alert
    allowed_methods: [POST]
    local_only: true               # false only if the stack runs off your LAN; then use a long random ID
variables:
  chat: https://chat.example.com   # your webui_url
  # Fail open: a partial or non-JSON body still notifies.
  body: "{{ trigger.json if trigger.json is mapping else {} }}"
  kid: "{{ body.kid | default('a kid', true) }}"
  excerpt: "{{ (body.excerpt | default('(no excerpt)', true) | string)[:280] }}"
  # The webhook is unauthenticated: only follow links on your own chat site.
  link: >-
    {% set l = body.link | default('', true) | string %}
    {{ l if l == chat or l.startswith(chat ~ '/') else chat }}
actions:
  - action: notify.mobile_app_parent_phone   # a mobile_app action, not a notify entity (those can't carry a tap URL)
    data:
      title: "Family AI: check {{ kid }}'s chat"
      message: >-
        "{{ excerpt }}"{{ ' (AI pointed to help)' if body.source == 'reply' else '' }}
      data:
        clickAction: "{{ link }}"  # Android
        priority: high
        ttl: 0
        channel: family_ai
        importance: high
        url: "{{ link }}"          # iOS
        push:
          interruption-level: time-sensitive
```

Payload fields: `kid`, `email`, `source` (`kid` or `reply`), `chat_id`, `link`, `matched`, `excerpt`.

Testing: Home Assistant answers a webhook with HTTP 200 even when it rejects it as non-local, so a 200 proves nothing. Look for a new trace on the automation; a rejection logs "Received remote request for local webhook". The setup prompt's test section has the full check.

Keyword matching is noisy. That's fine for a nudge. Tune the patterns to your family, and treat an alert as "go read the chat," not "something happened."

## How often to look

A reasonable rhythm: skim weekly, read closely when an alert fires or something seems off, and do it less as trust is earned. See [talking-with-kids.md](talking-with-kids.md).
