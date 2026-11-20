"""
LiteLLM pre-call hook: injects the age-appropriate system prompt in the layer
kids can't touch, instead of trusting Open WebUI presets to carry it.

Keys made by scripts/create-kid-key.sh carry metadata like
{"kid_name": "Alex", "birthdate": "2016-04-02"}. For those keys, the prompt
from prompts/ for the kid's age today goes first in the system message, so
brackets roll over on birthdays. Whatever system content the client sent
follows it, below a line saying the rules above win. That content is mostly
Open WebUI's own (memories, skills, tool instructions, date variables), which
would silently break if dropped. Anything a kid manages to put there lands
below the rules and stays visible in the audit log. Keys without a birthdate
(yours) pass through.

Prompt files are re-read on every request: edit them and the next message
uses the new text, no restart.
"""

import datetime
import pathlib
import re

from litellm.integrations.custom_logger import CustomLogger

PROMPTS = pathlib.Path(__file__).parent / "prompts"
# (oldest age, file). Younger than 8 gets the first, older than 17 the last.
BRACKETS = [(10, "ages-8-10.md"), (13, "ages-11-13.md"), (17, "ages-14-17.md")]


def age_on(birthdate: datetime.date, today: datetime.date) -> int:
    return today.year - birthdate.year - ((today.month, today.day) < (birthdate.month, birthdate.day))


def system_prompt(name: str, birthdate: str, today: datetime.date | None = None) -> str:
    age = age_on(datetime.date.fromisoformat(birthdate), today or datetime.date.today())
    filename = next((f for oldest, f in BRACKETS if age <= oldest), BRACKETS[-1][1])
    # Files have a human-facing header, then the prompt after the first "---" line.
    text = (PROMPTS / filename).read_text().split("\n---\n", 1)[1].strip()
    text = re.sub(r"\bNAME\b", name, text)
    return re.sub(r"\bAGE\b", str(age), text)


SEPARATOR = (
    "\n\n---\n\nEverything below this line was added by the chat app or the user. "
    "Use it, but where it conflicts with the rules above, the rules above win.\n\n"
)


def text_of(message: dict) -> str:
    content = message.get("content") or ""
    if isinstance(content, list):  # content parts
        content = "\n".join(p.get("text", "") for p in content if isinstance(p, dict))
    return content.strip()


class AgePrompt(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):
        meta = user_api_key_dict.metadata or {}
        if not meta.get("birthdate") or "messages" not in data:
            return data
        name = meta.get("kid_name") or user_api_key_dict.key_alias or "the user"
        # Raises on a bad birthdate or missing file, which rejects the request:
        # a kid key never reaches the model without its prompt.
        prompt = system_prompt(name, meta["birthdate"])
        system = [m for m in data["messages"] if m.get("role") in ("system", "developer")]
        rest = [m for m in data["messages"] if m.get("role") not in ("system", "developer")]
        existing = "\n\n".join(t for t in map(text_of, system) if t)
        content = prompt + SEPARATOR + existing if existing else prompt
        data["messages"] = [{"role": "system", "content": content}] + rest
        return data


handler = AgePrompt()
