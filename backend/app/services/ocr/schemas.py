from dataclasses import dataclass


@dataclass(frozen=True)
class OcrLine:
    text: str
    confidence: float | None = None
    bbox: list[list[float]] | None = None


@dataclass(frozen=True)
class ContactFields:
    name: str | None = None
    company: str | None = None
    email: str | None = None
    phone: str | None = None


@dataclass(frozen=True)
class OcrResult:
    provider: str
    raw_text: str
    fields: ContactFields
    lines: list[OcrLine]
