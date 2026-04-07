"""
atualizar_coordenadas.py
------------------------
Busca na tabela [temp_CGUSC].[fp].[dados_farmacia] todos os registros com
latitude ou longitude nulas, geocodifica via HERE Geocoding API e atualiza
a tabela diretamente.

HERE Maps: alta precisão para endereços brasileiros, plano gratuito com
250.000 requisições/mês. Para 35k registros o processamento leva ~20-30 minutos.
Rode com LIMITE = None para testar antes de processar tudo.

Uso:
    python src/scripts/atualizar_coordenadas.py

Dependências:
    pip install requests sqlalchemy pyodbc
"""

import time
import urllib
import urllib.parse
import unicodedata
import logging
import sys
import os
import requests
import urllib3
from pathlib import Path
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError, OperationalError

# Carrega .env da raiz do projeto (dois níveis acima de src/scripts/)
_env_path = Path(__file__).resolve().parents[2] / '.env'
if _env_path.exists():
    for _line in _env_path.read_text(encoding='utf-8').splitlines():
        _line = _line.strip()
        if _line and not _line.startswith('#') and '=' in _line:
            _k, _v = _line.split('=', 1)
            os.environ.setdefault(_k.strip(), _v.strip())

# ── Logging ────────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%H:%M:%S',
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler('geocodificacao.log', encoding='utf-8'),
    ],
)
log = logging.getLogger(__name__)

# Suprime avisos de SSL (necessário em redes corporativas com proxy de inspeção)
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# ── Configurações ─────────────────────────────────────────────────────────────

HERE_API_KEY = os.environ.get('HERE_API_KEY', '')
if not HERE_API_KEY:
    raise EnvironmentError("HERE_API_KEY não encontrada. Defina no arquivo .env na raiz do projeto.")

# HERE não tem limite estrito por segundo — delay pequeno por cortesia
DELAY_ENTRE_REQUESTS = 0.05

# Quantos registros processar (None = todos). Use 10 para testar primeiro.
LIMITE = None

# Para depurar endereços específicos, liste os CNPJs aqui.
# Quando preenchido, ignora o LIMITE e o filtro de nulos — processa só estes.
TEST_CNPJS = []

# Filtra por código IBGE do município (7 dígitos). Ignora o LIMITE mas respeita
# o filtro de nulos (só geocodifica quem ainda não tem coordenadas).
# Ex: 4207205 para Imaruí/SC. Deixe None para processar todos.
TEST_CODIBGE = None

# Tamanho do lote para commit no banco
BATCH_SIZE = 50

# Tentativas de reconexão ao banco
DB_MAX_RETRIES = 5
DB_RETRY_DELAY = 10  # segundos entre tentativas de reconexão

# Tentativas por requisição de geocodificação
MAX_RETRIES_GEO = 3
RETRY_DELAY_GEO = 3  # segundos entre tentativas

# ── Conexão (mesma do backend) ─────────────────────────────────────────────────

params = (
    "Driver={ODBC Driver 17 for SQL Server};"
    "Server=SDH-DIE-BD;"
    "Database=temp_CGUSC;"
    "Trusted_Connection=yes;"
)
DATABASE_URL = f"mssql+pyodbc:///?odbc_connect={urllib.parse.quote_plus(params)}"
engine = create_engine(DATABASE_URL, echo=False, pool_pre_ping=True)

# ── Sessão HTTP ────────────────────────────────────────────────────────────────

_session = requests.Session()
_session.verify = False  # proxy corporativo CGU não reconhecido pelo Python

# ── Geocodificação via HERE ────────────────────────────────────────────────────

HERE_BASE = 'https://geocode.search.hereapi.com/v1/geocode'


def _parse_here(resp_json: dict) -> tuple[float | None, float | None]:
    """Extrai (lat, lon) do primeiro resultado HERE, ou (None, None)."""
    items = resp_json.get('items', [])
    if items:
        pos = items[0].get('position', {})
        lat = pos.get('lat')
        lng = pos.get('lng')
        if lat is not None and lng is not None:
            return float(lat), float(lng)
    return None, None


def geocodificar(endereco: str) -> tuple[float | None, float | None]:
    """
    Geocodifica um endereço via HERE Geocoding API.

    Retorna (latitude, longitude) ou (None, None) em caso de falha.
    Realiza até MAX_RETRIES_GEO tentativas com backoff em erros de rede.
    """
    if not endereco or not endereco.strip():
        return None, None

    params = {
        'q': endereco.strip(),
        'apiKey': HERE_API_KEY,
        'lang': 'pt-BR',
        'in': 'countryCode:BRA',
        'limit': 1,
    }

    for tentativa in range(1, MAX_RETRIES_GEO + 1):
        try:
            resp = _session.get(HERE_BASE, params=params, timeout=15)
            resp.raise_for_status()
            lat, lon = _parse_here(resp.json())
            if lat is None:
                log.info("  ⚠️  Não encontrado: '%s'", endereco)
            return lat, lon

        except requests.exceptions.Timeout:
            log.warning("  ⏱️  Timeout (tentativa %d/%d)", tentativa, MAX_RETRIES_GEO)
        except requests.exceptions.ConnectionError as e:
            log.warning("  🔌 Erro de conexão (tentativa %d/%d): %s", tentativa, MAX_RETRIES_GEO, e)
        except requests.exceptions.HTTPError as e:
            status = e.response.status_code if e.response is not None else 0
            log.warning("  🌐 Erro HTTP %d (tentativa %d/%d): %s", status, tentativa, MAX_RETRIES_GEO, e)
            if status == 429:
                log.warning("  ⏳ Rate limit — aguardando 30s...")
                time.sleep(30)
                continue
            if status in (401, 403):
                log.error("  🔑 API Key inválida ou sem permissão. Verifique HERE_API_KEY.")
                return None, None
        except Exception as e:
            log.warning("  ❌ Erro inesperado (tentativa %d/%d): %s", tentativa, MAX_RETRIES_GEO, e)

        if tentativa < MAX_RETRIES_GEO:
            time.sleep(RETRY_DELAY_GEO)

    return None, None


def geocodificar_cep(cep: str) -> tuple[float | None, float | None]:
    """Geocodifica via CEP usando HERE."""
    if not cep:
        return None, None
    return geocodificar(f"{cep}, Brasil")


# ── Normalização de endereço ───────────────────────────────────────────────────

def normalizar(texto: str) -> str:
    """Remove acentos e caracteres especiais, mantendo apenas ASCII."""
    return unicodedata.normalize('NFKD', texto).encode('ascii', 'ignore').decode('ascii')


TIPO_LOGRADOURO = {
    # Rua / Via
    'R':   'Rua',
    'VIA': 'Via',
    'VEL': 'Viela',
    'LAD': 'Ladeira',
    'TRC': 'Trecho',
    # Avenida / Rodovia / Estrada
    'AV':  'Avenida',
    'ROD': 'Rodovia',
    'RDV': 'Rodovia',
    'EST': 'Estrada',
    # Praça / Largo
    'PC':  'Praca',
    'PCA': 'Praca',
    'PR':  'Praca',
    'LG':  'Largo',
    'LGO': 'Largo',
    # Travessa / Alameda
    'TV':  'Travessa',
    'TR':  'Travessa',
    'AL':  'Alameda',
    # Bairro / Setor / Quadra / Conjunto
    'ST':  'Setor',
    'QD':  'Quadra',
    'CJ':  'Conjunto',
    'BL':  'Bloco',
    # Vila / Residencial / Loteamento / Condomínio
    'VL':  'Vila',
    'RSD': 'Residencial',
    'LOT': 'Loteamento',
    'CON': 'Condominio',
    'CND': 'Condominio',
    # Parque / Área
    'PRQ': 'Parque',
    'PQ':  'Parque',
    'AR':  'Area',
    # Rural
    'SIT': 'Sitio',
    'CH':  'Chacara',
    'COL': 'Colonia',
    'FAZ': 'Fazenda',
    'DT':  'Distrito',
    # Genéricos / sem tipo válido
    'OTR': '',
    'ETC': '',
}


def montar_endereco(row: dict) -> tuple[str | None, str | None, str | None]:
    """Monta string de endereço expandindo as abreviações de tipo de logradouro.

    Returns:
        Tupla (endereco_completo, endereco_simples, cep).
    """
    logradouro = (row.get('logradouro', '') or '').strip()
    numero     = str(row.get('numero',  '') or '').strip()
    bairro     = str(row.get('bairro',  '') or '').strip()

    if not logradouro:
        return None, None, None

    municipio = (row.get('municipio', '') or '').strip()
    uf        = (row.get('uf',        '') or '').strip()

    # Remove separador de milhar brasileiro (ex: "2.162" → "2162")
    if numero:
        numero = numero.replace('.', '')

    logradouro_completo = logradouro

    partes_completo = [logradouro_completo]
    if numero and numero not in ('None', ''):
        partes_completo.append(numero)
    if bairro and bairro not in ('None', ''):
        partes_completo.append(bairro)
    if municipio and municipio not in ('None', ''):
        partes_completo.append(municipio)
    if uf and uf not in ('None', ''):
        partes_completo.append(uf)
    partes_completo.append('Brasil')

    # Versão simplificada: só logradouro + cidade + estado (sem número/bairro)
    partes_simples = [logradouro_completo]
    if municipio and municipio not in ('None', ''):
        partes_simples.append(municipio)
    if uf and uf not in ('None', ''):
        partes_simples.append(uf)
    partes_simples.append('Brasil')

    cep = (row.get('cep', '') or '').strip()
    cep_str = normalizar(cep) if cep and cep not in ('None', '') else None

    return (
        normalizar(', '.join(partes_completo)),
        normalizar(', '.join(partes_simples)),
        cep_str,
    )


# ── Persistência com retry ─────────────────────────────────────────────────────

def commit_lote(conn, update_sql, pendentes: list) -> bool:
    """Executa UPDATE em lote com até DB_MAX_RETRIES tentativas."""
    for tentativa in range(1, DB_MAX_RETRIES + 1):
        try:
            conn.execute(update_sql, pendentes)
            conn.commit()
            log.info("  💾 %d registros gravados no banco.", len(pendentes))
            return True
        except OperationalError as e:
            log.error("  🔴 Erro de banco (tentativa %d/%d): %s", tentativa, DB_MAX_RETRIES, e)
            if tentativa < DB_MAX_RETRIES:
                log.info("  ⏳ Aguardando %ds antes de nova tentativa...", DB_RETRY_DELAY)
                time.sleep(DB_RETRY_DELAY)
                try:
                    conn.rollback()
                except Exception:
                    pass
        except SQLAlchemyError as e:
            log.error("  🔴 Erro SQLAlchemy inesperado: %s", e)
            break

    log.error("  ❌ Falha permanente ao gravar lote — %d registros perdidos.", len(pendentes))
    return False


# ── Principal ──────────────────────────────────────────────────────────────────

def main():
    if TEST_CNPJS:
        cnpjs_in = ', '.join(f"'{c}'" for c in TEST_CNPJS)
        select_sql = f"""
            SELECT
                f.cnpj, f.tipoLogradouro, f.logradouro, f.numero, f.bairro, f.cep,
                m.no_municipio AS municipio, m.uf
            FROM [temp_CGUSC].[fp].[dados_farmacia] f
            LEFT JOIN (
                SELECT cnpj, MAX(no_municipio) AS no_municipio, MAX(uf) AS uf
                FROM [temp_CGUSC].[fp].[movimentacao_mensal_cnpj]
                GROUP BY cnpj
            ) m ON f.cnpj = m.cnpj
            WHERE f.cnpj IN ({cnpjs_in})
              AND (f.latitude IS NULL OR f.longitude IS NULL)
        """
    elif TEST_CODIBGE is not None:
        select_sql = f"""
            SELECT
                f.cnpj, f.tipoLogradouro, f.logradouro, f.numero, f.bairro, f.cep,
                m.no_municipio AS municipio, m.uf
            FROM [temp_CGUSC].[fp].[dados_farmacia] f
            LEFT JOIN (
                SELECT cnpj, MAX(no_municipio) AS no_municipio, MAX(uf) AS uf
                FROM [temp_CGUSC].[fp].[movimentacao_mensal_cnpj]
                GROUP BY cnpj
            ) m ON f.cnpj = m.cnpj
            WHERE f.codibge = {TEST_CODIBGE}
              AND (f.latitude IS NULL OR f.longitude IS NULL)
              AND f.logradouro IS NOT NULL
        """
    else:
        limit_clause = f"TOP {LIMITE}" if LIMITE else ""
        select_sql = f"""
            SELECT {limit_clause}
                f.cnpj, f.tipoLogradouro, f.logradouro, f.numero, f.bairro, f.cep,
                m.no_municipio AS municipio, m.uf
            FROM [temp_CGUSC].[fp].[dados_farmacia] f
            LEFT JOIN (
                SELECT cnpj, MAX(no_municipio) AS no_municipio, MAX(uf) AS uf
                FROM [temp_CGUSC].[fp].[movimentacao_mensal_cnpj]
                GROUP BY cnpj
            ) m ON f.cnpj = m.cnpj
            WHERE (f.latitude IS NULL OR f.longitude IS NULL)
              AND f.logradouro IS NOT NULL
        """

    update_sql = text("""
        UPDATE [temp_CGUSC].[fp].[dados_farmacia]
        SET latitude  = :lat,
            longitude = :lon
        WHERE cnpj = :cnpj
    """)

    atualizadas = 0
    falhas = 0
    total = 0

    try:
        with engine.connect() as conn:
            try:
                rows = conn.execute(text(select_sql)).mappings().all()
            except SQLAlchemyError as e:
                log.error("❌ Falha ao consultar o banco: %s", e)
                return

            total = len(rows)
            log.info("\n📋 %d farmácias sem coordenadas encontradas.", total)
            tempo_est = total * DELAY_ENTRE_REQUESTS / 60
            log.info("⏳ Tempo estimado: ~%.0f minutos\n", tempo_est)

            pendentes: list[dict] = []

            for i, row in enumerate(rows, 1):
                cnpj = row['cnpj']

                try:
                    endereco, endereco_simples, cep = montar_endereco(dict(row))
                except Exception as e:
                    log.error("[%d/%d] CNPJ %s — erro ao montar endereço: %s", i, total, cnpj, e)
                    falhas += 1
                    continue

                log.info("[%d/%d] CNPJ %s — %s", i, total, cnpj, endereco)

                if not endereco:
                    log.info("  ⏩ Sem endereço suficiente, pulando.")
                    falhas += 1
                    continue

                lat, lon = None, None

                try:
                    lat, lon = geocodificar(endereco)
                    time.sleep(DELAY_ENTRE_REQUESTS)

                    if lat is None and endereco_simples and endereco_simples != endereco:
                        log.info("  🔄 Tentando simplificado: %s", endereco_simples)
                        lat, lon = geocodificar(endereco_simples)
                        time.sleep(DELAY_ENTRE_REQUESTS)
                        if lat is not None:
                            log.info("     ↳ Encontrado pelo simplificado")


                except KeyboardInterrupt:
                    log.warning("\n⚠️  Interrompido durante geocodificação.")
                    if pendentes:
                        log.info("💾 Gravando %d registros pendentes antes de sair...", len(pendentes))
                        commit_lote(conn, update_sql, pendentes)
                    raise

                except Exception as e:
                    log.error("  ❌ Erro inesperado na geocodificação do CNPJ %s: %s", cnpj, e)
                    falhas += 1
                    continue

                if lat is not None and lon is not None:
                    pendentes.append({'lat': lat, 'lon': lon, 'cnpj': cnpj})
                    log.info("  ✅ lat=%.6f, lon=%.6f (pendente)", lat, lon)
                    atualizadas += 1
                else:
                    falhas += 1

                processados = atualizadas + falhas
                taxa = (atualizadas / processados * 100) if processados > 0 else 0
                restantes = total - i
                tempo_restante = restantes * DELAY_ENTRE_REQUESTS / 60
                log.info(
                    "  📊 Taxa: %.1f%% | ✅ %d | ⚠️ %d | Restantes: %d (~%.0f min)",
                    taxa, atualizadas, falhas, restantes, tempo_restante,
                )

                if len(pendentes) >= BATCH_SIZE:
                    commit_lote(conn, update_sql, pendentes)
                    pendentes = []

            if pendentes:
                commit_lote(conn, update_sql, pendentes)

    except KeyboardInterrupt:
        log.warning("\n⛔ Execução interrompida pelo usuário.")
    except OperationalError as e:
        log.error("❌ Falha de conexão com o banco de dados: %s", e)
    except Exception as e:
        log.error("❌ Erro fatal inesperado: %s", e, exc_info=True)
    finally:
        log.info("\n%s", "─" * 50)
        log.info("✅ Atualizadas      : %d", atualizadas)
        log.info("⚠️  Falhas/Sem dados : %d", falhas)
        log.info("Total processado   : %d", total)


if __name__ == '__main__':
    main()
