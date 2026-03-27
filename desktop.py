"""
Sentinela Desktop - PyWebView
Com sistema de logging profissional em arquivo.
"""
import threading
import time
import sys
import os
import socket
import traceback
import logging
from datetime import datetime

# Determinar diretorio base
if getattr(sys, 'frozen', False):
    # Modo executavel (PyInstaller)
    APP_DIR = os.path.dirname(sys.executable)
    BASE_DIR = sys._MEIPASS
else:
    # Modo desenvolvimento
    APP_DIR = os.path.dirname(os.path.abspath(__file__))
    BASE_DIR = APP_DIR

# Configurar logging em arquivo
LOG_FILE = os.path.join(APP_DIR, f"sentinela_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")

logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[
        logging.FileHandler(LOG_FILE, encoding='utf-8'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('Sentinela')

# Inicio dos logs
logger.info("="*60)
logger.info("SENTINELA DESKTOP - INICIANDO")
logger.info("="*60)
logger.info(f"Log file: {LOG_FILE}")
logger.info(f"Python: {sys.version}")
logger.info(f"Executavel: {sys.executable}")
logger.info(f"Frozen: {getattr(sys, 'frozen', False)}")
logger.info(f"APP_DIR (onde esta o .exe): {APP_DIR}")
logger.info(f"BASE_DIR (arquivos internos): {BASE_DIR}")
logger.info(f"CWD: {os.getcwd()}")

# Listar arquivos em BASE_DIR
logger.info("")
logger.info("Arquivos em BASE_DIR:")
try:
    items = os.listdir(BASE_DIR)
    for item in items[:30]:
        full_path = os.path.join(BASE_DIR, item)
        tipo = "DIR " if os.path.isdir(full_path) else "FILE"
        logger.info(f"  [{tipo}] {item}")
    if len(items) > 30:
        logger.info(f"  ... e mais {len(items) - 30} itens")
except Exception as e:
    logger.error(f"Erro ao listar BASE_DIR: {e}")

# Verificar pasta backend
backend_path = os.path.join(BASE_DIR, 'backend')
logger.info("")
logger.info(f"Pasta backend: {backend_path}")
logger.info(f"  Existe: {os.path.exists(backend_path)}")

if os.path.exists(backend_path):
    logger.info("  Conteudo:")
    try:
        for item in os.listdir(backend_path)[:15]:
            logger.info(f"    - {item}")
    except Exception as e:
        logger.error(f"    Erro: {e}")

# Verificar pasta frontend
frontend_path = os.path.join(BASE_DIR, 'frontend', 'dist')
logger.info("")
logger.info(f"Pasta frontend/dist: {frontend_path}")
logger.info(f"  Existe: {os.path.exists(frontend_path)}")

if os.path.exists(frontend_path):
    logger.info("  Conteudo:")
    try:
        for item in os.listdir(frontend_path)[:10]:
            logger.info(f"    - {item}")
    except Exception as e:
        logger.error(f"    Erro: {e}")

# Configurar sys.path
sys.path.insert(0, backend_path)
sys.path.insert(0, BASE_DIR)

logger.info("")
logger.info("sys.path configurado:")
for i, p in enumerate(sys.path[:7]):
    logger.info(f"  [{i}] {p}")

def is_port_open(port, host="127.0.0.1", timeout=1):
    """Verifica se a porta esta aberta."""
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        result = sock.connect_ex((host, port))
        sock.close()
        return result == 0
    except Exception as e:
        logger.debug(f"Erro ao verificar porta: {e}")
        return False

def wait_for_server(port, timeout=30):
    """Aguarda o servidor iniciar."""
    logger.info("")
    logger.info(f"Aguardando servidor na porta {port}...")
    start = time.time()
    check_count = 0
    while time.time() - start < timeout:
        check_count += 1
        if is_port_open(port):
            elapsed = time.time() - start
            logger.info(f"Servidor respondeu! (apos {elapsed:.1f}s, {check_count} tentativas)")
            return True
        if check_count % 10 == 0:
            logger.info(f"  Ainda aguardando... {time.time() - start:.0f}s")
        time.sleep(0.5)
    logger.error(f"TIMEOUT! Servidor nao respondeu apos {timeout}s")
    return False

def start_server():
    """Inicia o FastAPI em background."""
    logger.info("")
    logger.info("="*40)
    logger.info("INICIANDO SERVIDOR FASTAPI")
    logger.info("="*40)

    try:
        logger.info("Importando uvicorn...")
        import uvicorn
        logger.info("  uvicorn OK")

        logger.info("Importando backend.main...")
        from backend.main import app
        logger.info("  backend.main OK")

        logger.info("Iniciando uvicorn.run() na porta 8002...")
        uvicorn.run(app, host="127.0.0.1", port=8002, log_level="info")

    except ImportError as e:
        logger.error(f"ERRO DE IMPORT: {e}")
        logger.error("Modulo nao encontrado. Verifique se o backend foi incluido no build.")
        logger.error("")
        logger.error("Traceback completo:")
        logger.error(traceback.format_exc())

    except Exception as e:
        logger.error(f"ERRO FATAL AO INICIAR SERVIDOR: {type(e).__name__}")
        logger.error(f"Mensagem: {e}")
        logger.error("")
        logger.error("Traceback completo:")
        logger.error(traceback.format_exc())

def main():
    logger.info("")
    logger.info("="*40)
    logger.info("FUNCAO MAIN INICIADA")
    logger.info("="*40)

    # Importar webview
    try:
        logger.info("Importando webview...")
        import webview
        version = getattr(webview, '__version__', 'desconhecida')
        logger.info(f"  webview OK (versao: {version})")
    except Exception as e:
        logger.error(f"ERRO ao importar webview: {e}")
        logger.error(traceback.format_exc())
        return

    # Iniciar servidor em thread
    logger.info("")
    logger.info("Criando thread do servidor...")
    server_thread = threading.Thread(target=start_server, daemon=True)
    server_thread.start()
    logger.info("Thread iniciada")

    # Aguardar servidor
    if not wait_for_server(8002, timeout=30):
        logger.error("")
        logger.error("="*40)
        logger.error("FALHA: Servidor nao iniciou!")
        logger.error("="*40)
        logger.error(f"Verifique o log em: {LOG_FILE}")
        return

    # Abrir janela
    logger.info("")
    logger.info("="*40)
    logger.info("ABRINDO JANELA")
    logger.info("="*40)

    try:
        logger.info("Criando janela webview...")
        webview.create_window(
            title="Sentinela",
            url="http://127.0.0.1:8002",
            width=1280,
            height=720,
            resizable=True
        )
        logger.info("Janela criada, iniciando webview.start()...")
        webview.start()
        logger.info("webview.start() retornou - aplicacao encerrada")

    except Exception as e:
        logger.error(f"ERRO ao criar janela: {e}")
        logger.error(traceback.format_exc())

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        logger.critical(f"ERRO FATAL NAO TRATADO: {e}")
        logger.critical(traceback.format_exc())
    finally:
        logger.info("")
        logger.info("="*60)
        logger.info("SENTINELA ENCERRADO")
        logger.info("="*60)
