#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKEND_ROOT="${REPOSITORY_ROOT}/services/backend"
VENV_ROOT="${BACKEND_ROOT}/.venv"
VENV_PYTHON="${VENV_ROOT}/bin/python"
BOOTSTRAP_PYTHON="${PYTHON_BIN:-python3}"

fail() {
  printf 'Mema startup error: %s\n' "$1" >&2
  exit 1
}

python_is_supported() {
  "$1" -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' \
    >/dev/null 2>&1
}

dependencies_are_current() {
  (
    cd "${BACKEND_ROOT}"
    "${VENV_PYTHON}" -m pip install \
      --dry-run \
      --quiet \
      --no-index \
      --no-build-isolation \
      --report - \
      -r requirements.txt 2>/dev/null
  ) | "${VENV_PYTHON}" -c '
import json
import sys

report = json.load(sys.stdin)
planned = report.get("install", [])
only_local_editable = all(
    item.get("is_direct")
    and item.get("download_info", {}).get("dir_info", {}).get("editable") is True
    for item in planned
)
raise SystemExit(0 if only_local_editable else 1)
'
}

project_install_is_current() {
  (
    cd "${BACKEND_ROOT}"
    "${VENV_PYTHON}" - <<'PY'
import re
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path

contents = Path("pyproject.toml").read_text(encoding="utf-8")
project = re.search(r"(?ms)^\[project\]\s*$.*?(?=^\[|\Z)", contents)
declared = re.search(r'(?m)^version\s*=\s*"([^"]+)"\s*$', project.group(0)) if project else None
if declared is None:
    raise SystemExit(1)
try:
    installed = version("mema-backend")
except PackageNotFoundError:
    raise SystemExit(1)
raise SystemExit(0 if installed == declared.group(1) else 1)
PY
  )
}

if [[ ! -x "${VENV_PYTHON}" ]]; then
  command -v "${BOOTSTRAP_PYTHON}" >/dev/null 2>&1 \
    || fail "Python 3.10 or later was not found. Set PYTHON_BIN to a compatible interpreter."
  python_is_supported "${BOOTSTRAP_PYTHON}" \
    || fail "${BOOTSTRAP_PYTHON} is older than Python 3.10."

  printf 'Creating backend virtual environment at %s\n' "${VENV_ROOT}"
  "${BOOTSTRAP_PYTHON}" -m venv "${VENV_ROOT}"
fi

python_is_supported "${VENV_PYTHON}" \
  || fail "The existing backend virtual environment uses Python older than 3.10. Remove services/backend/.venv and rerun."

if ! "${VENV_PYTHON}" -c \
  'import fastapi, openai, pydantic_settings, pytest, uvicorn' >/dev/null 2>&1 \
  || ! project_install_is_current \
  || ! dependencies_are_current; then
  printf 'Installing backend dependencies\n'
  (
    cd "${BACKEND_ROOT}"
    "${VENV_PYTHON}" -m pip install --upgrade pip
    "${VENV_PYTHON}" -m pip install -r requirements.txt
  )
fi

"${VENV_PYTHON}" -m pip check >/dev/null \
  || fail "The backend virtual environment has incompatible dependencies."
project_install_is_current \
  || fail "The backend virtual environment does not contain the current Mema package."
dependencies_are_current \
  || fail "The backend virtual environment does not satisfy requirements.txt."

SETTINGS="$({
  cd "${BACKEND_ROOT}"
  "${VENV_PYTHON}" - <<'PY'
from mema_backend.config import get_settings

settings = get_settings()
print(
    "|".join(
        (
            settings.mema_host,
            str(settings.mema_port),
            str(settings.mema_database_path),
            "yes" if settings.openai_configured else "no",
        )
    )
)
PY
})" || fail "Mema configuration is invalid. Check the root .env file."

IFS='|' read -r MEMA_HOST MEMA_PORT MEMA_DATABASE OPENAI_CONFIGURED \
  <<< "${SETTINGS}"
if [[ "${MEMA_HOST}" == *:* ]]; then
  URL_HOST="[${MEMA_HOST}]"
else
  URL_HOST="${MEMA_HOST}"
fi

BASE_URL="http://${URL_HOST}:${MEMA_PORT}"
HEALTH_URL="${BASE_URL}/health"

health_response() {
  "${VENV_PYTHON}" - "${HEALTH_URL}" <<'PY'
import json
import sys
from urllib.request import urlopen

with urlopen(sys.argv[1], timeout=0.5) as response:
    payload = json.load(response)

if (
    response.status != 200
    or payload.get("status") != "ok"
    or payload.get("database") != "ok"
):
    raise SystemExit(1)

print(json.dumps(payload, separators=(",", ":")))
PY
}

port_is_open() {
  "${VENV_PYTHON}" - "${MEMA_HOST}" "${MEMA_PORT}" <<'PY'
import socket
import sys

try:
    with socket.create_connection((sys.argv[1], int(sys.argv[2])), timeout=0.25):
        pass
except OSError:
    raise SystemExit(1)
PY
}

if HEALTH_JSON="$(health_response 2>/dev/null)"; then
  printf 'Mema backend is already healthy.\n'
  printf 'Health:   %s\n' "${HEALTH_URL}"
  printf 'Status:   %s\n' "${HEALTH_JSON}"
  exit 0
fi

if port_is_open >/dev/null 2>&1; then
  fail "${MEMA_HOST}:${MEMA_PORT} is already in use, but Mema health is not OK."
fi

printf 'Starting Mema backend\n'
printf 'Database: %s\n' "${MEMA_DATABASE}"
printf 'OpenAI configured: %s\n' "${OPENAI_CONFIGURED}"

(
  cd "${BACKEND_ROOT}"
  exec "${VENV_PYTHON}" -m mema_backend
) &
SERVER_PID=$!

cleanup() {
  if kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT TERM

HEALTH_JSON=""
for _ in {1..100}; do
  if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
    set +e
    wait "${SERVER_PID}"
    SERVER_STATUS=$?
    set -e
    fail "Backend exited before becoming healthy with status ${SERVER_STATUS}."
  fi
  if HEALTH_JSON="$(health_response 2>/dev/null)"; then
    break
  fi
  sleep 0.1
done

[[ -n "${HEALTH_JSON}" ]] \
  || fail "Backend did not become healthy within 10 seconds."

printf 'Mema is ready.\n'
printf 'Health:   %s\n' "${HEALTH_URL}"
printf 'Status:   %s\n' "${HEALTH_JSON}"
printf 'Press Control-C to stop the backend.\n'

set +e
wait "${SERVER_PID}"
SERVER_STATUS=$?
set -e
trap - EXIT INT TERM
exit "${SERVER_STATUS}"
