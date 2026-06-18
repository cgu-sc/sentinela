"""
sincronizar_cache.py
--------------------
Script interativo para sincronizar modulos do cache Sentinela com o CGUData.
Permite escolher exatamente quais modulos atualizar, sem precisar rodar tudo.

Uso:
    python src/scripts/sincronizar_cache.py

Dependencias:
    pip install sqlalchemy pyodbc pandas polars
"""

import os
import sys
import time

# Adiciona o backend ao path para importar data_cache e database.
ROOT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT_DIR, "backend"))

from database import engine
from data_cache import (
    _sync_analise_gtin_inconsistencia_clinica,
    _sync_analise_gtin_inconsistencia_clinica_municipio,
    _sync_analise_gtin_inconsistencia_clinica_regiao,
    _sync_cnpj_parquets,
    _sync_crm_benchmarks,
    _sync_crm_prescricoes_brasil_semestre,
    _sync_dados_farmacia,
    _sync_dados_ibge_demografia,
    _sync_dados_medico,
    _sync_dados_par,
    _sync_dados_socios,
    _sync_esocial,
    _sync_falecidos,
    _sync_geografico_origem_uf,
    _sync_localidades,
    _sync_matriz_risco,
    _sync_medicamentos,
    _sync_movimentacao,
    _sync_par_teia_alvos,
    _sync_perfil_estabelecimento,
    _sync_rede,
    _sync_sentinela_metadados_base,
    _sync_teia_expansao_completa,
    _sync_volume_atipico_semestral,
)


def _sync_clinica_anual_completa(engine, progress_callback=None):
    """Sincroniza os modulos clinicos anual por CNPJ, municipio e regiao."""
    def progress_cnpj(p: int):
        if progress_callback:
            progress_callback(int(p / 3))

    def progress_municipio(p: int):
        if progress_callback:
            progress_callback(33 + int(p / 3))

    def progress_regiao(p: int):
        if progress_callback:
            progress_callback(66 + int(p / 3))

    _sync_analise_gtin_inconsistencia_clinica(engine, progress_cnpj)
    _sync_analise_gtin_inconsistencia_clinica_municipio(engine, progress_municipio)
    _sync_analise_gtin_inconsistencia_clinica_regiao(engine, progress_regiao)

    if progress_callback:
        progress_callback(100)


MODULOS = sorted([
    {"id": 1, "name": "Localidades", "func": _sync_localidades, "peso": "rapido"},
    {"id": 2, "name": "Rede", "func": _sync_rede, "peso": "rapido"},
    {"id": 3, "name": "Matriz risco", "func": _sync_matriz_risco, "peso": "medio"},
    {"id": 18, "name": "Clinica anual completa", "func": _sync_clinica_anual_completa, "peso": "rapido"},
    {"id": 20, "name": "Clinica municipal", "func": _sync_analise_gtin_inconsistencia_clinica_municipio, "peso": "rapido"},
    {"id": 21, "name": "Clinica regiao", "func": _sync_analise_gtin_inconsistencia_clinica_regiao, "peso": "rapido"},
    {"id": 19, "name": "Demografia", "func": _sync_dados_ibge_demografia, "peso": "rapido"},
    {"id": 12, "name": "Volume atipico", "func": _sync_volume_atipico_semestral, "peso": "medio"},
    {"id": 22, "name": "Geo origem UF", "func": _sync_geografico_origem_uf, "peso": "rapido"},
    {"id": 16, "name": "eSocial", "func": _sync_esocial, "peso": "rapido"},
    {"id": 17, "name": "Metadados", "func": _sync_sentinela_metadados_base, "peso": "rapido"},
    {"id": 14, "name": "PAR", "func": _sync_dados_par, "peso": "rapido"},
    {"id": 7, "name": "Farmacias e CNAEs", "func": _sync_dados_farmacia, "peso": "medio"},
    {"id": 13, "name": "Perfil estab.", "func": _sync_perfil_estabelecimento, "peso": "medio"},
    {"id": 4, "name": "Falecidos global", "func": _sync_falecidos, "peso": "medio"},
    {"id": 5, "name": "Bench CRM", "func": _sync_crm_benchmarks, "peso": "rapido"},
    {"id": 23, "name": "CRM Brasil semestre", "func": _sync_crm_prescricoes_brasil_semestre, "peso": "rapido"},
    {"id": 24, "name": "Dados medico", "func": _sync_dados_medico, "peso": "rapido", "ordem": 5.5},
    {"id": 8, "name": "Movimentacao", "func": _sync_movimentacao, "peso": "muito pesado"},
    {"id": 9, "name": "Medicamentos", "func": _sync_medicamentos, "peso": "rapido"},
    {"id": 10, "name": "Socios", "func": _sync_dados_socios, "peso": "medio"},
    {"id": 11, "name": "Teia completa", "func": _sync_teia_expansao_completa, "peso": "pesado"},
    {"id": 15, "name": "PAR teia", "func": _sync_par_teia_alvos, "peso": "rapido"},
    {"id": 6, "name": "CNPJ modulos", "func": _sync_cnpj_parquets, "peso": "muito pesado", "ordem": 11.5},
], key=lambda modulo: modulo["id"])

DEPENDENCIAS_MODULOS = {
    6: {7, 10, 11},
    11: {10},
}


def _incluir_dependencias(selecionados: list[dict]) -> list[dict]:
    ids = {modulo["id"] for modulo in selecionados}
    pendentes = list(ids)

    while pendentes:
        modulo_id = pendentes.pop()
        for dependencia_id in DEPENDENCIAS_MODULOS.get(modulo_id, set()):
            if dependencia_id not in ids:
                ids.add(dependencia_id)
                pendentes.append(dependencia_id)

    return sorted(
        [modulo for modulo in MODULOS if modulo["id"] in ids],
        key=lambda modulo: modulo.get("ordem", modulo["id"]),
    )


def exibir_menu():
    print("\n" + "=" * 46)
    print(" SENTINELA - SYNC CACHE")
    print("=" * 46)
    for m in MODULOS:
        print(f" [{m['id']:>2}] {m['name']:<18} {m['peso']}")
    print("-" * 46)
    print("  [0] Sincronizar TODOS os modulos")
    print("=" * 46)


def selecionar_modulos() -> list[dict]:
    exibir_menu()
    entrada = input("\nDigite os numeros separados por virgula (ex: 1,3,7): ").strip()

    if entrada == "0":
        return _incluir_dependencias(MODULOS)

    ids_validos = {m["id"] for m in MODULOS}
    selecionados = []
    erros = []

    for parte in entrada.split(","):
        parte = parte.strip()
        if not parte:
            continue
        try:
            num = int(parte)
            if num in ids_validos:
                selecionados.append(next(m for m in MODULOS if m["id"] == num))
            else:
                erros.append(parte)
        except ValueError:
            erros.append(parte)

    if erros:
        print(f"\nAviso: opcoes ignoradas (invalidas): {', '.join(erros)}")

    return _incluir_dependencias(selecionados)


def perguntar_params(selecionados: list[dict]) -> None:
    """Coleta parametros extras para modulos que os suportam."""
    for modulo in selecionados:
        if modulo["id"] == 6:
            entrada = input(
                "\nCNPJs para exportar (separados por virgula) - Enter para TODOS: "
            ).strip()
            if entrada:
                modulo["params"] = {
                    "cnpjs": [c.strip() for c in entrada.split(",") if c.strip()]
                }


def confirmar(selecionados: list[dict]) -> bool:
    print("\nModulos selecionados para sincronizacao:")
    for m in selecionados:
        detalhe = ""
        if "params" in m and m["params"].get("cnpjs"):
            detalhe = f"  ({len(m['params']['cnpjs'])} CNPJ(s) especifico(s))"
        print(f"  - {m['name']}{detalhe}")
    resposta = input("\nConfirmar? [S/n]: ").strip().lower()
    return resposta in ("", "s", "sim", "y", "yes")


def progresso_console(nome: str, p: int):
    barra = int(p / 5)
    print(f"\r  {'#' * barra}{'.' * (20 - barra)} {p:>3}%  {nome}", end="", flush=True)


def executar(selecionados: list[dict]):
    total = len(selecionados)
    print(f"\nIniciando sincronizacao de {total} modulo(s)...\n")
    t_inicio = time.perf_counter()

    for i, modulo in enumerate(selecionados, 1):
        nome = modulo["name"]
        print(f"[{i}/{total}] {nome}")

        def callback(p, _nome=nome):
            progresso_console(_nome, p)

        t0 = time.perf_counter()
        try:
            modulo["func"](engine, callback, **modulo.get("params", {}))
            elapsed = time.perf_counter() - t0
            print(f"\r  OK {nome:<35} concluido em {elapsed:.1f}s")
        except Exception as e:
            print(f"\r  ERRO {nome:<33} {e}")

    total_elapsed = time.perf_counter() - t_inicio
    print(f"\n{'=' * 55}")
    print(f"  Sincronizacao concluida em {total_elapsed:.1f}s")
    print(f"{'=' * 55}\n")


def main():
    try:
        selecionados = selecionar_modulos()

        if not selecionados:
            print("\nAviso: nenhum modulo selecionado. Encerrando.")
            return

        perguntar_params(selecionados)

        if not confirmar(selecionados):
            print("\nOperacao cancelada.")
            return

        executar(selecionados)

    except KeyboardInterrupt:
        print("\n\nInterrompido pelo usuario.")


if __name__ == "__main__":
    main()
