from sqlalchemy.orm import Session
from ..schemas.geo import LocalidadeSchema, LocalidadesResponseSchema, EstabelecimentoGeoSchema, EstabelecimentosGeoResponseSchema
from data_cache import get_localidades_df, get_df_dados_farmacia, get_df_matriz_risco, get_df
import polars as pl

class GeoService:
    @staticmethod
    def get_localidades(_db: Session) -> LocalidadesResponseSchema:
        """
        Retorna a lista de localidades (UF, Município, Região) a partir do Cache Polars.
        Isso permite funcionamento offline e maior velocidade.
        """
        try:
            df = get_localidades_df()
            
            # Map Polars rows to Schema (convert to dicts first)
            # no_regiao_saude, id_regiao_saude, no_municipio, id_ibge7, sg_uf
            localidades = [
                LocalidadeSchema(
                    sg_uf=r["sg_uf"],
                    no_regiao_saude=r["no_regiao_saude"],
                    id_regiao_saude=r["id_regiao_saude"],
                    no_municipio=r["no_municipio"],
                    id_ibge7=r["id_ibge7"],
                    nu_populacao=r["nu_populacao"]
                ) 
                for r in df.iter_rows(named=True)
            ]
            
            return LocalidadesResponseSchema(localidades=localidades)
        except Exception as e:
            import traceback
            print("❌ ERRO AO BUSCAR LOCALIDADES DO CACHE:")
            print(traceback.format_exc())
            return LocalidadesResponseSchema(localidades=[])

    @staticmethod
    def get_estabelecimentos_geo() -> EstabelecimentosGeoResponseSchema:
        """
        Retorna coordenadas e score de risco de todos os estabelecimentos com lat/lon
        preenchidos. Cruza dados_farmacia com matriz_risco em memória (sem SQL).
        """
        try:
            df_farm = get_df_dados_farmacia()
            df_risco = get_df_matriz_risco()
            df_mov = get_df()

            # Filtra apenas quem tem coordenadas
            df_farm = df_farm.filter(
                pl.col("latitude").is_not_null() & pl.col("longitude").is_not_null()
            )

            # Seleciona necessário da matriz de risco
            df_risco_slim = df_risco.select([
                "cnpj", "score_risco_final", "classificacao_risco"
            ]).rename({"score_risco_final": "score_risco"})

            # Agrega histórico completo de movimentação por CNPJ
            df_mov_agg = df_mov.group_by("cnpj").agg([
                pl.sum("total_vendas").alias("totalMov"),
                pl.sum("total_sem_comprovacao").alias("valSemComp")
            ]).with_columns([
                (pl.col("valSemComp") / pl.when(pl.col("totalMov") > 0).then(pl.col("totalMov")).otherwise(None) * 100).fill_null(0).alias("percValSemComp")
            ])

            # Join para trazer score e dados financeiros
            df = df_farm.join(df_risco_slim, on="cnpj", how="left") \
                        .join(df_mov_agg, on="cnpj", how="left")

            estabelecimentos = [
                EstabelecimentoGeoSchema(
                    cnpj=r["cnpj"],
                    razao_social=r.get("razao_social"),
                    lat=r["latitude"],
                    lon=r["longitude"],
                    id_ibge7=r.get("id_ibge7"),
                    score_risco=r.get("score_risco"),
                    classificacao_risco=r.get("classificacao_risco"),
                    percValSemComp=r.get("percValSemComp") or 0.0,
                    totalMov=r.get("totalMov") or 0.0,
                    valSemComp=r.get("valSemComp") or 0.0,
                )
                for r in df.iter_rows(named=True)
            ]

            return EstabelecimentosGeoResponseSchema(estabelecimentos=estabelecimentos)
        except Exception as e:
            import traceback
            print("❌ ERRO AO BUSCAR ESTABELECIMENTOS GEO:")
            print(traceback.format_exc())
            return EstabelecimentosGeoResponseSchema(estabelecimentos=[])
