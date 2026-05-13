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
from data_cache import get_df, get_rede_df, get_localidades_df, get_df_matriz_risco, get_df_dados_farmacia, get_cache_dir
from .volume_atipico import get_volume_atipico_id_cnpjs_df
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
    MesMensalGtinItem,
    EvolucaoMensalGtinResponse,
    GtinDetalhamentoMensalResponse,
    GtinDetalhamentoMensalSummary,
    GtinDetalhamentoMensalItem,
)

def get_fator_risco_data(db: Session, data_inicio=None, data_fim=None, perc_min=None, perc_max=None, val_min=None, uf=None, regiao_saude=None, municipio=None, situacao_rf=None, conexao_ms=None, porte_empresa=None, grande_rede=None, cnpj_raiz=None, unidade_pf=None, razao_social=None, regiao_id: Optional[int] = None, volume_atipico: bool = False, volume_atipico_limite: Optional[float] = None) -> FatorRiscoResponseSchema:
    """
    Calcula as faixas de risco (Buckets de 10%) via Polars.
    """
    try:
        MIN_DATA = date(2015, 7, 1)
        inicio = max(data_inicio, MIN_DATA) if data_inicio else MIN_DATA
        fim = data_fim if data_fim else date(2199, 12, 31)
        p_min = perc_min if perc_min is not None else 0.0
        p_max = perc_max if perc_max is not None else 100.0
        v_min = float(val_min) if val_min is not None and val_min > 0 else None

        df = get_df()
        mask = pl.col("periodo").is_between(inicio, fim)
        if uf:                                        mask = mask & (pl.col("uf") == uf)
        if regiao_id:                                 mask = mask & (pl.col("id_regiao_saude") == str(regiao_id))
        elif regiao_saude and regiao_saude != 'Todos': 
            from data_cache import get_localidades_df
            df_loc = get_localidades_df()
            reg_row = df_loc.filter(pl.col("no_regiao_saude") == regiao_saude).select("id_regiao_saude").unique()
            if not reg_row.is_empty():
                target_id = str(reg_row.item(0, 0))
                mask = mask & (pl.col("id_regiao_saude") == target_id)
        if municipio:                                 mask = mask & (pl.col("no_municipio") == municipio)
        if situacao_rf and situacao_rf != 'Todos':     mask = mask & (pl.col("situacao_rf") == situacao_rf)
        if conexao_ms and conexao_ms != 'Todos':
            mask = mask & (pl.col("is_conexao_ativa") == (conexao_ms == 'Ativa'))
        if porte_empresa and porte_empresa != 'Todos': mask = mask & (pl.col("porte_empresa") == porte_empresa)
        if grande_rede and grande_rede != 'Todos':
            mask = mask & (pl.col("is_grande_rede") == (grande_rede == 'Sim'))
        if unidade_pf and unidade_pf != 'Todos':
            mask = mask & (pl.col("unidade_pf") == unidade_pf)
        if cnpj_raiz:
            if len(cnpj_raiz) == 14:
                mask = mask & (pl.col("cnpj") == cnpj_raiz)
            else:
                mask = mask & (pl.col("cnpj").str.slice(0, 8) == cnpj_raiz)
        if razao_social:
            mask = mask & (pl.col("razao_social").str.to_lowercase().str.contains(razao_social.lower()))

        period_df = df.filter(mask)
        if volume_atipico:
            id_cnpjs_volume_df = get_volume_atipico_id_cnpjs_df(inicio, fim, volume_atipico_limite)
            period_df = period_df.join(id_cnpjs_volume_df, on="id_cnpj", how="semi")

        cnpj_agg = (
            period_df
            .group_by("id_cnpj")
            .agg([
                pl.sum("total_vendas").alias("tv"),
                pl.sum("total_sem_comprovacao").alias("tsc"),
            ])
            .with_columns([
                (pl.col("tsc") / pl.when(pl.col("tv") > 0).then(pl.col("tv")).otherwise(None) * 100).fill_null(0).alias("pct")
            ])
            .filter((pl.col("pct") >= p_min) & (pl.col("pct") <= p_max))
        )

        if v_min is not None:
            cnpj_agg = cnpj_agg.filter(pl.col("tsc") >= v_min)

        faixa_expr = (
            pl.when(pl.col("pct") <= 10).then(pl.lit("00% - 10%"))
            .when(pl.col("pct") <= 20).then(pl.lit("10% - 20%"))
            .when(pl.col("pct") <= 30).then(pl.lit("20% - 30%"))
            .when(pl.col("pct") <= 40).then(pl.lit("30% - 40%"))
            .when(pl.col("pct") <= 50).then(pl.lit("40% - 50%"))
            .when(pl.col("pct") <= 60).then(pl.lit("50% - 60%"))
            .when(pl.col("pct") <= 70).then(pl.lit("60% - 70%"))
            .when(pl.col("pct") <= 80).then(pl.lit("70% - 80%"))
            .when(pl.col("pct") <= 90).then(pl.lit("80% - 90%"))
            .otherwise(pl.lit("90% - 100%"))
        )
        ordem_expr = (
            pl.when(pl.col("pct") <= 10).then(1).when(pl.col("pct") <= 20).then(2)
            .when(pl.col("pct") <= 30).then(3).when(pl.col("pct") <= 40).then(4)
            .when(pl.col("pct") <= 50).then(5).when(pl.col("pct") <= 60).then(6)
            .when(pl.col("pct") <= 70).then(7).when(pl.col("pct") <= 80).then(8)
            .when(pl.col("pct") <= 90).then(9).otherwise(10)
        )

        buckets_df = (
            cnpj_agg
            .with_columns([faixa_expr.alias("faixa"), ordem_expr.alias("ordem")])
            .group_by(["faixa", "ordem"])
            .agg([pl.len().alias("qtd"), pl.sum("tsc").alias("valor_raw")])
            .sort("ordem")
        )

        buckets = [
            FatorRiscoBucketSchema(
                faixa=r["faixa"],
                qtd=r["qtd"],
                valor=f"R$ {r['valor_raw']:,.2f}".replace(',', 'X').replace('.', ',').replace('X', '.'),
                valor_raw=r["valor_raw"]
            )
            for r in buckets_df.iter_rows(named=True)
        ]

        return FatorRiscoResponseSchema(
            periodo_formatado=f"{inicio} a {fim}" if data_inicio and data_fim else "Acumulado Histórico",
            buckets=buckets
        )
    except Exception as e:
        return FatorRiscoResponseSchema(periodo_formatado="Erro ao calcular", buckets=[])

def get_regional_benchmarking(uf: Optional[str] = None, data_inicio: Optional[date] = None, data_fim: Optional[date] = None, regiao_id: Optional[int] = None) -> RegionalResponse:
    """
    Constrói o payload completo de Benchmarking Regional.
    """
    try:
        df_mov   = get_df()
        df_loc   = get_localidades_df()
        df_risco = get_df_matriz_risco()
        df_risco = df_risco.rename({c: c.lower() for c in df_risco.columns})

        # ── Resolução de Nome para Exibição ──────────────────────────────
        nome_exibicao = uf or ""
        id_regiao: Optional[str] = str(regiao_id) if regiao_id is not None else None

        if regiao_id:
            loc_row = df_loc.filter(pl.col("id_regiao_saude").cast(pl.String) == str(regiao_id)).limit(1)
            if not loc_row.is_empty():
                nome_exibicao = loc_row.get_column("no_regiao_saude")[0]
                # Se não passou UF, pegamos a UF da região
                if not uf or uf == 'Todos':
                    uf = loc_row.get_column("sg_uf")[0]

        # ── Filtros de Período ───────────────────────────────────────────
        MIN_DATA = date(2015, 7, 1)
        MAX_DATA = date(2024, 12, 31)
        inicio = (data_inicio if data_inicio and data_inicio >= MIN_DATA else MIN_DATA) if data_inicio else MIN_DATA
        fim = data_fim if data_fim else MAX_DATA

        # ── Filtra movimentação diretamente por ID ou UF ──────────────────
        mask = pl.col("periodo").is_between(inicio, fim)
        
        if regiao_id:
            # FILTRO PURO POR ID (Novo Padrão)
            mask = mask & (pl.col("id_regiao_saude") == str(regiao_id))
        else:
            # FILTRO POR UF (Escopo Estadual)
            mask = mask & (pl.col("uf") == uf)
            
        df_reg = df_mov.filter(mask)

        if df_reg.is_empty():
            return RegionalResponse(nome_regiao=nome_exibicao, id_regiao=id_regiao, municipios=[], farmacias=[])

        # ── 1. Resumo por Município ─────────────────────────────────────────
        # Join com cadastro de farmácias para obter id_ibge7 via CNPJ (mais robusto que por nome)
        df_farmacia = get_df_dados_farmacia().select(["id_cnpj", "id_ibge7"])
        df_reg = df_reg.join(df_farmacia, on="id_cnpj", how="left")

        # Agrega CNPJs únicos e valores financeiros por município
        mun_agg = (
            df_reg
            .group_by(["no_municipio", "uf", "id_ibge7"])
            .agg([
                pl.n_unique("id_cnpj").alias("qtd_farmacias"),
                pl.sum("total_vendas").alias("totalMov"),
                pl.sum("total_sem_comprovacao").alias("valSemComp"),
            ])
            .with_columns([
                (
                    pl.col("valSemComp") /
                    pl.when(pl.col("totalMov") > 0)
                    .then(pl.col("totalMov"))
                    .otherwise(pl.lit(1.0)) * 100
                ).round(2).alias("percValSemComp")
            ])
        )

        # Enriquece com população do IBGE (localidades_df) para densidade
        # Usamos id_ibge7 como chave primária de join
        loc_pop = df_loc.select([
            pl.col("id_ibge7"),
            pl.col("nu_populacao"),
            pl.col("id_regiao_saude"),
        ]).unique(subset=["id_ibge7"])

        mun_enriched = mun_agg.join(
            loc_pop,
            on="id_ibge7",
            how="left"
        ).with_columns([
            pl.col("nu_populacao").fill_null(0).alias("populacao"),
            (
                pl.col("nu_populacao").fill_null(0).cast(pl.Float64) /
                pl.when(pl.col("qtd_farmacias") > 0)
                .then(pl.col("qtd_farmacias").cast(pl.Float64))
                .otherwise(pl.lit(1.0))
            ).round(2).alias("densidade"),
        ]).sort("no_municipio")

        # Pega o id_regiao_saude a partir da primeira ocorrência no dataset filtrado
        id_regiao: str | None = None
        if not mun_enriched.is_empty():
            id_regiao = str(mun_enriched.row(0, named=True).get("id_regiao_saude") or "")

        municipios = [
            RegionalMunicipioSchema(
                uf=r["uf"],
                municipio=str(r["no_municipio"]).title(),
                id_ibge7=int(r["id_ibge7"]) if r.get("id_ibge7") else None,
                populacao=int(r["populacao"] or 0),
                qtd_farmacias=int(r["qtd_farmacias"] or 0),
                densidade=float(r["densidade"] or 0.0),
                totalMov=float(r.get("totalMov") or 0.0),
                valSemComp=float(r.get("valSemComp") or 0.0),
                percValSemComp=float(r.get("percValSemComp") or 0.0),
            )
            for r in mun_enriched.iter_rows(named=True)
        ]

        # ── 2. Ranking de Farmácias ──────────────────────────────────────────
        # Agrega valores financeiros acumulados por CNPJ (histórico completo)
        cnpj_agg = (
            df_reg
            .group_by("id_cnpj")
            .agg([
                pl.col("cnpj").first().alias("cnpj"),
                pl.col("no_municipio").first().alias("municipio"),
                pl.col("uf").first().alias("uf"),
                pl.col("razao_social").first().alias("razao_social"),
                pl.col("is_conexao_ativa").first().alias("is_conexao_ativa"),
                pl.sum("total_vendas").alias("totalMov"),
                pl.sum("total_sem_comprovacao").alias("valSemComp"),
                pl.col("periodo").max().alias("data_ultima_venda"),
            ])
            .with_columns([
                (
                    pl.col("valSemComp") /
                    pl.when(pl.col("totalMov") > 0)
                    .then(pl.col("totalMov"))
                    .otherwise(pl.lit(1.0)) * 100
                ).round(2).alias("percValSemComp")
            ])
        )

        # Enriquece com score e classificação de risco da matriz_risco_consolidada
        risco_cols = ["cnpj"]
        risco_available = []
        for col in ["score_risco_final", "classificacao_risco"]:
            if col in df_risco.columns:
                risco_available.append(col)
                risco_cols.append(col)

        if risco_available:
            df_risco_slim = df_risco.select(risco_cols)
            cnpj_enriched = cnpj_agg.join(df_risco_slim, on="cnpj", how="left")
        else:
            cnpj_enriched = cnpj_agg.with_columns([
                pl.lit(None).cast(pl.Float64).alias("score_risco_final"),
                pl.lit(None).cast(pl.Utf8).alias("classificacao_risco"),
            ])

        # Ordena pelo score de risco (maior risco primeiro)
        cnpj_sorted = cnpj_enriched.sort(
            "score_risco_final", descending=True, nulls_last=True
        ).with_columns(
            pl.lit(range(1, cnpj_enriched.height + 1))
            .alias("rank_")
        )

        farmacias = []
        for i, r in enumerate(cnpj_sorted.iter_rows(named=True), start=1):
            farmacias.append(RegionalFarmaciaSchema(
                cnpj=r["cnpj"],
                razao_social=str(r.get("razao_social") or "").title(),
                municipio=str(r.get("municipio") or "").title(),
                uf=r.get("uf"),
                score_risco=float(r["score_risco_final"]) if r.get("score_risco_final") is not None else None,
                classificacao_risco=r.get("classificacao_risco"),
                valSemComp=float(r.get("valSemComp") or 0.0),
                totalMov=float(r.get("totalMov") or 0.0),
                percValSemComp=float(r.get("percValSemComp") or 0.0),
                is_conexao_ativa=r.get("is_conexao_ativa"),
                data_ultima_venda=r.get("data_ultima_venda"),
                rank=i,
            ))

        return RegionalResponse(
            nome_regiao=nome_exibicao,
            id_regiao=id_regiao,
            municipios=municipios,
            farmacias=farmacias,
        )

    except Exception as e:
        import traceback
        print(f"❌ ERRO AO CALCULAR DADOS REGIONAIS: {e}")
        print(traceback.format_exc())
        return RegionalResponse(nome_regiao=nome_exibicao if 'nome_exibicao' in locals() else "", municipios=[], farmacias=[])

def get_regional_benchmarking_animation(
    uf: Optional[str] = None,
    data_inicio: Optional[date] = None,
    data_fim: Optional[date] = None,
    regiao_id: Optional[int] = None
) -> RegionalAnimationResponse:
    """
    Retorna todos os trimestres do período em uma única chamada.
    Usado pela animação do scatter de posicionamento regional — evita N round-trips.
    """
    try:
        df_mov = get_df()
        df_loc = get_localidades_df()
        
        # Resolução de Nome para Exibição
        nome_exibicao = uf or ""
        if regiao_id:
            loc_row = df_loc.filter(pl.col("id_regiao_saude").cast(pl.String) == str(regiao_id)).limit(1)
            if not loc_row.is_empty():
                nome_exibicao = loc_row.get_column("no_regiao_saude")[0]
                if not uf or uf == 'Todos':
                    uf = loc_row.get_column("sg_uf")[0]

        df_risco = get_df_matriz_risco()
        df_risco = df_risco.rename({c: c.lower() for c in df_risco.columns})

        MIN_DATA = date(2015, 7, 1)
        MAX_DATA = date(2024, 12, 31)
        inicio = (data_inicio if data_inicio and data_inicio >= MIN_DATA else MIN_DATA) if data_inicio else MIN_DATA
        fim    = data_fim if data_fim else MAX_DATA

        # ── Filtro geográfico + temporal diretamente por ID ou UF ─────────
        mask = pl.col("periodo").is_between(inicio, fim)
        if regiao_id:
            mask = mask & (pl.col("id_regiao_saude") == str(regiao_id))
        else:
            mask = mask & (pl.col("uf") == uf)

        df_filtered = df_mov.filter(mask)
        nome_escopo = nome_exibicao

        if df_filtered.is_empty():
            return RegionalAnimationResponse(nome_regiao=nome_escopo, quarters=[])

        # ── Deriva índice de período relativo ao início do período ────
        # period_idx = 0 → primeiros 2 meses, 1 → próximos 2 meses, etc.
        # Janela de 2 meses para coincidir com PLAY_STEP=2 do slider de animação.
        inicio_year  = inicio.year
        inicio_month = inicio.month
        df_q = df_filtered.with_columns([
            (
                (pl.col("periodo").dt.year() - inicio_year) * 12
                + pl.col("periodo").dt.month()
                - inicio_month
            ).alias("_months_since_start")
        ]).with_columns([
            (pl.col("_months_since_start") // 2).alias("_quarter_idx")
        ])

        # ── Agrega por (trimestre, CNPJ) em uma única operação ──────────
        cnpj_q = (
            df_q
            .group_by(["_quarter_idx", "id_cnpj"])
            .agg([
                pl.col("cnpj").first().alias("cnpj"),
                pl.col("no_municipio").first().alias("municipio"),
                pl.col("uf").first().alias("uf"),
                pl.col("razao_social").first().alias("razao_social"),
                pl.col("is_conexao_ativa").first().alias("is_conexao_ativa"),
                pl.sum("total_vendas").alias("totalMov"),
                pl.sum("total_sem_comprovacao").alias("valSemComp"),
            ])
            .with_columns([
                (
                    pl.col("valSemComp")
                    / pl.when(pl.col("totalMov") > 0)
                      .then(pl.col("totalMov"))
                      .otherwise(pl.lit(1.0))
                    * 100
                ).round(2).alias("percValSemComp")
            ])
        )

        # ── Enriquece com score de risco consolidado ────────────────────
        risco_cols = ["cnpj"]
        for col in ["score_risco_final", "classificacao_risco"]:
            if col in df_risco.columns:
                risco_cols.append(col)
        df_risco_slim = df_risco.select(risco_cols)
        cnpj_q = cnpj_q.join(df_risco_slim, on="cnpj", how="left")

        if "score_risco_final" not in cnpj_q.columns:
            cnpj_q = cnpj_q.with_columns(pl.lit(None).cast(pl.Float64).alias("score_risco_final"))
        if "classificacao_risco" not in cnpj_q.columns:
            cnpj_q = cnpj_q.with_columns(pl.lit(None).cast(pl.Utf8).alias("classificacao_risco"))

        # Ordena por trimestre (asc) e risco (desc) para ranking correto
        cnpj_q = cnpj_q.sort(
            ["_quarter_idx", "score_risco_final"],
            descending=[False, True],
            nulls_last=True,
        )

        # ── Monta dicionário de trimestres ──────────────────────────────
        def _add_months(d: date, n: int) -> date:
            """Avança n meses a partir de d, retornando o dia 1 do novo mês."""
            m = d.month - 1 + n
            return date(d.year + m // 12, m % 12 + 1, 1)

        quarters_map: dict = {}
        rank_counter: dict = {}

        for r in cnpj_q.iter_rows(named=True):
            idx = r["_quarter_idx"]
            if idx not in quarters_map:
                q_start = _add_months(inicio, idx * 2)
                q_end_first = _add_months(inicio, idx * 2 + 1)
                last_day = calendar.monthrange(q_end_first.year, q_end_first.month)[1]
                q_end = min(date(q_end_first.year, q_end_first.month, last_day), fim)
                quarters_map[idx] = {
                    "trimestre": f"{q_start.year}-{q_start.month:02d}",
                    "inicio": q_start,
                    "fim": q_end,
                    "farmacias": [],
                }
                rank_counter[idx] = 1

            quarters_map[idx]["farmacias"].append(RegionalFarmaciaSchema(
                cnpj=r["cnpj"],
                razao_social=str(r.get("razao_social") or "").title(),
                municipio=str(r.get("municipio") or "").title(),
                uf=r.get("uf"),
                score_risco=float(r["score_risco_final"]) if r.get("score_risco_final") is not None else None,
                classificacao_risco=r.get("classificacao_risco"),
                valSemComp=float(r.get("valSemComp") or 0.0),
                totalMov=float(r.get("totalMov") or 0.0),
                percValSemComp=float(r.get("percValSemComp") or 0.0),
                is_conexao_ativa=bool(r.get("is_conexao_ativa")),
                data_ultima_venda=None,
                rank=rank_counter[idx],
            ))
            rank_counter[idx] += 1

        quarters = [
            RegionalAnimationQuarterSchema(
                trimestre=v["trimestre"],
                inicio=v["inicio"],
                fim=v["fim"],
                farmacias=v["farmacias"],
            )
            for v in sorted(quarters_map.values(), key=lambda x: x["inicio"])
        ]

        return RegionalAnimationResponse(nome_regiao=nome_exibicao, quarters=quarters)

    except Exception as e:
        import traceback
        print(f"❌ ERRO NA ANIMAÇÃO REGIONAL: {e}", flush=True)
        print(traceback.format_exc(), flush=True)
        return RegionalAnimationResponse(nome_regiao=nome_exibicao if 'nome_exibicao' in locals() else "", quarters=[])

# Conjunto de diretórios de CNPJ já criados nesta sessão — evita syscalls redundantes.
_known_cnpj_dirs: set[str] = set()

def get_metric_percentiles(scope: str, uf: Optional[str] = None, regiao_id: Optional[str] = None, metric: str = 'score', data_inicio: Optional[date] = None, data_fim: Optional[date] = None) -> list[dict]:
    """
    Calcula a curva de percentis de score ou percentual de não comprovação (1% a 100%) para diferentes escopos.
    """
    try:
        # Se houver data e for percentual, calculamos do zero para ser dinâmico
        if (data_inicio or data_fim) and metric == "percentual_sem_comprovacao":
            df_base = get_df()
            MIN_DATA = date(2015, 7, 1)
            MAX_DATA = date(2024, 12, 31)
            inicio = (data_inicio if data_inicio and data_inicio >= MIN_DATA else MIN_DATA) if data_inicio else MIN_DATA
            fim = data_fim if data_fim else MAX_DATA
            
            mask = pl.col("periodo").is_between(inicio, fim)
            
            # Agrega por CNPJ primeiro
            df_agg = (
                df_base.filter(mask)
                .group_by("id_cnpj")
                .agg([
                    pl.col("cnpj").first().alias("cnpj"),
                    pl.col("uf").first().alias("uf"),
                    pl.col("no_municipio").first().alias("no_municipio"),
                    pl.sum("total_vendas").alias("tv"),
                    pl.sum("total_sem_comprovacao").alias("tsc")
                ])
                .with_columns([
                    (pl.col("tsc") / pl.when(pl.col("tv") > 0).then(pl.col("tv")).otherwise(pl.lit(1.0)) * 100).alias("pct_auditado")
                ])
            )
            
            # Injeta id_regiao_saude via join com localidades para suportar o filtro de escopo
            try:
                df_loc = get_localidades_df().select(["no_municipio", "sg_uf", "id_regiao_saude"]).unique(subset=["no_municipio", "sg_uf"])
                df_agg = df_agg.join(
                    df_loc,
                    left_on=["no_municipio", "uf"],
                    right_on=["no_municipio", "sg_uf"],
                    how="left"
                )
            except Exception as e:
                print(f"⚠️ Erro ao cruzar regiões em percentis: {e}")
            
            df = df_agg
        else:
            # Caso contrário, usa a matriz consolidada (mais rápido)
            from data_cache import get_df_matriz_risco
            df = get_df_matriz_risco()
            df = df.rename({c: c.lower() for c in df.columns})

        # Mapeamento de colunas conforme o schema real do cache
        col_target = "score_risco_final"
        if metric == "percentual_sem_comprovacao":
            col_target = "pct_auditado"

        # ── 1. Aplica o Filtro de Escopo ──────────────────────────────────
        df_scoped = df
        if scope == 'uf' and uf:
            df_scoped = df.filter(pl.col("uf") == uf)
        elif scope == 'regiao' and regiao_id:
            # Usa o ID da região de saúde (mais preciso que o nome)
            df_scoped = df.filter(pl.col("id_regiao_saude").cast(pl.Utf8) == str(regiao_id))
        elif scope == 'brasil':
            df_scoped = df  # Sem filtro
        
        if df_scoped.is_empty():
            return []

        # ── 2. Calcula 100 percentis (0.01 a 1.0) ─────────────────────────
        percentis_list = [i / 100.0 for i in range(1, 101)]
        
        # Seleciona a coluna correta baseada no metric selecionado
        # Se for percentual, limitamos a 100 para evitar que o eixo Y estique para outliers (ex: 713)
        # Usando uma expressão de clipping do polars para segurança máxima
        if metric == "percentual_sem_comprovacao":
            series_target = df_scoped.select(
                pl.when(pl.col(col_target) > 100).then(100).otherwise(pl.col(col_target)).alias("val")
            ).to_series().sort()
        else:
            series_target = df_scoped.select(pl.col(col_target)).to_series().sort()
        
        res = []
        for p in percentis_list:
            val = series_target.quantile(p)
            res.append({
                "percentile": int(p * 100),
                "score": float(val or 0.0)
            })

        return res
        
    except Exception as e:
        print(f"⚠️ Erro ao calcular percentis de score: {e}")
        return []

def get_metric_percentiles_animation(
    scope: str,
    uf: Optional[str] = None,
    regiao_id: Optional[str] = None,
    metric: str = 'score',
    data_inicio: Optional[date] = None,
    data_fim: Optional[date] = None,
) -> dict:
    """
    Retorna os percentis de métrica para cada janela de 2 meses no período.

    Usado pela animação da curva de risco — evita N round-trips HTTP.
    A janela de 2 meses coincide com PLAY_STEP=2 do slider de animação no frontend.

    Args:
        scope: Escopo geográfico ('brasil', 'uf', 'regiao').
        uf: Sigla do estado (obrigatório para scope 'uf' ou 'regiao').
        regiao_id: ID da região de saúde (obrigatório para scope 'regiao').
        metric: Métrica ('score' ou 'percentual_sem_comprovacao').
        data_inicio: Início do período total.
        data_fim: Fim do período total.

    Returns:
        Dict com lista de quarters, cada um contendo inicio, fim e percentiles.
    """
    MIN_DATA = date(2015, 7, 1)
    MAX_DATA = date(2024, 12, 31)
    inicio = (data_inicio if data_inicio and data_inicio >= MIN_DATA else MIN_DATA) if data_inicio else MIN_DATA
    fim    = data_fim if data_fim else MAX_DATA

    def _add_months(d: date, n: int) -> date:
        m = d.month - 1 + n
        return date(d.year + m // 12, m % 12 + 1, 1)

    def _end_of_month(d: date) -> date:
        last_day = calendar.monthrange(d.year, d.month)[1]
        return date(d.year, d.month, last_day)

    quarters = []
    cursor = inicio
    while cursor <= fim:
        window_start = cursor
        window_end   = min(_end_of_month(_add_months(cursor, 1)), fim)

        percentiles = get_metric_percentiles(
            scope, uf, regiao_id, metric, window_start, window_end
        )
        quarters.append({
            "inicio":      window_start,
            "fim":         window_end,
            "percentiles": percentiles,
        })
        cursor = _add_months(cursor, 2)

    return {"quarters": quarters}

def get_cnpj_lookup() -> list[dict]:
    """Retorna lista slim de {cnpj, razao_social, municipio, uf} para autocomplete no frontend.
    Usa get_rede_df() — DataFrame leve de cadastro, sem dados temporais."""
    try:
        df = get_rede_df()
        return (
            df.select(["cnpj", "razao_social", "municipio", "uf"])
            .unique(subset=["cnpj"])
            .sort("razao_social", nulls_last=True)
            .to_dicts()
        )
    except Exception as e:
        print(f"⚠️ Erro ao buscar lookup de CNPJs: {e}")
        return []

