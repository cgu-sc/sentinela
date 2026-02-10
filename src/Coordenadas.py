import pyodbc
from geopy import MapBox
from geopy.geocoders import OpenCage
from geopy.exc import GeocoderTimedOut, GeocoderUnavailable, GeocoderServiceError, GeocoderAuthenticationFailure
from geopy.extra.rate_limiter import RateLimiter
import time

NOMINATIM_USER_AGENT = 'GUIgeocodificador_cep/1.0'



TABLE_NAME = 'dadosFarmaciasFP_teste'  # Substitua pelo nome da sua tabela
CEP_COLUMN = 'cep'  # Coluna que armazena o CEP
LAT_COLUMN = 'latitude'  # Coluna para armazenar a Latitude
LON_COLUMN = 'longitude'  # Coluna para armazenar a Longitude



# --- Configurações ---
# Substitua pela sua Chave de API do OpenCage
MAPBOX_ACCESS_TOKEN = 'pk.eyJ1IjoiZ3VpbXciLCJhIjoiY21iaDJraGVnMDVrcjJrcHJvandhbDc0NyJ9.WchF5i4GXTCXZ1P0iuL-qQ'


# String de conexão fornecida diretamente (mantenha como no script anterior)
CONN_STR_DIRECT = (
    "DRIVER={ODBC Driver 17 for SQL Server};"
    "SERVER=SDH-DIE-BD;"
    "DATABASE=temp_CGUSC;"
    "Trusted_Connection=yes;"
)
# Configuração do Geocoder (Mapbox)
if MAPBOX_ACCESS_TOKEN == 'SEU_MAPBOX_ACCESS_TOKEN_AQUI' or \
   MAPBOX_ACCESS_TOKEN is None or MAPBOX_ACCESS_TOKEN.strip() == "":
    print("⚠️ ALERTA: O Access Token do Mapbox (MAPBOX_ACCESS_TOKEN) não foi configurado ou está com o valor padrão.")
    print("É crucial definir seu Access Token para usar a API do Mapbox.")
    geolocator = None
    geocode_with_delay = None
else:
    try:
        geolocator = MapBox(api_key=MAPBOX_ACCESS_TOKEN, user_agent="meu_app_geocodificador_cep/1.0 (seuemail@example.com)") # user_agent é bom, mas não tão crítico quanto no Nominatim
        # Verifique os limites de taxa da sua conta Mapbox.
        # Um limite comum é de 600 req/minuto (10 req/segundo) para algumas APIs,
        # mas pode variar. Comece com um delay conservador.
        # Ex: 0.2 segundos para 5 req/seg. Se o limite for maior, pode diminuir.
        geocode_with_delay = RateLimiter(geolocator.geocode, min_delay_seconds=0.2, error_wait_seconds=10.0, max_retries=3)
    except Exception as e:
        print(f"Erro ao inicializar o geolocator Mapbox: {e}.")
        geolocator = None
        geocode_with_delay = None

# --- Funções Auxiliares ---

def buscar_ceps_para_atualizar(cursor):
    """Busca CEPs distintos que ainda não possuem latitude ou longitude."""
    query = f"""
        SELECT DISTINCT {CEP_COLUMN}
        FROM {TABLE_NAME}
        WHERE {CEP_COLUMN} IS NOT NULL AND LTRIM(RTRIM({CEP_COLUMN})) <> ''
          AND ({LAT_COLUMN} IS NULL OR {LON_COLUMN} IS NULL OR {LAT_COLUMN} = 0 OR {LON_COLUMN} = 0)
    """
    print(f"Executando query para buscar CEPs: {query}")
    cursor.execute(query)
    return [row[0] for row in cursor.fetchall() if row[0] is not None]

def obter_lat_lon_mapbox(cep_str, geolocator_func):
    """Busca latitude e longitude para um CEP usando Mapbox."""
    if not geolocator_func:
        print("Geolocator Mapbox não inicializado. Pulando geocodificação.")
        return None

    if not cep_str or not isinstance(cep_str, str):
        print(f"CEP fornecido é inválido (não é string ou está vazio): '{cep_str}'. Pulando.")
        return None

    cep_formatado = cep_str.strip()
    # O Mapbox geralmente lida bem com CEPs, especialmente com o parâmetro 'country'.

    print(f"Consultando Mapbox para CEP: {cep_formatado}...")

    try:
        # country='BR' para restringir a busca ao Brasil.
        # types=['postcode'] pode ajudar a focar em CEPs, mas pode ser muito restritivo.
        # Teste sem 'types' primeiro.
        location = geolocator_func(cep_formatado, country='BR', timeout=10)
        if location:
            print(f"Encontrado para CEP {cep_str}: {location.address} -> Lat: {location.latitude}, Lon: {location.longitude}")
            return location.latitude, location.longitude
        else:
            print(f"CEP {cep_str} não encontrado pelo Mapbox.")
            return None
    except GeocoderAuthenticationFailure:
        print(f"Erro de autenticação com a API Mapbox. Verifique seu MAPBOX_ACCESS_TOKEN.")
        # Você pode querer parar o script aqui, pois outras tentativas falharão.
        # global geocode_with_delay # Para modificar a variável global
        # geocode_with_delay = None # Desabilita futuras tentativas
        return "STOP_PROCESSING" # Sinaliza para parar
    except GeocoderTimedOut:
        print(f"Timeout ao consultar Mapbox para o CEP {cep_str}.")
        return None
    except GeocoderUnavailable:
        print(f"Serviço Mapbox indisponível para o CEP {cep_str} (GeocoderUnavailable).")
        return None
    except GeocoderServiceError as e:
        print(f"Erro do serviço Mapbox para o CEP {cep_str}: {e}")
        return None
    except Exception as e:
        print(f"Erro inesperado ao processar CEP {cep_str} com Mapbox: {e}")
        return None

def atualizar_lat_lon_no_banco(cursor, cep, latitude, longitude):
    """Atualiza a latitude e longitude para um CEP específico na tabela."""
    query = f"""
        UPDATE {TABLE_NAME}
        SET {LAT_COLUMN} = ?, {LON_COLUMN} = ?
        WHERE {CEP_COLUMN} = ?
          AND ({LAT_COLUMN} IS NULL OR {LON_COLUMN} IS NULL OR {LAT_COLUMN} = 0 OR {LON_COLUMN} = 0)
    """
    try:
        print(f"Atualizando CEP {cep} no banco com Lat: {latitude}, Lon: {longitude}")
        cursor.execute(query, latitude, longitude, cep)
        return cursor.rowcount
    except pyodbc.Error as ex:
        sqlstate = ex.args[0]
        print(f"Erro de banco de dados ao atualizar CEP {cep}: {sqlstate} - {ex}")
        return 0

# --- Principal ---
def main():
    if not geocode_with_delay or not geolocator:
        print("Finalizando script devido a erro na inicialização do geolocator Mapbox ou Access Token não configurado.")
        return

    conn = None
    ceps_processados_sucesso = 0
    ceps_nao_encontrados_api = 0
    ceps_com_erro_api = 0
    ceps_com_erro_db = 0

    try:
        print(f"Conectando ao banco de dados usando a string: {CONN_STR_DIRECT}")
        conn = pyodbc.connect(CONN_STR_DIRECT)
        cursor = conn.cursor()
        print("Conexão bem-sucedida!")

        ceps_para_processar = buscar_ceps_para_atualizar(cursor)
        total_ceps_para_processar = len(ceps_para_processar)
        print(f"Encontrados {total_ceps_para_processar} CEPs distintos para geocodificar via Mapbox.")
        print("Verifique os limites de uso (diário/mensal e por minuto) da sua conta Mapbox.")
        tempo_estimado_segundos = total_ceps_para_processar * (geocode_with_delay.min_delay_seconds if hasattr(geocode_with_delay, 'min_delay_seconds') else 0.2)
        print(f"Com o delay atual, o processo levará aproximadamente {tempo_estimado_segundos / 3600:.2f} horas.")


        if not ceps_para_processar:
            print("Nenhum CEP para atualizar.")
            return

        for i, cep_original in enumerate(ceps_para_processar):
            print(f"\nProcessando CEP {i+1}/{total_ceps_para_processar}: '{cep_original}'")

            if cep_original is None or not str(cep_original).strip():
                print(f"CEP inválido ou vazio na lista: '{cep_original}'. Pulando.")
                ceps_com_erro_api += 1
                continue

            resultado_geocoding = obter_lat_lon_mapbox(str(cep_original), geocode_with_delay)

            if resultado_geocoding == "STOP_PROCESSING":
                print("Erro crítico de autenticação com Mapbox. Interrompendo o processamento.")
                break # Sai do loop for

            if isinstance(resultado_geocoding, tuple): # Sucesso, obteve coordenadas
                lat, lon = resultado_geocoding
                try:
                    rows_affected = atualizar_lat_lon_no_banco(cursor, cep_original, lat, lon)
                    conn.commit()
                    if rows_affected > 0:
                        print(f"CEP {cep_original} atualizado no banco. Linhas afetadas: {rows_affected}")
                        ceps_processados_sucesso += rows_affected
                    else:
                        print(f"CEP {cep_original} processado (Mapbox retornou coordenadas), mas nenhuma linha foi atualizada no banco.")
                except pyodbc.Error as db_err:
                    print(f"Falha no commit/DB para o CEP {cep_original}: {db_err}. Tentando rollback.")
                    conn.rollback()
                    ceps_com_erro_db += 1
            else: # Não obteve coordenadas (None ou outro erro não crítico)
                print(f"Não foi possível obter coordenadas para o CEP {cep_original} via Mapbox.")
                ceps_nao_encontrados_api += 1


        print("\n--- Resumo do Processamento (Mapbox) ---")
        print(f"Total de CEPs que precisavam de atualização: {total_ceps_para_processar}")
        print(f"CEPs atualizados com sucesso no banco (linhas afetadas): {ceps_processados_sucesso}")
        print(f"CEPs não encontrados ou com erro na API Mapbox: {ceps_nao_encontrados_api + ceps_com_erro_api}")
        print(f"CEPs com erro durante a atualização no banco: {ceps_com_erro_db}")

    except pyodbc.Error as ex:
        sqlstate = ex.args[0]
        print(f"Erro de conexão ou execução no SQL Server: {sqlstate} - {ex}")
        if conn:
            try:
                conn.rollback()
            except pyodbc.Error as rb_err:
                print(f"Erro ao tentar rollback: {rb_err}")
    except Exception as e:
        print(f"Ocorreu um erro inesperado no script: {e}")
    finally:
        if conn:
            conn.close()
            print("Conexão com o banco de dados fechada.")

if __name__ == "__main__":
    if MAPBOX_ACCESS_TOKEN == 'SEU_MAPBOX_ACCESS_TOKEN_AQUI' or \
       MAPBOX_ACCESS_TOKEN is None or MAPBOX_ACCESS_TOKEN.strip() == "":
        print("ERRO CRÍTICO: O Access Token do Mapbox (MAPBOX_ACCESS_TOKEN) não foi definido no script.")
        print("Por favor, edite o script, adicione seu token e tente novamente.")
    else:
        main()