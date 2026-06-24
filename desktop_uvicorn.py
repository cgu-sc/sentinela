"""
Sentinela Desktop - PyWebView (Uvicorn)
Com sistema de logging profissional em arquivo.
"""
import time
import sys
import os
import base64
import socket
import traceback
import logging
import subprocess
import multiprocessing
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
logger.info("SENTINELA DESKTOP (UVICORN) - INICIANDO")
logger.info("="*60)
logger.info(f"Log file: {LOG_FILE}")
logger.info(f"Python: {sys.version}")
logger.info(f"Executavel: {sys.executable}")
logger.info(f"Frozen: {getattr(sys, 'frozen', False)}")
logger.info(f"APP_DIR (onde esta o .exe): {APP_DIR}")
logger.info(f"BASE_DIR (arquivos internos): {BASE_DIR}")
logger.info(f"CWD: {os.getcwd()}")


NOTAS_TECNICAS_DIR = os.path.join(APP_DIR, "notas_tecnicas")
DEFAULT_PORT = 8002
MAX_PORT = 8020


def sanitize_filename(filename):
    """Remove caracteres invalidos para nomes de arquivo no Windows."""
    cleaned = "".join("_" if ch in '\\/:*?"<>|' else ch for ch in str(filename or "").strip())
    return cleaned or "arquivo"


def unique_file_path(directory, filename):
    """Evita sobrescrever arquivos ja existentes."""
    base, ext = os.path.splitext(filename)
    path = os.path.join(directory, filename)
    counter = 2
    while os.path.exists(path):
        path = os.path.join(directory, f"{base}_{counter}{ext}")
        counter += 1
    return path


class DesktopApi:
    """Ponte nativa para recursos que o WebView nao executa como navegador."""

    def save_file(self, filename, base64_content):
        safe_filename = sanitize_filename(filename)
        os.makedirs(NOTAS_TECNICAS_DIR, exist_ok=True)
        path = unique_file_path(NOTAS_TECNICAS_DIR, safe_filename)
        try:
            content = base64.b64decode(str(base64_content or ""), validate=True)
            with open(path, "wb") as file:
                file.write(content)
            logger.info(f"Arquivo salvo via DesktopApi: {path}")
            return {"ok": True, "filename": os.path.basename(path), "path": path}
        except Exception as exc:
            logger.error(f"Erro ao salvar arquivo via DesktopApi: {exc}")
            logger.error(traceback.format_exc())
            return {"ok": False, "error": str(exc)}

    def open_file(self, path):
        try:
            target = os.path.abspath(str(path or ""))
            allowed_root = os.path.abspath(NOTAS_TECNICAS_DIR)
            if not target.startswith(allowed_root + os.sep):
                raise RuntimeError("Caminho fora da pasta notas_tecnicas.")
            if not os.path.exists(target):
                raise FileNotFoundError(target)
            os.startfile(target)
            logger.info(f"Arquivo aberto via DesktopApi: {target}")
            return {"ok": True}
        except Exception as exc:
            logger.error(f"Erro ao abrir arquivo via DesktopApi: {exc}")
            logger.error(traceback.format_exc())
            return {"ok": False, "error": str(exc)}

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


def is_port_available(port, host="127.0.0.1"):
    """Verifica se a porta pode ser usada pelo Sentinela."""
    if is_port_open(port, host=host, timeout=0.2):
        return False

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
            exclusive_addr = getattr(socket, "SO_EXCLUSIVEADDRUSE", None)
            if exclusive_addr is not None:
                sock.setsockopt(socket.SOL_SOCKET, exclusive_addr, 1)
            sock.bind((host, port))
            return True
    except OSError:
        return False


def find_available_port(start=DEFAULT_PORT, end=MAX_PORT):
    """Escolhe uma porta previsivel, evitando abrir outro servico por engano."""
    for port in range(start, end + 1):
        if is_port_available(port):
            if port != DEFAULT_PORT:
                logger.warning(f"Porta {DEFAULT_PORT} ocupada; usando porta {port}.")
            return port
    raise RuntimeError(f"Nenhuma porta livre encontrada entre {start} e {end}.")


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


def parse_server_port():
    """Le a porta recebida pelo processo servidor."""
    if "--port" not in sys.argv:
        return DEFAULT_PORT
    index = sys.argv.index("--port")
    if index + 1 >= len(sys.argv):
        raise RuntimeError("Parametro --port informado sem valor.")
    return int(sys.argv[index + 1])


def start_server(port):
    """Inicia o FastAPI com Uvicorn no processo atual."""
    logger.info("")
    logger.info("="*40)
    logger.info("INICIANDO SERVIDOR FASTAPI (UVICORN)")
    logger.info("="*40)

    try:
        logger.info("Importando uvicorn...")
        import uvicorn
        logger.info("  uvicorn OK")

        logger.info("Importando backend.main para validar app...")
        from backend.main import app  # noqa: F401
        logger.info("  backend.main OK")

        logger.info(f"Iniciando Uvicorn na porta {port}...")
        uvicorn.run(
            "backend.main:app",
            host="127.0.0.1",
            port=port,
            log_level="info",
            access_log=True,
        )
        return True

    except ImportError as e:
        logger.error(f"ERRO DE IMPORT: {e}")
        logger.error("Modulo nao encontrado. Verifique se o backend foi incluido no build.")
        logger.error("")
        logger.error("Traceback completo:")
        logger.error(traceback.format_exc())
        return False

    except Exception as e:
        logger.error(f"ERRO FATAL AO INICIAR SERVIDOR: {type(e).__name__}")
        logger.error(f"Mensagem: {e}")
        logger.error("")
        logger.error("Traceback completo:")
        logger.error(traceback.format_exc())
        return False

def build_server_command(port):
    """Monta o comando do processo servidor para dev e executavel."""
    if getattr(sys, 'frozen', False):
        return [sys.executable, "--server", "--port", str(port)]
    return [sys.executable, os.path.abspath(__file__), "--server", "--port", str(port)]

def start_server_process(port):
    """Inicia o servidor em processo separado."""
    command = build_server_command(port)
    logger.info("")
    logger.info("Iniciando processo servidor:")
    logger.info(f"  Comando: {' '.join(command)}")

    try:
        return subprocess.Popen(
            command,
            cwd=APP_DIR,
        )
    except Exception:
        logger.error("ERRO ao iniciar processo servidor")
        logger.error(traceback.format_exc())
        return None

def stop_server_process(process):
    """Encerra o processo servidor iniciado pelo desktop."""
    if process is None:
        return
    if process.poll() is not None:
        logger.info(f"Processo servidor ja encerrado com codigo {process.returncode}")
        return

    logger.info("Encerrando processo servidor...")
    process.terminate()
    try:
        process.wait(timeout=10)
        logger.info("Processo servidor encerrado")
    except subprocess.TimeoutExpired:
        logger.warning("Servidor nao encerrou no prazo; finalizando processo")
        process.kill()
        process.wait(timeout=5)

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

    try:
        port = find_available_port()
    except RuntimeError as exc:
        logger.error(f"FALHA: {exc}")
        return

    app_url = f"http://127.0.0.1:{port}"
    logger.info(f"URL local escolhida: {app_url}")

    # Iniciar servidor em processo separado
    server_process = start_server_process(port)
    if server_process is None:
        logger.error("FALHA: Processo servidor nao iniciou")
        return

    # Aguardar servidor
    if not wait_for_server(port, timeout=30):
        logger.error("")
        logger.error("="*40)
        logger.error("FALHA: Servidor nao iniciou!")
        logger.error("="*40)
        logger.error(f"Verifique o log em: {LOG_FILE}")
        stop_server_process(server_process)
        return

    # Abrir janela
    logger.info("")
    logger.info("="*40)
    logger.info("ABRINDO JANELA")
    logger.info("="*40)

    try:
        logger.info("Criando janela webview...")
        window = webview.create_window(
            title="Sentinela",
            url=app_url,
            width=1280,
            height=720,
            resizable=True,
            js_api=DesktopApi(),
        )
        logger.info("Janela criada, iniciando webview.start()...")

        def set_title_bar_color():
            """Define a cor da barra de título via pywinstyles (Windows 10/11)."""
            try:
                import pywinstyles
                import ctypes

                hwnd = ctypes.windll.user32.FindWindowW(None, "Sentinela")
                if not hwnd:
                    logger.warning("Barra de título: handle da janela não encontrado pelo título.")
                    return

                pywinstyles.change_header_color(hwnd, "#1a1a1a")
                logger.info(f"Cor da barra de título aplicada via pywinstyles. HWND={hwnd}")
            except Exception as e:
                logger.warning(f"Não foi possível aplicar cor na barra de título: {e}")

        def on_shown():
            logger.info("Maximizando janela")
            window.maximize()
  
            set_title_bar_color()

        webview.start(on_shown)
        logger.info("webview.start() retornou - aplicacao encerrada")

    except Exception as e:
        logger.error(f"ERRO ao criar janela: {e}")
        logger.error(traceback.format_exc())
    finally:
        stop_server_process(server_process)

if __name__ == "__main__":
    multiprocessing.freeze_support()
    try:
        if "--server" in sys.argv:
            ok = start_server(parse_server_port())
            if not ok:
                sys.exit(1)
        else:
            main()
    except Exception as e:
        logger.critical(f"ERRO FATAL NAO TRATADO: {e}")
        logger.critical(traceback.format_exc())
    finally:
        logger.info("")
        logger.info("="*60)
        logger.info("SENTINELA ENCERRADO")
        logger.info("="*60)
