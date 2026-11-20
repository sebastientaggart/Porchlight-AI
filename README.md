# Porchlight-AI

Self-hosted AI for your kids, with the porchlight on. Your kids get a real, capable AI assistant. You get to read what they're doing with it.

Most consumer AI products either don't allow kids at all or offer "parental controls" built around alerts and time limits, not transcripts. This project takes the opposite position: kids get access, parents get visibility, and everyone knows the rules.

## What you get

- **A normal chat app** (Open WebUI) with a separate account per kid.
- **Parent can read every conversation** from the admin panel.
- **An independent audit log** (LiteLLM + Postgres) that kids can't edit or delete, even if they find a way around the UI.
- **Per-kid monthly budgets**, so nobody runs up a surprise bill.
- **Parents use it too**, with their own models and provider keys that kids can't reach.
- **Age-appropriate system prompts**, injected by LiteLLM where kids can't override them, picked by each kid's age so they grow up with them.
- **Optional alerts** to Home Assistant, ntfy, or any webhook when a conversation looks like it needs a parent, with an optional local Llama Guard classifier.

```
Kid device ──> Open WebUI ──> LiteLLM ──> Anthropic API (optional: OpenRouter, local model)
 (DNS blocks     per-kid        per-kid keys,
  public AI)     accounts,      budgets,
                 parent reads   full audit log
                 all chats
```

## What this is not

It is not a safety guarantee. System prompts shape behavior; they don't enforce it. The real controls here are **visibility** (you can read everything) and **conversation** (you talk to your kids about what you see). If you want AI to babysit, this won't do that, and nothing else will either.

## Where your data goes

The stack runs at home, but the default model is Anthropic's API, so conversations leave the house. Claude is used because it holds age-appropriate behavior well when a determined teenager pushes, and this setup leans on that. A local model works too (see `litellm/config.yaml`), at the cost of that behavior on most home hardware. The optional Llama Guard classifier is local either way.

## Who it's for

Parents comfortable with Docker and a bit of networking. The same setup works for anyone who wants supervised or shared AI access: helping an aging parent, a small household, a classroom pilot.

This is the setup I run for my own family, shared as a reference architecture rather than a supported product (see [CONTRIBUTING.md](CONTRIBUTING.md)). Image tags are pinned in `docker-compose.yml` and tested against Open WebUI `v0.12.4` and LiteLLM `v1.106.6`.

## Quick start

```bash
cp .env.example .env         # fill in keys and passwords
docker compose up -d         # add --profile guard for the local Llama Guard
```

Then follow [docs/setup.md](docs/setup.md) (about 20 minutes) to create accounts, per-kid connections, and model presets.

After that, `make help` lists everything you'll need later (adding a kid, reading the audit log, spending), and `make doctor` checks the whole setup and says what's wrong. The Makefile only wraps `scripts/`, which also run without `make`.

## Docs

- [Setup](docs/setup.md): accounts, per-kid keys, model presets, permissions
- [Admin guide](docs/admin.md): where to click (or edit) to change things later
- [Features](docs/features.md): what's on and off for kids, and why
- [Monitoring](docs/monitoring.md): reading chats, the audit log, alerts
- [Network](docs/network.md): making this the path of least resistance
- [OpenRouter](docs/openrouter.md): optional, for models from other providers
- [Talking with your kids](docs/talking-with-kids.md): the part that actually matters

## Costs

You pay the model provider per use. Kid-scale usage on a small model is typically a few dollars a month. Set budgets anyway (see setup).

## Terms of service

Check your model provider's terms and usage policies before putting their API in front of minors. Anthropic's consumer Claude app, for example, is 18+ only; API use in products serving minors has its own requirements (disclosure that it's an AI, appropriate safeguards). You're the operator here, so this part is on you. If you add OpenRouter, its terms and each model provider's apply too (see [docs/openrouter.md](docs/openrouter.md#terms)).

## License

MIT
