# SENTINELA - Build com PyWebView (Uvicorn)
# =======================================

$ROOT = $PSScriptRoot
Set-Location $ROOT

Write-Host "Iniciando Build do Sentinela (PyWebView + Uvicorn)..." -ForegroundColor Cyan

$PY = "$ROOT\.venv\Scripts\python.exe"
if (!(Test-Path $PY)) {
    Write-Host "Erro: Ambiente virtual nao encontrado em .venv!" -ForegroundColor Red
    exit 1
}

# 1. INSTALAR DEPENDENCIAS DESKTOP
Write-Host "`n[1/4] Instalando dependencias desktop..." -ForegroundColor Yellow
& $PY -m pip install uvicorn pywebview pyinstaller pywinstyles --quiet
if ($LASTEXITCODE -ne 0) {
    Write-Host "Erro ao instalar dependencias desktop." -ForegroundColor Red
    exit $LASTEXITCODE
}

# 2. BUILD DO FRONTEND
Write-Host "`n[2/4] Construindo o Frontend Vue..." -ForegroundColor Yellow
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

# 3. BUILD DO SENTINELA UPDATER (deve preceder o Sentinela.exe, que o embute)
Write-Host "`n[3/4] Gerando SentinelaUpdater.exe..." -ForegroundColor Yellow
& $PY -m PyInstaller --noconfirm SentinelaUpdater.spec
if ($LASTEXITCODE -ne 0) {
    Write-Host "Erro ao gerar SentinelaUpdater.exe." -ForegroundColor Red
    exit $LASTEXITCODE
}
if (!(Test-Path "dist/SentinelaUpdater.exe")) {
    Write-Host "Erro: dist/SentinelaUpdater.exe nao foi gerado." -ForegroundColor Red
    exit 1
}
$sizeU = [math]::Round((Get-Item "dist/SentinelaUpdater.exe").Length / 1MB, 1)
Write-Host "SentinelaUpdater.exe gerado: $sizeU MB" -ForegroundColor Gray

# 4. BUILD DO EXECUTAVEL PRINCIPAL (embute SentinelaUpdater.exe via Sentinela.spec)
Write-Host "`n[4/4] Gerando Sentinela.exe..." -ForegroundColor Yellow
& $PY -m PyInstaller --noconfirm Sentinela.spec
if ($LASTEXITCODE -ne 0) {
    Write-Host "Erro ao gerar Sentinela.exe." -ForegroundColor Red
    exit $LASTEXITCODE
}

if (!(Test-Path "dist/Sentinela.exe")) {
    Write-Host "Erro: dist/Sentinela.exe nao foi gerado." -ForegroundColor Red
    exit 1
}

Write-Host "`nBUILD CONCLUIDO!" -ForegroundColor Green
Write-Host "Executaveis em: dist/" -ForegroundColor Yellow

$size = [math]::Round((Get-Item "dist/Sentinela.exe").Length / 1MB, 1)
Write-Host "  Sentinela.exe      : $size MB" -ForegroundColor Gray
Write-Host "  SentinelaUpdater.exe: $sizeU MB" -ForegroundColor Gray
