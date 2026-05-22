from pathlib import Path
import tempfile
import unittest

from fastapi.testclient import TestClient


class FakeDetector:
    def detect(self, image_path: Path, confidence: float | None = None):
        from app.services.detector import Detection, DetectionResult

        return DetectionResult(
            image_width=100,
            image_height=100,
            detections=[
                Detection(
                    x1=10,
                    y1=20,
                    x2=90,
                    y2=80,
                    confidence=0.88,
                    class_id=0,
                    class_name="Business Card",
                    crop_path="crops/test-card.jpg",
                    crop_url="/storage/crops/test-card.jpg",
                )
            ],
        )


class FakeOcrService:
    def extract(self, image_path: Path, provider_name: str | None = None):
        from app.services.ocr.schemas import ContactFields, OcrLine, OcrResult

        return OcrResult(
            provider=provider_name or "easyocr",
            raw_text="John Smith\nExample Pty Ltd\njohn@example.com\n+61 400 000 000",
            fields=ContactFields(
                name="John Smith",
                company="Example Pty Ltd",
                email="john@example.com",
                phone="+61 400 000 000",
            ),
            lines=[
                OcrLine(text="John Smith", confidence=0.95),
                OcrLine(text="Example Pty Ltd", confidence=0.92),
            ],
        )


class ApiWorkflowTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)

        from app.core.config import settings
        from app.db.database import init_db
        from app.services.image_storage import ensure_storage_dirs

        self.original_paths = {
            "database_path": settings.database_path,
            "storage_dir": settings.storage_dir,
            "upload_dir": settings.upload_dir,
            "crop_dir": settings.crop_dir,
        }
        object.__setattr__(
            settings, "database_path", self.root / "business_card_contacts.sqlite3"
        )
        object.__setattr__(settings, "storage_dir", self.root / "storage")
        object.__setattr__(settings, "upload_dir", self.root / "storage" / "uploads")
        object.__setattr__(settings, "crop_dir", self.root / "storage" / "crops")
        ensure_storage_dirs()
        init_db()
        (settings.crop_dir / "test-card.jpg").write_bytes(b"fake image")

        from app.api import cards
        from app.main import app

        self.original_detector = cards.detector
        self.original_ocr_service = cards.ocr_service
        cards.detector = FakeDetector()
        cards.ocr_service = FakeOcrService()
        self.client = TestClient(app)

    def tearDown(self) -> None:
        from app.api import cards
        from app.core.config import settings

        cards.detector = self.original_detector
        cards.ocr_service = self.original_ocr_service
        for key, value in self.original_paths.items():
            object.__setattr__(settings, key, value)
        self.temp_dir.cleanup()

    def test_detect_extract_and_save_contact(self) -> None:
        detect_response = self.client.post(
            "/cards/detect",
            files={"file": ("card.jpg", b"image bytes", "image/jpeg")},
        )
        self.assertEqual(detect_response.status_code, 200)
        detection_payload = detect_response.json()
        self.assertEqual(len(detection_payload["detections"]), 1)
        self.assertEqual(
            detection_payload["detections"][0]["crop_path"],
            "crops/test-card.jpg",
        )

        extract_response = self.client.post(
            "/cards/extract",
            json={"image_path": "crops/test-card.jpg", "provider": "easyocr"},
        )
        self.assertEqual(extract_response.status_code, 200)
        extraction_payload = extract_response.json()
        self.assertEqual(extraction_payload["fields"]["name"], "John Smith")
        self.assertEqual(extraction_payload["fields"]["email"], "john@example.com")

        contact_response = self.client.post(
            "/contacts",
            json={
                "name": extraction_payload["fields"]["name"],
                "company": extraction_payload["fields"]["company"],
                "email": extraction_payload["fields"]["email"],
                "phone": extraction_payload["fields"]["phone"],
                "raw_text": extraction_payload["raw_text"],
                "image_path": detection_payload["image_path"],
                "crop_path": detection_payload["detections"][0]["crop_path"],
            },
        )
        self.assertEqual(contact_response.status_code, 201)
        contact_payload = contact_response.json()
        upload_path = self.root / "storage" / detection_payload["image_path"]
        crop_path = self.root / "storage" / detection_payload["detections"][0]["crop_path"]
        self.assertTrue(upload_path.exists())
        self.assertTrue(crop_path.exists())

        search_response = self.client.get("/contacts/search?q=example")
        self.assertEqual(search_response.status_code, 200)
        search_payload = search_response.json()
        self.assertEqual(search_payload["total"], 1)
        self.assertEqual(search_payload["items"][0]["name"], "John Smith")

        delete_response = self.client.delete(f"/contacts/{contact_payload['id']}")
        self.assertEqual(delete_response.status_code, 204)
        self.assertFalse(upload_path.exists())
        self.assertFalse(crop_path.exists())


if __name__ == "__main__":
    unittest.main()
