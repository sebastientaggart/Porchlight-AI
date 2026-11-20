# TODO

## Next

- [ ] **`make install`** (phase 2 of [docs/plans/makefile.md](docs/plans/makefile.md)): first-boot setup script that generates secrets, asks for the Anthropic key and admin UI login, starts the stack, creates the parent key, and runs `doctor`.

## Later

- [ ] **Image generation (nice to have).** Findings so far:
  - Wire through LiteLLM so every image prompt is logged and budgeted: Open WebUI `ENABLE_IMAGE_GENERATION=true`, `IMAGE_GENERATION_ENGINE=openai`, `IMAGES_OPENAI_API_BASE_URL=http://litellm:4000/v1`, `IMAGES_OPENAI_API_KEY` = a dedicated LiteLLM "images" key with its own small budget (about $3/month), `IMAGE_GENERATION_MODEL`. Grant `Image Generation` per kid group. The forwarded user header attributes images per kid.
  - Model: OpenAI `gpt-image-1-mini` via OpenRouter, roughly $0.005 to $0.04 per image, with OpenAI's content filter on every prompt and output. **Not Gemini image models**: Google's API terms forbid apps likely used by under-18s.
  - Check first: OpenAI's API terms on minors. Whether LiteLLM's OpenRouter image route works for the chosen model (it strips `modalities`; test per model).
  - The age prompt doesn't apply (image calls carry no chat messages); safety rests on the provider's filter.
  - The audit log stores the response, including base64 image data (truncated at 100k characters per string); fine, but noisy.
  - Skip self-hosted CPU generation on a typical home server: slow, low quality, no content filter.
- [ ] **Channels (shared learning).** Slack-style rooms where family members post and @mention a model; the closest thing Open WebUI has to learning together. Off: `ENABLE_CHANNELS` defaults to false and isn't set in `docker-compose.yml`. Before turning it on, verify:
  - A kid's @mention runs on that kid's preset and key (age prompt, budget, `who` in the audit log), not on someone else's.
  - The parent alert filter runs on channel messages.
  - What kids can do to each other there: kid-to-kid messages bypass LiteLLM entirely, so the only record is Open WebUI's database.
  - `USER_PERMISSIONS_FEATURES_CHANNELS` defaults to true, so enabling channels gives them to every kid unless that's pinned to false and granted per group.
- [ ] **`OFFLINE_MODE=true`** for Open WebUI: stops Hugging Face model update checks and the version check. Test after first boot that embeddings and Whisper still load from the volume.

## Maybe never

- **Provisioning script** (`family.yaml` plus Open WebUI REST API for users, groups, presets, functions). Only worth it if this gets packaged for other families; for one household, the database parts rarely change once set up.
