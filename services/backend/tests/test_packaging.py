from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path


BACKEND_ROOT = Path(__file__).resolve().parents[1]


def test_release_wheel_loads_packaged_enrichment_schema(tmp_path: Path) -> None:
    isolated_source = tmp_path / "backend"
    shutil.copytree(
        BACKEND_ROOT / "app",
        isolated_source / "app",
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
    wheel = next(wheel_directory.glob("recall_backend-*.whl"))
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

    smoke_test = subprocess.run(
        [
            sys.executable,
            "-I",
            "-c",
            (
                "import sys; "
                f"sys.path.insert(0, {str(installed_directory)!r}); "
                "from app.enrichment import enrichment_schema; "
                "from app.database import discover_migrations; "
                "schema = enrichment_schema(); "
                "assert schema['type'] == 'object'; "
                "assert 'search_aliases' in schema['required']; "
                "assert [item.version for item in discover_migrations()] == [1, 2]"
            ),
        ],
        cwd=tmp_path,
        check=False,
        capture_output=True,
        text=True,
    )
    assert smoke_test.returncode == 0, smoke_test.stdout + smoke_test.stderr
