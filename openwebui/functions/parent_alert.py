"""
title: Parent Alert
description: Flags conversations a parent should look at and sends a webhook
             (Home Assistant, ntfy, Gotify, Slack, anything that takes a POST).
version: 0.2.0

Install: Admin > Functions > Create, then enable it globally. Configure the
Valves in the UI.

This is a nudge to go read the transcript, not a safety system. It never
blocks or slows a chat: checks run in the background.

- The kid's message is checked on the way in, so it's caught even if they hit
  Stop or the model errors.
- The reply is checked on the way out against its own pattern list. Those
  patterns look for the AI pointing to help (a crisis line, a trusted adult),
  which usually means the kid said something serious. Scanning replies with
  the kid's patterns would page you every time the AI says "never share your
  password".
- Optional: a local Llama Guard model on Ollama classifies both sides too. It
  catches slang and context the regexes miss; the regexes catch secrecy and
  grooming signals Llama Guard doesn't treat as unsafe. Use both.

Keyword matching is noisy on purpose: a false alarm costs you thirty seconds,
a miss costs more.
"""

import asyncio
import logging
import re
from functools import lru_cache
from typing import Optional

import aiohttp
from pydantic import BaseModel, Field

log = logging.getLogger(__name__)

KID_PATTERNS = [
    # Wellbeing
    r"\bkill (myself|me)\b", r"\bwant to die\b", r"\bhurt(ing)? myself\b",
    r"\bcut(ting)? myself\b", r"\bno one (likes|cares about) me\b", r"\bhate myself\b",
    r"\bkms\b", r"\bunalive\b", r"\bend it all\b", r"\bkys\b",
    # Secrecy and grooming signals
    r"\bdon'?t tell (my )?(mom|dad|parents?)\b", r"\bour (little )?secret\b",
    r"\bmeet (up|in person)\b", r"\bsend (me )?(a )?(pic|photo|picture)s?\b",
    # Personal info leaving the house
    r"\bmy (home )?address is\b", r"\bmy phone number is\b", r"\bmy password is\b",
    # Getting around the rules
    r"\bignore (your|previous|all|the) (instructions|rules)\b", r"\bjailbreak\b",
    r"\bdeveloper mode\b", r"\bpretend (you have|there are) no rules\b",
]

REPLY_PATTERNS = [
    r"\b988\b", r"\bcrisis (line|lifeline|text line)\b", r"\b911\b", r"\btrusted adult\b",
]

# Llama Guard 3 hazard categories. Defaults skip the ones that don't matter
# for kids (defamation, specialized advice, IP, elections, code abuse).
LLAMA_GUARD_CATEGORIES = {
    "S1": "violent crimes", "S2": "non-violent crimes", "S3": "sex-related crimes",
    "S4": "child sexual exploitation", "S5": "defamation", "S6": "specialized advice",
    "S7": "privacy", "S8": "intellectual property", "S9": "indiscriminate weapons",
    "S10": "hate", "S11": "suicide and self-harm", "S12": "sexual content",
    "S13": "elections", "S14": "code interpreter abuse",
}


@lru_cache(maxsize=8)
def compile_patterns(source: str) -> list:
    compiled = []
    for p in source.splitlines():
        if p := p.strip():
            try:
                compiled.append(re.compile(p, re.IGNORECASE))
            except re.error:
                log.warning("parent_alert: skipping bad regex %r", p)
    return compiled


class Filter:
    class Valves(BaseModel):
        webhook_url: str = Field(
            default="",
            description="Called from inside the Open WebUI container, so that container must resolve "
            "and trust it (.local mDNS names don't resolve in Docker). "
            "e.g. https://homeassistant.home.lan/api/webhook/family_ai_alert",
        )
        webui_url: str = Field(
            default="",
            description="Where you open chats from your phone, e.g. https://chat.home.lan. Adds a chat link to alerts.",
        )
        kid_patterns: str = Field(
            default="\n".join(KID_PATTERNS),
            description="Checked against the kid's messages. One regex per line, case-insensitive.",
        )
        reply_patterns: str = Field(
            default="\n".join(REPLY_PATTERNS),
            description="Checked against the AI's replies. Empty to skip replies.",
        )
        llama_guard_url: str = Field(
            default="", description="Ollama base URL, e.g. http://ollama:11434. Empty to disable."
        )
        llama_guard_model: str = Field(default="llama-guard3:1b")
        llama_guard_categories: str = Field(
            default="S1,S2,S3,S4,S9,S10,S11,S12",
            description="Comma-separated Llama Guard categories that trigger an alert.",
        )

    def __init__(self):
        self.valves = self.Valves()
        self._tasks = set()  # keep background tasks referenced until they finish

    @staticmethod
    def _text(message: dict) -> str:
        content = message.get("content") or ""
        if isinstance(content, list):  # multimodal messages
            content = " ".join(c.get("text", "") for c in content if isinstance(c, dict))
        return content

    async def _llama_guard(self, session, conversation: list) -> list:
        """Returns the alerting category names Llama Guard flags for the last turn."""
        async with session.post(
            f"{self.valves.llama_guard_url.rstrip('/')}/api/chat",
            json={"model": self.valves.llama_guard_model, "messages": conversation, "stream": False},
        ) as r:
            r.raise_for_status()
            verdict = (await r.json())["message"]["content"].strip().split("\n")
        if verdict[0].strip().lower() != "unsafe" or len(verdict) < 2:
            return []
        wanted = {c.strip().upper() for c in self.valves.llama_guard_categories.split(",")}
        codes = [c.strip().upper() for c in verdict[1].split(",")]
        return [f"llama-guard {c} ({LLAMA_GUARD_CATEGORIES.get(c, '?')})" for c in codes if c in wanted]

    async def _check(self, user: dict, chat_id: Optional[str], source: str, patterns: str, conversation: list):
        text = self._text(conversation[-1])
        hits = [p.pattern for p in compile_patterns(patterns) if p.search(text)]
        try:
            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=60)) as session:
                if self.valves.llama_guard_url and text:
                    try:
                        hits += await self._llama_guard(
                            session, [{"role": m["role"], "content": self._text(m)} for m in conversation]
                        )
                    except Exception:
                        log.exception("parent_alert: Llama Guard check failed")
                if not hits:
                    return
                link = f"{self.valves.webui_url.rstrip('/')}/c/{chat_id}" if self.valves.webui_url and chat_id else None
                async with session.post(
                    self.valves.webhook_url,
                    json={
                        "kid": user.get("name"),
                        "email": user.get("email"),
                        "source": source,  # "kid" or "reply"
                        "chat_id": chat_id,
                        "link": link,
                        "matched": sorted(set(hits)),
                        "excerpt": text[:280],
                    },
                ) as r:
                    r.raise_for_status()
        except Exception:
            log.exception("parent_alert: webhook failed")  # never break the kid's chat

    def _spawn(self, coro):
        task = asyncio.create_task(coro)
        self._tasks.add(task)
        task.add_done_callback(self._tasks.discard)

    def _skip(self, user: Optional[dict]) -> bool:
        return not self.valves.webhook_url or not user or user.get("role") == "admin"

    async def inlet(self, body: dict, __user__: Optional[dict] = None, __metadata__: Optional[dict] = None) -> dict:
        metadata = __metadata__ or {}
        messages = body.get("messages") or []
        # Background tasks (titles etc.) replay the chat; the real turn was already checked.
        if self._skip(__user__) or metadata.get("task") or not messages or messages[-1].get("role") != "user":
            return body
        self._spawn(self._check(__user__, metadata.get("chat_id"), "kid", self.valves.kid_patterns, messages[-1:]))
        return body

    async def outlet(self, body: dict, __user__: Optional[dict] = None) -> dict:
        messages = body.get("messages") or []
        if self._skip(__user__) or not self.valves.reply_patterns.strip() and not self.valves.llama_guard_url:
            return body
        if len(messages) < 2 or messages[-1].get("role") != "assistant":
            return body
        self._spawn(self._check(__user__, body.get("chat_id"), "reply", self.valves.reply_patterns, messages[-2:]))
        return body
