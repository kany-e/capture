from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


BACKEND_ROOT = Path(__file__).resolve().parents[1]


def test_release_wheel_runs_as_a_standalone_local_service(tmp_path: Path) -> None:
    isolated_source = tmp_path / "backend"
    shutil.copytree(
        BACKEND_ROOT / "mema_backend",
        isolated_source / "mema_backend",
        ignore=shutil.ignore_patterns("__pycache__"),
    )
    shutil.copy2(
        BACKEND_ROOT / "pyproject.toml",
        isolated_source / "pyproject.toml",
    )
    wheel_directory = tmp_path / "wheel"
    wheel_directory.mkdir()

    build = subprocess.run(
        [
            sys.executable,
            "-m",
            "pip",
            "wheel",
            "--no-deps",
            "--no-build-isolation",
            "--wheel-dir",
            str(wheel_directory),
            str(isolated_source),
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    assert build.returncode == 0, build.stdout + build.stderr
    wheel = next(wheel_directory.glob("mema_backend-*.whl"))
    installed_directory = tmp_path / "installed"
    install = subprocess.run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--no-deps",
            "--target",
            str(installed_directory),
            str(wheel),
        ],
        check=False,
        capture_output=True,
        text=True,
    )
    assert install.returncode == 0, install.stdout + install.stderr

    smoke_source = f"""
import os
import sys
from pathlib import Path

sys.path.insert(0, {str(installed_directory)!r})
os.environ["OPENAI_API_KEY"] = ""
os.environ["MEMA_DATABASE_PATH"] = str(Path.cwd() / "data" / "mema.db")

from fastapi.testclient import TestClient
from mema_backend.config import REPOSITORY_ROOT, get_settings
from mema_backend.database import discover_migrations
from mema_backend.enrichment import enrichment_schema
from mema_backend.image_enrichment import image_enrichment_schema
from mema_backend.main import app

assert REPOSITORY_ROOT == Path.cwd()
assert enrichment_schema()["type"] == "object"
assert "search_aliases" in enrichment_schema()["required"]
assert "extracted_text" in image_enrichment_schema()["required"]
assert [item.version for item in discover_migrations()] == [1, 2, 3, 4, 5]

get_settings.cache_clear()
with TestClient(app) as client:
    response = client.get("/health")
assert response.status_code == 200
assert response.json()["status"] == "ok"
assert (Path.cwd() / "data" / "mema.db").is_file()
"""
    smoke_test = subprocess.run(
        [
            sys.executable,
            "-I",
            "-c",
            smoke_source,
        ],
        cwd=tmp_path,
        check=False,
        capture_output=True,
        text=True,
    )
    assert smoke_test.returncode == 0, smoke_test.stdout + smoke_test.stderr
