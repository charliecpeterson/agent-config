"""Read source agent Markdown for harness-specific renderers."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re

from .tomlfmt import toml_str


@dataclass(frozen=True)
class AgentSource:
    description: str
    instructions: str


def read_agent(path: Path) -> AgentSource:
    text = path.read_text()
    match = re.match(r"---\n(.*?)\n---\n(.*)\Z", text, re.DOTALL)
    if match is None:
        raise ValueError(f"{path}: missing frontmatter")
    return AgentSource(
        description=_description(match.group(1), path),
        instructions=match.group(2),
    )


def codex_agent_toml(name: str, source: AgentSource) -> str:
    return "\n".join((
        f"name = {toml_str(name)}",
        f"description = {toml_str(source.description)}",
        'sandbox_mode = "read-only"',
        f"developer_instructions = {toml_str(source.instructions)}",
        "",
    ))


def opencode_agent_markdown(name: str, source: AgentSource) -> str:
    import json

    return (
        "---\n"
        f"name: {name}\n"
        f"description: {json.dumps(source.description)}\n"
        "mode: subagent\n"
        "permission:\n"
        "  edit: deny\n"
        "---\n\n"
        f"{source.instructions}"
    )


def _description(frontmatter: str, path: Path) -> str:
    lines = frontmatter.splitlines()
    for index, line in enumerate(lines):
        if not line.startswith("description:"):
            continue
        value = line.partition(":")[2].strip()
        if value not in {">", "|"}:
            return value.strip('"')
        continuation = []
        for next_line in lines[index + 1:]:
            if not next_line.startswith((" ", "\t")):
                break
            continuation.append(next_line.strip())
        return " ".join(continuation)
    raise ValueError(f"{path}: missing description")
