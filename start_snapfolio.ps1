param(
    [int]$BackendPort = 8000,
    [int]$FrontendPort = 5173,
    [string]$FlutterPath = "D:\_Env\flutter\bin\flutter.bat"
)

$ErrorActionPreference = "Stop"

$RootDir = $PSScriptRoot
$BackendDir = Join-Path $RootDir "backend"
$FrontendDir = Join-Path $RootDir "frontend"
$PythonPath = Join-Path $BackendDir ".venv\Scripts\python.exe"

function Test-LocalPort {
    param([int]$Port)

    $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    return $null -ne $connection
}

function Resolve-FlutterPath {
    param([string]$PreferredPath)

    if (Test-Path -LiteralPath $PreferredPath) {
        return $PreferredPath
    }

    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($null -ne $flutterCommand) {
        return $flutterCommand.Source
    }

    throw "Flutter was not found. Install Flutter or pass -FlutterPath."
}

if (-not (Test-Path -LiteralPath $PythonPath)) {
    throw "Backend Python environment was not found at $PythonPath"
}

if (-not (Test-Path -LiteralPath (Join-Path $BackendDir "app\main.py"))) {
    throw "Backend application was not found in $BackendDir"
}

if (-not (Test-Path -LiteralPath (Join-Path $FrontendDir "pubspec.yaml"))) {
    throw "Frontend application was not found in $FrontendDir"
}

$ResolvedFlutterPath = Resolve-FlutterPath $FlutterPath
$ApiBaseUrl = "http://127.0.0.1:$BackendPort"
$FrontendUrl = "http://127.0.0.1:$FrontendPort"

if (Test-LocalPort $BackendPort) {
    Write-Host "Backend port $BackendPort is already in use. Skipping backend start."
} else {
    $backendCommand = "cd /d `"$BackendDir`" && `"$PythonPath`" -m uvicorn app.main:app --host 127.0.0.1 --port $BackendPort --reload"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/k", $backendCommand
    Write-Host "Started backend on $ApiBaseUrl"
}

if (Test-LocalPort $FrontendPort) {
    Write-Host "Frontend port $FrontendPort is already in use. Skipping frontend start."
} else {
    $frontendCommand = "cd /d `"$FrontendDir`" && `"$ResolvedFlutterPath`" run -d web-server --web-hostname 127.0.0.1 --web-port $FrontendPort --dart-define=API_BASE_URL=$ApiBaseUrl"
    Start-Process -FilePath "cmd.exe" -ArgumentList "/k", $frontendCommand
    Write-Host "Started frontend on $FrontendUrl"
}

Write-Host ""
Write-Host "Open $FrontendUrl"
Write-Host "Backend docs: $ApiBaseUrl/docs"
