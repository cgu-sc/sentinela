"""Verificacao explicita dos caches necessarios para documentos do CNPJ."""

from __future__ import annotations

import os
from datetime import date
from typing import Any

import cache_files
import cache_registry
from data_cache import get_cache_dir


def _clean_cnpj(cnpj: str) -> str:
    clean = "".join(ch for ch in str(cnpj or "") if ch.isdigit())
    if len(clean) != 14:
        raise ValueError("CNPJ invalido para verificacao da Nota Tecnica.")
    return clean


def _module(
    key: str,
    label: str,
    files: list[tuple[str, str]],
    *,
    scope: str,
    required: bool = True,
) -> dict[str, Any]:
    missing = [display for display, path in files if not os.path.exists(path)]
    return {
        "key": key,
        "label": label,
        "scope": scope,
        "required": required,
        "ready": not missing,
        "missing_files": missing,
        "detail": None if not missing else f"{len(missing)} arquivo(s) ausente(s).",
    }


def _global_files(keys: list[str], global_files: dict[str, str], cache_dir: str) -> list[tuple[str, str]]:
    files: list[tuple[str, str]] = []
    for key in keys:
        filename = global_files.get(key)
        display = filename or f"cache global nao registrado: {key}"
        path = os.path.join(cache_dir, filename) if filename else ""
        files.append((display, path))
    return files


def _cnpj_files(cnpj: str, filenames: list[str], cache_dir: str) -> list[tuple[str, str]]:
    return [
        (os.path.join(cnpj, filename), os.path.join(cache_dir, cnpj, filename))
        for filename in filenames
    ]


def _document_base_modules() -> list[dict[str, Any]]:
    cache_dir = get_cache_dir()
    global_files = cache_registry.get_global_parquet_files_by_key()

    return [
        _module(
            "base_cadastral",
            "Base cadastral do estabelecimento",
            _global_files(
                ["dados_farmacia", "perfil_estabelecimento", "localidades"],
                global_files,
                cache_dir,
            ),
            scope="global",
        ),
        _module(
            "movimentacao_matriz",
            "Movimentacao e matriz de risco",
            _global_files(
                [
                    "movimentacao",
                    "matriz_risco",
                    "volume_atipico_semestral",
                    "geografico_origem_uf",
                ],
                global_files,
                cache_dir,
            ),
            scope="global",
        ),
    ]


def _pdf_modules(cnpj: str) -> list[dict[str, Any]]:
    cache_dir = get_cache_dir()
    global_files = cache_registry.get_global_parquet_files_by_key()

    return [
        *_document_base_modules(),
        _module(
            "crm",
            "Dados de CRM",
            _global_files(
                [
                    "bench_crm_uf",
                    "bench_crm_regiao",
                    "bench_crm_br",
                    "crm_prescricoes_brasil_semestre",
                    "dados_medico",
                ],
                global_files,
                cache_dir,
            )
            + _cnpj_files(
                cnpj,
                [
                    cache_files.CRM_PRESCRITORES_PARQUET,
                    cache_files.GEOGRAFICO_PARQUET,
                    cache_files.CRM_CONCENTRACAO_UNICO_ALERTAS_PARQUET,
                    cache_files.CRM_CONCENTRACAO_MULTIPLO_ALERTAS_PARQUET,
                ],
                cache_dir,
            ),
            scope="cnpj",
        ),
        _module(
            "falecidos",
            "Vendas para pessoas falecidas",
            _global_files(["falecidos"], global_files, cache_dir),
            scope="global",
        ),
    ]


def _nota_tecnica_modules(cnpj: str) -> list[dict[str, Any]]:
    cache_dir = get_cache_dir()
    global_files = cache_registry.get_global_parquet_files_by_key()

    return [
        *_document_base_modules(),
        _module(
            "memoria_calculo",
            "Memoria de calculo do CNPJ",
            _cnpj_files(cnpj, [cache_files.MEMORIA_CALCULO_PARQUET], cache_dir),
            scope="cnpj",
        ),
        _module(
            "gtin_mensal",
            "Movimentacao mensal por GTIN",
            _cnpj_files(cnpj, [cache_files.MOVIMENTACAO_MENSAL_GTIN_PARQUET], cache_dir)
            + _global_files(["medicamentos"], global_files, cache_dir),
            scope="cnpj",
        ),
        _module(
            "falecidos",
            "Vendas para pessoas falecidas",
            _global_files(["falecidos"], global_files, cache_dir),
            scope="global",
        ),
        _module(
            "socios_esocial",
            "Socios e vinculos trabalhistas",
            _global_files(
                [
                    "dados_socios",
                    "esocial_cnpj_ano",
                    "esocial_cnpj_trabalhador_ano",
                    "esocial_cnpj_ultima_movimentacao",
                    "sentinela_metadados_base",
                ],
                global_files,
                cache_dir,
            ),
            scope="global",
        ),
        _module(
            "clinico",
            "Incompatibilidade clinica/patologica",
            _global_files(
                [
                    "analise_gtin_inconsistencia_clinica",
                    "analise_gtin_inconsistencia_clinica_municipio",
                    "analise_gtin_inconsistencia_clinica_regiao",
                    "dados_ibge_demografia",
                ],
                global_files,
                cache_dir,
            ),
            scope="global",
        ),
        _module(
            "crm",
            "Evidencias e indicadores de CRM",
            _global_files(
                [
                    "bench_crm_uf",
                    "bench_crm_regiao",
                    "bench_crm_br",
                    "crm_prescricoes_brasil_semestre",
                    "dados_medico",
                ],
                global_files,
                cache_dir,
            )
            + _cnpj_files(
                cnpj,
                [
                    cache_files.CRM_PRESCRITORES_PARQUET,
                    cache_files.GEOGRAFICO_PARQUET,
                    cache_files.CRM_RAIOX_TX_PARQUET,
                    cache_files.CRM_CONCENTRACAO_UNICO_ALERTAS_PARQUET,
                    cache_files.CRM_CONCENTRACAO_MULTIPLO_ALERTAS_PARQUET,
                    cache_files.CRM_TIMELINE_DIA_PARQUET,
                    cache_files.CRM_TIMELINE_HORA_PARQUET,
                    cache_files.CRM_TIMELINE_EVENTOS_PARQUET,
                ],
                cache_dir,
            ),
            scope="cnpj",
        ),
    ]


def _build_readiness(
    cnpj: str,
    modules: list[dict[str, Any]],
    data_inicio: date | None = None,
    data_fim: date | None = None,
) -> dict[str, Any]:
    clean = _clean_cnpj(cnpj)
    missing_modules = [module for module in modules if module["required"] and not module["ready"]]
    return {
        "cnpj": clean,
        "ready": not missing_modules,
        "data_inicio": data_inicio,
        "data_fim": data_fim,
        "modules": modules,
        "missing_modules": missing_modules,
    }


def get_nota_tecnica_readiness(
    cnpj: str,
    data_inicio: date | None = None,
    data_fim: date | None = None,
) -> dict[str, Any]:
    """Retorna a prontidao dos caches obrigatorios da Nota Tecnica."""
    clean = _clean_cnpj(cnpj)
    return _build_readiness(clean, _nota_tecnica_modules(clean), data_inicio, data_fim)


def get_relatorio_pdf_readiness(
    cnpj: str,
    data_inicio: date | None = None,
    data_fim: date | None = None,
) -> dict[str, Any]:
    """Retorna a prontidao dos caches obrigatorios do relatorio PDF."""
    clean = _clean_cnpj(cnpj)
    return _build_readiness(clean, _pdf_modules(clean), data_inicio, data_fim)
