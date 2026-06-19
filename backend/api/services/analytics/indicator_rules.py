"""Shared methodological thresholds for Sentinela indicators."""

from typing import Any

from ..preferences import PreferencesService

CLINICA_VALOR_MINIMO_DETALHAMENTO = 1000.0
PARKINSON_PREVALENCIA_50_MAIS = 0.0086
DIABETES_PREVALENCIA_MENOR_20 = 0.0346
IBGE_ANO_CENSO_DEMOGRAFIA = 2022
DEFAULT_VOLUME_ATIPICO_AUMENTO_MINIMO = 10000.0
MIN_VOLUME_ATIPICO_AUMENTO_MINIMO = 0.0
MAX_VOLUME_ATIPICO_AUMENTO_MINIMO = 1000000000.0
VOLUME_ATIPICO_AUMENTO_MINIMO = DEFAULT_VOLUME_ATIPICO_AUMENTO_MINIMO
DEFAULT_AUDIT_HIGH_VALUE = 150000.0
MIN_AUDIT_HIGH_VALUE = 0.0
MAX_AUDIT_HIGH_VALUE = 1000000000.0
FALECIDOS_VALOR_LIMITE_ATENCAO = 3000.0
NAO_COMPROVACAO_PCT_ATENCAO = 5.0
NAO_COMPROVACAO_PCT_CRITICO = 15.0


def normalize_volume_atipico_aumento_minimo(value: Any) -> float:
    if value is None or value == "":
        return DEFAULT_VOLUME_ATIPICO_AUMENTO_MINIMO
    try:
        normalized = float(value)
    except (TypeError, ValueError) as exc:
        raise RuntimeError("Valor minimo de aumento atipico deve ser numerico.") from exc

    if normalized < MIN_VOLUME_ATIPICO_AUMENTO_MINIMO:
        raise RuntimeError("Valor minimo de aumento atipico nao pode ser negativo.")
    if normalized > MAX_VOLUME_ATIPICO_AUMENTO_MINIMO:
        raise RuntimeError("Valor minimo de aumento atipico excede o limite permitido.")
    return normalized


def get_volume_atipico_aumento_minimo() -> float:
    preferences = PreferencesService.read()
    metodologia = preferences.get("metodologia")
    if metodologia is None:
        return DEFAULT_VOLUME_ATIPICO_AUMENTO_MINIMO
    if not isinstance(metodologia, dict):
        raise RuntimeError("Preferencias metodologicas devem ser um objeto.")
    return normalize_volume_atipico_aumento_minimo(
        metodologia.get("volume_atipico_aumento_minimo")
    )


def normalize_audit_high_value(value: Any) -> float:
    if value is None or value == "":
        return DEFAULT_AUDIT_HIGH_VALUE
    try:
        normalized = float(value)
    except (TypeError, ValueError) as exc:
        raise RuntimeError("Valor de destaque financeiro deve ser numerico.") from exc

    if normalized < MIN_AUDIT_HIGH_VALUE:
        raise RuntimeError("Valor de destaque financeiro nao pode ser negativo.")
    if normalized > MAX_AUDIT_HIGH_VALUE:
        raise RuntimeError("Valor de destaque financeiro excede o limite permitido.")
    return normalized


def get_audit_high_value() -> float:
    preferences = PreferencesService.read()
    metodologia = preferences.get("metodologia")
    if metodologia is None:
        return DEFAULT_AUDIT_HIGH_VALUE
    if not isinstance(metodologia, dict):
        raise RuntimeError("Preferencias metodologicas devem ser um objeto.")
    return normalize_audit_high_value(metodologia.get("audit_high_value"))
