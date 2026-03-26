# SENTINELA - Script de Build (Tauri + FastAPI Sidecar)
# =====================================================

$ROOT = $PSScriptRoot
Set-Location $ROOT

Write-Host "Iniciando Build do Sentinela..." -ForegroundColor Cyan

# 1. BUILD DO FRONTEND (VUE)
Write-Host "`n[1/3] Construindo o Frontend Vue..." -ForegroundColor Yellow
Set-Location "$ROOT/frontend"
npm install
npm run build
Set-Location $ROOT

# 2. BUILD DO BACKEND (PYTHON SIDECAR)
Write-Host "`n[2/3] Compilando o Backend FastAPI..." -ForegroundColor Yellow

$PY = "$ROOT\.venv\Scripts\python.exe"
if (!(Test-Path $PY)) {
    Write-Host "Erro: Ambiente virtual nao encontrado em .venv!" -ForegroundColor Red
    Write-Host "Execute: python -m venv .venv" -ForegroundColor Yellow
    exit 1
}

# Compila o backend com PyInstaller
& $PY -m PyInstaller --noconfirm --onefile --console `
    --name "sentinela-api" `
    --paths "backend" `
    --add-data "frontend/dist;frontend/dist" `
    --hidden-import "pyodbc" `
    --hidden-import "uvicorn" `
    backend/main.py

# Copia para a pasta bin do Tauri (padrao)
$BIN_DIR = "$ROOT/src-tauri/bin"
if (!(Test-Path $BIN_DIR)) {
    New-Item -ItemType Directory -Force -Path $BIN_DIR
}
Copy-Item "$ROOT/dist/sentinela-api.exe" "$BIN_DIR/sentinela-api-x86_64-pc-windows-msvc.exe" -Force

Write-Host "Sidecar copiado para: $BIN_DIR" -ForegroundColor Gray

# 3. BUILD DO TAURI
Write-Host "`n[3/3] Gerando o executavel Tauri..." -ForegroundColor Yellow
Set-Location $ROOT
cargo tauri build --no-bundle

# 4. ORGANIZAR DIST
Write-Host "`n[4/4] Organizando pasta dist..." -ForegroundColor Yellow

$DIST_DIR = "$ROOT/dist/sentinela"
if (Test-Path $DIST_DIR) {
    Remove-Item -Recurse -Force $DIST_DIR
}
New-Item -ItemType Directory -Force -Path $DIST_DIR | Out-Null

Copy-Item "$ROOT/src-tauri/target/release/sentinela.exe" "$DIST_DIR/sentinela.exe" -Force
Copy-Item "$BIN_DIR/sentinela-api-x86_64-pc-windows-msvc.exe" "$DIST_DIR/sentinela-api-x86_64-pc-windows-msvc.exe" -Force

Write-Host "`nBUILD CONCLUIDO!" -ForegroundColor Green
Write-Host "Pasta pronta para distribuicao: dist/sentinela/" -ForegroundColor Yellow
Write-Host "  - sentinela.exe" -ForegroundColor Gray
Write-Host "  - sentinela-api-x86_64-pc-windows-msvc.exe" -ForegroundColor Gray
