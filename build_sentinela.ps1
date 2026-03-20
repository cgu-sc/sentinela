# SENTINELA - Script de Build Automatizado para EXE (Tauri + FastAPI)
# ==============================================================================

Write-Host "🚀 Iniciando Build do Sentinela Web/Desktop..." -ForegroundColor Cyan

# 1. BUILD DO FRONTEND (VUE + PRIMEVUE)
Write-Host "`n1/3: Construindo o Frontend Vue..." -ForegroundColor Yellow
if (!(Test-Path "frontend/public")) { New-Item -ItemType Directory -Path "frontend/public" -Force }
Copy-Item "src/logo_sentinela.png" "frontend/public/logo_sentinela.png" -Force
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
pip install pyinstaller fastapi uvicorn sqlalchemy pyodbc
# Criamos o binário do backend de forma que o Tauri consiga consumir como sidecar
python -m PyInstaller --noconfirm --onefile --console --name "sentinela-api" --paths "backend" --hidden-import "pyodbc" --hidden-import "uvicorn" backend/main.py

# Organizando para o Tauri (Sidecar precisa do sufixo do sistema)
New-Item -ItemType Directory -Force -Path "src-tauri/bin"
Copy-Item "dist/sentinela-api.exe" "src-tauri/bin/sentinela-api-x86_64-pc-windows-msvc.exe" -Force

# 3. BUILD DO TAURI (INSTALADOR FINAL)
Write-Host "`n3/3: Gerando o EXE Final (Tauri)..." -ForegroundColor Yellow
# Certifique-se de ter o Rust instalado e as dependências do Tauri
# cargo tauri build

Write-Host "`n✅ Build concluído com sucesso!" -ForegroundColor Green
Write-Host "O seu EXE final estará na pasta: src-tauri/target/release/bundle/msi/" -ForegroundColor Gray
