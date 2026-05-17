from dataclasses import dataclass
from decimal import Decimal, ROUND_HALF_UP
import copy
import json
import os
import time as _time
import traceback
import zlib

import polars as pl
from sqlalchemy import text
from sqlalchemy.exc import InterfaceError as SQLAInterfaceError

from cache_files import MEMORIA_CALCULO_PARQUET


@dataclass(frozen=True)
class CacheLoadResult:
    df: pl.DataFrame
    from_cache: bool
    read_time_ms: float | None = None
    query_time_ms: float | None = None
    save_time_ms: float | None = None
    error: str | None = None


def _cache_path(cnpj: str) -> str:
    return os.path.join(_get_cnpj_cache_dir(cnpj), MEMORIA_CALCULO_PARQUET)


def _get_cnpj_cache_dir(cnpj: str) -> str:
    from data_cache import get_cache_dir

    cnpj_dir = os.path.join(get_cache_dir(), cnpj)
    os.makedirs(cnpj_dir, exist_ok=True)
    return cnpj_dir


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


def _load_memoria_sql(cnpj: str, engine) -> tuple[list[dict] | None, dict[str | float, str], float | None]:
    query_time_ms = None
    with engine.connect() as conn:
        _tq0 = _time.perf_counter()
        result = conn.execute(text("""
            SELECT TOP 1
                memoria_calculo_payload,
                schema_version,
                id_processamento
            FROM temp_CGUSC.fp.memoria_calculo_consolidada
            WHERE cnpj = :cnpj
            ORDER BY id_processamento DESC
        """), {"cnpj": cnpj}).fetchone()
        query_time_ms = round((_time.perf_counter() - _tq0) * 1000, 1)

        if not result or not result[0]:
            print(f"Aviso: nenhum dado no banco para CNPJ {cnpj}")
            return None, {}, query_time_ms

        memoria_calculo_payload = result[0]

        med_rows = conn.execute(text("""
            SELECT codigo_barra, principio_ativo
            FROM temp_CGUSC.fp.medicamentos_patologia
        """)).fetchall()
        medicamentos_map: dict[str | float, str] = {}
        for row in med_rows:
            if not row[0]:
                continue
            codigo = str(row[0]).strip()
            principio_ativo = str(row[1] or "DESCONHECIDO")
            medicamentos_map[codigo] = principio_ativo
            try:
                medicamentos_map[float(codigo)] = principio_ativo
            except (TypeError, ValueError):
                pass

    json_str_v2 = zlib.decompress(memoria_calculo_payload).decode("utf-8")
    dados_v2 = json.loads(json_str_v2)
    dados = _legacy_rows_from_memoria_v2(dados_v2)

    for item in dados:
        for key in [
            "periodo_inicial",
            "periodo_final",
            "periodo_inicial_nao_comprovacao",
            "data_aquis_dev_estoq",
            "data_estoque_inicial",
            "data_aquisicao",
            "data_devolucao",
        ]:
            if key in item and item[key] and isinstance(item[key], str):
                try:
                    from datetime import datetime as _dt

                    if "T" in item[key]:
                        item[key] = _dt.fromisoformat(item[key]).date()
                    else:
                        item[key] = _dt.strptime(item[key], "%Y-%m-%d").date()
                except Exception:
                    pass

        for key in ["valor_movimentado", "valor_sem_comprovacao"]:
            if key in item and item[key] is not None:
                item[key] = Decimal(str(item[key]))

    return dados, medicamentos_map, query_time_ms


def _build_memoria_calculo_df(dados: list[dict], medicamentos_map: dict[str | float, str]) -> pl.DataFrame:
    results = copy.deepcopy(dados)

    contador = 0
    for i, item in enumerate(results):
        if item["tipo"] in ("c", "d"):
            contador += 1
        if item["tipo"] in ("s", "h"):
            contador = 0
        if item["tipo"] == "v":
            if item.get("notas"):
                contador = 0
                continue
            lista_nfs = []
            for idx in range(1, contador + 1):
                item_ant = results[i - idx]
                if item_ant["tipo"] == "c":
                    dt = item_ant["data_aquis_dev_estoq"].strftime("%d/%m/%Y") if item_ant.get("data_aquis_dev_estoq") else ""
                    qtd = int(item_ant["qnt_aquis_dev"]) if item_ant.get("qnt_aquis_dev") else 0
                    lista_nfs.append(f"NF Aquisicao: {item_ant.get('numero_nfe', '')} - {dt} | Qtde: {qtd}")
                elif item_ant["tipo"] == "d":
                    dt = item_ant["data_aquis_dev_estoq"].strftime("%d/%m/%Y") if item_ant.get("data_aquis_dev_estoq") else ""
                    qtd = int(item_ant["qnt_aquis_dev"]) if item_ant.get("qnt_aquis_dev") else 0
                    lista_nfs.append(f"NF Transferencia: {item_ant.get('numero_nfe', '')} - {dt} | Qtde: {qtd}")
                elif item_ant["tipo"] == "e":
                    est = int(item_ant.get("estoque_inicial", 0))
                    lista_nfs.append(f"Estoque Inicial Estimado: {est} - 01/07/2015")
            if not lista_nfs:
                for idx in range(i - 1, -1, -1):
                    if results[idx]["tipo"] == "e":
                        est = int(results[idx].get("estoque_inicial", 0))
                        lista_nfs.append(f"Estoque Inicial Estimado: {est} - 01/07/2015")
                        break
                    if results[idx]["tipo"] == "h":
                        break
            results[i]["notas"] = "; ".join(lista_nfs)
            contador = 0

    fmt_date = lambda value: value.strftime("%d/%m/%Y") if value else "-"

    lista_linhas: list[dict] = []
    lista_parcial: list[dict] = []
    numero_vendas_gtin = 0
    ultimo_estoque_valido = 0
    gtin_atual: str | None = None
    medicamento_atual: str | None = None

    for item in results:
        tipo = item["tipo"]

        if tipo == "h":
            numero_vendas_gtin = 0
            codigo = int(item["codigo_barra"])
            gtin_atual = str(codigo)
            medicamento_atual = medicamentos_map.get(float(codigo), "DESCONHECIDO")
            estoque = item.get("estoque_inicial", 0) or 0
            ultimo_estoque_valido = estoque

            lista_parcial.append({
                "tipo_linha": "header_medicamento",
                "gtin": gtin_atual,
                "medicamento": f"{medicamento_atual} (Estoque Inicial: {int(estoque)} un.)",
            })
            lista_parcial.append({"tipo_linha": "header_colunas"})

        elif tipo == "e":
            ultimo_estoque_valido = item.get("estoque_inicial", 0) or 0

        elif tipo == "v":
            ultimo_estoque_valido = item.get("estoque_final", 0) or 0
            tem_irregular = (item.get("valor_sem_comprovacao") or Decimal(0)) > 0
            numero_vendas_gtin += 1

            dt_nc = item.get("periodo_inicial_nao_comprovacao")
            dt_nc_fmt = "-" if (dt_nc is None or str(dt_nc) == "9999-01-01") else fmt_date(dt_nc)

            lista_parcial.append({
                "tipo_linha": "venda_irregular" if tem_irregular else "venda_normal",
                "gtin": gtin_atual,
                "medicamento": medicamento_atual,
                "periodo_inicial": fmt_date(item.get("periodo_inicial")),
                "periodo_inicio_irregular": dt_nc_fmt,
                "periodo_final": fmt_date(item.get("periodo_final")),
                "estoque_inicial": int(item.get("estoque_inicial") or 0),
                "estoque_final": int(item.get("estoque_final") or 0),
                "vendas": int(item.get("vendas_periodo") or 0),
                "vendas_irregular": int(item.get("vendas_sem_comprovacao") or 0),
                "valor": float(Decimal(str(item.get("valor_movimentado") or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
                "valor_irregular": float(Decimal(str(item.get("valor_sem_comprovacao") or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
                "notas": item.get("notas", ""),
            })

        elif tipo in ("c", "d"):
            ultimo_estoque_valido = item.get("estoque_final", 0) or 0

        elif tipo == "s":
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
                "vendas": int(item.get("vendas_periodo") or 0),
                "vendas_irregular": int(item.get("vendas_sem_comprovacao") or 0),
                "valor": float(Decimal(str(item.get("valor_movimentado") or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
                "valor_irregular": float(Decimal(str(item.get("valor_sem_comprovacao") or 0)).quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)),
            })

            if numero_vendas_gtin > 0:
                lista_linhas.extend(copy.deepcopy(lista_parcial))

            lista_parcial.clear()
            numero_vendas_gtin = 0

    schema_cols = [
        "tipo_linha",
        "gtin",
        "medicamento",
        "periodo_inicial",
        "periodo_inicio_irregular",
        "periodo_final",
        "estoque_inicial",
        "estoque_final",
        "vendas",
        "vendas_irregular",
        "valor",
        "valor_irregular",
        "notas",
    ]

    for row in lista_linhas:
        for col in schema_cols:
            row.setdefault(col, None)

    if not lista_linhas:
        return pl.DataFrame([])

    return (
        pl.DataFrame(lista_linhas)
        .select(schema_cols)
        .with_columns([
            pl.col("estoque_inicial").cast(pl.Int64, strict=False),
            pl.col("estoque_final").cast(pl.Int64, strict=False),
            pl.col("vendas").cast(pl.Int64, strict=False),
            pl.col("vendas_irregular").cast(pl.Int64, strict=False),
            pl.col("valor").cast(pl.Float64, strict=False),
            pl.col("valor_irregular").cast(pl.Float64, strict=False),
        ])
    )


def load_or_sync_memoria_calculo(cnpj: str, engine, check_cache: bool = False) -> CacheLoadResult:
    cache_path = _cache_path(cnpj)

    if os.path.exists(cache_path):
        try:
            t0 = _time.perf_counter()
            df_cached = pl.read_parquet(cache_path)
            read_time_ms = round((_time.perf_counter() - t0) * 1000, 1)
            return CacheLoadResult(df_cached, from_cache=True, read_time_ms=read_time_ms)
        except Exception as exc:
            print(f"[ CACHE ] {cnpj} - MOVIMENTACAO - erro de leitura ({exc})")

    if check_cache:
        return CacheLoadResult(pl.DataFrame([]), from_cache=False)

    try:
        dados, medicamentos_map, query_time_ms = _load_memoria_sql(cnpj, engine)
    except (SQLAInterfaceError, Exception):
        print(f"[ ANALYTICS ] {cnpj} - MOVIMENTACAO - indisponivel (sem cache e banco offline)")
        return CacheLoadResult(
            pl.DataFrame([]),
            from_cache=False,
            error="Arquivo Parquet local nao encontrado e Banco Offline.",
        )

    if dados is None:
        return CacheLoadResult(pl.DataFrame([]), from_cache=False, query_time_ms=query_time_ms)

    df_result = _build_memoria_calculo_df(dados, medicamentos_map)
    save_time_ms = None

    if not df_result.is_empty():
        try:
            t1 = _time.perf_counter()
            df_result.write_parquet(cache_path, compression="zstd")
            save_time_ms = round((_time.perf_counter() - t1) * 1000, 1)
            print(f"Cache Parquet salvo: {cache_path}")
        except Exception as exc:
            print(f"Erro ao salvar Parquet de memoria de calculo para {cnpj}: {exc}")
            print(traceback.format_exc())

    return CacheLoadResult(
        df_result,
        from_cache=False,
        query_time_ms=query_time_ms,
        save_time_ms=save_time_ms,
    )
