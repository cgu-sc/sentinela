import polars as pl
from typing import List, Optional
from datetime import date
from ...schemas.analytics import SocioSchema, SociosResponse

def get_socios_farmacia(cnpj: str) -> SociosResponse:
    """Retorna o quadro societário de uma farmácia a partir do cache global."""
    try:
        from data_cache import get_df_dados_socios
        df = get_df_dados_socios()
        
        # Filtra sócios pelo CNPJ
        df_socios = df.filter(pl.col("cnpj") == cnpj).sort("data_entrada_sociedade", descending=True)
        
        if df_socios.is_empty():
            return SociosResponse(cnpj=cnpj, socios=[], from_cache=True)
            
        # Pega a data de processamento (primeira disponível)
        data_proc = df_socios["data_processamento"][0] if "data_processamento" in df_socios.columns else None

        # Converte para lista de dicionários
        socios_dicts = df_socios.to_dicts()

        return SociosResponse(
            cnpj=cnpj,
            socios=[SocioSchema(**s) for s in socios_dicts],
            data_processamento=data_proc,
            from_cache=True
        )
    except Exception as e:
        print(f"⚠️ Erro ao buscar quadro societário da farmácia {cnpj}: {e}")
        return SociosResponse(cnpj=cnpj, socios=[], from_cache=False)
