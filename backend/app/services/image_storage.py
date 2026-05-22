from dataclasses import dataclass
from pathlib import Path
from uuid import uuid4

from app.core.config import settings


ALLOWED_IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}


@dataclass(frozen=True)
class StoredImage:
    path: Path
    relative_path: str
    url: str


def ensure_storage_dirs() -> None:
    settings.upload_dir.mkdir(parents=True, exist_ok=True)
    settings.crop_dir.mkdir(parents=True, exist_ok=True)


def image_suffix(filename: str | None) -> str:
    suffix = Path(filename or "").suffix.lower()
    if suffix not in ALLOWED_IMAGE_SUFFIXES:
        raise ValueError("Unsupported image type")
    return suffix


def storage_url(path: Path) -> str:
    relative_path = path.relative_to(settings.storage_dir).as_posix()
    return f"/storage/{relative_path}"


def stored_image(path: Path) -> StoredImage:
    relative_path = path.relative_to(settings.storage_dir).as_posix()
    return StoredImage(path=path, relative_path=relative_path, url=f"/storage/{relative_path}")


def resolve_storage_path(relative_path: str) -> Path:
    clean_path = relative_path.removeprefix("/storage/").lstrip("/\\")
    root = settings.storage_dir.resolve()
    target = (settings.storage_dir / clean_path).resolve()
    try:
        target.relative_to(root)
    except ValueError as exc:
        raise ValueError("Storage path is outside the storage directory") from exc
    if not target.exists() or not target.is_file():
        raise FileNotFoundError(f"Storage file not found: {relative_path}")
    return target


def save_image_bytes(filename: str | None, content: bytes) -> StoredImage:
    ensure_storage_dirs()
    suffix = image_suffix(filename)
    target = settings.upload_dir / f"{uuid4().hex}{suffix}"
    target.write_bytes(content)
    return stored_image(target)
