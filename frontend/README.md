# SnapFolio Flutter Frontend

Flutter frontend for the SnapFolio business card scanner.

## Status

This directory contains the Flutter application source code. Flutter is not available in the current shell environment, so platform folders were not generated here.

## Setup

Install Flutter, then run:

```powershell
cd frontend
flutter create .
flutter pub get
```

## Run

For Flutter Web:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

For Android emulator:

```powershell
flutter run -d emulator --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

For iOS simulator:

```powershell
flutter run -d ios --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

For a physical phone, use the backend machine LAN address:

```powershell
flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8000
```

## Features

- Pick a business card image from the device
- Upload the image to `POST /cards/detect`
- Display detection boxes over the image
- Extract OCR fields with `POST /cards/extract`
- Review and edit extracted contact fields
- Save contacts with `POST /contacts`
- List and search saved contacts

The backend must be running before using the app.
