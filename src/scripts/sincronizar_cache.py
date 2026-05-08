"""
sincronizar_cache.py
--------------------
Script interativo para sincronizar módulos do cache Sentinela com o CGUData.
Permite escolher exatamente quais módulos atualizar, sem precisar rodar tudo.

Uso:
    python src/scripts/sincronizar_cache.py

Dependências:
    pip install sqlalchemy pyodbc pandas polars
"""

import sys
import os
import time

# Adiciona o backend ao path para importar data_cache e database
ROOT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT_DIR, 'backend'))

from database import engine
from data_cache import (
    _sync_localidades,
    _sync_rede,
    _sync_matriz_risco,
    _sync_medicamentos,
    _sync_crm_benchmarks,
    _sync_dados_farmacia,
    _sync_dados_socios,
    _sync_socios_participacoes_externas,
    _sync_movimentacao,
)

_CNPJ_PARQUETS = [
    "memoria_calculo.parquet",
    "movimentacao_mensal_gtin.parquet",
    "falecidos.parquet",
    "dados_crms.parquet",
    "geografico.parquet",
    "volume_horario_anomalo_alertas.parquet",
    "crm_raiox_tx.parquet",
    "crm_concentracao_unico_alertas.parquet",
    "crm_concentracao_multiplo_alertas.parquet",
    "crm_perfil_diario.parquet",
    "crm_horario.parquet",
    "crm_horario_eventos.parquet",
    "mediana_autorizacoes_horaria.parquet",
    "network_nodes.parquet",
    "network_edges.parquet",
]


def _schema_cnpj_parquet(pl):
    """Schemas usados para criar parquets vazios quando nao ha dados no SQL."""
    return {
        "memoria_calculo.parquet": {
            "tipo_linha": pl.Utf8,
            "gtin": pl.Utf8,
            "medicamento": pl.Utf8,
            "periodo_inicial": pl.Utf8,
            "periodo_inicio_irregular": pl.Utf8,
            "periodo_final": pl.Utf8,
            "estoque_inicial": pl.Int64,
            "estoque_final": pl.Int64,
            "vendas": pl.Int64,
            "vendas_irregular": pl.Int64,
            "valor": pl.Float64,
            "valor_irregular": pl.Float64,
            "notas": pl.Utf8,
        },
        "movimentacao_mensal_gtin.parquet": {
            "codigo_barra": pl.Utf8,
            "periodo": pl.Date,
            "qnt_vendas": pl.Int64,
            "qnt_vendas_sem_comprovacao": pl.Int64,
            "valor_vendas": pl.Float64,
            "valor_sem_comprovacao": pl.Float64,
        },
        "falecidos.parquet": {
            "cpf": pl.Utf8,
            "cnpj": pl.Utf8,
            "nome_falecido": pl.Utf8,
            "municipio_falecido": pl.Utf8,
            "uf_falecido": pl.Utf8,
            "dt_nascimento": pl.Date,
            "dt_obito": pl.Date,
            "fonte_obito": pl.Utf8,
            "data_autorizacao": pl.Date,
            "num_autorizacao": pl.Utf8,
            "qtd_itens_na_autorizacao": pl.Int64,
            "valor_total_autorizacao": pl.Float64,
            "dias_apos_obito": pl.Int64,
        },
        "dados_crms.parquet": {
            "id_medico": pl.Utf8,
            "competencia": pl.Int32,
            "vl_total_prescricoes": pl.Float64,
            "nu_prescricoes_mes": pl.Int64,
            "nu_prescricoes_total_brasil": pl.Int64,
            "flag_crm_invalido": pl.Int8,
            "flag_prescricao_antes_registro": pl.Int8,
            "alerta_concentracao_multiplos_crms": pl.Int8,
            "flag_concentracao_mesmo_crm": pl.Int8,
            "flag_distancia_geografica": pl.Int8,
            "dt_primeira_prescricao": pl.Utf8,
            "dt_inscricao_crm": pl.Utf8,
            "nu_estabelecimentos": pl.Int64,
        },
        "geografico.parquet": {
            "id_medico": pl.Utf8,
            "competencia": pl.Int32,
            "cnpj_a": pl.Utf8,
            "no_municipio_a": pl.Utf8,
            "sg_uf_a": pl.Utf8,
            "dt_ini_a": pl.Utf8,
            "dt_fim_a": pl.Utf8,
            "nu_prescricoes_a": pl.Int32,
            "cnpj_b": pl.Utf8,
            "no_municipio_b": pl.Utf8,
            "sg_uf_b": pl.Utf8,
            "dt_ini_b": pl.Utf8,
            "dt_fim_b": pl.Utf8,
            "nu_prescricoes_b": pl.Int32,
            "distancia_km": pl.Float64,
        },
        "volume_horario_anomalo_alertas.parquet": {
            "id_cnpj": pl.Int32,
            "competencia": pl.Int32,
            "dt_alerta": pl.Utf8,
            "hr_janela": pl.Int32,
            "nu_prescricoes": pl.Int32,
            "nu_crms": pl.Int32,
            "mediana_hora": pl.Float64,
            "multiplicador": pl.Float64,
        },
        "crm_raiox_tx.parquet": {
            "dt_janela": pl.Utf8,
            "hr_janela": pl.Int32,
            "data_hora": pl.Utf8,
            "num_autorizacao": pl.Utf8,
            "id_medico": pl.Utf8,
            "codigo_barra": pl.Utf8,
            "valor_pago": pl.Float64,
        },
        "crm_concentracao_unico_alertas.parquet": {
            "id_medico": pl.Utf8,
            "competencia": pl.Int32,
            "dt_alerta": pl.Utf8,
            "hr_janela": pl.Int32,
            "nu_prescricoes_dia": pl.Int32,
            "nu_minutos_dia": pl.Int32,
            "taxa_hora": pl.Float64,
            "dt_ini_hora": pl.Datetime,
            "dt_fim_hora": pl.Datetime,
            "severidade": pl.Utf8,
            "nu_5min": pl.Int32,
            "nu_10min": pl.Int32,
            "nu_15min": pl.Int32,
            "nu_20min": pl.Int32,
            "nu_25min": pl.Int32,
            "nu_30min": pl.Int32,
            "nu_60min": pl.Int32,
        },
        "crm_concentracao_multiplo_alertas.parquet": {
            "id_cnpj": pl.Int32,
            "competencia": pl.Int32,
            "dt_dia": pl.Utf8,
            "dt_alerta": pl.Utf8,
            "hr_janela": pl.Int32,
            "dt_ini_concentracao": pl.Utf8,
            "dt_fim_concentracao": pl.Utf8,
            "nu_prescricoes": pl.Int32,
            "nu_crms": pl.Int32,
            "nu_60min": pl.Int32,
            "nu_minutos_span": pl.Int32,
            "nu_crms_distintos": pl.Int32,
            "severidade": pl.Utf8,
            "nu_5min": pl.Int32,
            "nu_10min": pl.Int32,
            "nu_15min": pl.Int32,
            "nu_20min": pl.Int32,
            "nu_25min": pl.Int32,
            "nu_30min": pl.Int32,
        },
        "crm_perfil_diario.parquet": {
            "dt_janela": pl.Utf8,
            "competencia": pl.Int32,
            "nu_prescricoes_dia": pl.Int32,
            "nu_crms_distintos": pl.Int32,
            "mediana_diaria": pl.Float64,
            "is_dia_com_volume_horario_anomalo": pl.Int8,
            "is_anomalo_unico": pl.Int8,
            "is_crm_multiplo": pl.Int8,
        },
        "crm_horario.parquet": {
            "dt_janela": pl.Utf8,
            "hr_janela": pl.Int32,
            "nu_prescricoes": pl.Int32,
            "nu_crms_diferentes": pl.Int32,
            "mediana_hora": pl.Float64,
            "is_hora_com_alerta": pl.Int8,
            "is_volume_horario_anomalo": pl.Int8,
            "is_crm_unico": pl.Int8,
            "is_crm_multiplo": pl.Int8,
        },
        "crm_horario_eventos.parquet": {
            "tipo": pl.Utf8,
            "dt_dia": pl.Utf8,
            "id_medico": pl.Utf8,
            "nu_crms_distintos": pl.Int32,
            "dt_ini_concentracao": pl.Datetime,
            "dt_fim_concentracao": pl.Datetime,
            "severidade": pl.Utf8,
            "hora_inicio": pl.Utf8,
            "hora_fim": pl.Utf8,
            "minuto_inicio": pl.Int32,
            "minuto_fim": pl.Int32,
        },
        "mediana_autorizacoes_horaria.parquet": {
            "ano": pl.Int32,
            "trimestre": pl.Int32,
            "hr_janela": pl.Int32,
            "mediana_hora": pl.Float64,
        },
        "network_nodes.parquet": {
            "id": pl.Utf8,
            "label": pl.Utf8,
            "type": pl.Utf8,
            "razao_social": pl.Utf8,
            "nome_fantasia": pl.Utf8,
            "municipio": pl.Utf8,
            "uf": pl.Utf8,
            "situacao_rf": pl.Utf8,
        },
        "network_edges.parquet": {
            "id": pl.Utf8,
            "source": pl.Utf8,
            "target": pl.Utf8,
            "label": pl.Utf8,
            "type": pl.Utf8,
        },
    }


def _criar_parquets_vazios(cnpj_dir: str, arquivos: list[str]) -> list[str]:
    """Materializa parquets vazios para caches opcionais sem dados."""
    import polars as pl

    schemas = _schema_cnpj_parquet(pl)
    criados = []
    for arquivo in arquivos:
        schema = schemas.get(arquivo)
        if not schema:
            continue
        path = os.path.join(cnpj_dir, arquivo)
        pl.DataFrame(schema=schema).write_parquet(path, compression="zstd")
        criados.append(arquivo)
    return criados


def _sync_falecidos(engine, progress_callback=None):
    """Gera os parquets de falecidos por CNPJ usando a rotina atual da API."""
    from sqlalchemy import text
    from api.services.analytics import AnalyticsService

    with engine.connect() as conn:
        res = conn.execute(text("""
            SELECT DISTINCT cnpj
            FROM [temp_CGUSC].[fp].[falecidos_por_farmacia]
            ORDER BY cnpj
        """))
        cnpjs = [row[0] for row in res if row[0]]

    total = len(cnpjs)
    print(f"Sincronizando Falecidos por Farmacia para {total} estabelecimento(s)...")

    if total == 0:
        if progress_callback:
            progress_callback(100)
        return

    for i, cnpj in enumerate(cnpjs, 1):
        try:
            AnalyticsService.get_falecidos_data(str(cnpj))
        except Exception as e:
            print(f"\n  Aviso: erro ao sincronizar falecidos do CNPJ {cnpj}: {e}")
        if progress_callback:
            progress_callback(int((i / total) * 100))


def _buscar_cnpjs_matriz(engine) -> list[str]:
    """Busca os CNPJs ativos da matriz de risco para sincronizacao em lote."""
    from sqlalchemy import text

    with engine.connect() as conn:
        res = conn.execute(text("""
            SELECT DISTINCT cnpj
            FROM [temp_CGUSC].[fp].[matriz_risco_consolidada]
            ORDER BY cnpj
        """))
        return [str(row[0]).strip() for row in res if row[0]]


def _sync_cnpj_parquets(engine, progress_callback=None, cnpjs: list[str] | None = None):
    """Gera todos os parquets mantidos em sentinela_cache/<cnpj>/."""
    from api.services.analytics import AnalyticsService

    if not cnpjs:
        cnpjs = _buscar_cnpjs_matriz(engine)

    cnpjs = [str(cnpj).strip() for cnpj in cnpjs if str(cnpj).strip()]
    total = len(cnpjs)
    print(f"Sincronizando todos os parquets por CNPJ para {total} estabelecimento(s)...")

    if total == 0:
        if progress_callback:
            progress_callback(100)
        return

    etapas = [
        ("memoria_calculo", lambda cnpj: AnalyticsService.get_movimentacao_data(cnpj, engine, check_cache=False)),
        ("movimentacao_mensal_gtin", lambda cnpj: AnalyticsService.get_evolucao_mensal_gtin(cnpj)),
        ("falecidos", lambda cnpj: AnalyticsService.get_falecidos_data(cnpj)),
        ("crm_dados", lambda cnpj: AnalyticsService.get_crm_data(cnpj)),
        ("crm_perfil_diario", lambda cnpj: AnalyticsService.get_crm_perfil_diario(cnpj)),
        ("crm_perfil_horario", lambda cnpj: AnalyticsService.get_crm_perfil_horario(cnpj)),
        ("crm_raiox_tx", lambda cnpj: AnalyticsService.sync_crm_raiox_tx(cnpj)),
        ("mediana_horaria", lambda cnpj: AnalyticsService.sync_mediana_autorizacoes_horaria(cnpj)),
        ("teia_societaria", lambda cnpj: AnalyticsService.sync_network(cnpj)),
    ]

    for i, cnpj in enumerate(cnpjs, 1):
        print(f"\n  [{i}/{total}] CNPJ {cnpj}")

        for nome_etapa, func in etapas:
            try:
                print(f"    - {nome_etapa}...", end="", flush=True)
                func(cnpj)
                print(" ok")
            except Exception as e:
                print(f" erro: {e}")

        cnpj_dir = AnalyticsService._get_cnpj_cache_dir(cnpj)
        faltantes = [
            arquivo for arquivo in _CNPJ_PARQUETS
            if not os.path.exists(os.path.join(cnpj_dir, arquivo))
        ]
        if faltantes:
            criados = _criar_parquets_vazios(cnpj_dir, faltantes)
            if criados:
                print(f"    Parquets vazios criados: {', '.join(criados)}")

            ainda_faltantes = [
                arquivo for arquivo in _CNPJ_PARQUETS
                if not os.path.exists(os.path.join(cnpj_dir, arquivo))
            ]
            if ainda_faltantes:
                print(f"    Aviso: parquets faltantes: {', '.join(ainda_faltantes)}")

        if progress_callback:
            progress_callback(int((i / total) * 100))

    if progress_callback:
        progress_callback(100)

# ── Módulos disponíveis ────────────────────────────────────────────────────────

MODULOS = [
    {"id": 1, "name": "Localidades (IBGE)",        "func": _sync_localidades,    "peso": "~rápido"},
    {"id": 2, "name": "Rede de Estabelecimentos",  "func": _sync_rede,           "peso": "~rápido"},
    {"id": 3, "name": "Matriz de Risco",           "func": _sync_matriz_risco,   "peso": "~médio"},
    {"id": 4, "name": "Falecidos por Farmácia",    "func": _sync_falecidos,      "peso": "~médio"},
    {"id": 5, "name": "Benchmarks CRM",            "func": _sync_crm_benchmarks, "peso": "~rápido"},
    {"id": 6, "name": "Todos por CNPJ (parquets)", "func": _sync_cnpj_parquets,  "peso": "~muito pesado"},
    {"id": 7, "name": "Dados das Farmácias",       "func": _sync_dados_farmacia, "peso": "~médio"},
    {"id": 8, "name": "Movimentação Mensal",       "func": _sync_movimentacao,   "peso": "~muito pesado"},
    {"id": 9, "name": "Cadastro de Medicamentos",  "func": _sync_medicamentos,   "peso": "~rápido"},
    {"id": 10, "name": "Dados dos Sócios",         "func": _sync_dados_socios,   "peso": "~médio"},
    {"id": 11, "name": "Participações Externas",   "func": _sync_socios_participacoes_externas, "peso": "~médio"},
]

# ── Menu ───────────────────────────────────────────────────────────────────────

def exibir_menu():
    print("\n" + "=" * 55)
    print("   SENTINELA — SINCRONIZAÇÃO SELETIVA DE CACHE")
    print("=" * 55)
    for m in MODULOS:
        print(f"  [{m['id']}] {m['name']:<25} {m['peso']}")
    print("-" * 55)
    print("  [0] Sincronizar TODOS os módulos")
    print("=" * 55)

def selecionar_modulos() -> list[dict]:
    exibir_menu()
    entrada = input("\nDigite os números separados por vírgula (ex: 1,3,7): ").strip()

    if entrada == '0':
        return MODULOS

    ids_validos = {m["id"] for m in MODULOS}
    selecionados = []
    erros = []

    for parte in entrada.split(','):
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
        print(f"\n⚠️  Opções ignoradas (inválidas): {', '.join(erros)}")

    # Mantém a ordem original dos módulos
    ordem = {m["id"]: i for i, m in enumerate(MODULOS)}
    return sorted(selecionados, key=lambda m: ordem[m["id"]])

# ── Execução ───────────────────────────────────────────────────────────────────

def perguntar_params(selecionados: list[dict]) -> None:
    """Coleta parâmetros extras para módulos que os suportam."""
    for modulo in selecionados:
        if modulo["id"] == 6:
            entrada = input(
                "\nCNPJs para exportar (separados por vírgula) — Enter para TODOS: "
            ).strip()
            if entrada:
                modulo["params"] = {
                    "cnpjs": [c.strip() for c in entrada.split(",") if c.strip()]
                }


def confirmar(selecionados: list[dict]) -> bool:
    print("\nMódulos selecionados para sincronização:")
    for m in selecionados:
        detalhe = ""
        if "params" in m and m["params"].get("cnpjs"):
            detalhe = f"  ({len(m['params']['cnpjs'])} CNPJ(s) específico(s))"
        print(f"  • {m['name']}{detalhe}")
    resposta = input("\nConfirmar? [S/n]: ").strip().lower()
    return resposta in ('', 's', 'sim', 'y', 'yes')

def progresso_console(nome: str, p: int):
    barra = int(p / 5)
    print(f"\r  {'█' * barra}{'░' * (20 - barra)} {p:>3}%  {nome}", end='', flush=True)

def executar(selecionados: list[dict]):
    total = len(selecionados)
    print(f"\n🚀 Iniciando sincronização de {total} módulo(s)...\n")
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
            print(f"\r  ✅ {nome:<25} concluído em {elapsed:.1f}s")
        except Exception as e:
            print(f"\r  ❌ {nome:<25} ERRO: {e}")

    total_elapsed = time.perf_counter() - t_inicio
    print(f"\n{'=' * 55}")
    print(f"  Sincronização concluída em {total_elapsed:.1f}s")
    print(f"{'=' * 55}\n")

# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    try:
        selecionados = selecionar_modulos()

        if not selecionados:
            print("\n⚠️  Nenhum módulo selecionado. Encerrando.")
            return

        perguntar_params(selecionados)

        if not confirmar(selecionados):
            print("\n⛔ Operação cancelada.")
            return

        executar(selecionados)

    except KeyboardInterrupt:
        print("\n\n⛔ Interrompido pelo usuário.")


if __name__ == '__main__':
    main()
