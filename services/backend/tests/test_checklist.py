from __future__ import annotations

from html.parser import HTMLParser
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.checklist import build_checklist_snapshot
from app.config import get_settings
from app.main import app


class BalancedHtmlParser(HTMLParser):
    void_elements = {
        "area",
        "base",
        "br",
        "col",
        "embed",
        "hr",
        "img",
        "input",
        "link",
        "meta",
        "source",
        "track",
        "wbr",
    }

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.stack: list[str] = []
        self.ids: list[str] = []

    def handle_starttag(
        self,
        tag: str,
        attrs: list[tuple[str, str | None]],
    ) -> None:
        if tag not in self.void_elements:
            self.stack.append(tag)
        self.ids.extend(value for name, value in attrs if name == "id" and value)

    def handle_endtag(self, tag: str) -> None:
        assert self.stack, f"Closing {tag} without an open element"
        assert self.stack.pop() == tag, f"Mismatched closing element: {tag}"


@pytest.fixture(autouse=True)
def isolated_database(monkeypatch: pytest.MonkeyPatch, tmp_path: Path):
    # The dashboard does not need a provider and must remain testable when a
    # developer has configured the repository-root .env.
    monkeypatch.setenv("OPENAI_API_KEY", "")
    monkeypatch.setenv("RECALL_DATABASE_PATH", str(tmp_path / "recall.db"))
    get_settings.cache_clear()
    yield
    get_settings.cache_clear()


def test_snapshot_contains_completed_layer_dashboard_and_error_state() -> None:
    snapshot = build_checklist_snapshot()

    layer_two = next(layer for layer in snapshot["layers"] if layer["number"] == 2)
    error = next(entry for entry in snapshot["errors"] if entry["id"] == "E-009")

    assert layer_two["status"] == "complete"
    assert layer_two["total_tasks"] > 0
    assert snapshot["dashboard"]["status"] == "complete"
    assert error["status"] == "Resolved"


def test_snapshot_rereads_markdown_instead_of_caching(tmp_path: Path) -> None:
    checklist = tmp_path / "checklist.md"
    checklist.write_text(
        """Last updated: 2026-07-18
Current phase: First phase
Current branch: `main`
Last verified commit: `abc1234`

# Layer 2 — SQLite persistence

Status: `[~]` in progress

- [~] First task.
""",
        encoding="utf-8",
    )
    first = build_checklist_snapshot(checklist)

    checklist.write_text(
        checklist.read_text(encoding="utf-8").replace("First phase", "Second phase"),
        encoding="utf-8",
    )
    second = build_checklist_snapshot(checklist)

    assert first["metadata"]["current_phase"] == "First phase"
    assert second["metadata"]["current_phase"] == "Second phase"


def test_dashboard_and_json_endpoints_are_read_only_and_uncached() -> None:
    with TestClient(app) as client:
        dashboard = client.get("/dev/checklist")
        snapshot = client.get("/dev/checklist.json")

    assert dashboard.status_code == 200
    assert dashboard.headers["cache-control"] == "no-store"
    assert "Recall build pulse" in dashboard.text
    assert "POLL_INTERVAL_MS = 2_000" in dashboard.text
    assert snapshot.status_code == 200
    assert snapshot.headers["cache-control"] == "no-store"
    assert snapshot.json()["metadata"]["current_branch"] == "main"


def test_dashboard_html_has_balanced_elements_and_unique_ids() -> None:
    dashboard = Path(__file__).parents[1] / "app" / "static" / "checklist.html"
    parser = BalancedHtmlParser()

    parser.feed(dashboard.read_text(encoding="utf-8"))
    parser.close()

    assert parser.stack == []
    assert len(parser.ids) == len(set(parser.ids))


def test_dashboard_preserves_expanded_layers_across_refreshes() -> None:
    dashboard = Path(__file__).parents[1] / "app" / "static" / "checklist.html"
    html = dashboard.read_text(encoding="utf-8")

    assert "openStreams: new Set()" in html
    assert 'root.querySelectorAll("details.layer[open]")' in html
    assert "details.dataset.streamKey = key" in html
    assert "state.openStreams.has(key)" in html
    assert 'details.addEventListener("toggle"' in html
