# Home Assistant alerts: setup prompt

The parent alert filter ([monitoring.md](monitoring.md#3-alerts-optional)) POSTs a webhook when a kid's chat trips a watch pattern. This prompt has an AI agent with access to your Home Assistant (for example through Home Assistant's [MCP Server integration](https://www.home-assistant.io/integrations/mcp_server/)) build and test the automation that turns that webhook into a phone notification. If you'd rather build it by hand, start from the [YAML example](monitoring.md#home-assistant-example).

Fill in the five values under "My setup", then paste everything below the line into your agent.

What it was tested on: an Android phone, with Home Assistant behind a reverse proxy on the same LAN. The iOS fields come from the companion app's documentation, not from a run.

---

Set up a Home Assistant automation that turns a webhook from my kids' AI chat (Porchlight AI, an Open WebUI filter) into a notification on my phone.

## My setup

- Home Assistant URL as the Porchlight container reaches it: `<HA_URL>` (e.g. `http://192.168.1.10:8123`, or a reverse proxy hostname. Not a `.local` name: those don't resolve inside containers.)
- Webhook ID: `<WEBHOOK_ID>` (e.g. `family_ai_alert`)
- Where Porchlight runs relative to Home Assistant: `<same host or LAN | elsewhere>`
- Phone to notify: `<NOTIFY_TARGET>` (e.g. `notify.mobile_app_my_phone`, or the device name in the Home Assistant companion app)
- Chat base URL: `<CHAT_BASE_URL>` (e.g. `https://chat.example.com`)

## Ground rules

Home Assistant is production. Don't restart it or reload integrations. Create the automation the normal way (the automation editor or the config API), not by editing configuration files. Look at how this instance is actually set up before you build, and tell me if anything above doesn't match what you find.

## Trigger

Webhook, ID `<WEBHOOK_ID>`, POST only.

- If Porchlight runs on the same host or LAN as Home Assistant, set `local_only: true`.
- If it runs elsewhere, `local_only` has to be false. The webhook ID is then the only credential, so stop and ask me for a long random ID instead of a readable one.

Requests may arrive through a reverse proxy. Home Assistant answers HTTP 200 whether it accepted the webhook or rejected it as non-local, so a 200 proves nothing. To confirm a request was accepted, check that the automation has a new trace. A rejection shows up in the Home Assistant log as "Received remote request for local webhook".

## Payload

The JSON body:

- `kid`: display name of the kid's account
- `email`: their account email
- `source`: `"kid"` (their own message matched) or `"reply"` (the AI pointed them to help, e.g. a crisis line or a trusted adult)
- `chat_id`: chat ID
- `link`: URL that opens the chat, e.g. `<CHAT_BASE_URL>/c/<id>`
- `matched`: list of the pattern or category names that fired
- `excerpt`: up to 280 characters of the message

## Action

Notify `<NOTIFY_TARGET>`.

- Title: `Family AI: check {{ kid }}'s chat`
- Message: the excerpt in quotation marks, cut to 280 characters. Add `(AI pointed to help)` when `source` is `"reply"`.
- Fail open. This is a safety alert, so a missing field, an empty excerpt, or a body that isn't JSON must still produce a notification with fallback text. It must never error out and send nothing.
- Tapping the notification opens `link`, but only when `link` is `<CHAT_BASE_URL>` or starts with `<CHAT_BASE_URL>/`. Otherwise open `<CHAT_BASE_URL>`. The webhook is unauthenticated, so don't trust the URL it sends.
- Check whether `<NOTIFY_TARGET>` is a notify entity (called through `notify.send_message`, which can't carry a tap URL) or a `notify.mobile_app_*` action. If it's an entity, use the matching `notify.mobile_app_*` action.
- Check whether the phone is iOS or Android (the device's manufacturer in Home Assistant tells you) and use the right fields:
  - iOS: `data.url` for the tap, and `data.push.interruption-level: time-sensitive`.
  - Android: `data.clickAction` for the tap, plus `priority: high`, `ttl: 0`, and a dedicated `channel` with `importance: high`.
- It should not get buried, but it means "go read the chat". Don't use alarm streams, critical alerts, or anything that overrides silent mode.

Mode: queued, so two alerts close together both arrive.

## Test

1. POST this body to `<HA_URL>/api/webhook/<WEBHOOK_ID>` with `Content-Type: application/json`, from the place Porchlight runs (ideally inside the Open WebUI container, which also proves it can resolve the hostname):

   ```json
   {"kid": "Test Kid", "email": "test@example.com", "source": "kid",
    "chat_id": "test", "link": "<CHAT_BASE_URL>", "matched": ["self_harm"],
    "excerpt": "test alert, ignore"}
   ```

   If you can't reach that network yourself, give me the exact curl command to run and wait for me to say it's sent. Don't call the test done without it.
2. Confirm from the automation trace that the run happened and finished without error. Check the log for a non-local rejection.
3. Ask me to confirm the notification arrived and that tapping it opens the chat site. You can't see my phone, so don't report this as passed until I answer.

## Report

Give me the final automation as YAML, what you verified and how, anything you could not verify, and everything you changed from this prompt and why.
