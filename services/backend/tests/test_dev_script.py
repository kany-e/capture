from __future__ import annotations

import os
import subprocess

from mema_backend.config import REPOSITORY_ROOT


def test_clean_start_script_is_executable_and_valid_bash() -> None:
    script = REPOSITORY_ROOT / "scripts" / "dev.sh"

    assert script.is_file()
    assert os.access(script, os.X_OK)
    result = subprocess.run(
        ["/bin/bash", "-n", str(script)],
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr


def test_clean_start_script_keeps_secrets_out_of_status_output() -> None:
    script = (REPOSITORY_ROOT / "scripts" / "dev.sh").read_text(encoding="utf-8")

    assert "settings.openai_api_key" not in script
    assert "OPENAI_API_KEY" not in script
    assert "settings.openai_configured" in script


def test_clean_start_script_repairs_stale_requirement_versions() -> None:
    script = (REPOSITORY_ROOT / "scripts" / "dev.sh").read_text(encoding="utf-8")

    assert "dependencies_are_current" in script
    assert "--dry-run" in script
    assert "--no-index" in script
    assert "--no-build-isolation" in script
    assert "--report -" in script
    assert 'report.get("install", [])' in script
    assert script.count("dependencies_are_current") >= 3
    assert "project_install_is_current" in script
    assert 'version("mema-backend")' in script
