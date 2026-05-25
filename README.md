# SnapFolio

SnapFolio is a local demo app for business card detection, OCR extraction, and contact management.

The app uses a FastAPI backend, a Flutter frontend, and a YOLO model for business card detection.

## Model

The backend loads this model file:

```text
backend/models/model.pt
```

The model path is fixed in `backend/app/core/config.py`. There is no fallback model path and no environment variable override. If the model file is missing, the backend raises `FileNotFoundError` when the detector loads.

## Run Locally

Open the app after both backend and frontend are running:

```text
http://127.0.0.1:5173
```

### Backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Open the backend API docs:

```text
http://127.0.0.1:8000/docs
```

### Frontend

Flutter is required to run the frontend.

```powershell
cd frontend
flutter create .
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

For Android emulator:

```powershell
flutter run -d emulator --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

For a physical device, replace the API URL with the backend machine LAN IP:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

### Windows Helper

Run:

```powershell
.\start_snapfolio_windows.cmd
```

The script creates the backend virtual environment if needed, installs backend dependencies, runs `flutter pub get`, and starts the backend and frontend.

### macOS Helper

Run once:

```bash
chmod +x start_snapfolio_macos.command
```

Then run:

```bash
./start_snapfolio_macos.command
```

## Backend API

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

## Environment

```text
SNAPFOLIO_DATABASE_PATH=backend/storage/business_card_contacts.sqlite3
SNAPFOLIO_CORS_ORIGINS=http://localhost:5173,http://127.0.0.1:5173
SNAPFOLIO_OCR_PROVIDER=easyocr
SNAPFOLIO_EASYOCR_LANGUAGES=en
OPENAI_API_KEY=
SNAPFOLIO_OPENAI_MODEL=gpt-4.1-mini
```

## Notes

Training notebooks and model experiment outputs are kept under `ml/`. The backend does not load models from the training output folders.
