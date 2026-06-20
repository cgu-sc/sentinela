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

# 1. INSTALAR DEPENDENCIAS DESKTOP
Write-Host "`n[1/3] Instalando dependencias desktop..." -ForegroundColor Yellow
& $PY -m pip install granian pywebview pyinstaller --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host "Erro ao instalar dependencias desktop." -ForegroundColor Red
    exit $LASTEXITCODE
}

# 2. BUILD DO FRONTEND
Write-Host "`n[2/3] Construindo o Frontend Vue..." -ForegroundColor Yellow
Set-Location "$ROOT/frontend"
npm install --silent
if ($LASTEXITCODE -ne 0) {
    Write-Host "Erro ao instalar dependencias do frontend." -ForegroundColor Red
    exit $LASTEXITCODE
}
npm run build
if ($LASTEXITCODE -ne 0) {
    Write-Host "Erro ao construir o frontend." -ForegroundColor Red
    exit $LASTEXITCODE
}
Set-Location $ROOT

# 3. BUILD DO EXECUTAVEL
Write-Host "`n[3/3] Gerando executavel..." -ForegroundColor Yellow

& $PY -m PyInstaller --noconfirm --onefile --console `
    --name "sentinela_server2" `
    --icon "frontend/public/img/icon.ico" `
    --paths "backend" `
    --add-data "frontend/dist;frontend/dist" `
    --add-data "backend;backend" `
    --add-data "version.json;." `
    --add-data "backend/data/update_manifest_public_key.pem;backend/data" `
    --hidden-import "pyodbc" `
    --hidden-import "uvicorn" `
    --hidden-import "granian" `
    --hidden-import "webview" `
    --hidden-import "clr" `
    --hidden-import "cryptography" `
    --hidden-import "httpx" `
    --hidden-import "packaging" `
    desktop_granian.py

if ($LASTEXITCODE -ne 0) {
    Write-Host "Erro ao gerar executavel." -ForegroundColor Red
    exit $LASTEXITCODE
}

if (!(Test-Path "dist/sentinela_server2.exe")) {
    Write-Host "Erro: dist/sentinela_server2.exe nao foi gerado." -ForegroundColor Red
    exit 1
}

Write-Host "`nBUILD CONCLUIDO!" -ForegroundColor Green
Write-Host "Executavel em: dist/sentinela_server2.exe" -ForegroundColor Yellow

# Mostrar tamanho
$size = [math]::Round((Get-Item "dist/sentinela_server2.exe").Length / 1MB, 1)
Write-Host "Tamanho: $size MB" -ForegroundColor Gray
