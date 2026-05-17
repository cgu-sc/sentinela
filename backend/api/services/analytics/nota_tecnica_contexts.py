import os
from datetime import date
from statistics import median
from typing import Any, Optional

import polars as pl

from cache_files import MOVIMENTACAO_MENSAL_GTIN_PARQUET
from data_cache import get_df, get_df_perfil_estabelecimento, get_localidades_df, get_medicamentos_df
from ._cache import _get_cnpj_cache_dir
from .financeiro import get_evolucao_financeira, get_evolucao_mensal_gtin
from .nota_tecnica_formatters import (
    _format_date_month_year_long_pt,
    _format_month_year_long_pt,
    _format_month_year_pt,
    _format_semestre_pt,
    _semester_distance,
    _semester_key_from_date,
    _semester_key_from_label,
)
from .regional import get_metric_percentiles, get_regional_benchmarking


def _resolve_regional_context(cadastro: dict) -> dict[str, Any]:
    """Resolve id_regiao_saude a partir do id_ibge7 cadastral da farmacia."""
    id_ibge7 = cadastro.get("id_ibge7")
    if id_ibge7 in (None, "", "None"):
        raise RuntimeError("id_ibge7 e obrigatorio para resolver a Regiao de Saude da Nota Tecnica.")

    df_loc = get_localidades_df()
    required_cols = {"id_ibge7", "id_regiao_saude", "sg_uf"}
    missing_cols = required_cols - set(df_loc.columns)
    if missing_cols:
        raise RuntimeError(
            f"Cache de localidades sem colunas obrigatorias para Nota Tecnica: {', '.join(sorted(missing_cols))}."
        )

    rows = df_loc.filter(pl.col("id_ibge7").cast(pl.String) == str(id_ibge7))
    if rows.is_empty():
        raise RuntimeError(f"id_ibge7 {id_ibge7} nao encontrado no cache de localidades.")

    row = rows.row(0, named=True)
    id_regiao_saude = row.get("id_regiao_saude")
    uf = row.get("sg_uf")
    if id_regiao_saude in (None, "", "None") or not uf:
        raise RuntimeError(f"Localidade {id_ibge7} sem id_regiao_saude/UF obrigatorios para Nota Tecnica.")

    return {
        "id_regiao_saude": int(id_regiao_saude),
        "uf": str(uf),
        "nome_regiao": f"ID {id_regiao_saude}",
    }


def _build_regional_comparison_context(
    cnpj_data: dict,
    cadastro: dict,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any]:
    """Calcula comparacao do percentual do CNPJ contra a mediana regional no periodo."""
    regional_context = _resolve_regional_context(cadastro)
    regional = get_regional_benchmarking(
        uf=regional_context["uf"],
        data_inicio=data_inicio,
        data_fim=data_fim,
        regiao_id=regional_context["id_regiao_saude"],
    )

    if not regional.farmacias:
        raise RuntimeError("Benchmarking regional sem farmacias para o periodo da Nota Tecnica.")

    percentual_cnpj = cnpj_data.get("percValSemComp")
    if percentual_cnpj is None:
        raise RuntimeError("percValSemComp e obrigatorio para comparacao regional da Nota Tecnica.")

    percentuais_regionais = [
        f.percValSemComp
        for f in regional.farmacias
        if f.percValSemComp is not None
    ]
    if not percentuais_regionais:
        raise RuntimeError("Percentuais regionais obrigatorios ausentes para comparacao da Nota Tecnica.")

    mediana_regional = median(percentuais_regionais)
    if mediana_regional <= 0:
        raise RuntimeError("Mediana regional deve ser maior que zero para calcular o multiplicador da Nota Tecnica.")

    municipios = [m.municipio for m in regional.municipios if m.municipio]
    if not municipios:
        raise RuntimeError("Municipios regionais obrigatorios ausentes para comparacao da Nota Tecnica.")

    uf_comp = _build_scope_percentual_comparison(cnpj_data, data_inicio, data_fim, uf=regional_context["uf"])
    br_comp = _build_scope_percentual_comparison(cnpj_data, data_inicio, data_fim)

    return {
        **regional_context,
        "multiplicador": float(percentual_cnpj) / mediana_regional,
        "mediana_regional": mediana_regional,
        "qtd_farmacias": len(regional.farmacias),
        "municipios": municipios,
        "multiplicador_uf": uf_comp["multiplicador"],
        "mediana_uf": uf_comp["mediana"],
        "multiplicador_brasil": br_comp["multiplicador"],
        "mediana_brasil": br_comp["mediana"],
    }


def _build_posicionamento_regional_context(
    cnpj: str,
    cadastro: dict,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any]:
    """Monta o contexto do scatter de posicionamento regional da Nota Tecnica."""
    regional_context = _resolve_regional_context(cadastro)
    regional = get_regional_benchmarking(
        uf=regional_context["uf"],
        data_inicio=data_inicio,
        data_fim=data_fim,
        regiao_id=regional_context["id_regiao_saude"],
    )

    if not regional.farmacias:
        raise RuntimeError("Benchmarking regional sem farmacias para Figura de Posicionamento Regional.")

    cnpj_norm = "".join(ch for ch in str(cnpj) if ch.isdigit())
    rows: list[dict[str, Any]] = []
    current_row: dict[str, Any] | None = None
    for farmacia in regional.farmacias:
        farmacia_cnpj = "".join(ch for ch in str(farmacia.cnpj or "") if ch.isdigit())
        row = {
            "cnpj": farmacia_cnpj,
            "razao_social": farmacia.razao_social or "",
            "municipio": farmacia.municipio or "",
            "total_mov": float(farmacia.totalMov or 0.0),
            "pct_sem_comprovacao": min(float(farmacia.percValSemComp or 0.0), 100.0),
            "score_risco": float(farmacia.score_risco or 0.0),
            "is_current": farmacia_cnpj == cnpj_norm,
        }
        rows.append(row)
        if row["is_current"]:
            current_row = row

    if current_row is None:
        raise RuntimeError("CNPJ analisado nao encontrado no benchmarking regional da Nota Tecnica.")

    return {
        **regional_context,
        "rows": rows,
        "current": current_row,
        "metric_label": "% de dispensações sem comprovação",
    }


def _build_percentil_risco_context(
    cnpj_data: dict,
    cadastro: dict,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any]:
    """Monta a curva de percentis do percentual de vendas sem comprovacao na regiao."""
    regional_context = _resolve_regional_context(cadastro)
    percentiles = get_metric_percentiles(
        scope="regiao",
        uf=regional_context["uf"],
        regiao_id=str(regional_context["id_regiao_saude"]),
        metric="percentual_sem_comprovacao",
        data_inicio=data_inicio,
        data_fim=data_fim,
    )
    if not percentiles:
        raise RuntimeError("Percentis regionais indisponiveis para Figura de Percentil de Risco.")

    valor_cnpj = min(float(cnpj_data.get("percValSemComp") or 0.0), 100.0)
    percentile_rank = 100
    for point in percentiles:
        if float(point.get("score") or 0.0) >= valor_cnpj:
            percentile_rank = int(point.get("percentile") or 100)
            break

    return {
        **regional_context,
        "scope": "regiao",
        "metric": "percentual_sem_comprovacao",
        "metric_label": "% de vendas sem comprovação",
        "current_value": valor_cnpj,
        "percentile_rank": percentile_rank,
        "percentiles": percentiles,
    }


def _build_scope_percentual_comparison(
    cnpj_data: dict,
    data_inicio: Optional[date],
    data_fim: Optional[date],
    *,
    uf: Optional[str] = None,
) -> dict[str, float]:
    """Calcula mediana de percentual sem comprovacao para UF ou Brasil no periodo."""
    percentual_cnpj = cnpj_data.get("percValSemComp")
    if percentual_cnpj is None:
        raise RuntimeError("percValSemComp e obrigatorio para comparacao geografica da Nota Tecnica.")

    df = get_df().join(get_df_perfil_estabelecimento(), on="id_cnpj", how="left")
    min_data = date(2015, 7, 1)
    max_data = date(2024, 12, 31)
    inicio = (data_inicio if data_inicio and data_inicio >= min_data else min_data) if data_inicio else min_data
    fim = data_fim if data_fim else max_data

    mask = pl.col("periodo").is_between(inicio, fim)
    if uf:
        mask = mask & (pl.col("uf") == uf)

    scoped = df.filter(mask)
    if scoped.is_empty():
        label = f"UF {uf}" if uf else "Brasil"
        raise RuntimeError(f"Sem movimentacao para calcular mediana de {label} da Nota Tecnica.")

    cnpj_agg = (
        scoped
        .group_by("id_cnpj")
        .agg([
            pl.sum("total_vendas").alias("totalMov"),
            pl.sum("total_sem_comprovacao").alias("valSemComp"),
        ])
        .with_columns(
            (
                pl.col("valSemComp") /
                pl.when(pl.col("totalMov") > 0)
                .then(pl.col("totalMov"))
                .otherwise(None) * 100
            ).alias("percValSemComp")
        )
        .filter(pl.col("percValSemComp").is_not_null())
    )
    if cnpj_agg.is_empty():
        label = f"UF {uf}" if uf else "Brasil"
        raise RuntimeError(f"Percentuais ausentes para calcular mediana de {label} da Nota Tecnica.")

    mediana_raw = cnpj_agg.get_column("percValSemComp").median()
    mediana = float(mediana_raw if isinstance(mediana_raw, (int, float)) else 0.0)
    if mediana <= 0:
        label = f"UF {uf}" if uf else "Brasil"
        raise RuntimeError(f"Mediana de {label} deve ser maior que zero para calcular o multiplicador da Nota Tecnica.")

    return {
        "mediana": mediana,
        "multiplicador": float(percentual_cnpj) / mediana,
    }


def _normalize_gtin(value: Any) -> str:
    """Normaliza GTIN/codigo de barras preservando zeros quando vier como texto."""
    text = str(value).strip()
    return text.split(".")[0] if "." in text else text


def _build_medicamentos_lookup() -> dict[str, str]:
    """Monta lookup GTIN -> descricao obrigatoria do medicamento."""
    df_med = get_medicamentos_df()
    required_cols = {"codigo_barra"}
    missing_cols = required_cols - set(df_med.columns)
    if missing_cols:
        raise RuntimeError(
            f"Cache de medicamentos sem colunas obrigatorias para Nota Tecnica: {', '.join(sorted(missing_cols))}."
        )

    lookup: dict[str, str] = {}
    for row in df_med.iter_rows(named=True):
        codigo = row.get("codigo_barra")
        if codigo in (None, "", "None"):
            continue
        descricao = row.get("principio_ativo") or row.get("produto") or row.get("descricao")
        if descricao in (None, "", "None"):
            continue
        gtin = _normalize_gtin(codigo)
        lookup[gtin] = str(descricao)

    if not lookup:
        raise RuntimeError("Cache de medicamentos sem descricoes validas para Nota Tecnica.")
    return lookup


def _build_gtin_sem_comprovacao_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
    concentration_target: float = 0.80,
) -> dict[str, Any]:
    """Agrega todos os GTINs com valor sem comprovacao no periodo e calcula concentracao."""
    get_evolucao_mensal_gtin(cnpj, data_inicio, data_fim)

    parquet_path = os.path.join(_get_cnpj_cache_dir(cnpj), MOVIMENTACAO_MENSAL_GTIN_PARQUET)
    if not os.path.exists(parquet_path):
        raise RuntimeError(f"Parquet mensal por GTIN obrigatorio nao encontrado para Nota Tecnica: {parquet_path}.")

    df = pl.read_parquet(parquet_path)
    required_cols = {
        "codigo_barra",
        "periodo",
        "qnt_caixas_sem_comprovacao",
        "valor_sem_comprovacao",
    }
    missing_cols = required_cols - set(df.columns)
    if missing_cols:
        raise RuntimeError(
            f"Parquet mensal por GTIN sem colunas obrigatorias para Nota Tecnica: {', '.join(sorted(missing_cols))}."
        )

    df = df.with_columns([
        pl.col("codigo_barra").cast(pl.String),
        pl.col("periodo").cast(pl.Date),
        pl.col("qnt_caixas_sem_comprovacao").cast(pl.Int64, strict=False).fill_null(0),
        pl.col("valor_sem_comprovacao").cast(pl.Float64, strict=False).fill_null(0.0),
    ])
    if data_inicio:
        df = df.filter(pl.col("periodo") >= pl.lit(data_inicio).cast(pl.Date))
    if data_fim:
        df = df.filter(pl.col("periodo") <= pl.lit(data_fim).cast(pl.Date))

    if df.is_empty():
        raise RuntimeError("Movimentacao mensal por GTIN vazia no periodo da Nota Tecnica.")

    agg = (
        df.group_by("codigo_barra")
        .agg([
            pl.sum("qnt_caixas_sem_comprovacao").alias("qtd_sem_comprovacao"),
            pl.sum("valor_sem_comprovacao").alias("valor_sem_comprovacao"),
        ])
        .filter(pl.col("valor_sem_comprovacao") > 0)
        .sort("valor_sem_comprovacao", descending=True)
    )
    if agg.is_empty():
        raise RuntimeError("Nenhum GTIN com valor sem comprovacao encontrado no periodo da Nota Tecnica.")

    medicamentos_lookup = _build_medicamentos_lookup()
    rows: list[dict[str, Any]] = []
    missing_descriptions: list[str] = []
    for r in agg.iter_rows(named=True):
        gtin = _normalize_gtin(r["codigo_barra"])
        descricao = medicamentos_lookup.get(gtin)
        if not descricao:
            missing_descriptions.append(gtin)
            continue
        rows.append({
            "gtin": gtin,
            "descricao": descricao,
            "qtd_sem_comprovacao": int(r["qtd_sem_comprovacao"] or 0),
            "valor_sem_comprovacao": round(float(r["valor_sem_comprovacao"] or 0.0), 2),
        })

    if missing_descriptions:
        preview = ", ".join(missing_descriptions[:10])
        raise RuntimeError(f"Descricao obrigatoria ausente para GTIN(s) da Nota Tecnica: {preview}.")
    if not rows:
        raise RuntimeError("Lista de GTINs sem comprovacao vazia apos enriquecimento de medicamentos.")

    total_valor = round(sum(r["valor_sem_comprovacao"] for r in rows), 2)
    total_qtd = sum(r["qtd_sem_comprovacao"] for r in rows)
    target_value = total_valor * concentration_target
    acumulado = 0.0
    representativos_count = 0
    for row in rows:
        if acumulado >= target_value and representativos_count > 0:
            break
        acumulado += row["valor_sem_comprovacao"]
        representativos_count += 1

    representativos_valor = round(acumulado, 2)
    representativos_pct = (representativos_valor / total_valor * 100) if total_valor > 0 else 0.0

    return {
        "rows": rows,
        "total_gtins": len(rows),
        "total_qtd": total_qtd,
        "total_valor": total_valor,
        "representativos_count": representativos_count,
        "representativos_valor": representativos_valor,
        "representativos_pct": representativos_pct,
        "concentration_target_pct": concentration_target * 100,
    }


def _model_to_dict(model: Any) -> dict[str, Any]:
    """Converte modelos Pydantic ou dicts em dicionario simples."""
    if isinstance(model, dict):
        return model
    if hasattr(model, "model_dump"):
        return model.model_dump()
    if hasattr(model, "dict"):
        return model.dict()
    raise TypeError(f"Objeto semestral inesperado para Nota Tecnica: {type(model)!r}.")


def _build_ultimo_mes_sav_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
) -> dict[str, Any]:
    """Identifica o ultimo mes com vendas no SAV dentro do periodo analisado."""
    evolucao = get_evolucao_financeira(cnpj, data_inicio, data_fim)
    semestres_raw = getattr(evolucao, "semestres", None)
    if semestres_raw is None:
        raise RuntimeError("Resposta de evolucao financeira sem campo semestres para Nota Tecnica.")

    meses: list[dict[str, Any]] = []
    for sem in semestres_raw:
        sem_item = _model_to_dict(sem)
        for mes in sem_item.get("meses") or []:
            mes_item = _model_to_dict(mes)
            if mes_item.get("mes"):
                meses.append(mes_item)

    if not meses:
        raise RuntimeError("Evolucao financeira mensal obrigatoria vazia para Nota Tecnica.")

    ultimo_mes = max(meses, key=lambda item: str(item.get("mes") or ""))
    total = float(ultimo_mes.get("total") or 0.0)
    return {
        "mes": str(ultimo_mes["mes"]),
        "mes_formatado": _format_month_year_pt(str(ultimo_mes["mes"])),
        "total": round(total, 2),
    }


def _build_evolucao_financeira_context(
    cnpj: str,
    data_inicio: Optional[date],
    data_fim: Optional[date],
    growth_threshold_pct: float = 50.0,
) -> dict[str, Any]:
    """Monta a evolucao financeira semestral e identifica saltos relevantes."""
    evolucao = get_evolucao_financeira(cnpj, data_inicio, data_fim)
    semestres_raw = getattr(evolucao, "semestres", None)
    if semestres_raw is None:
        raise RuntimeError("Resposta de evolucao financeira sem campo semestres para Nota Tecnica.")
    if not semestres_raw:
        raise RuntimeError("Evolucao financeira obrigatoria vazia para Nota Tecnica.")

    rows: list[dict[str, Any]] = []
    for sem in semestres_raw:
        item = _model_to_dict(sem)
        for col in ("semestre", "total", "regular", "irregular", "pct_irregular"):
            if col not in item:
                raise RuntimeError(f"Evolucao financeira sem coluna obrigatoria para Nota Tecnica: {col}.")
        total = float(item["total"] or 0.0)
        irregular = float(item["irregular"] or 0.0)
        regular = float(item["regular"] or 0.0)
        pct_irregular = float(item["pct_irregular"] or 0.0)
        semestre = str(item["semestre"])
        taxa_crescimento_raw = item.get("taxa_crescimento_pct")
        limite_volume_atipico_raw = item.get("limite_volume_atipico_pct")
        chave_semestre = item.get("chave_semestre") or _semester_key_from_label(semestre)
        rows.append({
            "semestre": semestre,
            "semestre_fmt": _format_semestre_pt(semestre),
            "chave_semestre": int(chave_semestre) if chave_semestre is not None else None,
            "mes_inicio": item.get("mes_inicio"),
            "mes_fim": item.get("mes_fim"),
            "total": round(total, 2),
            "regular": round(regular, 2),
            "irregular": round(irregular, 2),
            "pct_irregular": round(pct_irregular, 2),
            "volume_atipico": bool(item.get("volume_atipico")),
            "taxa_crescimento_pct": round(float(taxa_crescimento_raw), 2) if taxa_crescimento_raw is not None else None,
            "chave_semestre_anterior": item.get("chave_semestre_anterior"),
            "limite_volume_atipico_pct": float(limite_volume_atipico_raw) if limite_volume_atipico_raw is not None else None,
        })

    if not rows:
        raise RuntimeError("Evolucao financeira sem linhas validas para Nota Tecnica.")

    total_geral = round(sum(row["total"] for row in rows), 2)
    irregular_geral = round(sum(row["irregular"] for row in rows), 2)
    regular_geral = round(sum(row["regular"] for row in rows), 2)
    pct_irregular_geral = (irregular_geral / total_geral * 100) if total_geral > 0 else 0.0

    semestres_atipicos = [row for row in rows if row["volume_atipico"]]
    limites_volume_atipico = [
        row["limite_volume_atipico_pct"]
        for row in rows
        if row["limite_volume_atipico_pct"] is not None
    ]
    limite_volume_atipico = limites_volume_atipico[0] if limites_volume_atipico else growth_threshold_pct

    semestres_irregulares = [
        row for row in rows
        if row["irregular"] > 0
    ]
    top_irregulares = sorted(semestres_irregulares, key=lambda row: row["irregular"], reverse=True)[:3]
    primeiro_mes = rows[0].get("mes_inicio")
    ultimo_mes = rows[-1].get("mes_fim")
    periodo_meses = (
        f'{_format_month_year_long_pt(primeiro_mes)} a {_format_month_year_long_pt(ultimo_mes)}'
        if primeiro_mes and ultimo_mes
        else (
            rows[0]["semestre_fmt"] if rows[0]["semestre"] == rows[-1]["semestre"]
            else f'{rows[0]["semestre_fmt"]} a {rows[-1]["semestre_fmt"]}'
        )
    )

    return {
        "rows": rows,
        "total": total_geral,
        "regular": regular_geral,
        "irregular": irregular_geral,
        "pct_irregular": pct_irregular_geral,
        "primeiro_semestre": rows[0]["semestre"],
        "ultimo_semestre": rows[-1]["semestre"],
        "primeiro_semestre_fmt": rows[0]["semestre_fmt"],
        "ultimo_semestre_fmt": rows[-1]["semestre_fmt"],
        "periodo_semestres": (
            rows[0]["semestre_fmt"] if rows[0]["semestre"] == rows[-1]["semestre"]
            else f'{rows[0]["semestre_fmt"]} a {rows[-1]["semestre_fmt"]}'
        ),
        "periodo_meses": periodo_meses,
        "growth_threshold_pct": limite_volume_atipico,
        "crescimento_relevante": semestres_atipicos,
        "semestres_atipicos": semestres_atipicos,
        "top_irregulares": top_irregulares,
    }


def _build_socios_volume_atipico_context(
    socios_ativos: list[Any],
    evolucao_comp: dict[str, Any],
    max_semestres_apos_entrada: int = 2,
) -> list[dict[str, Any]]:
    """Identifica aumentos atipicos proximos ao ingresso de socios ativos."""
    semestres_atipicos = evolucao_comp.get("semestres_atipicos") or []
    matches: list[dict[str, Any]] = []

    for socio in socios_ativos:
        entrada = getattr(socio, "data_entrada_sociedade", None)
        if not entrada:
            continue

        entrada_key = _semester_key_from_date(entrada)
        nome = getattr(socio, "nome_socio", None) or "socio nao identificado"

        for semestre in semestres_atipicos:
            semestre_key = semestre.get("chave_semestre") or _semester_key_from_label(semestre.get("semestre"))
            if semestre_key is None:
                continue

            distancia = _semester_distance(entrada_key, int(semestre_key))
            if 0 <= distancia <= max_semestres_apos_entrada:
                matches.append({
                    "nome_socio": nome,
                    "entrada": entrada,
                    "entrada_txt": _format_date_month_year_long_pt(entrada),
                    "semestre_fmt": semestre.get("semestre_fmt") or _format_semestre_pt(semestre.get("semestre")),
                    "taxa_crescimento_pct": semestre.get("taxa_crescimento_pct"),
                    "distancia_semestres": distancia,
                })

    return sorted(matches, key=lambda item: (item["entrada"], item["distancia_semestres"], item["nome_socio"]))
