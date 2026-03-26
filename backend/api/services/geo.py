from sqlalchemy.orm import Session
from sqlalchemy import text
from ..schemas.geo import LocalidadeSchema, LocalidadesResponseSchema

class GeoService:
    @staticmethod
    def get_localidades(db: Session) -> LocalidadesResponseSchema:
        try:
            sql = text("""
                SELECT
                    sg_uf,
                    no_regiao_saude,
                    id_regiao_saude,
                    no_municipio,
                    id_ibge7
                FROM [temp_CGUSC].[fp].[dados_ibge]
                ORDER BY sg_uf, no_regiao_saude, no_municipio
            """)
            rows = db.execute(sql).fetchall()
            localidades = [LocalidadeSchema(**row._mapping) for row in rows]
            return LocalidadesResponseSchema(localidades=localidades)
        except Exception as e:
            import traceback
            print("ERRO AO BUSCAR LOCALIDADES:")
            print(traceback.format_exc())
            return LocalidadesResponseSchema(localidades=[])
