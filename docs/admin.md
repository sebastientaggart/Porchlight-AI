# Admin guide

Where to go to change things after setup. Paths are for Open WebUI v0.12.4; reasons behind each setting are in [features.md](features.md).

## The words

Open WebUI's names overlap, which is most of what makes it confusing.

| These docs say | Open WebUI shows | What it is |
|---|---|---|
| Base model | Admin Panel > Settings > Models, e.g. `alex.claude-kids` | A model from LiteLLM, through one connection (one LiteLLM key). The prefix says whose key. |
| Preset | Workspace > Models, e.g. "Alex's Helper" | A friendly wrapper around a base model: name, description, prompt suggestions, optional extra instructions, and who can see it. What kids actually pick. |
| Group | Admin Panel > Users > Groups | One per kid. Decides which presets and skills a kid can see, and their default model. |
| Default permissions | `docker-compose.yml` (`USER_PERMISSIONS_*`) | What every kid can do. Not the button in the UI (see [Traps](#traps)). |
| Skill | Workspace > Skills | A page of instructions a kid can load into a chat by typing `$` and picking it. |
| Function | Admin Panel > Functions | Server-side code. Here, only the parent alert filter. |

Open WebUI's sidebar has **Workspace**. **Admin Panel** is in the menu under your name, bottom left.

**Start here:** `make help` lists the commands; `make doctor` checks everything and points at the fix. Every `make` target wraps a script in `scripts/`, which also runs on its own.

## Where each kind of change goes

**Rule of thumb: it depends on where the thing lives.**
- **LiteLLM (keys, models, budgets) and anything in the repo (permissions, features, prompts):** a script in `scripts/` or a file edit. These are the controls that matter.
- **Open WebUI's database (people, groups, presets, skills, functions, reading chats):** the web UI. There are no scripts for these; they rarely change once set up.

| Change | Where | Survives restart? |
|---|---|---|
| A kid's preset (name, suggestions, description, access) | Workspace > Models | Yes (database) |
| Groups, members, a group's default model | Admin Panel > Users > Groups | Yes (database) |
| What every kid can do (permissions, features) | `docker-compose.yml`, then `docker compose up -d --wait` | Yes (files) |
| Anything in Admin Panel > Settings | Admin Panel > Settings | **No.** Reverts on restart. Put it in `docker-compose.yml` or `.env`. |
| How the AI talks to each age | `prompts/*.md` | Yes. Applies on the next message, no restart. |
| A kid's budget | `make set-budget` or `./scripts/set-kid-budget.sh <kid> <usd>` (or the LiteLLM admin UI, `http://localhost:4000/ui` > Virtual Keys) | Yes |
| A kid's allowed models | `make set-models` or `./scripts/set-kid-models.sh <kid> <models>`, e.g. `alex claude-kids,claude-kids-plus` | Yes |
| A new kid | `make add-kid`, then the UI steps it prints ([setup.md](setup.md#3-create-a-litellm-key-per-kid) steps 3 to 7) | Yes |

## Common tasks

**Change a kid's starter suggestions.** Workspace > Models > click the kid's preset > Prompt suggestions. Switch from default to custom, then add, remove, or reorder. Each has a title, a subtitle, and the text that goes into the chat box. **Only the first three ever show**, with no way for a kid to see the rest, so put the three that matter at the top.

**Rename a preset or change its description.** Same page, top. The description is what kids see under the name.

**Add instructions to a preset.** Same page, System Prompt. Usually leave it empty: LiteLLM already puts the age prompt first, and anything here goes below it. Useful for a mode (a "Spelling coach" preset), not for rules. Rules belong in `prompts/`.

**Change what kids see as their default model.** Admin Panel > Users > Groups > the kid's group > Default Model. Pick their preset.

**Check what a kid can see.** Every preset and skill has an **Access** button. Each kid's preset should list only that kid's group. Never "Public" (any kid could use it, on someone else's key).

**Share a skill with a kid.** Workspace > Skills > Import Skills (or create one), then Access > add the kid's group. Kids load it by typing `$` in the chat box.

**Hide the raw base models.** Admin Panel > Settings > Models > the model's menu > Hide Model. Cosmetic; access is what protects them.

**Search the web (parents).** Switch on Web Search in the chat box's Integrations menu, per chat. Without it the model doesn't get the search tools and will say it can't search. Kids don't have the option ([setup.md step 9](setup.md#9-web-search-for-parents-optional)).

**Read a kid's chats.** [monitoring.md](monitoring.md#1-reading-chats-open-webui).

**Add a kid, or a new model for a kid.** [setup.md](setup.md#3-create-a-litellm-key-per-kid), steps 3 to 7. The parts that need you at a terminal are steps 3 and 4.

**Change the alert webhook.** Admin Panel > Functions > the gear icon on the parent alert. Values are in [setup.md](setup.md#8-parent-alerts-optional).

## Traps

- **Admin Panel > Settings changes revert on restart.** They work immediately, which makes them look permanent. They're not: `docker-compose.yml` and `.env` are re-applied on every start.
- **Groups > Edit Default Permissions** is the same: the compose file resets it. Change `USER_PERMISSIONS_*` in `docker-compose.yml` instead.
- **Group permissions only add.** Turning something off in a group does nothing if the defaults allow it. Use a kid's group to grant an extra, never to lock down.
- **A preset is tied to one kid's key.** Its base model's prefix (`alex.`) decides whose budget, age prompt, and audit log name it uses. Two kids on one preset means one kid's rules for both.
- **The group page's "Who can share to this group"** is about granting Workspace items to the group, not collaboration. Kids can't share Workspace items at all, so leave it alone.
