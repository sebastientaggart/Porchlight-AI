# Plan: web search for kids

Status: phases 1 and 2 built 2026-11-19, parents only ([setup.md step 9](../setup.md#9-web-search-for-parents-optional)). Phase 3 (kids) not planned for now. Owner: parent. Cost: free (self-hosted); the model reads more tokens per search (a few cents per research-heavy chat on Haiku, about 20x that on Sonnet).

## Decision (2026-11-19): no search for kids, for now

For elementary and middle-school kids, the model's own knowledge covers their schoolwork. Search adds clickable links to the open web, and testing showed strict safe search only catches the obvious (below). Parents use it first; revisit phase 3 for older kids later, alongside device- and network-level filtering.

## Findings from building phases 1 and 2

- **Engines:** from a home IP, only Bing works reliably. DuckDuckGo CAPTCHAs intermittently, Google says "access denied", Brave returns broken links (`http:///go/...`, also on the newest image), Startpage doesn't load. `searxng/settings.yml` keeps Bing, DuckDuckGo, and Wikipedia. One working engine is a single point of failure.
- **The lock works:** `safesearch=0` returns the same results as strict.
- **Strict filters explicit, not borderline.** Against an unlocked copy: "xxx videos" went from 10 porn sites to zero results. "nude beach" returned the identical 10 results, NSFW aggregators included.
- **Kids can't reach it:** Open WebUI checks the `features.web_search` permission server-side on all three paths (the model's `search_web`/`fetch_url` tools, the chat toggle, and `/process/web/search`), so the global switch doesn't expose it to them.
- **Not done:** `WEB_FETCH_FILTER_LIST` (the page-fetch block list). Open WebUI's default list already blocks private networks; a content block list only matters for phase 3.

## Outcome

Kids who've been granted it (older kids first) can ask the model to search the web. Results come from a SearXNG instance locked to strict safe search, page fetches are filtered, and every query and result shows up in the audit log like any other chat content.

## Constraints and findings

- **Open WebUI barely enforces safe search.** It sends `safesearch=1` (moderate) to SearXNG, and nothing at all to Brave, Tavily, Exa, or Kagi. Tavily's and Exa's filters default off. Safe search has to be enforced by the search backend itself.
- **SearXNG can lock it.** `search.safe_search: 2` (strict) plus `preferences.lock: [safesearch]` makes the instance ignore the request's own `safesearch` value.
- **SearXNG only forwards safe search to engines that support it.** Engines without support return unfiltered results, so only enable engines that support it (the instance's Preferences page shows which). Google, Bing, DuckDuckGo, Brave, and Startpage translate the level; Wikipedia is low-risk. Disable image, video, and torrent categories.
- **Open WebUI uses native tool calling by default.** The model gets `search_web` (result snippets) and `fetch_url` (any URL, full page text). Safe search filters result lists, not what `fetch_url` reads, so page fetches need their own filter (`WEB_FETCH_FILTER_LIST`). Claude and the age prompt are the last layer.
- **Searches go straight from the Open WebUI container** to SearXNG, not through LiteLLM. The model's tool calls (queries) and the tool results (snippets, pages) are in the next chat request, so the audit log still has them.
- **Model-side search** (Anthropic's web search tool, OpenRouter's) has no safe-search control at all, only domain lists. Not for kids.
- **Fallback if SearXNG is a pain:** Brave Search API, $5/1,000 queries with $5/month free credit (about 1,000 queries), safe search "moderate" by default and not settable from Open WebUI.

## Decision: a dedicated SearXNG for kids

If you already run SearXNG for yourself, don't reuse it here: locking it to strict would also lock your own searches, and its config would live outside this repo. A small dedicated instance in this stack keeps the kid-facing settings in version control, internal-only (no published port, so no rate limiter or Valkey needed).

## Phase 1: SearXNG service

Scope:
- `searxng` service in `docker-compose.yml` under a `search` profile (added to `COMPOSE_PROFILES`), pinned image tag, no published port.
- `searxng/settings.yml` in the repo: `use_default_settings: true`; `server.secret_key` from `.env`; `server.limiter: false`; `search.safe_search: 2`; `search.formats: [html, json]` (Open WebUI needs JSON); `preferences.lock: [safesearch]`; general category only; only safe-search-capable engines.

Acceptance:
- From the Open WebUI container, a JSON search returns results.
- Adding `&safesearch=0` to a query doesn't change its results (the lock works).
- A query that returns explicit results on an unlocked instance returns filtered results here.

## Phase 2: Open WebUI wiring

Scope (all in `docker-compose.yml`):
- `ENABLE_WEB_SEARCH=true`, `WEB_SEARCH_ENGINE=searxng`, `SEARXNG_QUERY_URL=http://searxng:8080/search?q=<query>`.
- `WEB_SEARCH_RESULT_COUNT` (3 to 5).
- `WEB_FETCH_FILTER_LIST`: a block list for page fetches (`!domain` entries; plain entries make it an allow list). Start small; decide whether to adopt a maintained adult-content list.
- Optionally `WEB_SEARCH_DOMAIN_FILTER_LIST` for search results.

Acceptance:
- As a parent, a question needing current information triggers a search and cites results.
- A kid without the permission sees no web search option.
- The query and results appear in `review-logs.sh` output.
- A fetch of a blocked domain fails.

## Phase 3: Grant per group

Scope:
- Grant `Web Search` to chosen kids' groups (Admin > Users > Groups). Defaults stay off.
- Consider a line in the age prompts about judging sources ("search results can be wrong or misleading; say where information came from").

Acceptance:
- A granted kid can search; an ungranted one can't.
- Parent alerts still fire on the kid's messages as before.

## Open questions

- Which ages get search, and does the youngest bracket ever?
- Final engine list, after checking the Preferences page.
- Block list for `fetch_url`: hand-maintained, a maintained list, or rely on safe search plus the model?
