# Open WebUI features

What's on, what's off, and why. Checked against Open WebUI v0.12.4.

## Where settings live

| Setting | Lives in | Changed by |
|---|---|---|
| Connections, features, default permissions, sharing, task generation | `docker-compose.yml` and `.env` | Editing the files, then `docker compose up -d --wait` |
| Users, groups, group permissions | Open WebUI database | Admin > Users |
| Model presets and their access | Open WebUI database | Workspace > Models |
| Functions (parent alert) and their valves | Open WebUI database | Admin > Functions |

Open WebUI runs with `ENABLE_PERSISTENT_CONFIG=false`, so the files win on every start. Changes in Admin > Settings take effect immediately but revert on the next restart: fine for trying something, not for keeping it. Any admin setting the compose file doesn't mention goes back to Open WebUI's default on restart.

The database parts survive restarts and are backed up by `scripts/backup.sh`. Open WebUI has a REST API that could manage them from a script too; not worth it for one family, since they rarely change once set up.

## Permissions model

- **Default permissions are what kids get.** Parents are admins and have everything.
- **Groups can only add.** Permissions are OR'd across the defaults and every group a user is in, so a group can't take something away. Use a kid's group to grant an extra (say, web search for a teenager), never to lock down.

## Features

| Feature | Kids | Why |
|---|---|---|
| Delete or edit chats and messages, temporary chats | Off | The chat record is the point. (The LiteLLM audit log keeps everything anyway, but the UI is what you read day to day.) |
| Chat controls, advanced params, system prompt, folders | Off | Each is a way to write a system prompt. Folder system prompts aren't checked server-side, so folders go too. |
| Voice (speech-to-text, read-aloud, voice calls) | Off | Talking out loud to it makes it feel like a person. Audio is local by default (Whisper in the container, the browser's own voices), so this is about the experience, not privacy. Parents keep it. |
| Memories | Off | An assistant that remembers them reads as a friend, and the model can write memories itself. Parents keep it. |
| Notes | Off | Note chats don't appear in the admin chat list. |
| Attach a URL | Off | Fetches arbitrary pages into the chat. |
| File upload | On | Homework handouts, their own writing. Extraction and embeddings run locally; content goes into the user message, so the age prompt still applies and the audit log has it. |
| Code interpreter, and running code blocks | On | Pyodide runs in the kid's browser sandbox, not on the server. Never switch the engine to Jupyter for kids: that runs code on the server. Running code blocks has no per-user switch; the interpreter does. |
| Web search | Off | Parents only ([setup.md step 9](setup.md#9-web-search-for-parents-optional)). Strict safe search blocks explicit queries but passes borderline ones, and every answer comes with links kids can click. [plans/web-search.md](plans/web-search.md). |
| Image generation | Off | Nice-to-have, later: see TODO.md. |
| Automations | Off | Scheduled prompts that run unattended on the kid's key, with no one watching the chat. Off upstream too; pinned. |
| Calendar | On | Open WebUI's own per-user calendar ("put my science test on Friday"). Nothing leaves the house, and it's useful for planning homework. Upstream default, not pinned. |
| Sub-agents | Off (global) | One prompt can fan out into up to 20 parallel agent loops, and there's no per-user switch. |
| Community sharing | Off (global) | No links or uploads to openwebui.com. |
| Message rating | On | Ratings stay in Open WebUI's database and feed the admin Evaluations page; nothing leaves the house. A kid's thumbs-down is a mild signal worth a look. |
| Tags, follow-ups, search-query generation | Off (global) | Extra model calls on the kid's key. Title generation stays. |
| Direct connections | Off (global) | Would let users add their own AI endpoints, bypassing LiteLLM. |

## The system message

LiteLLM's age prompt hook puts the age prompt first in the system message, and keeps whatever Open WebUI put there below a line saying the age rules win. Open WebUI uses the system message for memories, skills, tool and MCP instructions, the code interpreter's file notes, and variables like `{{CURRENT_DATE}}`; dropping it would break those silently.

Document and web search context goes in the user message (`RAG_SYSTEM_CONTEXT=false`, pinned in the compose file), and tool results go in tool messages, so neither depends on the system slot.
