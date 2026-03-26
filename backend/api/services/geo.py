from sqlalchemy.orm import Session
from ..schemas.geo import LocalidadeSchema, LocalidadesResponseSchema
from data_cache import get_localidades_df

class GeoService:
    @staticmethod
    def get_localidades(db: Session) -> LocalidadesResponseSchema:
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
                    id_ibge7=r["id_ibge7"]
                ) 
                for r in df.iter_rows(named=True)
            ]
            
            return LocalidadesResponseSchema(localidades=localidades)
        except Exception as e:
            import traceback
            print("❌ ERRO AO BUSCAR LOCALIDADES DO CACHE:")
            print(traceback.format_exc())
            return LocalidadesResponseSchema(localidades=[])
