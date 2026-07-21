"""Read the historical development checklist into a live dashboard snapshot."""

from __future__ import annotations

import re
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.config import REPOSITORY_ROOT


CHECKLIST_PATH = REPOSITORY_ROOT / "docs" / "developer-b-checklist.md"
LAYER_HEADING = re.compile(r"^# Layer (?P<number>[0-9]+) — (?P<title>.+)$")
ENTRY_HEADING = re.compile(r"^## (?P<id>[BE]-[0-9]{3}) — (?P<title>.+)$")
CHECKBOX = re.compile(r"^- \[(?P<mark>[ x~!D])\] (?P<text>.+)$")
FIELD = re.compile(r"^- (?P<name>[^:]+): (?P<value>.*)$")
STATUS_BY_MARK = {
    " ": "pending",
    "~": "in_progress",
    "x": "complete",
    "!": "blocked",
    "D": "deferred",
}


def _metadata(markdown: str) -> dict[str, str]:
    fields = {
        "current_phase": ("Current phase",),
        "current_branch": ("Implementation branch", "Current branch"),
        "last_verified_commit": ("Last verified commit",),
        "last_updated": ("Last updated",),
    }
    metadata: dict[str, str] = {}
    for key, labels in fields.items():
        metadata[key] = "unknown"
        for label in labels:
            match = re.search(
                rf"^{re.escape(label)}: (?P<value>.+)$", markdown, re.MULTILINE
            )
            if match is not None:
                metadata[key] = match.group("value").strip("`")
                break
    return metadata


def _section(lines: list[str], start: int) -> list[str]:
    end = len(lines)
    for index in range(start + 1, len(lines)):
        if lines[index].startswith("# "):
            end = index
            break
    return lines[start:end]


def _tasks(lines: list[str]) -> list[dict[str, str]]:
    tasks: list[dict[str, str]] = []
    current_group = "Tasks"
    current: dict[str, str] | None = None

    for line in lines:
        if line.startswith("## "):
            current_group = line.removeprefix("## ").strip()
            current = None
            continue

        match = CHECKBOX.fullmatch(line)
        if match is not None:
            current = {
                "status": STATUS_BY_MARK[match.group("mark")],
                "text": match.group("text").strip(),
                "group": current_group,
            }
            tasks.append(current)
            continue

        if current is not None and line.startswith("  ") and line.strip():
            continuation = line.strip()
            if continuation.startswith("- "):
                continuation = continuation[2:]
            current["text"] = f"{current['text']} {continuation}"

    return tasks


def _declared_status(lines: list[str]) -> str:
    for line in lines:
        if line.startswith("Status: "):
            match = re.search(r"\[(?P<mark>[ x~!D])\]", line)
            if match is not None:
                return STATUS_BY_MARK[match.group("mark")]
            return line.removeprefix("Status: ").strip().lower()
    return "pending"


def _workstream(number: int | None, title: str, lines: list[str]) -> dict[str, Any]:
    tasks = _tasks(lines)
    resolved = sum(task["status"] in {"complete", "deferred"} for task in tasks)
    return {
        "number": number,
        "title": title,
        "status": _declared_status(lines),
        "tasks": tasks,
        "resolved_tasks": resolved,
        "total_tasks": len(tasks),
        "progress_percent": round((resolved / len(tasks)) * 100) if tasks else 0,
    }


def _layers(lines: list[str]) -> list[dict[str, Any]]:
    layers: list[dict[str, Any]] = []
    for index, line in enumerate(lines):
        match = LAYER_HEADING.fullmatch(line)
        if match is None:
            continue
        layers.append(
            _workstream(
                int(match.group("number")),
                match.group("title"),
                _section(lines, index),
            )
        )
    return layers


def _dashboard_workstream(lines: list[str]) -> dict[str, Any] | None:
    heading = "# Developer status dashboard — addition D-012"
    try:
        index = lines.index(heading)
    except ValueError:
        return None
    return _workstream(None, "Live checklist dashboard", _section(lines, index))


def _entry_fields(lines: list[str]) -> dict[str, str]:
    fields: dict[str, str] = {}
    current_field: str | None = None
    for line in lines:
        match = FIELD.fullmatch(line)
        if match is not None:
            current_field = match.group("name").strip().lower().replace(" ", "_")
            fields[current_field] = match.group("value").strip()
            continue
        if current_field is not None and line.startswith("  ") and line.strip():
            fields[current_field] = f"{fields[current_field]} {line.strip()}"
    return fields


def _entries(lines: list[str], prefix: str) -> list[dict[str, str]]:
    entries: list[dict[str, str]] = []
    for index, line in enumerate(lines):
        match = ENTRY_HEADING.fullmatch(line)
        if match is None or not match.group("id").startswith(prefix):
            continue

        end = len(lines)
        for candidate in range(index + 1, len(lines)):
            if lines[candidate].startswith("## ") or lines[candidate].startswith("# "):
                end = candidate
                break
        entries.append(
            {
                "id": match.group("id"),
                "title": match.group("title"),
                **_entry_fields(lines[index + 1 : end]),
            }
        )
    return entries


def build_checklist_snapshot(checklist_path: Path = CHECKLIST_PATH) -> dict[str, Any]:
    markdown = checklist_path.read_text(encoding="utf-8")
    lines = markdown.splitlines()
    modified_at = datetime.fromtimestamp(
        checklist_path.stat().st_mtime, tz=timezone.utc
    ).isoformat(timespec="seconds")
    generated_at = datetime.now(timezone.utc).isoformat(timespec="seconds")

    return {
        "generated_at": generated_at,
        "source_modified_at": modified_at,
        "metadata": _metadata(markdown),
        "layers": _layers(lines),
        "dashboard": _dashboard_workstream(lines),
        "blockers": _entries(lines, "B-"),
        "errors": _entries(lines, "E-"),
    }
