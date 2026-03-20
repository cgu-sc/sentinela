from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
import urllib

# =============================================================================
# CONFIGURAÇÃO DE CONEXÃO AO SQL SERVER
# =============================================================================
# Nota: Usamos urllib.parse.quote_plus para garantir que caracteres especiais na
# string de conexão ODBC não causem erros de URI no SQLAlchemy.

params = (
    "Driver={ODBC Driver 17 for SQL Server};"
    "Server=SDH-DIE-BD;"
    "Database=temp_CGUSC;"
    "Trusted_Connection=yes;"
)

DATABASE_URL = f"mssql+pyodbc:///?odbc_connect={urllib.parse.quote_plus(params)}"

# Engine com Pool de Conexões para suportar múltiplos usuários simultâneos no BI/Web
engine = create_engine(
    DATABASE_URL,
    pool_size=10,
    max_overflow=20,
    pool_recycle=3600,
    echo=False  # Mude para True se quiser ver os SQLs reais no console (útil para debug)
)

# Fabrica de Sessões para interagir com o banco
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Classe base para futuros modelos ORM (se você quiser mapear tabelas para objetos)
Base = declarative_base()

# =============================================================================
# INJEÇÃO DE DEPENDÊNCIA (Para uso no FastAPI)
# =================================)
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
