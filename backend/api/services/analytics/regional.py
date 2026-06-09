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
from data_cache import get_df, get_rede_df, get_localidades_df, get_df_perfil_estabelecimento, get_cache_dir
from .matriz_risco_dinamica import build_dynamic_matriz_risco
from ...schemas.analytics import (
    AnalyticsKPISchema,
    ResultadoSentinelaUFSchema,
    AnalyticsResponse,
    ResultadoSentinelaMunicipioSchema,
    ResultadoSentinelaCnpjSchema,
    RedeEstabelecimentoSchema,
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
    MesMensalGtinItem,
    EvolucaoMensalGtinResponse,
    GtinDetalhamentoMensalResponse,
    GtinDetalhamentoMensalSummary,
    GtinDetalhamentoMensalItem,
)


def get_regional_benchmarking(uf: Optional[str] = None, data_inicio: Optional[date] = None, data_fim: Optional[date] = None, regiao_id: Optional[int] = None) -> RegionalResponse:
    """
    Constrói o payload completo de Benchmarking Regional.
    """
    nome_exibicao = uf or ""
    try:
        df_mov   = get_df().join(get_df_perfil_estabelecimento(), on="id_cnpj", how="left")
        df_loc   = get_localidades_df()
        # ── Resolução de Nome para Exibição ──────────────────────────────
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
        if "id_ibge7" not in df_reg.columns:
            df_reg = df_reg.join(
                get_df_perfil_estabelecimento().select(["id_cnpj", "id_ibge7"]),
                on="id_cnpj",
                how="left",
            )

        df_reg = df_reg.with_columns(
            pl.col("id_ibge7").cast(pl.Int64, strict=False)
        )

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
            pl.col("id_ibge7").cast(pl.Int64, strict=False).alias("id_ibge7"),
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
                pl.col("id_ibge7").first().alias("id_ibge7"),
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

        df_risco_slim = build_dynamic_matriz_risco(
            data_inicio=inicio,
            data_fim=fim,
        ).select(["id_cnpj", "score_risco_final", "classificacao_risco"])
        cnpj_enriched = cnpj_agg.join(df_risco_slim, on="id_cnpj", how="left")

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
                id_ibge7=int(r["id_ibge7"]) if r.get("id_ibge7") is not None else None,
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
        return RegionalResponse(nome_regiao=nome_exibicao, municipios=[], farmacias=[])

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
    nome_exibicao = uf or ""
    try:
        df_mov = get_df().join(get_df_perfil_estabelecimento(), on="id_cnpj", how="left")
        df_loc = get_localidades_df()
        
        # Resolução de Nome para Exibição
        if regiao_id:
            loc_row = df_loc.filter(pl.col("id_regiao_saude").cast(pl.String) == str(regiao_id)).limit(1)
            if not loc_row.is_empty():
                nome_exibicao = loc_row.get_column("no_regiao_saude")[0]
                if not uf or uf == 'Todos':
                    uf = loc_row.get_column("sg_uf")[0]

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
                pl.col("id_ibge7").first().alias("id_ibge7"),
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

        # ── Enriquece com score de risco dinâmico ───────────────────────
        df_risco_slim = build_dynamic_matriz_risco(
            data_inicio=inicio,
            data_fim=fim,
        ).select(["id_cnpj", "score_risco_final", "classificacao_risco"])
        cnpj_q = cnpj_q.join(df_risco_slim, on="id_cnpj", how="left")

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
                id_ibge7=int(r["id_ibge7"]) if r.get("id_ibge7") is not None else None,
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
        return RegionalAnimationResponse(nome_regiao=nome_exibicao, quarters=[])

# Conjunto de diretórios de CNPJ já criados nesta sessão — evita syscalls redundantes.
_known_cnpj_dirs: set[str] = set()

def get_metric_percentiles(scope: str, uf: Optional[str] = None, regiao_id: Optional[str] = None, metric: str = 'score', data_inicio: Optional[date] = None, data_fim: Optional[date] = None) -> list[dict]:
    """
    Calcula a curva de percentis de score ou percentual de não comprovação (1% a 100%) para diferentes escopos.
    """
    try:
        # Se houver data e for percentual, calculamos do zero para ser dinâmico
        if (data_inicio or data_fim) and metric == "percentual_sem_comprovacao":
            df_base = get_df().join(get_df_perfil_estabelecimento(), on="id_cnpj", how="left")
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
                    pl.col("id_regiao_saude").first().alias("id_regiao_saude"),
                    pl.sum("total_vendas").alias("tv"),
                    pl.sum("total_sem_comprovacao").alias("tsc")
                ])
                .with_columns([
                    (pl.col("tsc") / pl.when(pl.col("tv") > 0).then(pl.col("tv")).otherwise(pl.lit(1.0)) * 100).alias("pct_sem_comprovacao")
                ])
            )
            df = df_agg
        else:
            df = build_dynamic_matriz_risco(data_inicio=data_inicio, data_fim=data_fim)

        # Mapeamento de colunas conforme o schema real do cache
        col_target = "score_risco_final"
        if metric == "percentual_sem_comprovacao":
            col_target = "pct_sem_comprovacao"

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

