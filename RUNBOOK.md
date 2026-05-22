# SnapFolio Local Runbook

This runbook explains how to run the local product demo.

## One Command

Double-click:

```text
start_snapfolio.cmd
```

Or run:

```powershell
.\start_snapfolio.ps1
```

Open:

```text
http://127.0.0.1:5173
```

## Backend

```powershell
cd backend
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Open:

```text
http://127.0.0.1:8000/docs
```

The backend exposes:

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

## Flutter Frontend

Flutter is required to generate platform folders and run the app.

```powershell
cd frontend
flutter create .
flutter pub get
```

Run on Flutter Web:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

Run on Android emulator:

```powershell
flutter run -d emulator --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Run on a physical device by replacing the URL with the backend machine LAN IP:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

## Verification

Run backend tests:

```powershell
cd ..
$env:PYTHONPATH = "backend"
backend\.venv\Scripts\python.exe -m unittest discover -s backend\tests
```

Expected result:

```text
OK
```
