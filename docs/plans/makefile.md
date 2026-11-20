# Plan: `make` front door

Status: phase 1 built 2026-11-19. Phase 2 not started. Owner: parent.

## Outcome

After two months away, `make help` is enough to find everything: daily checks, adding a kid, and a `doctor` that says what's wrong and where to fix it.

## Principles

- **The Makefile is a thin wrapper.** Every target is one line calling `scripts/`. The scripts work without `make` (Unraid doesn't ship it) and keep taking arguments.
- **Prompt, don't require arguments.** A script missing an argument asks for it when run in a terminal, and fails with the usage line when not. Make variables (`KID=alex`) skip the prompt.
- **Python runs inside the containers** (the LiteLLM image has python3; the host may not). Secrets never go on a command line.
- **No Open WebUI admin API key.** Users, groups, and presets stay in the UI; scripts print exact values to paste. Revisit if this gets published and the clicks turn out to be a hurdle.

## Phase 1: wrappers, `doctor`, `add-kid` (built)

| Target | Script |
|---|---|
| `help` (default) | Makefile |
| `review`, `audit` | `review-logs.sh` |
| `spending`, `budget` | `spending.sh` |
| `open` | `open.sh` |
| `add-kid` | `add-kid.sh` (calls `create-kid-key.sh`) |
| `set-budget`, `set-models` | `set-kid-budget.sh`, `set-kid-models.sh` |
| `doctor` | `doctor.sh` |
| `up`, `down`, `logs`, `backup` | compose, `backup.sh` |

`doctor` checks the running stack, read-only: `.env` required values, containers, every connection key (is it a LiteLLM key, kid or parent, does its prefix match its alias), kid keys (birthdate, a model list, no parent models, age prompt resolves, budget use), provider keys for configured models, web search (answers, lock holds), Open WebUI presets (access entry, not public, not shared across kids), group default models, the parent alert function, and backup age. Exit code 1 on any failure.

Acceptance:
- `make` with no target prints grouped help.
- Every target works; every script still runs directly with arguments.
- `doctor` flags each of the misconfigurations hit during setup (provider key in a connection slot, empty `*_PARENTS` key, preset with no access entry, a preset shared with two kids' groups, alerts off).
- `add-kid` refuses an alias that already exists, backs up `.env`, never prints the key, and ends with the UI checklist.

## Phase 2: `install` (not started)

First run on a new machine: refuse if `.env` exists; generate secrets; ask for the Anthropic key and admin UI login; start the stack; create the parent key and write it into `.env`; finish with "open :3000 and create your own account first", then `doctor`. Belongs with publishing (it mostly helps other families).
