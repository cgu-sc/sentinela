"""
Serviço de verificação de atualizações do Sentinela.

Fluxo:
  1. Tenta buscar manifest.json e manifest.sig remotamente (timeout 4 s).
  2. Valida Ed25519 sobre os bytes exatos do manifesto.
  3. Valida schema (schema_version==1, product=="sentinela", channel=="stable").
  4. Compara versões com packaging.version.Version (SemVer rigoroso).
  5. Grava cache local atomicamente apenas se a validação passar.
  6. Proteção anti-downgrade: rejeita manifesto com minimum_supported_version
     menor que o do cache anterior ou published_at anterior.
  7. Política offline: usa cache válido ou retorna verification_unavailable.
"""

from __future__ import annotations

import base64
import json
import logging
import os
import sys
import tempfile
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
