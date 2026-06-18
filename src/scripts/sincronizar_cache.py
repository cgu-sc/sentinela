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

from sqlalchemy import text

from database import engine
from data_cache import (
    _sync_analise_gtin_inconsistencia_clinica,
    _sync_analise_gtin_inconsistencia_clinica_municipio,
    _sync_analise_gtin_inconsistencia_clinica_regiao,
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


CRM_CNPJ_CACHE_KEYS = [
    ("crm_prescritores", "CRM prescritores"),
    ("geografico", "CRM geografico"),
    ("crm_concentracao_unico_alertas", "CRM concentracao unico"),
    ("crm_concentracao_multiplo_alertas", "CRM concentracao multiplo"),
    ("crm_timeline_dia", "CRM timeline dia"),
    ("crm_timeline_hora", "CRM timeline hora"),
    ("crm_timeline_eventos", "CRM timeline eventos"),
    ("crm_raiox_tx", "CRM Raio-X transacoes"),
]

CRM_CNPJ_INDIVIDUAL_IDS = frozenset(range(26, 34))


def _buscar_cnpjs_crm(engine) -> list[str]:
    """Retorna os CNPJs elegiveis para sincronizacao de modulos CRM por CNPJ."""
    with engine.connect() as conn:
        res = conn.execute(text("""
            SELECT DISTINCT F.cnpj
            FROM temp_CGUSC.fp.matriz_risco_consolidada M
            INNER JOIN temp_CGUSC.fp.dados_farmacia F
                ON F.id = M.id_cnpj
            ORDER BY F.cnpj
        """))
        return [str(r[0]).strip() for r in res if str(r[0]).strip()]


def _sync_crm_cnpj_unit(cache_key: str, cnpj: str, engine) -> None:
    import cache_manager

    cache_manager.sync_cnpj_cache(cache_key, cnpj, engine)


def _sync_crm_cnpj_cache_key(cache_key: str, engine, progress_callback=None) -> None:
    """Sincroniza um modulo CRM por CNPJ usando o produtor registrado no cache_registry."""
    cnpjs_sync = _buscar_cnpjs_crm(engine)

    total = len(cnpjs_sync)
    print(f"Sincronizando {cache_key} para {total} estabelecimento(s)...")

    if total == 0:
        if progress_callback:
            progress_callback(100)
        return

    for i, cnpj in enumerate(cnpjs_sync, 1):
        try:
            _sync_crm_cnpj_unit(cache_key, cnpj, engine)
            if progress_callback:
                progress_callback(int((i / total) * 100))
        except Exception as e:
            print(f"\n[AVISO] Erro ao sincronizar {cache_key} para CNPJ {cnpj}: {e}")
            raise

    if progress_callback:
        progress_callback(100)


def _criar_sync_crm_cnpj(cache_key: str):
    def _sync(engine, progress_callback=None):
        return _sync_crm_cnpj_cache_key(cache_key, engine, progress_callback)

    return _sync


def _sync_crm_cnpj_completo(engine, progress_callback=None) -> None:
    """Sincroniza somente os modulos CRM ativos por CNPJ."""
    cnpjs_sync = _buscar_cnpjs_crm(engine)

    total = len(cnpjs_sync)
    if total == 0:
        if progress_callback:
            progress_callback(100)
        return

    print(
        "Sincronizando pacote CRM por CNPJ: "
        f"{len(CRM_CNPJ_CACHE_KEYS)} modulo(s), {total} estabelecimento(s)..."
    )

    total_steps = total * len(CRM_CNPJ_CACHE_KEYS)
    step = 0
    for cnpj in cnpjs_sync:
        for cache_key, label in CRM_CNPJ_CACHE_KEYS:
            try:
                _sync_crm_cnpj_unit(cache_key, cnpj, engine)
                step += 1
                if progress_callback:
                    progress_callback(int((step / total_steps) * 100))
            except Exception as e:
                print(f"\n[AVISO] Erro ao sincronizar {label} para CNPJ {cnpj}: {e}")
                raise

    if progress_callback:
        progress_callback(100)


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
    {"id": 1, "name": "Localidades", "func": _sync_localidades, "peso": "rapido", "ordem": 1},
    {"id": 2, "name": "Rede", "func": _sync_rede, "peso": "rapido", "ordem": 2},
    {"id": 3, "name": "Matriz risco", "func": _sync_matriz_risco, "peso": "medio", "ordem": 3},
    {"id": 4, "name": "Falecidos global", "func": _sync_falecidos, "peso": "medio", "ordem": 4},
    {"id": 5, "name": "Bench CRM", "func": _sync_crm_benchmarks, "peso": "rapido", "ordem": 5},
    {"id": 23, "name": "CRM Brasil semestre", "func": _sync_crm_prescricoes_brasil_semestre, "peso": "rapido", "ordem": 5.1},
    {"id": 24, "name": "Dados medico", "func": _sync_dados_medico, "peso": "rapido", "ordem": 5.2},
    {"id": 25, "name": "CRM CNPJ completo", "func": _sync_crm_cnpj_completo, "peso": "pesado", "ordem": 5.3},
    {"id": 26, "name": "CRM prescritores", "func": _criar_sync_crm_cnpj("crm_prescritores"), "peso": "medio", "ordem": 5.4},
    {"id": 27, "name": "CRM geografico", "func": _criar_sync_crm_cnpj("geografico"), "peso": "medio", "ordem": 5.5},
    {"id": 28, "name": "CRM conc. unico", "func": _criar_sync_crm_cnpj("crm_concentracao_unico_alertas"), "peso": "medio", "ordem": 5.6},
    {"id": 29, "name": "CRM conc. multiplo", "func": _criar_sync_crm_cnpj("crm_concentracao_multiplo_alertas"), "peso": "medio", "ordem": 5.7},
    {"id": 30, "name": "CRM timeline dia", "func": _criar_sync_crm_cnpj("crm_timeline_dia"), "peso": "medio", "ordem": 5.8},
    {"id": 31, "name": "CRM timeline hora", "func": _criar_sync_crm_cnpj("crm_timeline_hora"), "peso": "medio", "ordem": 5.9},
    {"id": 32, "name": "CRM timeline eventos", "func": _criar_sync_crm_cnpj("crm_timeline_eventos"), "peso": "medio", "ordem": 6.0},
    {"id": 33, "name": "CRM Raio-X", "func": _criar_sync_crm_cnpj("crm_raiox_tx"), "peso": "medio", "ordem": 6.1},
    {"id": 7, "name": "Farmacias e CNAEs", "func": _sync_dados_farmacia, "peso": "medio", "ordem": 7},
    {"id": 13, "name": "Perfil estab.", "func": _sync_perfil_estabelecimento, "peso": "medio", "ordem": 7.5},
    {"id": 8, "name": "Movimentacao", "func": _sync_movimentacao, "peso": "muito pesado", "ordem": 8},
    {"id": 9, "name": "Medicamentos", "func": _sync_medicamentos, "peso": "rapido", "ordem": 9},
    {"id": 10, "name": "Socios", "func": _sync_dados_socios, "peso": "medio", "ordem": 10},
    {"id": 11, "name": "Teia completa", "func": _sync_teia_expansao_completa, "peso": "pesado", "ordem": 11},
    {"id": 12, "name": "Volume atipico", "func": _sync_volume_atipico_semestral, "peso": "medio", "ordem": 12},
    {"id": 14, "name": "PAR", "func": _sync_dados_par, "peso": "rapido", "ordem": 14},
    {"id": 15, "name": "PAR teia", "func": _sync_par_teia_alvos, "peso": "rapido", "ordem": 15},
    {"id": 16, "name": "eSocial", "func": _sync_esocial, "peso": "rapido", "ordem": 16},
    {"id": 17, "name": "Metadados", "func": _sync_sentinela_metadados_base, "peso": "rapido", "ordem": 17},
    {"id": 18, "name": "Clinica anual completa", "func": _sync_clinica_anual_completa, "peso": "rapido", "ordem": 18},
    {"id": 19, "name": "Demografia", "func": _sync_dados_ibge_demografia, "peso": "rapido", "ordem": 19},
    {"id": 20, "name": "Clinica municipal", "func": _sync_analise_gtin_inconsistencia_clinica_municipio, "peso": "rapido", "ordem": 20},
    {"id": 21, "name": "Clinica regiao", "func": _sync_analise_gtin_inconsistencia_clinica_regiao, "peso": "rapido", "ordem": 21},
    {"id": 22, "name": "Geo origem UF", "func": _sync_geografico_origem_uf, "peso": "rapido", "ordem": 22},
], key=lambda modulo: modulo["ordem"])

DEPENDENCIAS_MODULOS = {
    11: {10},
    25: {24},
    26: {24},
}


def _incluir_dependencias(selecionados: list[dict]) -> list[dict]:
    ids = {modulo["id"] for modulo in selecionados}
    if 25 in ids:
        ids.difference_update(CRM_CNPJ_INDIVIDUAL_IDS)

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
        modulos_todos = [
            modulo for modulo in MODULOS
            if modulo["id"] not in CRM_CNPJ_INDIVIDUAL_IDS
        ]
        return _incluir_dependencias(modulos_todos)

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


def confirmar(selecionados: list[dict]) -> bool:
    print("\nModulos selecionados para sincronizacao:")
    for m in selecionados:
        print(f"  - {m['name']}")
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
            modulo["func"](engine, callback)
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

        if not confirmar(selecionados):
            print("\nOperacao cancelada.")
            return

        executar(selecionados)

    except KeyboardInterrupt:
        print("\n\nInterrompido pelo usuario.")


if __name__ == "__main__":
    main()
