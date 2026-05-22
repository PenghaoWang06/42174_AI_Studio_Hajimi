from dataclasses import dataclass
from pathlib import Path
from uuid import uuid4

from PIL import Image

from app.core.config import settings
from app.services.image_storage import stored_image


@dataclass(frozen=True)
class Detection:
    x1: float
    y1: float
    x2: float
    y2: float
    confidence: float
    class_id: int
    class_name: str
    crop_path: str
    crop_url: str


@dataclass(frozen=True)
class DetectionResult:
    image_width: int
    image_height: int
    detections: list[Detection]


class BusinessCardDetector:
    def __init__(self, model_path: Path | None = None, confidence: float = 0.25) -> None:
        self.model_path = Path(model_path or settings.model_path)
        self.confidence = confidence
        self._model = None

    def _load_model(self):
        if self._model is None:
            if not self.model_path.exists():
                raise FileNotFoundError(f"Model file not found: {self.model_path}")
            from ultralytics import YOLO

            self._model = YOLO(str(self.model_path))
        return self._model

    def detect(self, image_path: Path, confidence: float | None = None) -> DetectionResult:
        with Image.open(image_path) as image:
            image_width, image_height = image.size

        model = self._load_model()
        results = model.predict(
            source=str(image_path),
            conf=self.confidence if confidence is None else confidence,
            save=False,
            verbose=False,
        )
        if not results:
            return DetectionResult(
                image_width=image_width,
                image_height=image_height,
                detections=[],
            )

        result = results[0]
        names = getattr(result, "names", {}) or {}
        detections: list[Detection] = []

        boxes = getattr(result, "boxes", None)
        if boxes is None:
            return DetectionResult(
                image_width=image_width,
                image_height=image_height,
                detections=[],
            )

        for index, box in enumerate(boxes):
            x1, y1, x2, y2 = [float(value) for value in box.xyxy[0].tolist()]
            confidence = float(box.conf[0])
            class_id = int(box.cls[0])
            class_name = names.get(class_id, str(class_id))
            crop = self._save_crop(image_path, (x1, y1, x2, y2), index)
            detections.append(
                Detection(
                    x1=x1,
                    y1=y1,
                    x2=x2,
                    y2=y2,
                    confidence=confidence,
                    class_id=class_id,
                    class_name=class_name,
                    crop_path=crop.relative_path,
                    crop_url=crop.url,
                )
            )

        detections.sort(key=lambda detection: detection.confidence, reverse=True)
        return DetectionResult(
            image_width=image_width,
            image_height=image_height,
            detections=detections,
        )

    def _save_crop(
        self,
        image_path: Path,
        xyxy: tuple[float, float, float, float],
        index: int,
    ):
        settings.crop_dir.mkdir(parents=True, exist_ok=True)
        with Image.open(image_path) as image:
            width, height = image.size
            x1, y1, x2, y2 = clamp_box(xyxy, width, height)
            crop = image.crop((x1, y1, x2, y2))
            if crop.mode not in ("RGB", "L"):
                crop = crop.convert("RGB")
            suffix = ".jpg" if image_path.suffix.lower() in {".jpg", ".jpeg"} else ".png"
            target = settings.crop_dir / f"{image_path.stem}_{index}_{uuid4().hex}{suffix}"
            crop.save(target)
        return stored_image(target)


def clamp_box(
    xyxy: tuple[float, float, float, float],
    width: int,
    height: int,
) -> tuple[int, int, int, int]:
    x1, y1, x2, y2 = xyxy
    left = max(0, min(width - 1, int(round(x1))))
    top = max(0, min(height - 1, int(round(y1))))
    right = max(left + 1, min(width, int(round(x2))))
    bottom = max(top + 1, min(height, int(round(y2))))
    return left, top, right, bottom


detector = BusinessCardDetector()
