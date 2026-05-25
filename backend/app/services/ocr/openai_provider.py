from pathlib import Path
import base64
import json
import mimetypes

from app.core.config import settings
from app.services.ocr.parser import parse_contact_fields
from app.services.ocr.schemas import ContactFields, OcrLine, OcrResult


OPENAI_PROMPT = """
Extract business card text from this image and return only JSON.
Use this schema:
{
  "raw_text": "all visible text with line breaks",
  "fields": {
    "name": null,
    "company": null,
    "email": null,
    "phone": null
  }
}
Use null when a field is not visible.
"""


class OpenAIOcrProvider:
    provider_name = "openai"

    def extract(self, image_path: Path) -> OcrResult:
        if not settings.openai_api_key:
            raise RuntimeError("OPENAI_API_KEY is required for OpenAI OCR")

        from openai import OpenAI

        client = OpenAI(api_key=settings.openai_api_key)
        response = client.responses.create(
            model=settings.openai_model,
            input=[
                {
                    "role": "user",
                    "content": [
                        {"type": "input_text", "text": OPENAI_PROMPT.strip()},
                        {
                            "type": "input_image",
                            "image_url": image_data_url(image_path),
                        },
                    ],
                }
            ],
        )
        output_text = response.output_text.strip()
        raw_text, fields = parse_openai_output(output_text)
        return OcrResult(
            provider=self.provider_name,
            raw_text=raw_text,
            fields=fields,
            lines=[OcrLine(text=line) for line in raw_text.splitlines() if line.strip()],
        )


def image_data_url(image_path: Path) -> str:
    mime_type, _ = mimetypes.guess_type(str(image_path))
    if mime_type is None:
        mime_type = "image/jpeg"
    encoded = base64.b64encode(image_path.read_bytes()).decode("utf-8")
    return f"data:{mime_type};base64,{encoded}"


def parse_openai_output(output_text: str) -> tuple[str, ContactFields]:
    try:
        payload = json.loads(output_text)
    except json.JSONDecodeError:
        raw_text = output_text
        return raw_text, parse_contact_fields(raw_text)

    raw_text = str(payload.get("raw_text") or "").strip()
    fields_payload = payload.get("fields") or {}
    fallback = parse_contact_fields(raw_text)
    return raw_text, ContactFields(
        name=fields_payload.get("name") or fallback.name,
        company=fields_payload.get("company") or fallback.company,
        email=fields_payload.get("email") or fallback.email,
        phone=fields_payload.get("phone") or fallback.phone,
    )
