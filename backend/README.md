# SnapFolio Backend

FastAPI backend for the SnapFolio business card contact workflow.

## Features

- Health check endpoint
- SQLite contact database
- Contact create, list, search, read, update, and delete APIs
- Business card image upload and YOLO detection API
- OCR extraction with EasyOCR by default
- Optional OpenAI Vision OCR provider
- Local storage for uploaded images and cropped detections
- CORS enabled for a local Flutter frontend

## Setup

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

## Run

```powershell
uvicorn app.main:app --reload --host 127.0.0.1 --port 8000
```

The API will create the SQLite database at `backend/storage/business_card_contacts.sqlite3`.
Uploaded images and crops are saved under `backend/storage/`.

## Environment

```text
SNAPFOLIO_DATABASE_PATH=backend/storage/business_card_contacts.sqlite3
SNAPFOLIO_CORS_ORIGINS=http://localhost:5173,http://127.0.0.1:5173
SNAPFOLIO_OCR_PROVIDER=easyocr
SNAPFOLIO_EASYOCR_LANGUAGES=en
OPENAI_API_KEY=
SNAPFOLIO_OPENAI_MODEL=gpt-4.1-mini
```

## Endpoints

```text
GET    /health
POST   /cards/detect
POST   /cards/extract
POST   /contacts
GET    /contacts
GET    /contacts/search?q=
GET    /contacts/{id}
PUT    /contacts/{id}
DELETE /contacts/{id}
```

## Card Detection

`POST /cards/detect` accepts a multipart image upload.

```powershell
curl.exe -X POST "http://127.0.0.1:8000/cards/detect" `
  -F "file=@..\ml\dataset\113.jpg"
```

Example response:

```json
{
  "image_path": "uploads/image.jpg",
  "image_url": "/storage/uploads/image.jpg",
  "image_width": 1024,
  "image_height": 1024,
  "detections": [
    {
      "x1": 100.0,
      "y1": 120.0,
      "x2": 900.0,
      "y2": 680.0,
      "confidence": 0.91,
      "class_id": 0,
      "class_name": "Business Card",
      "crop_path": "crops/card.jpg",
      "crop_url": "/storage/crops/card.jpg"
    }
  ]
}
```

## OCR Extraction

`POST /cards/extract` accepts a stored image path from `/cards/detect`.

```powershell
Invoke-RestMethod `
  -Method Post `
  -Uri "http://127.0.0.1:8000/cards/extract" `
  -ContentType "application/json" `
  -Body '{"image_path":"crops/card.jpg","provider":"easyocr"}'
```

Example response:

```json
{
  "provider": "easyocr",
  "raw_text": "John Smith\nExample Pty Ltd\njohn@example.com",
  "fields": {
    "name": "John Smith",
    "company": "Example Pty Ltd",
    "email": "john@example.com",
    "phone": "+61 400 000 000"
  },
  "lines": [
    {
      "text": "John Smith",
      "confidence": 0.95,
      "bbox": [[10.0, 20.0], [120.0, 20.0], [120.0, 48.0], [10.0, 48.0]]
    }
  ]
}
```

Set `"provider": "openai"` to use the OpenAI provider. It requires `OPENAI_API_KEY`.

## Contact Payload

```json
{
  "name": "John Smith",
  "company": "Example Pty Ltd",
  "email": "john@example.com",
  "phone": "+61 400 000 000",
  "raw_text": "John Smith\nExample Pty Ltd\njohn@example.com",
  "image_path": "storage/uploads/card.jpg",
  "crop_path": "storage/crops/card.jpg"
}
```
