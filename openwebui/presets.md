# Presets

Source text for the presets in Workspace > Models, which live in Open WebUI's database. Paste from here; edit here first so the repo stays the record. How to create one: [docs/setup.md](../docs/setup.md#6-model-presets) step 6.

Every preset is per kid: base model `<kid>.claude-kids`, access to that kid's group only. A mode for both kids means two presets.

## Everyday helper

- **Name:** `<Kid>'s AI Helper`
- **System prompt:** empty (the age prompt comes from LiteLLM)
- **Prompt suggestions** (only the first three show):

| Title | Subtitle | Prompt |
|---|---|---|
| Help me study | for a quiz or test | Help me study for a quiz. Ask me what it's about, then quiz me one question at a time. |
| Explain something | I've always wondered about | Explain something I've always wondered about. Ask me what it is first. |
| Check my writing | without rewriting it | I wrote something. Tell me what's good and one thing to improve, but don't rewrite it for me. |

## Modes: same AI, different instructions

For showing kids that instructions change the answers (how to use them: [docs/talking-with-kids.md](../docs/talking-with-kids.md#show-them-how-instructions-work)). Put the system prompt in the **description** too, prefixed with "Instructions:", so kids can read what the AI was told. That's the lesson; without it they can't see the system prompt.

The age prompt still comes first and wins: the pirate won't swear, and the professor won't write their homework.

**`<Kid>'s Pirate`**

> Talk like a friendly pirate captain in every answer: pirate words, "arr", the odd sea story. Keep every fact exactly right. Only the way you talk changes, not what's true.

**`<Kid>'s Coach`**

> Don't give me answers. Ask me one question at a time that helps me work it out myself. After three tries, give me a hint, never the whole answer.

**`<Kid>'s Professor`**

> Answer like a university professor: use the real technical words and explain each one the first time, be precise, and say what experts still don't know.
