from pathlib import Path

from app.core.config import settings
from app.services.ocr.easyocr_provider import EasyOcrProvider
from app.services.ocr.openai_provider import OpenAIOcrProvider
from app.services.ocr.schemas import OcrResult


class OcrService:
    def __init__(self) -> None:
        self._providers = {
            "easyocr": EasyOcrProvider(),
            "openai": OpenAIOcrProvider(),
        }

    def extract(self, image_path: Path, provider_name: str | None = None) -> OcrResult:
        name = (provider_name or settings.ocr_provider).lower()
        provider = self._providers.get(name)
        if provider is None:
            supported = ", ".join(sorted(self._providers))
            raise ValueError(f"Unsupported OCR provider '{name}'. Supported: {supported}")
        return provider.extract(image_path)


ocr_service = OcrService()
