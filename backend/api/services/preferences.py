import json
import os
import shutil
from pathlib import Path
from typing import Any, Dict, List


def _default_preferences_dir() -> Path:
    override = os.getenv("SENTINELA_PREFERENCES_DIR")
    if override:
        return Path(override)

    local_app_data = os.getenv("LOCALAPPDATA")
    if local_app_data:
        return Path(local_app_data) / "Sentinela" / "user_preferences"

    app_data = os.getenv("APPDATA")
    if app_data:
        return Path(app_data) / "Sentinela" / "user_preferences"

    return Path.home() / ".sentinela" / "user_preferences"


class PreferencesService:
    SCHEMA_VERSION = 1
    LEGACY_BASE_DIR = Path(__file__).resolve().parents[2] / "data" / "user_preferences"
    BASE_DIR = _default_preferences_dir()
    FILE_PATH = BASE_DIR / "preferences.json"
    BACKUP_PATH = BASE_DIR / "preferences.backup.json"

    @classmethod
    def _copy_file(cls, src: Path, dst: Path) -> None:
        try:
            dst.write_bytes(src.read_bytes())
        except OSError:
            pass

    @classmethod
    def default_preferences(cls) -> Dict[str, Any]:
        return {
            "schema_version": cls.SCHEMA_VERSION,
            "filters": {},
            "watchlist": [],
            "ui": {},
            "nota_tecnica": {},
        }

    @classmethod
    def _ensure_dir(cls) -> None:
        cls.BASE_DIR.mkdir(parents=True, exist_ok=True)

    @classmethod
    def _migrate_legacy_file(cls) -> None:
        if cls.FILE_PATH.exists() or cls.BASE_DIR == cls.LEGACY_BASE_DIR:
            return

        legacy_file = cls.LEGACY_BASE_DIR / "preferences.json"
        if not legacy_file.exists():
            return

        try:
            cls._copy_file(legacy_file, cls.FILE_PATH)
        except OSError:
            pass

    @classmethod
    def _normalize(cls, data: Dict[str, Any] | None) -> Dict[str, Any]:
        normalized = cls.default_preferences()
        if not isinstance(data, dict):
            return normalized

        normalized["schema_version"] = int(data.get("schema_version") or cls.SCHEMA_VERSION)
        normalized["filters"] = data.get("filters") if isinstance(data.get("filters"), dict) else {}
        normalized["watchlist"] = data.get("watchlist") if isinstance(data.get("watchlist"), list) else []
        normalized["ui"] = data.get("ui") if isinstance(data.get("ui"), dict) else {}
        normalized["nota_tecnica"] = data.get("nota_tecnica") if isinstance(data.get("nota_tecnica"), dict) else {}
        return normalized

    @classmethod
    def read(cls) -> Dict[str, Any]:
        cls._ensure_dir()
        cls._migrate_legacy_file()
        if not cls.FILE_PATH.exists():
            data = cls.default_preferences()
            cls.write(data)
            return data

        try:
            with cls.FILE_PATH.open("r", encoding="utf-8") as file:
                return cls._normalize(json.load(file))
        except (json.JSONDecodeError, OSError):
            corrupt_path = cls.BASE_DIR / "preferences.corrupt.json"
            try:
                cls._copy_file(cls.FILE_PATH, corrupt_path)
            except OSError:
                pass
            data = cls.default_preferences()
            cls.write(data)
            return data

    @classmethod
    def write(cls, data: Dict[str, Any]) -> Dict[str, Any]:
        cls._ensure_dir()
        normalized = cls._normalize(data)
        tmp_path = cls.FILE_PATH.with_suffix(".tmp")

        if cls.FILE_PATH.exists():
            cls._copy_file(cls.FILE_PATH, cls.BACKUP_PATH)

        try:
            with tmp_path.open("w", encoding="utf-8") as file:
                json.dump(normalized, file, ensure_ascii=False, indent=2)
                file.write("\n")
            os.replace(tmp_path, cls.FILE_PATH)
        except OSError as exc:
            # Disco cheio ou permissão negada — retorna os dados normalizados
            # sem persistir, evitando HTTP 500 no frontend.
            import warnings
            import traceback
            traceback.print_exc()
            warnings.warn(
                f"[PreferencesService] Nao foi possivel salvar preferencias em '{cls.FILE_PATH}': {exc}",
                RuntimeWarning,
                stacklevel=2,
            )
            try:
                tmp_path.unlink(missing_ok=True)
            except OSError:
                pass

        return normalized

    @classmethod
    def update_filters(cls, filters: Dict[str, Any]) -> Dict[str, Any]:
        data = cls.read()
        data["filters"] = filters
        return cls.write(data)

    @classmethod
    def update_watchlist(cls, watchlist: List[Dict[str, Any]]) -> Dict[str, Any]:
        data = cls.read()
        data["watchlist"] = watchlist
        return cls.write(data)

    @classmethod
    def update_ui(cls, ui: Dict[str, Any]) -> Dict[str, Any]:
        data = cls.read()
        data["ui"] = ui
        return cls.write(data)

    @classmethod
    def update_nota_tecnica(cls, nota_tecnica: Dict[str, Any]) -> Dict[str, Any]:
        data = cls.read()
        data["nota_tecnica"] = nota_tecnica
        return cls.write(data)
