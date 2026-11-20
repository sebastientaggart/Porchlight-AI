# Contributing

Porchlight-AI is built for one family's daily use and shared as a reference setup ("how we did it"), not a maintained product.

## What's welcome

- **Bug and security fixes:** especially if a kid permission loophole is found or an upstream Open WebUI / LiteLLM update changes a setting name or database column.
- **Checks for `doctor.sh`:** if a misconfiguration bit you during setup, add a read-only check that catches it.
- **Documentation fixes:** clearer wording, broken links, or provider ToS changes affecting minors.

If you send a pull request:
- Keep scripts Bash 3.2 compatible (macOS default `/bin/sh` and `/bin/bash`).
- Keep `Makefile` targets as one-line wrappers around `scripts/` so everything still works on hosts without `make` (such as Unraid).
- Don't add filters that silently block a kid's message; the safety model here is visibility and conversation, not blocking.

## What's out of scope

- Feature requests that turn this into a general-purpose or multi-tenant platform.
- One-on-one setup, Docker, or home-networking support.

Fork it, adapt the prompts and rules to your own house, and make it yours.
