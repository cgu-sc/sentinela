import json
import os
import warnings
from pathlib import Path
from typing import Any, Dict, List


def _project_preferences_dir() -> Path:
    project_root = Path(__file__).resolve().parents[3]
    return project_root / "modules" / "user_preferences"


def _preference_dir_candidates() -> List[Path]:
    candidates: List[Path] = []

    override = os.getenv("SENTINELA_PREFERENCES_DIR")
    if override:
        candidates.append(Path(override))

    candidates.append(_project_preferences_dir())

    unique_candidates: List[Path] = []
    seen = set()
    for candidate in candidates:
        key = os.path.normcase(os.path.abspath(candidate))
        if key not in seen:
            seen.add(key)
            unique_candidates.append(candidate)

    return unique_candidates


def _is_writable_dir(path: Path) -> bool:
    test_file = path / ".write_test"
    try:
        path.mkdir(parents=True, exist_ok=True)
        test_file.write_text("ok", encoding="utf-8")
        test_file.unlink(missing_ok=True)
        return True
    except OSError:
        try:
            test_file.unlink(missing_ok=True)
        except OSError:
            pass
        return False


def _default_preferences_dir() -> Path:
    candidates = _preference_dir_candidates()
    for candidate in candidates:
        if _is_writable_dir(candidate):
            return candidate

    return candidates[0]


class PreferencesService:
    SCHEMA_VERSION = 1
    LEGACY_BASE_DIR = Path(__file__).resolve().parents[2] / "data" / "user_preferences"
    BASE_DIR = _default_preferences_dir()
    FILE_PATH = BASE_DIR / "preferences.json"
    BACKUP_PATH = BASE_DIR / "preferences.backup.json"

    @classmethod
    def _set_base_dir(cls, base_dir: Path) -> None:
        cls.BASE_DIR = base_dir
        cls.FILE_PATH = base_dir / "preferences.json"
        cls.BACKUP_PATH = base_dir / "preferences.backup.json"

    @classmethod
    def _ordered_preference_dirs(cls) -> List[Path]:
        return [cls.BASE_DIR, *[path for path in _preference_dir_candidates() if path != cls.BASE_DIR]]

    @classmethod
    def _copy_file(cls, src: Path, dst: Path) -> None:
        try:
            dst.parent.mkdir(parents=True, exist_ok=True)
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
            "metodologia": {},
        }

    @classmethod
    def _ensure_dir(cls) -> None:
        cls.BASE_DIR.mkdir(parents=True, exist_ok=True)

    @classmethod
    def _migrate_legacy_file(cls) -> None:
        if cls.FILE_PATH.exists():
            return

        if cls.BASE_DIR != cls.LEGACY_BASE_DIR:
            legacy_file = cls.LEGACY_BASE_DIR / "preferences.json"
            if legacy_file.exists():
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
        normalized["metodologia"] = data.get("metodologia") if isinstance(data.get("metodologia"), dict) else {}
        return normalized

    @classmethod
    def _write_file(cls, base_dir: Path, data: Dict[str, Any]) -> None:
        base_dir.mkdir(parents=True, exist_ok=True)
        file_path = base_dir / "preferences.json"
        backup_path = base_dir / "preferences.backup.json"
        tmp_path = file_path.with_suffix(".tmp")

        if file_path.exists():
            cls._copy_file(file_path, backup_path)

        try:
            with tmp_path.open("w", encoding="utf-8") as file:
                json.dump(data, file, ensure_ascii=False, indent=2)
                file.write("\n")
            os.replace(tmp_path, file_path)
        except OSError:
            try:
                tmp_path.unlink(missing_ok=True)
            except OSError:
                pass
            raise

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
        normalized = cls._normalize(data)

        errors: List[str] = []
        original_dir = cls.BASE_DIR
        for candidate in cls._ordered_preference_dirs():
            try:
                cls._write_file(candidate, normalized)
            except OSError as exc:
                errors.append(f"{candidate}: {exc}")
                continue

            cls._set_base_dir(candidate)
            if candidate != original_dir:
                warnings.warn(
                    f"[PreferencesService] Preferencias salvas em '{candidate}' "
                    f"apos falha no diretorio original '{original_dir}'.",
                    RuntimeWarning,
                    stacklevel=2,
                )
            return normalized

        warnings.warn(
            "[PreferencesService] Nao foi possivel salvar preferencias. "
            f"Diretorios testados: {'; '.join(errors)}",
            RuntimeWarning,
            stacklevel=2,
        )

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
        current_ui = data.get("ui") if isinstance(data.get("ui"), dict) else {}
        data["ui"] = {**current_ui, **ui}
        return cls.write(data)

    @classmethod
    def update_nota_tecnica(cls, nota_tecnica: Dict[str, Any]) -> Dict[str, Any]:
        data = cls.read()
        data["nota_tecnica"] = nota_tecnica
        return cls.write(data)

    @classmethod
    def update_metodologia(cls, metodologia: Dict[str, Any]) -> Dict[str, Any]:
        data = cls.read()
        current_metodologia = data.get("metodologia") if isinstance(data.get("metodologia"), dict) else {}
        data["metodologia"] = {**current_metodologia, **metodologia}
        return cls.write(data)
