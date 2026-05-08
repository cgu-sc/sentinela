import os
import polars as pl
import pandas as pd
from typing import Optional
from sqlalchemy import text
from fastapi import HTTPException
from database import engine
from data_cache import get_cache_dir
from ...schemas.analytics import SocioSchema, SociosResponse

def get_socios_farmacia(cnpj: str) -> SociosResponse:
    """
    Retorna o quadro societário de uma farmácia seguindo o padrão de resiliência:
    Cache Físico -> Fallback SQL -> Validação de Disponibilidade.
    """
    PARQUET_PATH = os.path.join(get_cache_dir(), "socios.parquet")
    df_all = None
    from_cache = False

    # ── 1. Tentar carregar do cache físico (Performance máxima) ──────────
    if os.path.exists(PARQUET_PATH):
        try:
            df_all = pl.read_parquet(PARQUET_PATH)
            from_cache = True
        except Exception as e:
            print(f"[ CACHE ] SÓCIOS ● ⚠️ ERRO DE LEITURA EM {cnpj}: {e}")

    # ── 2. Fallback SQL (Resiliência: caso o cache global esteja ausente) ──
    if df_all is None:
        try:
            with engine.connect() as conn:
                # Busca cirúrgica apenas dos sócios do CNPJ alvo no banco
                query = text("SELECT * FROM [temp_CGUSC].[fp].[dados_socios] WHERE cnpj = :cnpj")
                pdf = pd.read_sql(query, conn, params={"cnpj": cnpj})
                
                if not pdf.empty:
                    df_all = pl.from_pandas(pdf)
                    from_cache = False
                else:
                    # Se o banco retornar vazio, criamos um DF vazio com colunas para evitar erro de 'None'
                    df_all = pl.DataFrame(schema={
                        "cnpj": pl.Utf8, "nome_socio": pl.Utf8, "data_processamento": pl.Date
                    })
        except Exception as e:
            print(f"[ ANALYTICS ] {cnpj} ● SÓCIOS ● ❌ INDISPONÍVEL (Cache ausente e Banco offline): {e}")
            df_all = None

    # ── 3. Validação de Disponibilidade (Segurança da Auditoria) ──────────
    # Se chegarmos aqui com df_all None, significa falha total de infraestrutura.
    if df_all is None or len(df_all.columns) == 0:
        raise HTTPException(
            status_code=503,
            detail="Base de dados societária indisponível no momento (Sem cache local e banco de dados offline)."
        )

    # ── 4. Processamento do Resultado ────────────────────────────────────
    # Filtra pelo CNPJ (necessário se o df_all veio do cache global completo)
    df_target = df_all.filter(pl.col("cnpj") == cnpj)

    # Caso 'Nada Consta': Sucesso técnico, mas zero registros.
    if df_target.is_empty():
        return SociosResponse(cnpj=cnpj, socios=[], from_cache=from_cache)
        
    # Ordenação e extração de metadados
    df_target = df_target.sort("data_entrada_sociedade", descending=True)
    data_proc = df_target["data_processamento"][0] if "data_processamento" in df_target.columns else None
    
    return SociosResponse(
        cnpj=cnpj,
        socios=[SocioSchema(**s) for s in df_target.to_dicts()],
        data_processamento=data_proc,
        from_cache=from_cache
    )
