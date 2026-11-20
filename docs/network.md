# Network

The setup only works if it's the easiest AI on the kids' devices.

## Block the public alternatives

On your DNS filter (Pi-hole, AdGuard Home, NextDNS, router), for the kids' devices or a kids' VLAN, block at least:

```
# General assistants
claude.ai
chatgpt.com
chat.openai.com
gemini.google.com
copilot.microsoft.com
perplexity.ai
meta.ai
poe.com
grok.com
chat.deepseek.com
chat.mistral.ai

# Companion and character apps: the riskiest category for kids
character.ai
replika.com
talkie-ai.com
janitorai.com
```

This list goes stale. If your filter offers a maintained AI or chatbot category, use that and keep this as a supplement. AI features also live inside apps you won't block (search engines, Snapchat, messaging apps, office suites), so treat blocking as friction, not a wall.

## Don't expose the stack to the internet

Keep Open WebUI on the LAN. For access away from home, use a VPN (WireGuard, Tailscale) rather than a public port. LiteLLM is published only on the host's loopback address (`127.0.0.1:4000`), never on the LAN. Keep it that way: anyone who can reach it can try the master key against the admin UI.

## Put it behind HTTPS

Plain HTTP on the LAN means anyone on the Wi-Fi with a packet sniffer can grab passwords and session cookies, including your admin session. That's a high bar for a kid, but not an impossible one for a curious teenager.

If you already run a reverse proxy (Caddy, Traefik, Nginx Proxy Manager), point it at Open WebUI, set `OPENWEBUI_BIND=127.0.0.1` in `.env` if the proxy is on the same host so the plain port isn't reachable from the LAN, and use a local CA or a DNS-challenge certificate for a LAN hostname.

## Known holes

- **School devices** are managed by the school. You can't filter them and shouldn't try; ask the school what AI access students have.
- **Friends' phones and houses.** See the conversation doc. This is the real reason talking beats blocking.
- **Cellular data** bypasses home DNS unless you use a device-level filter or VPN profile.
- **Encrypted DNS** (DNS over HTTPS, built into Firefox, Chrome, and some apps) bypasses Pi-hole and AdGuard entirely. Block `use-application-dns.net` (Firefox's off switch), block well-known DoH resolvers (community blocklists exist, such as HaGeZi's DoH/VPN/proxy bypass list), and on managed devices turn DoH off by policy.
- **VPN apps and proxies** get around all of the above. Device-level parental controls (Screen Time, Family Link) are the only thing that stops a kid installing them.
