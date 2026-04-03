
start "Unicorn Sentinela" powershell.exe -NoExit -Command "deactivate; cd D:\sentinela\.venv\Scripts; Activate.ps1; cd D:\sentinela\backend; uvicorn main:app --reload --host 127.0.0.1 --port 8002"
