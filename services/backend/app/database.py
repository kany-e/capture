"""SQLite connection and ordered migration support for Recall."""

from __future__ import annotations

import re
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterator


MIGRATIONS_DIRECTORY = Path(__file__).resolve().parent / "migrations"
MIGRATION_FILENAME = re.compile(r"^(?P<version>[0-9]{3})_(?P<name>[a-z0-9_]+)\.sql$")


class MigrationError(RuntimeError):
    """Raised when the database cannot reach the expected schema version."""


@dataclass(frozen=True, slots=True)
class Migration:
    version: int
    name: str
    path: Path


def discover_migrations() -> list[Migration]:
    migrations: list[Migration] = []
    for path in sorted(MIGRATIONS_DIRECTORY.glob("*.sql")):
        match = MIGRATION_FILENAME.fullmatch(path.name)
        if match is None:
            raise MigrationError(f"Invalid migration filename: {path.name}")
        migrations.append(
            Migration(
                version=int(match.group("version")),
                name=match.group("name"),
                path=path,
            )
        )

    expected_versions = list(range(1, len(migrations) + 1))
    actual_versions = [migration.version for migration in migrations]
    if not migrations or actual_versions != expected_versions:
        raise MigrationError(
            "Migration versions must be contiguous and begin with 001"
        )
    return migrations


@contextmanager
def database_connection(database_path: Path) -> Iterator[sqlite3.Connection]:
    database_path.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(database_path, timeout=5)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    try:
        yield connection
    finally:
        connection.close()


def _applied_migrations(connection: sqlite3.Connection) -> dict[int, str]:
    rows = connection.execute(
        "SELECT version, name FROM schema_migrations ORDER BY version"
    ).fetchall()
    return {int(row["version"]): str(row["name"]) for row in rows}


def _apply_migrations(database_path: Path) -> int:
    migrations = discover_migrations()
    known_versions = {migration.version for migration in migrations}

    with database_connection(database_path) as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
                version INTEGER PRIMARY KEY,
                name TEXT NOT NULL,
                applied_at TEXT NOT NULL
            )
            """
        )
        connection.commit()

        applied = _applied_migrations(connection)
        unknown_versions = set(applied) - known_versions
        if unknown_versions:
            versions = ", ".join(
                str(version) for version in sorted(unknown_versions)
            )
            raise MigrationError(
                f"Database contains migrations unknown to this build: {versions}"
            )

        for migration in migrations:
            applied_name = applied.get(migration.version)
            if applied_name is not None:
                if applied_name != migration.name:
                    raise MigrationError(
                        f"Migration {migration.version:03d} name mismatch: "
                        f"database={applied_name!r}, code={migration.name!r}"
                    )
                continue

            migration_sql = migration.path.read_text(encoding="utf-8")
            escaped_name = migration.name.replace("'", "''")
            applied_at = (
                datetime.now(timezone.utc)
                .isoformat(timespec="microseconds")
                .replace("+00:00", "Z")
            )
            script = (
                "BEGIN IMMEDIATE;\n"
                f"{migration_sql}\n"
                "INSERT INTO schema_migrations (version, name, applied_at) "
                f"VALUES ({migration.version}, '{escaped_name}', '{applied_at}');\n"
                "COMMIT;"
            )
            try:
                connection.executescript(script)
            except sqlite3.Error:
                if connection.in_transaction:
                    connection.rollback()
                raise

        return migrations[-1].version


def apply_migrations(database_path: Path) -> int:
    """Apply every pending migration and return the current schema version."""

    try:
        return _apply_migrations(database_path)
    except MigrationError:
        raise
    except (OSError, sqlite3.Error) as error:
        raise MigrationError(
            f"Unable to migrate SQLite database at {database_path}: {error}"
        ) from error


def database_schema_is_current(connection: sqlite3.Connection) -> bool:
    """Return whether a connection contains every migration known to this build."""

    try:
        expected = {
            migration.version: migration.name for migration in discover_migrations()
        }
        actual = _applied_migrations(connection)
    except (MigrationError, sqlite3.Error):
        return False
    return actual == expected
