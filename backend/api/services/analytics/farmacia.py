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
    MesMensalGtinItem,
    EvolucaoMensalGtinResponse,
    GtinDetalhamentoMensalResponse,
    GtinDetalhamentoMensalSummary,
    GtinDetalhamentoMensalItem,
)

from ._cache import _get_cnpj_cache_dir

def get_dados_farmacia(cnpj: str) -> DadosFarmaciaSchema:
    """Retorna os dados cadastrais e geográficos de uma farmácia específica."""
    try:
        from data_cache import get_df_dados_farmacia
        df = get_df_dados_farmacia()
        rows = df.filter(pl.col("cnpj") == cnpj)
        if rows.is_empty():
            return DadosFarmaciaSchema(cnpj=cnpj)
        return DadosFarmaciaSchema(**rows.row(0, named=True))
    except Exception as e:
        print(f"⚠️ Erro ao buscar dados cadastrais da farmácia {cnpj}: {e}")
        return DadosFarmaciaSchema(cnpj=cnpj)

def get_movimentacao_data(cnpj: str, engine, check_cache: bool = False) -> MovimentacaoResponse:
    """
    Retorna a memória de cálculo processada (Movimentação por GTIN) de um CNPJ.
    Estratégia de cache em 2 camadas.
    """
    import traceback
    from pathlib import Path
    from data_cache import get_cache_dir
    
    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    CACHE_PATH = os.path.join(cnpj_dir, "memoria_calculo.parquet")

    empty_summary = MovimentacaoSummarySchema()

    def _build_response_from_df(df: pl.DataFrame, from_cache: bool,
                                read_time_ms=None, query_time_ms=None, save_time_ms=None) -> MovimentacaoResponse:
        """Converte DataFrame Polars para o schema de resposta."""
        rows = [
            MovimentacaoRowSchema(
                tipo_linha=r["tipo_linha"],
                gtin=r.get("gtin"),
                medicamento=r.get("medicamento"),
                periodo_inicial=r.get("periodo_inicial"),
                periodo_inicio_irregular=r.get("periodo_inicio_irregular"),
                periodo_final=r.get("periodo_final"),
                estoque_inicial=int(r["estoque_inicial"]) if r.get("estoque_inicial") is not None else None,
                estoque_final=int(r["estoque_final"]) if r.get("estoque_final") is not None else None,
                vendas=int(r["vendas"]) if r.get("vendas") is not None else None,
                vendas_irregular=int(r["vendas_irregular"]) if r.get("vendas_irregular") is not None else None,
                valor=float(r["valor"]) if r.get("valor") is not None else None,
                valor_irregular=float(r["valor_irregular"]) if r.get("valor_irregular") is not None else None,
                notas=r.get("notas"),
            )
            for r in df.iter_rows(named=True)
        ]

        # Calcula totalizadores a partir das linhas de venda
        vendas_rows = [r for r in rows if r.tipo_linha in ("venda_normal", "venda_irregular")]
        tv  = sum(r.vendas or 0 for r in vendas_rows)
        tvi = sum(r.vendas_irregular or 0 for r in vendas_rows)
        vv  = sum(r.valor or 0.0 for r in vendas_rows)
        vvi = sum(r.valor_irregular or 0.0 for r in vendas_rows)
        pct = (vvi / vv * 100) if vv else 0.0

        return MovimentacaoResponse(
            cnpj=cnpj,
            summary=MovimentacaoSummarySchema(
                total_vendas=tv,
                total_vendas_irregular=tvi,
                valor_total=round(vv, 2),
                valor_irregular=round(vvi, 2),
                pct_irregular=round(pct, 2),
                from_cache=from_cache,
            ),
            rows=rows,
            from_cache=from_cache,
            read_time_ms=read_time_ms,
            query_time_ms=query_time_ms,
            save_time_ms=save_time_ms,
        )

    import time as _time

    # ── 1. Tenta carregar do cache Parquet ─────────────────────────────
    if os.path.exists(CACHE_PATH):
        try:
            _t0 = _time.perf_counter()
            df_cached = pl.read_parquet(CACHE_PATH)
            _read_ms = round((_time.perf_counter() - _t0) * 1000, 1)
            return _build_response_from_df(df_cached, from_cache=True, read_time_ms=_read_ms)
        except Exception as e:
            import traceback
            print(f"⚠️ Erro ao ler Parquet '{cnpj}': {e}")

    # ── 1b. Se for apenas check_cache e não existia/corrompeu, retorna vazio
    if check_cache:
        return MovimentacaoResponse(cnpj=cnpj, summary=MovimentacaoSummarySchema(), rows=[])

    # ── 2. Busca e processa a memória de cálculo do SQL Server ─────────
    _query_ms = None
    try:
        from sqlalchemy.exc import InterfaceError as SQLAInterfaceError
        with engine.connect() as conn:
            # 2a. Busca dados comprimidos
            _tq0 = _time.perf_counter()
            result = conn.execute(text("""
                SELECT TOP 1 dados_comprimidos, id_processamento
                FROM temp_CGUSC.fp.memoria_calculo_consolidada
                WHERE cnpj = :cnpj
                ORDER BY id_processamento DESC
            """), {"cnpj": cnpj}).fetchone()
            _query_ms = round((_time.perf_counter() - _tq0) * 1000, 1)

            if not result or not result[0]:
                print(f"⚠️ Nenhum dado no banco para CNPJ {cnpj}")
                return MovimentacaoResponse(cnpj=cnpj, summary=empty_summary, rows=[])

            dados_comprimidos = result[0]

            # 2b. Busca nomes dos princípios ativos (GTIN → Nome)
            med_rows = conn.execute(text("""
                SELECT codigo_barra, principio_ativo
                FROM temp_CGUSC.fp.medicamentos_patologia
            """)).fetchall()
            medicamentos_map = {float(r[0]): r[1] for r in med_rows if r[0]}

        # 2c. Descompacta e desserializa
        json_str = zlib.decompress(dados_comprimidos).decode("utf-8")
        dados = json.loads(json_str)

        # 2d. Converte dates e Decimals
        for item in dados:
            for key in ["periodo_inicial", "periodo_final", "periodo_inicial_nao_comprovacao",
                        "data_aquis_dev_estoq", "data_estoque_inicial", "data_aquisicao", "data_devolucao"]:
                if key in item and item[key] and isinstance(item[key], str):
                    try:
                        from datetime import datetime as _dt
                        if "T" in item[key]:
                            item[key] = _dt.fromisoformat(item[key]).date()
                        else:
                            item[key] = _dt.strptime(item[key], "%Y-%m-%d").date()
                    except: pass
            
            # Formata campos decimais
            for key in ["valor_movimentado", "valor_sem_comprovacao"]:
                if key in item and item[key] is not None:
                    from decimal import Decimal
                    item[key] = Decimal(str(item[key]))
    
    except (SQLAInterfaceError, Exception) as e:
        msg = str(e)
        if "IM002" in msg or "ODBC" in msg or "InterfaceError" in msg:
            print(f"❌ [INFO] Driver ODBC não disponível. Consulta 'live' ignorada.")
            return MovimentacaoResponse(
                cnpj=cnpj, summary=empty_summary, rows=[],
                error="Arquivo Parquet local não encontrado e Driver ODBC ausente."
            )
        
        print(f"❌ ERRO ao buscar movimentação para {cnpj}: {e}")
        print(traceback.format_exc())
        raise HTTPException(
            status_code=503,
            detail="Erro interno ao processar dados de movimentação. Verifique os logs do servidor."
        )

    # ── 3. Processa linhas (lógica espelhada de gerar_relatorio.py) ──────
    results = copy.deepcopy(dados)

    # Passo A: Enriquece vendas com lista de NFs (campo 'notas')
    contador = 0
    for i, j in enumerate(results):
        if j["tipo"] in ("c", "d"):
            contador += 1
        if j["tipo"] in ("s", "h"):
            contador = 0
        if j["tipo"] == "v":
            lista_nfs = []
            for idx in range(1, contador + 1):
                item_ant = results[i - idx]
                if item_ant["tipo"] == "c":
                    dt = item_ant["data_aquis_dev_estoq"].strftime("%d/%m/%Y") if item_ant.get("data_aquis_dev_estoq") else ""
                    qtd = int(item_ant["qnt_aquis_dev"]) if item_ant.get("qnt_aquis_dev") else 0
                    lista_nfs.append(f"NF Aquisição: {item_ant.get('numero_nfe', '')} - {dt} | Qtde: {qtd}")
                elif item_ant["tipo"] == "d":
                    dt = item_ant["data_aquis_dev_estoq"].strftime("%d/%m/%Y") if item_ant.get("data_aquis_dev_estoq") else ""
                    qtd = int(item_ant["qnt_aquis_dev"]) if item_ant.get("qnt_aquis_dev") else 0
                    lista_nfs.append(f"NF Transferência: {item_ant.get('numero_nfe', '')} - {dt} | Qtde: {qtd}")
                elif item_ant["tipo"] == "e":
                    est = int(item_ant.get("estoque_inicial", 0))
                    lista_nfs.append(f"Estoque Inicial Estimado: {est} - 01/07/2015")
            if not lista_nfs:
                for idx in range(i - 1, -1, -1):
                    if results[idx]["tipo"] == "e":
                        est = int(results[idx].get("estoque_inicial", 0))
                        lista_nfs.append(f"Estoque Inicial Estimado: {est} - 01/07/2015")
                        break
                    elif results[idx]["tipo"] == "h":
                        break
            results[i]["notas"] = "; ".join(lista_nfs)
            contador = 0

    # Passo B: Estrutura linhas tipadas (tipo_linha)
    _FMT_DATE = lambda d: d.strftime("%d/%m/%Y") if d else "-"

    lista_linhas: list[dict] = []
    lista_parcial: list[dict] = []
    numero_vendas_gtin = 0
    ultimo_estoque_valido = 0
    gtin_atual: str | None = None
    medicamento_atual: str | None = None

    for i, j in enumerate(results):
        tipo = j["tipo"]

        if tipo == "h":
            numero_vendas_gtin = 0
            cod = int(j["codigo_barra"])
            gtin_atual = str(cod)
            principio = medicamentos_map.get(float(cod), "DESCONHECIDO")
            medicamento_atual = principio
            est = j.get("estoque_inicial", 0) or 0
            ultimo_estoque_valido = est

            lista_parcial.append({
                "tipo_linha": "header_medicamento",
                "gtin": gtin_atual,
                "medicamento": f"{medicamento_atual} (Estoque Inicial: {int(est)} un.)",
            })
            lista_parcial.append({"tipo_linha": "header_colunas"})

        elif tipo == "e":
            ultimo_estoque_valido = j.get("estoque_inicial", 0) or 0

        elif tipo == "v":
            ultimo_estoque_valido = j.get("estoque_final", 0) or 0
            tem_irregular = (j.get("valor_sem_comprovacao") or Decimal(0)) > 0
            numero_vendas_gtin += 1

            dt_nc = j.get("periodo_inicial_nao_comprovacao")
            dt_nc_fmt = "-" if (dt_nc is None or str(dt_nc) == "9999-01-01") else _FMT_DATE(dt_nc)

            lista_parcial.append({
                "tipo_linha": "venda_irregular" if tem_irregular else "venda_normal",
                "gtin": gtin_atual,
                "medicamento": medicamento_atual,
                "periodo_inicial": _FMT_DATE(j.get("periodo_inicial")),
                "periodo_inicio_irregular": dt_nc_fmt,
                "periodo_final": _FMT_DATE(j.get("periodo_final")),
                "estoque_inicial": int(j.get("estoque_inicial") or 0),
                "estoque_final": int(j.get("estoque_final") or 0),
                "vendas": int(j.get("vendas_periodo") or 0),
                "vendas_irregular": int(j.get("vendas_sem_comprovacao") or 0),
                "valor": float(Decimal(str(j.get("valor_movimentado") or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
                "valor_irregular": float(Decimal(str(j.get("valor_sem_comprovacao") or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
                "notas": j.get("notas", ""),
            })

        elif tipo in ("c", "d"):
            ultimo_estoque_valido = j.get("estoque_final", 0) or 0

        elif tipo == "s":
            # Resumo Parcial do GTIN — só inclui o GTIN se tiver ao menos 1 venda
            estoque_visual = int(ultimo_estoque_valido)
            for item_rev in reversed(lista_parcial):
                if item_rev.get("estoque_final") is not None:
                    estoque_visual = item_rev["estoque_final"]
                    break

            lista_parcial.append({
                "tipo_linha": "resumo_parcial",
                "gtin": gtin_atual,
                "medicamento": medicamento_atual,
                "periodo_inicial": "Resumo Parcial",
                "estoque_final": estoque_visual,
                "vendas": int(j.get("vendas_periodo") or 0),
                "vendas_irregular": int(j.get("vendas_sem_comprovacao") or 0),
                "valor": float(Decimal(str(j.get("valor_movimentado") or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
                "valor_irregular": float(Decimal(str(j.get("valor_sem_comprovacao") or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
            })

            if numero_vendas_gtin > 0:
                lista_linhas.extend(copy.deepcopy(lista_parcial))

            lista_parcial.clear()
            numero_vendas_gtin = 0

    # ── 4. Converte para Polars e salva Parquet ───────────────────────
    SCHEMA_COLS = [
        "tipo_linha", "gtin", "medicamento",
        "periodo_inicial", "periodo_inicio_irregular", "periodo_final",
        "estoque_inicial", "estoque_final",
        "vendas", "vendas_irregular",
        "valor", "valor_irregular",
        "notas",
    ]

    # Garante que todas as colunas estejam presentes em cada dict
    for row in lista_linhas:
        for col in SCHEMA_COLS:
            row.setdefault(col, None)

    if lista_linhas:
        # Cria o DataFrame com todas as colunas como Utf8 (safe),
        # então faz cast explícito das colunas numéricas.
        # Isso evita erros de schema em linhas de cabeçalho que têm None
        # misturado com int/float nas linhas de venda.
        try:
            df_result = (
                pl.DataFrame(lista_linhas)
                .select(SCHEMA_COLS)
                .with_columns([
                    pl.col("estoque_inicial").cast(pl.Int64, strict=False),
                    pl.col("estoque_final").cast(pl.Int64, strict=False),
                    pl.col("vendas").cast(pl.Int64, strict=False),
                    pl.col("vendas_irregular").cast(pl.Int64, strict=False),
                    pl.col("valor").cast(pl.Float64, strict=False),
                    pl.col("valor_irregular").cast(pl.Float64, strict=False),
                ])
            )
            _t1 = _time.perf_counter()
            df_result.write_parquet(CACHE_PATH, compression="zstd")
            _save_ms = round((_time.perf_counter() - _t1) * 1000, 1)
            print(f"✅ Cache Parquet salvo: {CACHE_PATH}")
        except Exception as e:
            print(f"⚠️ Erro ao criar/salvar Parquet para {cnpj}: {e}")
            print(traceback.format_exc())
            _save_ms = None
            # Fallback sem persistir: entrega os dados sem cache
            try:
                df_result = pl.DataFrame(lista_linhas).select(SCHEMA_COLS)
            except Exception:
                df_result = pl.DataFrame([])
    else:
        df_result = pl.DataFrame([])
        _save_ms = None

    return _build_response_from_df(df_result, from_cache=False, query_time_ms=_query_ms, save_time_ms=_save_ms)

