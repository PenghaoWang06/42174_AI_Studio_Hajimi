from fastapi import APIRouter, File, HTTPException, Query, UploadFile
from pydantic import BaseModel, Field

from app.services.detector import detector
from app.services.image_storage import resolve_storage_path, save_image_bytes
from app.services.ocr.service import ocr_service


router = APIRouter(prefix="/cards", tags=["cards"])


class CardDetectionBox(BaseModel):
    x1: float
    y1: float
    x2: float
    y2: float
    confidence: float
    class_id: int
    class_name: str
    crop_path: str
    crop_url: str


class CardDetectionResponse(BaseModel):
    image_path: str
    image_url: str
    image_width: int
    image_height: int
    detections: list[CardDetectionBox]


class ContactFieldsResponse(BaseModel):
    name: str | None = None
    company: str | None = None
    email: str | None = None
    phone: str | None = None


class OcrLineResponse(BaseModel):
    text: str
    confidence: float | None = None
    bbox: list[list[float]] | None = None


class CardExtractionRequest(BaseModel):
    image_path: str = Field(
        ...,
        description="Relative storage path such as crops/card.jpg or /storage/crops/card.jpg",
    )
    provider: str | None = Field(
        default=None,
        description="Optional OCR provider override: easyocr or openai",
    )


class CardExtractionResponse(BaseModel):
    provider: str
    raw_text: str
    fields: ContactFieldsResponse
    lines: list[OcrLineResponse]


@router.post("/detect", response_model=CardDetectionResponse)
async def detect_card(
    file: UploadFile = File(...),
    confidence: float = Query(default=0.25, ge=0.01, le=1.0),
) -> dict:
    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="Uploaded image is empty")

    try:
        stored = save_image_bytes(file.filename, content)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    try:
        result = detector.detect(stored.path, confidence=confidence)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except ModuleNotFoundError as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Missing detection dependency: {exc.name}",
        ) from exc

    return {
        "image_path": stored.relative_path,
        "image_url": stored.url,
        "image_width": result.image_width,
        "image_height": result.image_height,
        "detections": [
            {
                "x1": detection.x1,
                "y1": detection.y1,
                "x2": detection.x2,
                "y2": detection.y2,
                "confidence": detection.confidence,
                "class_id": detection.class_id,
                "class_name": detection.class_name,
                "crop_path": detection.crop_path,
                "crop_url": detection.crop_url,
            }
            for detection in result.detections
        ],
    }


@router.post("/extract", response_model=CardExtractionResponse)
def extract_card(payload: CardExtractionRequest) -> dict:
    try:
        image_path = resolve_storage_path(payload.image_path)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    try:
        result = ocr_service.extract(image_path, provider_name=payload.provider)
    except ModuleNotFoundError as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Missing OCR dependency: {exc.name}",
        ) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    return {
        "provider": result.provider,
        "raw_text": result.raw_text,
        "fields": {
            "name": result.fields.name,
            "company": result.fields.company,
            "email": result.fields.email,
            "phone": result.fields.phone,
        },
        "lines": [
            {
                "text": line.text,
                "confidence": line.confidence,
                "bbox": line.bbox,
            }
            for line in result.lines
        ],
    }
