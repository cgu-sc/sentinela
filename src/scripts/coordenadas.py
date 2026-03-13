import pandas as pd
import requests
import time
# requests.utils.quote é usado para codificar o endereço para a URL
from requests.utils import quote as url_quote

# --- Configurações ---
# ATENÇÃO: O token abaixo é o que você forneceu. Mantenha-o seguro.
MAPBOX_ACCESS_TOKEN = 'pk.eyJ1Ijoi28ifQ.69Q1b-6sEULiIQdUloOvlA'
INPUT_EXCEL_FILE = 'endereco_latitude_longitude_faltante_outro.xls'  # <<< ATUALIZE COM O NOME DO SEU ARQUIVO EXCEL (.xls ou .xlsx)
OUTPUT_CSV_FILE = 'saida_cnpj_lat_lon_faltante_outro.csv'  # Nome do arquivo CSV de saída

# Nomes das colunas no seu arquivo Excel
ADDRESS_COLUMN_NAME = 'endereco'  # <<< NOME DA COLUNA QUE CONTÉM O ENDEREÇO COMPLETO
CNPJ_COLUMN_NAME = 'cnpj'  # <<< NOME DA COLUNA QUE CONTÉM O CNPJ

# Nomes das colunas de saída (latitude e longitude serão criadas/preenchidas)
LATITUDE_COLUMN_NAME = 'latitude'
LONGITUDE_COLUMN_NAME = 'longitude'
SHEET_NAME = 0  # Nome ou índice da planilha a ser lida (0 para a primeira)


# --- Fim das Configurações ---

def obter_coordenadas_mapbox_por_endereco(texto_endereco, token):
    """
    Busca as coordenadas (latitude, longitude) de um endereço completo usando a API da Mapbox.
    """
    if pd.isna(texto_endereco) or not str(texto_endereco).strip():
        print(f"Endereço está vazio ou é NaN. Pulando.")
        return None, None

    endereco_para_api = str(texto_endereco).strip()
    endereco_codificado = url_quote(endereco_para_api)

    url = f"https://api.mapbox.com/geocoding/v5/mapbox.places/{endereco_codificado}.json"
    params = {
        'access_token': token,
        'country': 'BR',
        'limit': 1
    }

    try:
        response = requests.get(url, params=params, timeout=15)
        response.raise_for_status()
        data = response.json()

        if data['features']:
            longitude, latitude = data['features'][0]['center']
            return latitude, longitude
        else:
            print(f"Endereço '{texto_endereco}' não encontrado na Mapbox.")
            return None, None
    except requests.exceptions.Timeout:
        print(f"Timeout na requisição para o endereço '{texto_endereco}'.")
        return None, None
    except requests.exceptions.RequestException as e:
        print(f"Erro na requisição para o endereço '{texto_endereco}': {e}")
        return None, None
    except (KeyError, IndexError) as e:
        print(f"Erro ao processar a resposta da Mapbox para o endereço '{texto_endereco}': {e}")
        return None, None


def processar_arquivo_excel_para_cnpj_lat_lon():
    """
    Lê o arquivo Excel contendo endereços e CNPJs, busca as coordenadas
    e salva um CSV com CNPJ, latitude e longitude.
    """
    if MAPBOX_ACCESS_TOKEN == 'SEU_ACCESS_TOKEN_DO_MAPBOX_AQUI' or not MAPBOX_ACCESS_TOKEN:
        print("🚨 Alerta: O token da Mapbox não parece estar configurado corretamente no script.")
        return

    if INPUT_EXCEL_FILE == 'seu_arquivo_com_enderecos_e_cnpj.xlsx' and 'seu_arquivo' in INPUT_EXCEL_FILE:  # Placeholder check
        print("🚨 Alerta: Por favor, atualize a variável 'INPUT_EXCEL_FILE' com o nome real do seu arquivo Excel.")
        return

    try:
        print(f"Tentando ler o arquivo Excel: '{INPUT_EXCEL_FILE}', Planilha: '{SHEET_NAME}'")
        print(
            f"Colunas esperadas: Endereço='{ADDRESS_COLUMN_NAME}', CNPJ='{CNPJ_COLUMN_NAME}'. Serão lidas como texto.")

        # Ler o arquivo Excel, tratando as colunas de ENDEREÇO e CNPJ como string
        # Isso é importante para preservar formatos, como zeros à esquerda em alguns CNPJs ou CEPs no endereço.
        df = pd.read_excel(INPUT_EXCEL_FILE,
                           sheet_name=SHEET_NAME,
                           dtype={
                               ADDRESS_COLUMN_NAME: str,
                               CNPJ_COLUMN_NAME: str  # Ler CNPJ como string
                           })

        print(f"\nColunas detectadas no arquivo Excel '{INPUT_EXCEL_FILE}': {df.columns.tolist()}")
        print(f"Arquivo Excel '{INPUT_EXCEL_FILE}' lido com sucesso. {len(df)} registros encontrados.")

    except FileNotFoundError:
        print(f"❌ Erro: Arquivo de entrada '{INPUT_EXCEL_FILE}' não encontrado.")
        return
    except ImportError:  # Para xlrd ou openpyxl
        print("❌ Erro: A biblioteca 'xlrd' (para .xls) ou 'openpyxl' (para .xlsx) pode ser necessária.")
        print("Instale a biblioteca apropriada com: pip install xlrd openpyxl")
        return
    except ValueError as ve:
        expected_cols_for_dtype = {ADDRESS_COLUMN_NAME, CNPJ_COLUMN_NAME}
        missing_dtype_col = None
        for col in expected_cols_for_dtype:
            if f"Column '{col}' not found in dtype" in str(ve):
                missing_dtype_col = col
                break
        if missing_dtype_col:
            print(
                f"❌ Erro: A coluna '{missing_dtype_col}' especificada em 'dtype' não foi encontrada nas colunas do Excel.")
            print(f"Verifique se o nome da coluna no arquivo Excel corresponde exatamente a '{missing_dtype_col}'.")
            print(
                f"Colunas disponíveis: {df.columns.tolist() if 'df' in locals() and hasattr(df, 'columns') else ' (DataFrame não carregado para listar colunas)'}")

        elif f"Worksheet named '{SHEET_NAME}' not found" in str(ve) or (
                isinstance(SHEET_NAME, int) and "sheet_name" in str(ve).lower()):
            print(f"❌ Erro: Planilha '{SHEET_NAME}' não encontrada no arquivo '{INPUT_EXCEL_FILE}'.")
        else:
            print(f"❌ Erro de valor ao ler o arquivo Excel: {ve}")
        return
    except Exception as e:
        print(f"❌ Erro inesperado ao ler o arquivo Excel '{INPUT_EXCEL_FILE}': {e}")
        return

    df.columns = df.columns.str.strip()  # Remove espaços dos nomes das colunas
    print(f"Nomes das colunas após remover espaços extras: {df.columns.tolist()}")

    # Verificar se as colunas essenciais (endereço e CNPJ) existem
    if ADDRESS_COLUMN_NAME not in df.columns:
        print(f"❌ Erro Crítico: A coluna de endereço '{ADDRESS_COLUMN_NAME}' não foi encontrada no arquivo Excel.")
        return
    if CNPJ_COLUMN_NAME not in df.columns:
        print(f"❌ Erro Crítico: A coluna de CNPJ '{CNPJ_COLUMN_NAME}' não foi encontrada no arquivo Excel.")
        return

    # Criar colunas de latitude e longitude se não existirem, preenchendo com pd.NA
    if LATITUDE_COLUMN_NAME not in df.columns:
        df[LATITUDE_COLUMN_NAME] = pd.NA
    if LONGITUDE_COLUMN_NAME not in df.columns:
        df[LONGITUDE_COLUMN_NAME] = pd.NA

    # Garantir que sejam numéricas para armazenar as coordenadas
    df[LATITUDE_COLUMN_NAME] = pd.to_numeric(df[LATITUDE_COLUMN_NAME], errors='coerce')
    df[LONGITUDE_COLUMN_NAME] = pd.to_numeric(df[LONGITUDE_COLUMN_NAME], errors='coerce')

    print("\nIniciando processo de geocodificação dos endereços...")
    for index, row in df.iterrows():
        endereco_atual = row[ADDRESS_COLUMN_NAME]
        # CNPJ é lido mas não usado para geocodificação, será incluído na saída
        # cnpj_atual = row[CNPJ_COLUMN_NAME]

        if pd.isna(endereco_atual) or str(endereco_atual).strip() == "":
            print(f"⏩ Endereço vazio ou NaN na linha {index + 2}. Pulando geocodificação.")
            # As colunas de lat/lon para esta linha permanecerão como pd.NA ou o valor original
            continue

        print(f"\n🔎 Processando Endereço ({index + 1}/{len(df)}): '{endereco_atual}'")

        lat, lon = obter_coordenadas_mapbox_por_endereco(endereco_atual, MAPBOX_ACCESS_TOKEN)

        if lat is not None and lon is not None:
            df.loc[index, LATITUDE_COLUMN_NAME] = lat
            df.loc[index, LONGITUDE_COLUMN_NAME] = lon
            print(f"✅ Coordenadas para Endereço '{endereco_atual}': Latitude={lat}, Longitude={lon}")
        else:
            print(f"⚠️ Não foi possível obter coordenadas para o Endereço '{endereco_atual}'.")

        # time.sleep(0.05) # Pausa opcional para evitar limites de taxa da API

    # Preparar o DataFrame de saída apenas com as colunas solicitadas
    print("\nPreparando arquivo de saída...")
    if CNPJ_COLUMN_NAME in df.columns and LATITUDE_COLUMN_NAME in df.columns and LONGITUDE_COLUMN_NAME in df.columns:
        df_output = df[[CNPJ_COLUMN_NAME, LATITUDE_COLUMN_NAME, LONGITUDE_COLUMN_NAME]]

        try:
            df_output.to_csv(OUTPUT_CSV_FILE, index=False, encoding='utf-8')
            print(
                f"\n🎉 Processamento concluído! Arquivo de saída salvo em '{OUTPUT_CSV_FILE}' com as colunas CNPJ, latitude, longitude.")
        except Exception as e:
            print(f"❌ Erro ao salvar o arquivo de saída CSV '{OUTPUT_CSV_FILE}': {e}")
    else:
        print(
            "❌ Erro: Uma ou mais colunas necessárias para o arquivo de saída (CNPJ, latitude, longitude) não estão presentes no DataFrame final.")
        print(f"Colunas disponíveis: {df.columns.tolist()}")


if __name__ == '__main__':
    processar_arquivo_excel_para_cnpj_lat_lon()