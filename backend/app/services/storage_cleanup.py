from collections.abc import Iterable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path

from app.core.config import settings
from app.services.image_storage import resolve_storage_path


@dataclass(frozen=True)
class CleanupPlan:
    orphan_paths: list[str]
    deleted_paths: list[str]


def delete_storage_files(relative_paths: Iterable[str]) -> list[str]:
    deleted_paths = []
    for relative_path in sorted(set(relative_paths)):
        try:
            path = resolve_storage_path(relative_path)
            path.unlink()
            deleted_paths.append(relative_path)
        except (FileNotFoundError, OSError, ValueError):
            continue
    return deleted_paths


def cleanup_orphan_storage_files(
    referenced_paths: set[str],
    max_age_hours: float = 24,
    dry_run: bool = True,
) -> CleanupPlan:
    orphan_paths = find_orphan_storage_files(
        referenced_paths=referenced_paths,
        max_age_hours=max_age_hours,
    )
    deleted_paths = [] if dry_run else delete_storage_files(orphan_paths)
    return CleanupPlan(orphan_paths=orphan_paths, deleted_paths=deleted_paths)


def find_orphan_storage_files(
    referenced_paths: set[str],
    max_age_hours: float = 24,
) -> list[str]:
    cutoff = datetime.now(timezone.utc) - timedelta(hours=max_age_hours)
    orphan_paths = []
    for directory in (settings.upload_dir, settings.crop_dir):
        if not directory.exists():
            continue
        for path in directory.iterdir():
            if not path.is_file():
                continue
            relative_path = path.relative_to(settings.storage_dir).as_posix()
            if relative_path in referenced_paths:
                continue
            modified_at = datetime.fromtimestamp(path.stat().st_mtime, timezone.utc)
            if modified_at <= cutoff:
                orphan_paths.append(relative_path)
    return sorted(orphan_paths)
