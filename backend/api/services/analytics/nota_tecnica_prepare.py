"""Preparacao explicita dos caches por CNPJ exigidos pela Nota Tecnica."""

from __future__ import annotations

import os
from datetime import date
from typing import Any

import cache_manager
import cache_registry
from data_cache import get_cnpj_cache_root

from .nota_tecnica_readiness import _clean_cnpj, get_nota_tecnica_readiness


_NOTA_TECNICA_CNPJ_CACHE_KEYS: tuple[str, ...] = (
    "memoria_calculo",
    "movimentacao_mensal_gtin",
    "crm_prescritores",
    "geografico",
    "crm_raiox_tx",
    "crm_concentracao_unico_alertas",
    "crm_concentracao_multiplo_alertas",
    "crm_timeline_dia",
    "crm_timeline_hora",
    "crm_timeline_eventos",
)


_RELATORIO_PDF_CNPJ_CACHE_KEYS: tuple[str, ...] = (
    "crm_prescritores",
    "geografico",
    "crm_concentracao_unico_alertas",
    "crm_concentracao_multiplo_alertas",
)


_NOTA_TECNICA_CNPJ_CACHE_LABELS: dict[str, str] = {
    "memoria_calculo": "Memoria de calculo do CNPJ",
    "movimentacao_mensal_gtin": "Movimentacao mensal por GTIN",
    "crm_prescritores": "CRM prescritores",
    "geografico": "CRM geografico",
    "crm_raiox_tx": "CRM Raio-X transacoes",
    "crm_concentracao_unico_alertas": "CRM concentracao unico",
    "crm_concentracao_multiplo_alertas": "CRM concentracao multiplo",
    "crm_timeline_dia": "CRM timeline dia",
    "crm_timeline_hora": "CRM timeline hora",
    "crm_timeline_eventos": "CRM timeline eventos",
}


_NOTA_TECNICA_CNPJ_CACHE_HINTS: dict[str, str] = {
    "memoria_calculo": (
        "Gere o modulo global Memoria Calculo Global ou conecte-se ao SQL Server "
        "para materializar a memoria de calculo deste CNPJ."
    ),
    "movimentacao_mensal_gtin": (
        "Gere o modulo GTIN Mensal Global pelo sincronizar_cache.py ou conecte-se "
        "ao SQL Server para materializar a movimentacao mensal por GTIN deste CNPJ."
    ),
    "crm_prescritores": "Gere o modulo CRM Prescritores Global e confira Dados Medico e Perfil Estabelecimento.",
    "geografico": "Gere o modulo CRM Geo Global e confira Perfil Estabelecimento.",
    "crm_raiox_tx": "Gere o modulo CRM Raio-X Global e confira Dados Medico e Perfil Estabelecimento.",
    "crm_concentracao_unico_alertas": "Gere o modulo CRM ConcUnico Global e confira Perfil Estabelecimento.",
    "crm_concentracao_multiplo_alertas": "Gere o modulo CRM ConcMulti Global e confira Perfil Estabelecimento.",
    "crm_timeline_dia": "Gere o modulo CRM Dia Global e confira Perfil Estabelecimento.",
    "crm_timeline_hora": "Gere o modulo CRM Hora Global e confira Perfil Estabelecimento.",
    "crm_timeline_eventos": "Gere o modulo CRM Eventos Global e confira Perfil Estabelecimento.",
}


def _cnpj_cache_path(cnpj: str, filename: str) -> str:
    return os.path.join(get_cnpj_cache_root(), cnpj, filename)


def _prepare_failure_message(key: str, exc: Exception) -> str:
    label = _NOTA_TECNICA_CNPJ_CACHE_LABELS.get(key, key)
    hint = _NOTA_TECNICA_CNPJ_CACHE_HINTS.get(key)
    detail = str(exc).strip()
    parts = [f"Nao foi possivel preparar o modulo {label} para a Nota Tecnica."]
    if hint:
        parts.append(hint)
    if detail:
        parts.append(f"Detalhe tecnico: {detail}")
    return " ".join(parts)


def prepare_nota_tecnica_cnpj(
    cnpj: str,
    engine: Any,
    data_inicio: date | None = None,
    data_fim: date | None = None,
) -> dict[str, Any]:
    """Materializa os caches por CNPJ necessarios para gerar a Nota Tecnica."""
    clean = _clean_cnpj(cnpj)
    initial_readiness = get_nota_tecnica_readiness(clean, data_inicio, data_fim)

    if not initial_readiness["ready"] and not initial_readiness["preparable"]:
        missing = ", ".join(module["label"] for module in initial_readiness["missing_modules"])
        raise RuntimeError(f"Nota Tecnica possui modulos globais pendentes: {missing}.")

    prepared_modules: list[dict[str, Any]] = []
    for key in _NOTA_TECNICA_CNPJ_CACHE_KEYS:
        definition = cache_registry.get_cnpj_cache_definition(key)
        cache_path = _cnpj_cache_path(clean, definition.filename)
        if os.path.exists(cache_path):
            prepared_modules.append({
                "key": key,
                "label": _NOTA_TECNICA_CNPJ_CACHE_LABELS[key],
                "status": "already_ready",
                "file": os.path.join("cnpjs", clean, definition.filename),
            })
            continue

        try:
            cache_manager.sync_cnpj_cache(key, clean, engine)
        except Exception as exc:
            raise RuntimeError(_prepare_failure_message(key, exc)) from exc
        if not os.path.exists(cache_path):
            raise RuntimeError(
                f"Producer do modulo {key} concluiu sem criar o arquivo obrigatorio: "
                f"{os.path.join('cnpjs', clean, definition.filename)}"
            )

        prepared_modules.append({
            "key": key,
            "label": _NOTA_TECNICA_CNPJ_CACHE_LABELS[key],
            "status": "prepared",
            "file": os.path.join("cnpjs", clean, definition.filename),
        })

    final_readiness = get_nota_tecnica_readiness(clean, data_inicio, data_fim)
    if not final_readiness["ready"]:
        missing = ", ".join(module["label"] for module in final_readiness["missing_modules"])
        raise RuntimeError(f"Preparacao concluida, mas a Nota Tecnica ainda possui pendencias: {missing}.")

    return {
        "cnpj": clean,
        "prepared_modules": prepared_modules,
        "readiness": final_readiness,
    }


def prepare_relatorio_pdf_cnpj(
    cnpj: str,
    engine: Any,
    data_inicio: date | None = None,
    data_fim: date | None = None,
) -> dict[str, Any]:
    """Materializa os caches por CNPJ necessarios para gerar o relatorio PDF."""
    from .nota_tecnica_readiness import get_relatorio_pdf_readiness

    clean = _clean_cnpj(cnpj)
    initial_readiness = get_relatorio_pdf_readiness(clean, data_inicio, data_fim)

    if not initial_readiness["ready"] and not initial_readiness["preparable"]:
        missing = ", ".join(module["label"] for module in initial_readiness["missing_modules"])
        raise RuntimeError(f"Relatorio PDF possui modulos globais pendentes: {missing}.")

    prepared_modules: list[dict[str, Any]] = []
    for key in _RELATORIO_PDF_CNPJ_CACHE_KEYS:
        definition = cache_registry.get_cnpj_cache_definition(key)
        cache_path = _cnpj_cache_path(clean, definition.filename)
        if os.path.exists(cache_path):
            prepared_modules.append({
                "key": key,
                "label": _NOTA_TECNICA_CNPJ_CACHE_LABELS[key],
                "status": "already_ready",
                "file": os.path.join("cnpjs", clean, definition.filename),
            })
            continue

        try:
            cache_manager.sync_cnpj_cache(key, clean, engine)
        except Exception as exc:
            raise RuntimeError(_prepare_failure_message(key, exc)) from exc
        if not os.path.exists(cache_path):
            raise RuntimeError(
                f"Producer do modulo {key} concluiu sem criar o arquivo obrigatorio: "
                f"{os.path.join('cnpjs', clean, definition.filename)}"
            )

        prepared_modules.append({
            "key": key,
            "label": _NOTA_TECNICA_CNPJ_CACHE_LABELS[key],
            "status": "prepared",
            "file": os.path.join("cnpjs", clean, definition.filename),
        })

    final_readiness = get_relatorio_pdf_readiness(clean, data_inicio, data_fim)
    if not final_readiness["ready"]:
        missing = ", ".join(module["label"] for module in final_readiness["missing_modules"])
        raise RuntimeError(f"Preparacao concluida, mas o Relatorio PDF ainda possui pendencias: {missing}.")

    return {
        "cnpj": clean,
        "prepared_modules": prepared_modules,
        "readiness": final_readiness,
    }
