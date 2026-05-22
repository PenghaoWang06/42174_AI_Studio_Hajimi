from dataclasses import dataclass
from pathlib import Path
import os

from dotenv import load_dotenv


PROJECT_DIR = Path(__file__).resolve().parents[3]
BACKEND_DIR = Path(__file__).resolve().parents[2]

load_dotenv(BACKEND_DIR / ".env")


def _split_csv(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def _default_model_path() -> Path:
    training_root = PROJECT_DIR / "runs" / "detect" / "Training_Log"
    candidates = sorted(
        training_root.glob("*/weights/best.pt"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if candidates:
        return candidates[0]
    return training_root / "SnapFolio_Final_Battle" / "weights" / "best.pt"


@dataclass(frozen=True)
class Settings:
    app_name: str = "SnapFolio API"
    project_dir: Path = PROJECT_DIR
    backend_dir: Path = BACKEND_DIR
    database_path: Path = Path(
        os.getenv(
            "SNAPFOLIO_DATABASE_PATH",
            BACKEND_DIR / "storage" / "business_card_contacts.sqlite3",
        )
    )
    storage_dir: Path = Path(os.getenv("SNAPFOLIO_STORAGE_DIR", BACKEND_DIR / "storage"))
    upload_dir: Path = Path(os.getenv("SNAPFOLIO_UPLOAD_DIR", BACKEND_DIR / "storage" / "uploads"))
    crop_dir: Path = Path(os.getenv("SNAPFOLIO_CROP_DIR", BACKEND_DIR / "storage" / "crops"))
    model_path: Path = Path(
        os.getenv(
            "SNAPFOLIO_MODEL_PATH",
            _default_model_path(),
        )
    )
    ocr_provider: str = os.getenv("SNAPFOLIO_OCR_PROVIDER", "easyocr")
    easyocr_languages: tuple[str, ...] = tuple(
        _split_csv(os.getenv("SNAPFOLIO_EASYOCR_LANGUAGES", "en"))
    )
    openai_api_key: str | None = os.getenv("OPENAI_API_KEY")
    openai_model: str = os.getenv("SNAPFOLIO_OPENAI_MODEL", "gpt-4.1-mini")
    cors_origins: tuple[str, ...] = tuple(
        _split_csv(
            os.getenv(
                "SNAPFOLIO_CORS_ORIGINS",
                "http://localhost:5173,http://127.0.0.1:5173",
            )
        )
    )


settings = Settings()
