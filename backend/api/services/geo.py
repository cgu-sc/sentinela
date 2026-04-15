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
                    nu_populacao=r["nu_populacao"],
                    unidade_pf=r.get("unidade_pf")
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
        Retorna coordenadas e indicadores de risco consolidados de todos os estabelecimentos.
        Utiliza os dados pré-calculados e enriquecidos no cache farmacias.parquet.
        """
        try:
            df = get_df_dados_farmacia()

            # Filtra apenas quem tem coordenadas (necessário para o mapa)
            df = df.filter(
                pl.col("latitude").is_not_null() & pl.col("longitude").is_not_null()
            )

            estabelecimentos = [
                EstabelecimentoGeoSchema(
                    cnpj=r["cnpj"],
                    razao_social=r.get("razao_social"),
                    lat=r["latitude"],
                    lon=r["longitude"],
                    id_ibge7=r.get("id_ibge7"),
                    score_risco=r.get("score_risco_final"),
                    classificacao_risco=r.get("classificacao_risco"),
                    percValSemComp=r.get("perc_val_sem_comp"),
                    totalMov=r.get("total_mov"),
                    valSemComp=r.get("val_sem_comp"),
                )
                for r in df.iter_rows(named=True)
            ]

            return EstabelecimentosGeoResponseSchema(estabelecimentos=estabelecimentos)
        except Exception as e:
            import traceback
            print("❌ ERRO AO BUSCAR ESTABELECIMENTOS GEO:")
            print(traceback.format_exc())
            return EstabelecimentosGeoResponseSchema(estabelecimentos=[])
