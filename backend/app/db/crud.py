from typing import Any
from collections.abc import Iterable
import sqlite3

from app.db.schemas import ContactCreate, ContactUpdate


CONTACT_COLUMNS = (
    "id",
    "name",
    "company",
    "email",
    "phone",
    "raw_text",
    "image_path",
    "crop_path",
    "created_at",
    "updated_at",
)

WRITABLE_COLUMNS = (
    "name",
    "company",
    "email",
    "phone",
    "raw_text",
    "image_path",
    "crop_path",
)


def _row_to_dict(row: sqlite3.Row | None) -> dict[str, Any] | None:
    if row is None:
        return None
    return {key: row[key] for key in CONTACT_COLUMNS}


def _model_to_dict(payload: ContactCreate | ContactUpdate, **kwargs: Any) -> dict[str, Any]:
    if hasattr(payload, "model_dump"):
        return payload.model_dump(**kwargs)
    return payload.dict(**kwargs)


def create_contact(
    connection: sqlite3.Connection, payload: ContactCreate
) -> dict[str, Any]:
    data = _model_to_dict(payload)
    values = [data.get(column) for column in WRITABLE_COLUMNS]
    placeholders = ", ".join("?" for _ in WRITABLE_COLUMNS)
    columns = ", ".join(WRITABLE_COLUMNS)
    cursor = connection.execute(
        f"INSERT INTO contacts ({columns}) VALUES ({placeholders})",
        values,
    )
    return get_contact(connection, cursor.lastrowid)


def get_contact(
    connection: sqlite3.Connection, contact_id: int
) -> dict[str, Any] | None:
    row = connection.execute(
        f"SELECT {', '.join(CONTACT_COLUMNS)} FROM contacts WHERE id = ?",
        (contact_id,),
    ).fetchone()
    return _row_to_dict(row)


def list_contacts(
    connection: sqlite3.Connection, limit: int = 50, offset: int = 0
) -> tuple[list[dict[str, Any]], int]:
    rows = connection.execute(
        f"""
        SELECT {', '.join(CONTACT_COLUMNS)}
        FROM contacts
        ORDER BY created_at DESC, id DESC
        LIMIT ? OFFSET ?
        """,
        (limit, offset),
    ).fetchall()
    total = connection.execute("SELECT COUNT(*) AS count FROM contacts").fetchone()
    return [_row_to_dict(row) for row in rows], total["count"]


def search_contacts(
    connection: sqlite3.Connection,
    query: str,
    limit: int = 50,
    offset: int = 0,
) -> tuple[list[dict[str, Any]], int]:
    pattern = f"%{query.strip()}%"
    params = (pattern, pattern, pattern, pattern, limit, offset)
    where_sql = """
    name LIKE ? COLLATE NOCASE
    OR company LIKE ? COLLATE NOCASE
    OR email LIKE ? COLLATE NOCASE
    OR phone LIKE ? COLLATE NOCASE
    """
    rows = connection.execute(
        f"""
        SELECT {', '.join(CONTACT_COLUMNS)}
        FROM contacts
        WHERE {where_sql}
        ORDER BY created_at DESC, id DESC
        LIMIT ? OFFSET ?
        """,
        params,
    ).fetchall()
    total = connection.execute(
        f"SELECT COUNT(*) AS count FROM contacts WHERE {where_sql}",
        params[:4],
    ).fetchone()
    return [_row_to_dict(row) for row in rows], total["count"]


def update_contact(
    connection: sqlite3.Connection, contact_id: int, payload: ContactUpdate
) -> dict[str, Any] | None:
    existing = get_contact(connection, contact_id)
    if existing is None:
        return None

    data = _model_to_dict(payload, exclude_unset=True)
    updates = {key: value for key, value in data.items() if key in WRITABLE_COLUMNS}
    if not updates:
        return existing

    set_sql = ", ".join(f"{column} = ?" for column in updates)
    values = list(updates.values())
    values.append(contact_id)
    connection.execute(
        f"""
        UPDATE contacts
        SET {set_sql}, updated_at = datetime('now')
        WHERE id = ?
        """,
        values,
    )
    return get_contact(connection, contact_id)


def delete_contact(connection: sqlite3.Connection, contact_id: int) -> bool:
    cursor = connection.execute("DELETE FROM contacts WHERE id = ?", (contact_id,))
    return cursor.rowcount > 0


def find_unreferenced_asset_paths(
    connection: sqlite3.Connection,
    paths: Iterable[str | None],
) -> list[str]:
    unique_paths = sorted({path.strip() for path in paths if path and path.strip()})
    unreferenced_paths = []
    for path in unique_paths:
        row = connection.execute(
            """
            SELECT COUNT(*) AS count
            FROM contacts
            WHERE image_path = ? OR crop_path = ?
            """,
            (path, path),
        ).fetchone()
        if row["count"] == 0:
            unreferenced_paths.append(path)
    return unreferenced_paths


def list_referenced_asset_paths(connection: sqlite3.Connection) -> set[str]:
    rows = connection.execute(
        """
        SELECT image_path, crop_path
        FROM contacts
        WHERE image_path IS NOT NULL OR crop_path IS NOT NULL
        """
    ).fetchall()
    referenced_paths: set[str] = set()
    for row in rows:
        for column in ("image_path", "crop_path"):
            value = row[column]
            if value and value.strip():
                referenced_paths.add(value.strip())
    return referenced_paths
