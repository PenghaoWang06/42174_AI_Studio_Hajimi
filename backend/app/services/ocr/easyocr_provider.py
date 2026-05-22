from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image

from app.core.config import settings
from app.services.ocr.parser import parse_contact_fields
from app.services.ocr.schemas import OcrLine, OcrResult


class EasyOcrProvider:
    provider_name = "easyocr"

    def __init__(self) -> None:
        self._reader = None

    def _load_reader(self) -> Any:
        if self._reader is None:
            import easyocr

            self._reader = easyocr.Reader(
                list(settings.easyocr_languages),
                gpu=False,
                verbose=False,
            )
        return self._reader

    def extract(self, image_path: Path) -> OcrResult:
        reader = self._load_reader()
        with Image.open(image_path) as image:
            image_array = np.array(image.convert("L"))
        entries = reader.readtext(image_array, detail=1, paragraph=False)
        lines = [entry_to_line(entry) for entry in entries]
        lines.sort(key=line_sort_key)
        raw_text = "\n".join(line.text for line in lines)
        return OcrResult(
            provider=self.provider_name,
            raw_text=raw_text,
            fields=parse_contact_fields(raw_text),
            lines=lines,
        )


def entry_to_line(entry: Any) -> OcrLine:
    bbox, text, confidence = entry
    return OcrLine(
        text=str(text).strip(),
        confidence=float(confidence),
        bbox=[[float(point[0]), float(point[1])] for point in bbox],
    )


def line_sort_key(line: OcrLine) -> tuple[float, float]:
    if not line.bbox:
        return (0.0, 0.0)
    xs = [point[0] for point in line.bbox]
    ys = [point[1] for point in line.bbox]
    return (min(ys), min(xs))
