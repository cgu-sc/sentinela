"""
Serviço de verificação e download automático de atualizações do Sentinela.

Fluxo de verificação:
  1. Tenta buscar manifest.json e manifest.sig remotamente (timeout 4 s).
  2. Valida Ed25519 sobre os bytes exatos do manifesto.
  3. Valida schema (schema_version==1, product=="sentinela", channel=="stable").
  4. Compara versões com packaging.version.Version (SemVer rigoroso).
  5. Grava cache local atomicamente apenas se a validação passar.
  6. Proteção anti-downgrade: rejeita manifesto com minimum_supported_version
     menor que o do cache anterior ou published_at anterior.
  7. Política offline: usa cache válido ou retorna verification_unavailable.

Fluxo de download automático (apenas sys.frozen):
  1. POST /download-update → dispara download assíncrono do novo .exe via HTTPX stream.
  2. Progresso (0.0–1.0) disponível em GET /download-progress.
  3. Ao terminar, gera update.bat temporário e o lança desvinculado (Popen).
  4. Backend chama sys.exit(0), fechando o processo.
  5. update.bat aguarda o PID original sair, substitui o .exe e reinicia.
"""

from __future__ import annotations

import base64
import json
import logging
import os
import subprocess
import sys
import tempfile
import threading
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import httpx
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.hazmat.primitives.serialization import load_pem_public_key
from cryptography.exceptions import InvalidSignature
from packaging.version import Version, InvalidVersion

from api.schemas.system_update import UpdateManifest, UpdateStatusResponse

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configurações
# ---------------------------------------------------------------------------

MANIFEST_URL = "https://cgu-sc.github.io/sentinela/updates/manifest.json"
SIGNATURE_URL = "https://cgu-sc.github.io/sentinela/updates/manifest.sig"
REQUEST_TIMEOUT = 4.0
MAX_MANIFEST_BYTES = 64 * 1024   # 64 KB
MAX_SIG_BYTES = 256               # Ed25519 sig em Base64 < 120 bytes

EXPECTED_PRODUCT = "sentinela"
EXPECTED_CHANNEL = "stable"
EXPECTED_SCHEMA_VERSION = 1

# ---------------------------------------------------------------------------
# Caminhos
# ---------------------------------------------------------------------------

def _cache_dir() -> Path:
    """Pasta persistente fora do _MEIPASS — sobrevive entre reinícios do exe."""
    base = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "Sentinela" / "updates"
    base.mkdir(parents=True, exist_ok=True)
    return base


def _public_key_path() -> Path:
    """Chave pública: dentro de _MEIPASS/backend/data no exe, ou backend/data/ em dev."""
    if getattr(sys, "frozen", False):
        base = Path(sys._MEIPASS) / "backend"  # type: ignore[attr-defined]
    else:
        base = Path(__file__).parent.parent.parent  # backend/
    return base / "data" / "update_manifest_public_key.pem"


def _version_json_path() -> Path:
    if getattr(sys, "frozen", False):
        base = Path(sys._MEIPASS)  # type: ignore[attr-defined]
    else:
        base = Path(__file__).parent.parent.parent.parent  # raiz do projeto
    return base / "version.json"


# ---------------------------------------------------------------------------
# Leitura da versão local
# ---------------------------------------------------------------------------

def get_current_version() -> str:
    path = _version_json_path()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return str(data["version"])
    except Exception as exc:
        raise RuntimeError(f"Não foi possível ler version.json: {exc}") from exc


# ---------------------------------------------------------------------------
# Criptografia
# ---------------------------------------------------------------------------

def _load_public_key() -> Ed25519PublicKey:
    pem = _public_key_path().read_bytes()
    key = load_pem_public_key(pem)
    if not isinstance(key, Ed25519PublicKey):
        raise ValueError("Chave pública não é do tipo Ed25519.")
    return key


def _verify_signature(manifest_bytes: bytes, sig_b64: bytes) -> None:
    """Lança InvalidSignature ou Exception se a assinatura não bater."""
    try:
        sig = base64.b64decode(sig_b64)
    except Exception as exc:
        raise ValueError(f"Assinatura Base64 inválida: {exc}") from exc
    key = _load_public_key()
    key.verify(sig, manifest_bytes)  # lança InvalidSignature se falhar


# ---------------------------------------------------------------------------
# Validação de manifesto
# ---------------------------------------------------------------------------

def _validate_manifest(raw: bytes) -> UpdateManifest:
    """Parseia e valida campos obrigatórios do manifesto. Falha visivelmente."""
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"Manifesto não é JSON válido: {exc}") from exc

    if data.get("schema_version") != EXPECTED_SCHEMA_VERSION:
        raise ValueError(
            f"schema_version inesperado: {data.get('schema_version')!r} "
            f"(esperado {EXPECTED_SCHEMA_VERSION})"
        )
    if data.get("product") != EXPECTED_PRODUCT:
        raise ValueError(f"product inesperado: {data.get('product')!r}")
    if data.get("channel") != EXPECTED_CHANNEL:
        raise ValueError(f"channel inesperado: {data.get('channel')!r}")

    # Valida versões com SemVer rigoroso
    for field in ("latest_version", "minimum_supported_version"):
        raw_ver = data.get(field)
        if not raw_ver:
            raise ValueError(f"Campo obrigatório ausente: {field}")
        try:
            Version(raw_ver)
        except InvalidVersion:
            raise ValueError(f"{field} não é SemVer válido: {raw_ver!r}")

    return UpdateManifest.model_validate(data)


# ---------------------------------------------------------------------------
# Proteção anti-downgrade
# ---------------------------------------------------------------------------

def _check_anti_downgrade(new: UpdateManifest, cached_raw: bytes | None) -> None:
    """Rejeita manifesto remoto que regride minimum_supported_version ou published_at."""
    if cached_raw is None:
        return
    try:
        cached_data = json.loads(cached_raw)
        cached_min = Version(cached_data.get("minimum_supported_version", "0.0.0"))
        new_min = Version(new.minimum_supported_version)
        if new_min < cached_min:
            raise ValueError(
                f"Manifesto remoto regride minimum_supported_version "
                f"({new.minimum_supported_version} < {cached_data['minimum_supported_version']}). "
                "Rejeitado por política anti-downgrade."
            )
        cached_pub = cached_data.get("published_at")
        if cached_pub and new.published_at < datetime.fromisoformat(cached_pub):
            raise ValueError(
                "Manifesto remoto tem published_at anterior ao cache. Rejeitado."
            )
    except (json.JSONDecodeError, InvalidVersion, KeyError):
        # Cache corrompido — não bloqueia o manifesto novo
        pass


# ---------------------------------------------------------------------------
# Cache local
# ---------------------------------------------------------------------------

def _cache_manifest_path() -> Path:
    return _cache_dir() / "manifest.json"


def _cache_sig_path() -> Path:
    return _cache_dir() / "manifest.sig"


def _cache_state_path() -> Path:
    return _cache_dir() / "state.json"


def _read_cache() -> tuple[bytes | None, bytes | None]:
    """Retorna (manifest_bytes, sig_bytes) ou (None, None) se ausente."""
    try:
        return (
            _cache_manifest_path().read_bytes(),
            _cache_sig_path().read_bytes(),
        )
    except FileNotFoundError:
        return None, None


def _write_cache_atomic(manifest_bytes: bytes, sig_bytes: bytes) -> None:
    """Grava manifest+sig atomicamente; valida antes de substituir."""
    cache_dir = _cache_dir()

    # Grava temporários
    tmp_manifest = Path(tempfile.mktemp(dir=cache_dir, suffix=".manifest.tmp"))
    tmp_sig = Path(tempfile.mktemp(dir=cache_dir, suffix=".sig.tmp"))
    try:
        tmp_manifest.write_bytes(manifest_bytes)
        tmp_sig.write_bytes(sig_bytes)

        # Re-valida antes de substituir o cache
        _verify_signature(manifest_bytes, sig_bytes)
        _validate_manifest(manifest_bytes)

        # Substituição atômica
        tmp_manifest.replace(_cache_manifest_path())
        tmp_sig.replace(_cache_sig_path())

        _cache_state_path().write_text(
            json.dumps({
                "checked_at": datetime.now(timezone.utc).isoformat(),
                "source_url": MANIFEST_URL,
            }),
            encoding="utf-8",
        )
    except Exception:
        # Limpa temporários em caso de falha
        tmp_manifest.unlink(missing_ok=True)
        tmp_sig.unlink(missing_ok=True)
        raise


def _read_cache_state() -> dict:
    try:
        return json.loads(_cache_state_path().read_text(encoding="utf-8"))
    except Exception:
        return {}


# ---------------------------------------------------------------------------
# Comparação de versões
# ---------------------------------------------------------------------------

def _compare_versions(current: str, latest: str, minimum: str) -> str:
    """Retorna o status semântico baseado em SemVer."""
    cur = Version(current)
    lat = Version(latest)
    mn = Version(minimum)

    if cur < mn:
        return "update_required"
    if cur < lat:
        return "update_available"
    return "current"


# ---------------------------------------------------------------------------
# Estado em memória (inicializado no boot, atualizado em background)
# ---------------------------------------------------------------------------

_cached_status: Optional[UpdateStatusResponse] = None


def get_cached_status() -> Optional[UpdateStatusResponse]:
    return _cached_status


def _build_response(
    current_version: str,
    manifest: UpdateManifest | None,
    status: str,
    source: str,
    checked_at: datetime | None,
    message: str,
) -> UpdateStatusResponse:
    return UpdateStatusResponse(
        current_version=current_version,
        latest_version=manifest.latest_version if manifest else None,
        minimum_supported_version=manifest.minimum_supported_version if manifest else None,
        status=status,  # type: ignore[arg-type]
        checked_at=checked_at,
        source=source,  # type: ignore[arg-type]
        download_url=str(manifest.download_url) if manifest else None,
        release_notes_url=str(manifest.release_notes_url) if manifest else None,
        message=message,
    )


# ---------------------------------------------------------------------------
# Lógica principal
# ---------------------------------------------------------------------------

def _fetch_remote() -> tuple[bytes, bytes]:
    """Busca manifest e sig remotamente com timeout e limite de tamanho."""
    with httpx.Client(timeout=REQUEST_TIMEOUT, follow_redirects=True) as client:
        r_manifest = client.get(MANIFEST_URL)
        r_manifest.raise_for_status()
        manifest_bytes = r_manifest.content
        if len(manifest_bytes) > MAX_MANIFEST_BYTES:
            raise ValueError("Manifesto remoto excede tamanho máximo permitido.")

        r_sig = client.get(SIGNATURE_URL)
        r_sig.raise_for_status()
        sig_bytes = r_sig.content
        if len(sig_bytes) > MAX_SIG_BYTES:
            raise ValueError("Assinatura remota excede tamanho máximo permitido.")

    return manifest_bytes, sig_bytes


def check_for_updates(force_remote: bool = False) -> UpdateStatusResponse:
    """
    Verifica atualizações e atualiza _cached_status.

    Args:
        force_remote: Se True, ignora o cache e força consulta remota.
    """
    global _cached_status

    current_version = get_current_version()
    cached_manifest_bytes, cached_sig_bytes = _read_cache()
    state = _read_cache_state()
    checked_at = None
    if state.get("checked_at"):
        try:
            checked_at = datetime.fromisoformat(state["checked_at"])
        except ValueError:
            pass

    # Tenta buscar remotamente
    remote_error: str | None = None
    try:
        manifest_bytes, sig_bytes = _fetch_remote()
        _verify_signature(manifest_bytes, sig_bytes)
        manifest = _validate_manifest(manifest_bytes)
        _check_anti_downgrade(manifest, cached_manifest_bytes)
        _write_cache_atomic(manifest_bytes, sig_bytes)

        status = _compare_versions(
            current_version,
            manifest.latest_version,
            manifest.minimum_supported_version,
        )
        messages = {
            "current": "Sistema atualizado.",
            "update_available": f"Nova versão disponível: {manifest.latest_version}.",
            "update_required": (
                f"Atualização obrigatória. Versão mínima exigida: "
                f"{manifest.minimum_supported_version}."
            ),
        }
        result = _build_response(
            current_version=current_version,
            manifest=manifest,
            status=status,
            source="remote",
            checked_at=datetime.now(timezone.utc),
            message=messages[status],
        )
        _cached_status = result
        return result

    except Exception as exc:
        remote_error = str(exc)
        logger.warning("Falha ao verificar atualizações remotamente: %s", remote_error)

    # Política offline — usa cache local se disponível e válido
    if cached_manifest_bytes and cached_sig_bytes:
        try:
            _verify_signature(cached_manifest_bytes, cached_sig_bytes)
            manifest = _validate_manifest(cached_manifest_bytes)

            # Cache válido ainda pode exigir bloqueio
            status = _compare_versions(
                current_version,
                manifest.latest_version,
                manifest.minimum_supported_version,
            )
            if status == "update_required":
                msg = (
                    f"Atualização obrigatória (verificação offline). "
                    f"Versão mínima: {manifest.minimum_supported_version}."
                )
                final_status = "update_required"
            else:
                msg = "Verificação offline. Usando último manifesto validado."
                final_status = "offline_cached"

            result = _build_response(
                current_version=current_version,
                manifest=manifest,
                status=final_status,
                source="cache",
                checked_at=checked_at,
                message=msg,
            )
            _cached_status = result
            return result

        except (InvalidSignature, ValueError) as exc:
            logger.error("Cache local com assinatura inválida: %s", exc)
            # Cache corrompido — não usar

    # Sem remote, sem cache: permite execução mas informa
    result = _build_response(
        current_version=current_version,
        manifest=None,
        status="verification_unavailable",
        source="none",
        checked_at=checked_at,
        message="Não foi possível verificar atualizações. Continuando sem verificação.",
    )
    _cached_status = result
    return result


def initialize_update_check() -> None:
    """
    Chamado no lifespan do FastAPI.
    Carrega cache local imediatamente (sem I/O de rede) para deixar
    um estado disponível antes da consulta remota em background.
    """
    global _cached_status

    current_version = get_current_version()
    cached_manifest_bytes, cached_sig_bytes = _read_cache()
    state = _read_cache_state()
    checked_at = None
    if state.get("checked_at"):
        try:
            checked_at = datetime.fromisoformat(state["checked_at"])
        except ValueError:
            pass

    if cached_manifest_bytes and cached_sig_bytes:
        try:
            _verify_signature(cached_manifest_bytes, cached_sig_bytes)
            manifest = _validate_manifest(cached_manifest_bytes)
            status = _compare_versions(
                current_version,
                manifest.latest_version,
                manifest.minimum_supported_version,
            )
            if status == "update_required":
                msg = (
                    f"Atualização obrigatória. Versão mínima: "
                    f"{manifest.minimum_supported_version}."
                )
            elif status == "update_available":
                msg = f"Nova versão disponível: {manifest.latest_version}."
            else:
                msg = "Sistema atualizado."

            _cached_status = _build_response(
                current_version=current_version,
                manifest=manifest,
                status=status,
                source="cache",
                checked_at=checked_at,
                message=msg,
            )
            return
        except Exception as exc:
            logger.warning("Cache local inválido no boot: %s", exc)

    _cached_status = _build_response(
        current_version=current_version,
        manifest=None,
        status="verification_unavailable",
        source="none",
        checked_at=None,
        message="Verificação de atualização pendente.",
    )


# ---------------------------------------------------------------------------
# Estado global de download
# ---------------------------------------------------------------------------

class _DownloadState:
    """Estado thread-safe do processo de download automático."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.status: str = "idle"   # idle | downloading | applying | done | error
        self.progress: float = 0.0  # 0.0 – 1.0
        self.error: str | None = None

    def update(self, status: str, progress: float = 0.0, error: str | None = None) -> None:
        with self._lock:
            self.status = status
            self.progress = progress
            self.error = error

    def snapshot(self) -> dict:
        with self._lock:
            return {
                "status": self.status,
                "progress": round(self.progress, 4),
                "error": self.error,
            }


_download_state = _DownloadState()


def get_download_state() -> dict:
    """Retorna snapshot thread-safe do estado de download para o endpoint de progresso."""
    return _download_state.snapshot()


# ---------------------------------------------------------------------------
# Download e aplicação do update
# ---------------------------------------------------------------------------

DOWNLOAD_CHUNK_SIZE = 1024 * 64   # 64 KB
DOWNLOAD_TIMEOUT = 300.0          # 5 minutos — EXE pode ser grande


def _current_exe_path() -> Path:
    """Caminho do executável em execução (frozen) ou lança erro."""
    if not getattr(sys, "frozen", False):
        raise RuntimeError(
            "Auto-update via download não é suportado fora do modo Desktop (sys.frozen=False)."
        )
    return Path(sys.executable)


def _updates_tmp_dir() -> Path:
    """Pasta temporária persistente para o download do .exe."""
    base = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "Sentinela" / "updates"
    base.mkdir(parents=True, exist_ok=True)
    return base


def _resolve_github_download_url(manifest_download_url: str) -> str:
    """
    Recebe a URL da release do GitHub (tag page) e retorna a URL direta
    para o asset sentinela_server1.exe dentro dessa release.

    Exemplo de entrada:
      https://github.com/cgu-sc/sentinela/releases/tag/v1.1.4
    Exemplo de saída:
      https://github.com/cgu-sc/sentinela/releases/download/v1.1.4/sentinela_server1.exe
    """
    # Converte /tag/vX.Y.Z → /download/vX.Y.Z/sentinela_server1.exe
    if "/releases/tag/" in manifest_download_url:
        tag = manifest_download_url.split("/releases/tag/")[-1].strip("/")
        return (
            f"https://github.com/cgu-sc/sentinela/releases/download/"
            f"{tag}/Sentinela.exe"
        )
    # Se já for URL direta (ex: download/), usa como está
    return manifest_download_url


def _write_update_ps1(exe_path: Path, tmp_path: Path) -> Path:
    """
    Gera um script PowerShell que:
      1. Encerra todos os processos Sentinela.
      2. Aguarda a porta do servidor liberar.
      3. Substitui o exe.
      4. Abre o novo exe.
      5. Remove os arquivos temporários.
    """
    ps1_path = exe_path.parent / "sentinela_update.ps1"
    exe_name = exe_path.name

    proc_name = exe_name.replace(".exe", "")
    script = f"""
$ErrorActionPreference = 'SilentlyContinue'

# 1. Encerra todos os processos Sentinela
Get-Process -Name '{proc_name}' | Stop-Process -Force

# 2. Aguarda processos encerrarem (max 15s)
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Process -Name '{proc_name}' -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {{
    Start-Sleep -Milliseconds 300
}}

# 3. Aguarda portas 8002-8010 liberarem (max 15s)
$deadline = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $deadline) {{
    $ocupadas = 8002..8010 | Where-Object {{
        (Get-NetTCPConnection -LocalPort $_ -State Listen -ErrorAction SilentlyContinue) -ne $null
    }}
    if ($ocupadas.Count -eq 0) {{ break }}
    Start-Sleep -Milliseconds 300
}}

# 4. Substitui o exe (max 10s)
$deadline = (Get-Date).AddSeconds(10)
while ((Test-Path '{exe_path}') -and (Get-Date) -lt $deadline) {{
    try {{ Remove-Item '{exe_path}' -Force; break }} catch {{ Start-Sleep -Milliseconds 300 }}
}}
Copy-Item '{tmp_path}' '{exe_path}' -Force

# 5. Abre o novo exe
Start-Process '{exe_path}'

# 6. Limpeza
Start-Sleep -Seconds 2
Remove-Item '{tmp_path}' -Force -ErrorAction SilentlyContinue
Remove-Item $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue
"""
    ps1_path.write_text(script, encoding="utf-8")
    return ps1_path


def _do_download_and_apply(download_url: str) -> None:
    """
    Executa em thread separada:
      - Download via HTTPX stream com atualização de progresso.
      - Gera update.bat, lança desvinculado e chama sys.exit(0).
    """
    exe_path = _current_exe_path()
    tmp_path = exe_path.parent / "sentinela_update.exe.tmp"

    try:
        direct_url = _resolve_github_download_url(download_url)
        logger.info("[auto-update] Iniciando download de: %s", direct_url)
        _download_state.update("downloading", progress=0.0)

        with httpx.Client(timeout=DOWNLOAD_TIMEOUT, follow_redirects=True) as client:
            with client.stream("GET", direct_url) as response:
                response.raise_for_status()
                total = int(response.headers.get("content-length", 0))
                downloaded = 0
                with open(tmp_path, "wb") as f:
                    for chunk in response.iter_bytes(chunk_size=DOWNLOAD_CHUNK_SIZE):
                        f.write(chunk)
                        downloaded += len(chunk)
                        if total > 0:
                            _download_state.update("downloading", progress=downloaded / total)

        logger.info("[auto-update] Download concluído (%d bytes). Aguardando confirmação do frontend.", downloaded)
        _download_state.update("done", progress=1.0)

    except Exception as exc:
        logger.error("[auto-update] Falha no download/aplicação: %s", exc, exc_info=True)
        _download_state.update("error", progress=0.0, error=str(exc))
        tmp_path.unlink(missing_ok=True)


def download_and_apply_update(download_url: str) -> None:
    """
    Ponto de entrada público. Valida modo frozen, verifica se já há download
    em andamento e dispara a thread de download.

    Lança RuntimeError se:
      - Não está em modo frozen (sys.frozen == False).
      - Já existe um download em andamento.
    """
    if not getattr(sys, "frozen", False):
        raise RuntimeError(
            "Auto-update via download não é suportado fora do modo Desktop (sys.frozen=False). "
            "Execute o aplicativo empacotado (.exe)."
        )

    state = _download_state.snapshot()
    if state["status"] in ("downloading", "applying"):
        raise RuntimeError(
            f"Download já em andamento (status atual: {state['status']}). Aguarde."
        )

    # Reseta estado para permitir re-download após done/error
    _download_state.update("idle", progress=0.0)

    logger.info("[auto-update] Disparando thread de download para: %s", download_url)
    t = threading.Thread(
        target=_do_download_and_apply,
        args=(download_url,),
        daemon=True,
        name="sentinela-auto-update",
    )
    t.start()


def apply_update() -> None:
    """
    Chamado pelo frontend após contagem regressiva.
    Gera o bat, lança-o e encerra o servidor.
    """
    exe_path = _current_exe_path()
    tmp_path = exe_path.parent / "sentinela_update.exe.tmp"

    if not tmp_path.exists():
        raise RuntimeError("Arquivo de atualização não encontrado. Faça o download novamente.")

    ps1_path = _write_update_ps1(exe_path, tmp_path)
    logger.info("[auto-update] Aplicando atualização. ps1: %s", ps1_path)

    subprocess.Popen(
        ["powershell.exe", "-ExecutionPolicy", "Bypass", "-File", str(ps1_path)],
        creationflags=subprocess.CREATE_NEW_CONSOLE | subprocess.CREATE_NEW_PROCESS_GROUP,
        close_fds=True,
    )

    time.sleep(0.5)
    sys.exit(0)


def cancel_update() -> None:
    """
    Chamado pelo frontend ao cancelar a contagem regressiva.
    Deleta o .tmp e reseta o estado.
    """
    exe_path = _current_exe_path()
    tmp_path = exe_path.parent / "sentinela_update.exe.tmp"
    tmp_path.unlink(missing_ok=True)

    bat_path = exe_path.parent / "sentinela_update.ps1"
    bat_path.unlink(missing_ok=True)

    _download_state.update("idle", progress=0.0)
    logger.info("[auto-update] Atualização cancelada pelo usuário.")
