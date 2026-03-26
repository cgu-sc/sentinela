# SENTINELA - Script de Build Automatizado para EXE (Tauri + FastAPI)
# ==============================================================================

# Garantir que o script use a pasta onde ele está localizado
$ROOT = $PSScriptRoot
Set-Location $ROOT

Write-Host "🚀 Iniciando Build do Sentinela Web/Desktop..." -ForegroundColor Cyan

# 1. BUILD DO FRONTEND (VUE + PRIMEVUE)
Write-Host "`n1/3: Construindo o Frontend Vue..." -ForegroundColor Yellow
if (!(Test-Path "frontend/public")) { New-Item -ItemType Directory -Path "frontend/public" -Force }

# Copia o logo para a pasta public do frontend (se existir na src do projeto)
if (Test-Path "src/logo_sentinela.png") {
    Copy-Item "src/logo_sentinela.png" "frontend/public/logo_sentinela.png" -Force
}

cd frontend
npm install
npm run build
cd ..

# Copiamos o build do frontend para ficar acessível ao Backend
New-Item -ItemType Directory -Force -Path "frontend/dist"
if (!(Test-Path "dist/frontend")) { New-Item -ItemType Directory -Force -Path "dist/frontend" }
Copy-Item -Recurse -Force "frontend/dist" "dist/frontend"

# 2. BUILD DO BACKEND (PYTHON SIDECAR)
Write-Host "`n2/3: Compilando o Backend FastAPI (Sidecar)..." -ForegroundColor Yellow

# Define o caminho do Python local para evitar conflitos com pastas antigas
$PY = "$ROOT\.venv\Scripts\python.exe"
if (!(Test-Path $PY)) {
    Write-Host "❌ Erro: Ambiente virtual não encontrado em .venv! Rode 'python -m venv .venv' primeiro." -ForegroundColor Red
    exit
}

# Criamos o binário do backend de forma que o Tauri consiga consumir como sidecar
& $PY -m PyInstaller --noconfirm --onefile --console `
    --name "sentinela-api" `
    --paths "backend" `
    --add-data "frontend/dist;frontend/dist" `
    --hidden-import "pyodbc" `
    --hidden-import "uvicorn" `
    backend/main.py

# Organizando para o Tauri (Motor camuflado como _engine em subpasta)
$BIN_DIR = "src-tauri/bin/_engine"
if (!(Test-Path $BIN_DIR)) { New-Item -ItemType Directory -Force -Path $BIN_DIR }
Copy-Item "dist/sentinela-api.exe" "$BIN_DIR/_engine-x86_64-pc-windows-msvc.exe" -Force

# 3. BUILD DO TAURI (APENAS EXECUTÁVEL, SEM INSTALADOR)
Write-Host "`n3/3: Gerando o EXE Final (Tauri - Modo Turbo)..." -ForegroundColor Yellow
cargo tauri build --no-bundle

# 4. ORGANIZAÇÃO FINAL (PORTABLE)
Write-Host "`n4/4: Organizando a pasta portátil final..." -ForegroundColor Cyan

$FINAL_DIR = "$ROOT/Sentinela_Portatil"
if (Test-Path $FINAL_DIR) { Remove-Item -Recurse -Force $FINAL_DIR }
New-Item -ItemType Directory -Force -Path "$FINAL_DIR/_engine"

# Copia o App Principal (Sentinela.exe)
Copy-Item "src-tauri/target/release/sentinela.exe" "$FINAL_DIR/sentinela.exe" -Force

# Copia o Motor (renomeando para _engine.exe a partir da pasta dist)
# Isso evita o erro de "argumento nulo" que aconteceu antes
Copy-Item "dist/sentinela-api.exe" "$FINAL_DIR/_engine/_engine.exe" -Force

Write-Host "`n✅ BUILD E ORGANIZAÇÃO CONCLUÍDOS!" -ForegroundColor Green
Write-Host "Sua pasta pronta para distribuição está em: $FINAL_DIR" -ForegroundColor Yellow
Write-Host "Estrutura:" -ForegroundColor Gray
Write-Host " - $FINAL_DIR/sentinela.exe" -ForegroundColor Gray
Write-Host " - $FINAL_DIR/_engine/_engine.exe" -ForegroundColor Gray
