from typing import List, Optional
from datetime import date
import calendar
import polars as pl
from sqlalchemy.orm import Session
from sqlalchemy import text
from fastapi import HTTPException
import os
import zlib
import json
import copy
from decimal import Decimal, ROUND_HALF_UP
from data_cache import get_df, get_rede_df, get_localidades_df, get_df_matriz_risco, get_df_bench_crm_regiao, get_df_bench_crm_br, get_df_dados_farmacia, get_cache_dir
from ...schemas.analytics import (
    AnalyticsKPISchema,
    ResultadoSentinelaUFSchema,
    AnalyticsResponse,
    ResultadoSentinelaSchema,
    ResultadoSentinelaMunicipioSchema,
    ResultadoSentinelaCnpjSchema,
    RedeEstabelecimentoSchema,
    FatorRiscoResponseSchema,
    FatorRiscoBucketSchema,
    EvolucaoSemestreSchema,
    EvolucaoFinanceiraResponse,
    IndicadorDataSchema,
    IndicadoresResponse,
    FalecidoTransactionSchema,
    FalecidosRankingSchema,
    FalecidosSummarySchema,
    FalecidosResponse,
    TimelineEventSchema,
    MultiCnpjTimelineResponse,
    RegionalMunicipioSchema,
    RegionalFarmaciaSchema,
    RegionalResponse,
    RegionalAnimationQuarterSchema,
    RegionalAnimationResponse,
    PrescritoresResponse,
    DadosFarmaciaSchema,
    MovimentacaoRowSchema,
    MovimentacaoSummarySchema,
    MovimentacaoResponse,
    IndicadorKpiSummarySchema,
    IndicadorCnpjRowSchema,
    IndicadorMunicipioRowSchema,
    IndicadorAnaliseResponse,
    CrmDailyProfileResponse,
    CrmHourlyProfileResponse,
    CrmMultiplosRaioXResponse,
    CrmUnicoRaioXResponse,
    MesMensalGtinItem,
    EvolucaoMensalGtinResponse,
    GtinDetalhamentoMensalResponse,
    GtinDetalhamentoMensalSummary,
    GtinDetalhamentoMensalItem,
)

from ._cache import _get_cnpj_cache_dir

def get_falecidos_data(
    cnpj: str,
    data_inicio: date | None = None,
    data_fim:    date | None = None,
) -> FalecidosResponse:
    """
    Retorna os dados detalhados de vendas para falecidos de um CNPJ.

    O parquet por CNPJ armazena as transações do próprio estabelecimento e de todos
    os demais CNPJs onde os mesmos CPFs compraram, permitindo calcular o ranking
    Multi-CNPJ a partir do cache local sem depender do dataset global.
    """
    import time
    import pandas as pd
    from sqlalchemy import text

    PARQUET_PATH = os.path.join(_get_cnpj_cache_dir(cnpj), "falecidos.parquet")
    from_cache    = False
    query_time_ms: float | None = None
    save_time_ms:  float | None = None
    read_time_ms:  float | None = None
    df_all = None

    # ── 1. Tentar carregar do cache local ────────────────────────────────
    if os.path.exists(PARQUET_PATH):
        try:
            t0 = time.perf_counter()
            df_all = pl.read_parquet(PARQUET_PATH)
            read_time_ms = round((time.perf_counter() - t0) * 1000, 1)
            from_cache = True
        except Exception as e:
            print(f"⚠️ Erro ao ler parquet falecidos '{cnpj}': {e}")

    # ── 2. Gerar parquet via SQL (primeira vez ou cache corrompido) ──────
    if df_all is None:
        try:
            from database import engine as _engine
            with _engine.connect() as conn:
                t0 = time.perf_counter()
                pdf = pd.read_sql(
                    text("""
                        SELECT f.*
                        FROM [temp_CGUSC].[fp].[falecidos_por_farmacia] f
                        WHERE f.cpf IN (
                            SELECT DISTINCT cpf
                            FROM [temp_CGUSC].[fp].[falecidos_por_farmacia]
                            WHERE cnpj = :cnpj
                        )
                    """),
                    conn,
                    params={"cnpj": cnpj},
                )
                query_time_ms = round((time.perf_counter() - t0) * 1000, 1)

            df_all = pl.from_pandas(pdf).with_columns([
                pl.col("dt_nascimento").cast(pl.Date, strict=False),
                pl.col("dt_obito").cast(pl.Date, strict=False),
                pl.col("data_autorizacao").cast(pl.Date, strict=False),
            ])
            t1 = time.perf_counter()
            df_all.write_parquet(PARQUET_PATH, compression="lz4")
            save_time_ms = round((time.perf_counter() - t1) * 1000, 1)
            print(f"⏱  Falecidos {cnpj}: SQL {query_time_ms}ms | parquet {save_time_ms}ms")

        except Exception as e:
            import traceback
            print(f"⚠️ Erro ao gerar parquet falecidos '{cnpj}': {e}")
            print(traceback.format_exc())
            df_all = pl.DataFrame()

    # ── 3. Filtro de período ─────────────────────────────────────────────
    if data_inicio:
        df_all = df_all.filter(pl.col("data_autorizacao") >= pl.lit(data_inicio).cast(pl.Date))
    if data_fim:
        df_all = df_all.filter(pl.col("data_autorizacao") <= pl.lit(data_fim).cast(pl.Date))

    _empty_response = FalecidosResponse(
        cnpj=cnpj,
        summary=FalecidosSummarySchema(
            cpfs_distintos=0, total_autorizacoes=0, valor_total=0.0,
            media_dias=0.0, max_dias=0, pct_faturamento=0.0,
            cpfs_multi_cnpj=0, pct_multi_cnpj=0.0,
        ),
        ranking=[],
        transacoes=[],
        from_cache=from_cache,
        query_time_ms=query_time_ms,
        save_time_ms=save_time_ms,
        read_time_ms=read_time_ms,
    )

    try:
        df_target = df_all.filter(pl.col("cnpj") == cnpj)

        if df_target.is_empty():
            return _empty_response

        # 1. KPIs Básicos
        cpfs_distintos = df_target["cpf"].n_unique()
        total_autorizacoes = df_target.height
        valor_total = float(df_target["valor_total_autorizacao"].sum() or 0.0)
        media_dias = float(df_target["dias_apos_obito"].mean() or 0.0)
        max_dias = int(df_target["dias_apos_obito"].max() or 0)

        # 2. Lógica Multi-CNPJ (Inteligência Cross-Pharmacy)
        # Encontra outros estabelecimentos onde ESSES CPFs compraram
        cpfs_alvo = df_target["cpf"].unique()
        df_outros = df_all.filter((pl.col("cpf").is_in(cpfs_alvo)) & (pl.col("cnpj") != cnpj))
        
        # Mapeia quais CPFs são Multi-CNPJ
        cpfs_multi = df_outros["cpf"].unique().to_list()
        cpfs_multi_cnpj = len(cpfs_multi)
        pct_multi_cnpj = cpfs_multi_cnpj / cpfs_distintos if cpfs_distintos > 0 else 0.0

        # 3. Ranking de Outros Estabelecimentos
        # Precisamos dos nomes das farmácias. Vamos usar a rede_df se possível.
        try:
            rede_df = get_rede_df().select(["cnpj", "razao_social", "municipio", "uf"])
            df_outros_nomes = df_outros.join(rede_df, on="cnpj", how="left")
            
            ranking_df = (
                df_outros_nomes
                .with_columns([
                    pl.concat_str([
                        pl.col("cnpj"), pl.lit(" - "), 
                        pl.col("razao_social").fill_null("DESCONHECIDO"),
                        pl.lit(" | "), 
                        pl.col("municipio").fill_null(""),
                        pl.lit("/"),
                        pl.col("uf").fill_null("")
                    ]).alias("estab")
                ])
                .group_by("estab")
                .agg([pl.col("cpf").n_unique().alias("qtd")])
                .with_columns([
                    (pl.col("qtd") / pl.when(pl.col("qtd").sum() > 0).then(pl.col("qtd").sum()).otherwise(1)).alias("pct")
                ])
                .sort("qtd", descending=True)
                .head(20)
            )
            ranking = [
                FalecidosRankingSchema(estabelecimento=r["estab"], qtd_cpfs=r["qtd"], pct_total=r["pct"])
                for r in ranking_df.iter_rows(named=True)
            ]
        except:
            ranking = []

        # 4. Cálculo do % de faturamento (usando o faturamento total cacheado)
        pct_faturamento = 0.0
        try:
            mov_df = get_df().filter(pl.col("cnpj") == cnpj)
            total_faturamento = float(mov_df["total_vendas"].sum() or 1.0)
            pct_faturamento = valor_total / total_faturamento if total_faturamento > 0 else 0.0
        except: pass

        # 5. Lista de Transações (com flag de multi-cnpj)
        # Vamos gerar a string de 'outros_estabelecimentos' para cada CPF
        try:
            outros_info = (
                df_outros_nomes
                .with_columns([
                    pl.concat_str([
                        pl.col("cnpj"), pl.lit(" | "), pl.col("municipio"), pl.lit("/"), pl.col("uf")
                    ]).alias("info")
                ])
                .group_by("cpf")
                .agg([pl.col("info").unique().str.join("; ").alias("outros")])
            )
            df_final = df_target.join(outros_info, on="cpf", how="left")
        except:
            df_final = df_target.with_columns(pl.lit(None).alias("outros"))

        transacoes = [
            FalecidoTransactionSchema(
                cpf=str(r["cpf"]).zfill(11),
                nome_falecido=r["nome_falecido"],
                municipio_falecido=r["municipio_falecido"],
                uf_falecido=r["uf_falecido"],
                dt_nascimento=r["dt_nascimento"],
                dt_obito=r["dt_obito"],
                fonte_obito=r["fonte_obito"],
                num_autorizacao=str(r["num_autorizacao"]),
                data_autorizacao=r["data_autorizacao"],
                qtd_itens_na_autorizacao=int(r["qtd_itens_na_autorizacao"] or 0),
                valor_total_autorizacao=float(r["valor_total_autorizacao"] or 0.0),
                dias_apos_obito=int(r["dias_apos_obito"] or 0),
                outros_estabelecimentos=r["outros"]
            )
            for r in df_final.sort(["cpf", "data_autorizacao"]).iter_rows(named=True)
        ]

        return FalecidosResponse(
            cnpj=cnpj,
            summary=FalecidosSummarySchema(
                cpfs_distintos=cpfs_distintos,
                total_autorizacoes=total_autorizacoes,
                valor_total=valor_total,
                media_dias=media_dias,
                max_dias=max_dias,
                pct_faturamento=pct_faturamento,
                cpfs_multi_cnpj=cpfs_multi_cnpj,
                pct_multi_cnpj=pct_multi_cnpj,
            ),
            ranking=ranking,
            transacoes=transacoes,
            from_cache=from_cache,
            query_time_ms=query_time_ms,
            save_time_ms=save_time_ms,
            read_time_ms=read_time_ms,
        )

    except Exception as e:
        import traceback
        print(f"❌ ERRO AO CALCULAR DADOS DE FALECIDOS: {e}")
        print(traceback.format_exc())
        return _empty_response

def get_timeline_cpf(cnpj_referencia: str, cpf: str) -> MultiCnpjTimelineResponse:
    """
    Retorna TODAS as transações de um CPF em TODOS os estabelecimentos
    presentes no dataset de falecidos. Permite montar o Mapa de Trilhas
    Temporais com dados 100% reais.

    Args:
        cnpj_referencia: O CNPJ do estabelecimento que originou a consulta
                         (usado para marcar `is_this_cnpj`).
        cpf: O CPF do paciente falecido a ser pesquisado.
    """
    try:
        # O parquet por CNPJ contém todas as transações dos CPFs do estabelecimento
        # (incluindo outras farmácias), suficiente para montar a linha do tempo.
        PARQUET_PATH = os.path.join(
            _get_cnpj_cache_dir(cnpj_referencia), "falecidos.parquet"
        )
        if not os.path.exists(PARQUET_PATH):
            return MultiCnpjTimelineResponse(
                cpf=cpf, nome_falecido=None, dt_obito=None, events=[], cnpjs_envolvidos=[]
            )
        df_all = pl.read_parquet(PARQUET_PATH)

        # Normaliza o CPF (remove zeros à esquerda para comparação segura)
        cpf_clean = cpf.strip().lstrip('0').zfill(11)
        df_cpf = df_all.filter(pl.col("cpf").cast(pl.Utf8).str.zfill(11) == cpf_clean)

        if df_cpf.is_empty():
            return MultiCnpjTimelineResponse(
                cpf=cpf, nome_falecido=None, dt_obito=None,
                events=[], cnpjs_envolvidos=[]
            )

        # Dados biográficos do falecido (primeira ocorrência)
        row0 = df_cpf.row(0, named=True)
        nome_falecido = row0.get("nome_falecido")
        dt_obito = row0.get("dt_obito")

        # Enriquece com razão social via rede_df
        try:
            rede_df = get_rede_df().select(["cnpj", "razao_social", "municipio", "uf"])
            df_enrich = df_cpf.join(rede_df, on="cnpj", how="left")
        except Exception:
            df_enrich = df_cpf.with_columns([
                pl.lit(None).cast(pl.Utf8).alias("razao_social"),
                pl.lit(None).cast(pl.Utf8).alias("municipio"),
                pl.lit(None).cast(pl.Utf8).alias("uf"),
            ])

        # Monta os eventos
        events = []
        for r in df_enrich.sort("data_autorizacao").iter_rows(named=True):
            events.append(TimelineEventSchema(
                cnpj=str(r["cnpj"]),
                razao_social=r.get("razao_social"),
                municipio=r.get("municipio"),
                uf=r.get("uf"),
                data_autorizacao=r.get("data_autorizacao"),
                valor_total_autorizacao=float(r.get("valor_total_autorizacao") or 0.0),
                num_autorizacao=str(r.get("num_autorizacao") or ""),
                is_this_cnpj=(str(r["cnpj"]) == cnpj_referencia),
            ))

        cnpjs_envolvidos = df_cpf["cnpj"].unique().to_list()

        return MultiCnpjTimelineResponse(
            cpf=cpf,
            nome_falecido=nome_falecido,
            dt_obito=dt_obito,
            events=events,
            cnpjs_envolvidos=cnpjs_envolvidos,
        )

    except Exception as e:
        import traceback
        print(f"❌ ERRO AO BUSCAR TIMELINE DO CPF: {e}")
        print(traceback.format_exc())
        return MultiCnpjTimelineResponse(
            cpf=cpf, nome_falecido=None, dt_obito=None,
            events=[], cnpjs_envolvidos=[]
        )

