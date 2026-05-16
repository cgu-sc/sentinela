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
    CnpjAccessStatusSchema,
)

from ._cache import _get_cnpj_cache_dir

def _clean_cnpj(value: str) -> str:
    return "".join(ch for ch in str(value or "") if ch.isdigit())

def get_cnpj_access_status(cnpj: str) -> CnpjAccessStatusSchema:
    clean_cnpj = _clean_cnpj(cnpj)
    if len(clean_cnpj) != 14:
        raise HTTPException(
            status_code=422,
            detail={
                "status": "invalid_format",
                "message": "A tela de estabelecimento aceita apenas CNPJ com 14 digitos.",
                "cnpj": clean_cnpj,
            },
        )

    df = get_df_dados_farmacia()
    rows = df.filter(pl.col("cnpj") == clean_cnpj)
    if rows.is_empty():
        raise HTTPException(
            status_code=404,
            detail={
                "status": "not_in_program",
                "message": "CNPJ nao encontrado na base carregada do Programa Farmacia Popular.",
                "cnpj": clean_cnpj,
            },
        )

    row = rows.select([
        "cnpj",
        "razao_social",
        "nome_fantasia",
        "municipio",
        "uf",
    ]).row(0, named=True)
    return CnpjAccessStatusSchema(
        cnpj=row["cnpj"],
        status="valid",
        in_program=True,
        razao_social=row.get("razao_social"),
        nome_fantasia=row.get("nome_fantasia"),
        municipio=row.get("municipio"),
        uf=row.get("uf"),
    )

def get_dados_farmacia(cnpj: str) -> DadosFarmaciaSchema:
    """Retorna os dados cadastrais e geográficos de uma farmácia específica."""
    try:
        clean_cnpj = _clean_cnpj(cnpj)
        if len(clean_cnpj) != 14:
            raise HTTPException(
                status_code=422,
                detail="A tela de estabelecimento aceita apenas CNPJ com 14 digitos.",
            )
        df = get_df_dados_farmacia()
        rows = df.filter(pl.col("cnpj") == clean_cnpj)
        if rows.is_empty():
            raise HTTPException(
                status_code=404,
                detail="CNPJ nao encontrado na base carregada do Programa Farmacia Popular.",
            )
        return DadosFarmaciaSchema(**rows.row(0, named=True))
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Erro ao buscar dados cadastrais da farmacia: {e}",
        ) from e

def get_movimentacao_data(cnpj: str, engine, check_cache: bool = False) -> MovimentacaoResponse:
    """
    Retorna a memória de cálculo processada (Movimentação por GTIN) de um CNPJ.
    Estratégia de cache em 2 camadas.
    """
    import traceback
    from pathlib import Path
    from data_cache import get_cache_dir
    
    cnpj_dir = _get_cnpj_cache_dir(cnpj)
    CACHE_PATH = os.path.join(cnpj_dir, "memoria_calculo_v2.parquet")

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

    def _parse_memory_date(value):
        if not value:
            return None
        if hasattr(value, "strftime"):
            return value
        try:
            from datetime import datetime as _dt
            text_value = str(value)
            if "T" in text_value:
                return _dt.fromisoformat(text_value).date()
            return _dt.strptime(text_value[:10], "%Y-%m-%d").date()
        except Exception:
            return None

    def _fmt_memory_date(value) -> str:
        parsed = _parse_memory_date(value)
        return parsed.strftime("%d/%m/%Y") if parsed else "-"

    def _as_decimal(value) -> Decimal:
        return Decimal(str(value or 0))

    def _as_int(value) -> int:
        return int(_as_decimal(value))

    def _formatar_notas_estoque_inicial(estoque_inicial: dict) -> str:
        quantidade = _as_int(estoque_inicial.get("quantidade"))
        data_ref = _fmt_memory_date(estoque_inicial.get("data_referencia"))
        partes = [f"Estoque Inicial Estimado: {quantidade} - {data_ref}"]
        for nota in estoque_inicial.get("notas") or []:
            numero = nota.get("numero_nfe") or ""
            data = _fmt_memory_date(nota.get("data"))
            qtd = _as_int(nota.get("quantidade"))
            partes.append(f"NF Estoque Inicial: {numero} - {data} | Qtde: {qtd}")
        return "; ".join(partes)

    def _formatar_referencia_v2(referencia: dict, estoque_inicial: dict) -> str:
        tipo = referencia.get("tipo")
        if tipo == "estoque_inicial":
            return _formatar_notas_estoque_inicial(estoque_inicial)

        numero = referencia.get("numero_nfe") or ""
        data = _fmt_memory_date(referencia.get("data"))
        qtd = _as_int(referencia.get("quantidade"))
        if tipo == "saida_estoque":
            return f"NF Transferencia: {numero} - {data} | Qtde: {qtd}"
        return f"NF Aquisicao: {numero} - {data} | Qtde: {qtd}"

    def _legacy_rows_from_memoria_v2(memoria_v2: dict) -> list[dict]:
        rows: list[dict] = []
        for gtin_info in memoria_v2.get("gtins") or []:
            gtin = str(gtin_info.get("gtin") or "").strip()
            if not gtin:
                continue

            estoque_inicial = gtin_info.get("estoque_inicial") or {}
            estoque_qtd = _as_decimal(estoque_inicial.get("quantidade"))
            data_estoque = _parse_memory_date(estoque_inicial.get("data_referencia"))

            rows.append({
                "tipo": "h",
                "codigo_barra": gtin,
                "estoque_inicial": estoque_qtd,
                "vendas_periodo": 0,
                "vendas_sem_comprovacao": 0,
                "qnt_aquis_dev": 0,
                "data_aquis_dev_estoq": None,
                "numero_nfe": None,
            })
            rows.append({
                "tipo": "e",
                "codigo_barra": gtin,
                "estoque_inicial": estoque_qtd,
                "data_estoque_inicial": data_estoque,
                "data_aquis_dev_estoq": data_estoque,
                "qnt_aquis_dev": 0,
                "numero_nfe": None,
                "notas_estoque_inicial": estoque_inicial.get("notas") or [],
            })

            for evento in gtin_info.get("eventos") or []:
                tipo_evento = evento.get("tipo")
                if tipo_evento == "estoque_inicial":
                    continue
                if tipo_evento in ("aquisicao", "saida_estoque"):
                    rows.append({
                        "tipo": "c" if tipo_evento == "aquisicao" else "d",
                        "codigo_barra": gtin,
                        "estoque_inicial": _as_decimal(evento.get("estoque_inicial")),
                        "estoque_final": _as_decimal(evento.get("estoque_final")),
                        "data_aquis_dev_estoq": _parse_memory_date(evento.get("data")),
                        "qnt_aquis_dev": _as_decimal(evento.get("quantidade")),
                        "numero_nfe": evento.get("numero_nfe"),
                    })
                elif tipo_evento == "venda":
                    referencias = evento.get("notas_referencia") or [{"tipo": "estoque_inicial"}]
                    notas = "; ".join(
                        _formatar_referencia_v2(ref, estoque_inicial)
                        for ref in referencias
                    )
                    rows.append({
                        "tipo": "v",
                        "codigo_barra": gtin,
                        "periodo_inicial": _parse_memory_date(evento.get("periodo_inicial")),
                        "periodo_final": _parse_memory_date(evento.get("periodo_final")),
                        "periodo_inicial_nao_comprovacao": _parse_memory_date(evento.get("periodo_inicio_irregular")),
                        "estoque_inicial": _as_decimal(evento.get("estoque_inicial")),
                        "estoque_final": _as_decimal(evento.get("estoque_final")),
                        "vendas_periodo": _as_decimal(evento.get("vendas")),
                        "vendas_sem_comprovacao": _as_decimal(evento.get("vendas_sem_comprovacao")),
                        "valor_movimentado": _as_decimal(evento.get("valor")),
                        "valor_sem_comprovacao": _as_decimal(evento.get("valor_sem_comprovacao")),
                        "data_aquis_dev_estoq": None,
                        "qnt_aquis_dev": 0,
                        "numero_nfe": None,
                        "notas": notas,
                    })

            resumo = gtin_info.get("summary") or {}
            rows.append({
                "tipo": "s",
                "codigo_barra": gtin,
                "vendas_periodo": _as_decimal(resumo.get("vendas")),
                "vendas_sem_comprovacao": _as_decimal(resumo.get("vendas_sem_comprovacao")),
                "valor_movimentado": _as_decimal(resumo.get("valor")),
                "valor_sem_comprovacao": _as_decimal(resumo.get("valor_sem_comprovacao")),
                "qnt_aquis_dev": 0,
                "data_aquis_dev_estoq": None,
                "numero_nfe": None,
            })
        return rows

    import time as _time

    # ── 1. Tenta carregar do cache Parquet ─────────────────────────────
    if os.path.exists(CACHE_PATH):
        try:
            _t0 = _time.perf_counter()
            df_cached = pl.read_parquet(CACHE_PATH)
            _read_ms = round((_time.perf_counter() - _t0) * 1000, 1)
            return _build_response_from_df(df_cached, from_cache=True, read_time_ms=_read_ms)
        except Exception as e:
            print(f"[ CACHE ] {cnpj} ● MOVIMENTAÇÃO ● ⚠️ ERRO DE LEITURA ({e})")

    # ── 1b. Se for apenas check_cache e não existia/corrompeu, retorna vazio
    if check_cache:
        return MovimentacaoResponse(cnpj=cnpj, summary=MovimentacaoSummarySchema(), rows=[])

    # ── 2. Busca e processa a memória de cálculo do SQL Server ─────────
    _query_ms = None
    dados_v2 = None
    try:
        from sqlalchemy.exc import InterfaceError as SQLAInterfaceError
        with engine.connect() as conn:
            # 2a. Busca dados comprimidos
            _tq0 = _time.perf_counter()
            result = conn.execute(text("""
                SELECT TOP 1
                    dados_comprimidos_v2,
                    schema_version,
                    id_processamento
                FROM temp_CGUSC.fp.memoria_calculo_consolidada
                WHERE cnpj = :cnpj
                ORDER BY id_processamento DESC
            """), {"cnpj": cnpj}).fetchone()
            _query_ms = round((_time.perf_counter() - _tq0) * 1000, 1)

            if not result or not result[0]:
                print(f"⚠️ Nenhum dado no banco para CNPJ {cnpj}")
                return MovimentacaoResponse(cnpj=cnpj, summary=empty_summary, rows=[])

            dados_comprimidos_v2 = result[0]

            # 2b. Busca nomes dos princípios ativos (GTIN → Nome)
            med_rows = conn.execute(text("""
                SELECT codigo_barra, principio_ativo
                FROM temp_CGUSC.fp.medicamentos_patologia
            """)).fetchall()
            medicamentos_map = {}
            for r in med_rows:
                if not r[0]:
                    continue
                codigo = str(r[0]).strip()
                medicamentos_map[codigo] = r[1]
                try:
                    medicamentos_map[float(codigo)] = r[1]
                except (TypeError, ValueError):
                    pass

        # 2c. Descompacta e desserializa
        json_str_v2 = zlib.decompress(dados_comprimidos_v2).decode("utf-8")
        dados_v2 = json.loads(json_str_v2)
        dados = _legacy_rows_from_memoria_v2(dados_v2)

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
    
    except (SQLAInterfaceError, Exception):
        print(f"[ ANALYTICS ] {cnpj} ● MOVIMENTAÇÃO ● ❌ INDISPONÍVEL (Sem Cache e Banco Offline)")
        return MovimentacaoResponse(
            cnpj=cnpj, summary=empty_summary, rows=[],
            error="Arquivo Parquet local não encontrado e Banco Offline."
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
            if j.get("notas"):
                contador = 0
                continue
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

