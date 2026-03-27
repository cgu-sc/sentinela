# SENTINELA - Build com PyWebView (Leve)
# =======================================

$ROOT = $PSScriptRoot
Set-Location $ROOT

Write-Host "Iniciando Build do Sentinela (PyWebView)..." -ForegroundColor Cyan

$PY = "$ROOT\.venv\Scripts\python.exe"
if (!(Test-Path $PY)) {
    Write-Host "Erro: Ambiente virtual nao encontrado em .venv!" -ForegroundColor Red
    exit 1
}

# 1. INSTALAR PYWEBVIEW
Write-Host "`n[1/3] Instalando PyWebView..." -ForegroundColor Yellow
& $PY -m pip install pywebview --quiet

# 2. BUILD DO FRONTEND
Write-Host "`n[2/3] Construindo o Frontend Vue..." -ForegroundColor Yellow
Set-Location "$ROOT/frontend"
npm install --silent
npm run build
Set-Location $ROOT

# 3. BUILD DO EXECUTAVEL
Write-Host "`n[3/3] Gerando executavel..." -ForegroundColor Yellow

& $PY -m PyInstaller --noconfirm --onefile --console `
    --name "Sentinela" `
    --icon "src-tauri/icons/icon.ico" `
    --paths "backend" `
    --add-data "frontend/dist;frontend/dist" `
    --add-data "backend;backend" `
    --hidden-import "pyodbc" `
    --hidden-import "uvicorn" `
    --hidden-import "webview" `
    --hidden-import "clr" `
    desktop.py

Write-Host "`nBUILD CONCLUIDO!" -ForegroundColor Green
Write-Host "Executavel em: dist/Sentinela.exe" -ForegroundColor Yellow

# Mostrar tamanho
$size = [math]::Round((Get-Item "dist/Sentinela.exe").Length / 1MB, 1)
Write-Host "Tamanho: $size MB" -ForegroundColor Gray
