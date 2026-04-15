"""
check_parquet_schema.py
-----------------------
Utilitário profissional para inspeção de arquivos Parquet do Sentinela.
Permite visualizar colunas, tipos de dados, contagem de registros e amostras.

Uso:
    python src/scripts/check_parquet_schema.py
"""

import sys
import os
import polars as pl
from datetime import datetime

# Adiciona o backend ao path para importar as constantes de path do data_cache
ROOT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT_DIR, 'backend'))

try:
    from data_cache import (
        _PARQUET_PATH,
        _LOCALIDADES_PARQUET_PATH,
        _REDE_PARQUET_PATH,
        _MATRIZ_PARQUET_PATH,
        _FALECIDOS_PARQUET_PATH,
        _CRMS_DETALHADO_PARQUET_PATH,
        _TOP20_CRMS_PARQUET_PATH,
        _DADOS_FARMACIA_PARQUET_PATH
    )
except ImportError:
    print("❌ Erro: Não foi possível importar as definições do backend.")
    sys.exit(1)

# ── Configuração dos Arquivos ──────────────────────────────────────────────────

ARQUIVOS = [
    {"id": 1, "name": "Movimentação Mensal",     "path": _PARQUET_PATH},
    {"id": 2, "name": "Localidades (IBGE)",      "path": _LOCALIDADES_PARQUET_PATH},
    {"id": 3, "name": "Rede de Estabelecimentos","path": _REDE_PARQUET_PATH},
    {"id": 4, "name": "Matriz de Risco",         "path": _MATRIZ_PARQUET_PATH},
    {"id": 5, "name": "Falecidos por Farmácia",  "path": _FALECIDOS_PARQUET_PATH},
    {"id": 6, "name": "Indicador CRM Detalhado", "path": _CRMS_DETALHADO_PARQUET_PATH},
    {"id": 7, "name": "Top 20 CRMs (Médicos)",   "path": _TOP20_CRMS_PARQUET_PATH},
    {"id": 8, "name": "Dados das Farmácias",     "path": _DADOS_FARMACIA_PARQUET_PATH},
]

# ── Funções de Interface ───────────────────────────────────────────────────────

def exibir_menu():
    print("\n" + "═" * 60)
    print("   SENTINELA — INSPEÇÃO DE ARQUIVOS PARQUET (CACHE)")
    print("═" * 60)
    for a in ARQUIVOS:
        status = "✅" if os.path.exists(a["path"]) else "❌"
        print(f"  [{a['id']}] {status} {a['name']:<30}")
    print("-" * 60)
    print("  [0] Sair")
    print("═" * 60)

def inspecionar_arquivo(item: dict):
    path = item["path"]
    nome = item["name"]

    if not os.path.exists(path):
        print(f"\n⚠️  Arquivo não encontrado: {path}")
        return

    try:
        # Configura o Polars para exibir TUDO sem truncar colunas
        pl.Config.set_tbl_cols(-1)
        pl.Config.set_tbl_width_chars(200)
        pl.Config.set_fmt_str_lengths(50)

        df = pl.read_parquet(path)
        
        info = os.stat(path)
        data_mod = datetime.fromtimestamp(info.st_mtime).strftime('%d/%m/%Y %H:%M:%S')
        tamanho_mb = info.st_size / (1024 * 1024)

        print("-" * 60)
        print(f"📄 ARQUIVO: {nome}")
        print(f"📍 PATH:    {path}")
        print(f"📅 MODIFICADO EM: {data_mod}")
        print(f"📦 TAMANHO:      {tamanho_mb:.2f} MB")
        print(f"🔢 REGISTROS:    {len(df):,}")
        print("-" * 60)

        print("\n🛠️  ESQUEMA COMPLETO (ORDEM ALFABÉTICA):")
        schema = df.schema
        sorted_cols = sorted(schema.keys())
        for col in sorted_cols:
            dtype = schema[col]
            print(f"  • {col:<30} | {dtype}")

        print("\n🔍 AMOSTRA DE DADOS (TOP 3):")
        # Se for muito larga, mostra cada registro como um bloco vertical
        if len(df.columns) > 8:
            for i in range(min(3, len(df))):
                print(f"\n--- [ Registro #{i+1} ] ---")
                row_dict = df.row(i, named=True)
                for k, v in row_dict.items():
                    print(f"  {k:<30}: {v}")
        else:
            print(df.head(3))
        
        input("\nPressione ENTER para voltar ao menu...")

    except Exception as e:
        print(f"\n❌ Erro ao ler arquivo: {e}")
        input("\nPressione ENTER para voltar ao menu...")

# ── Loop Principal ─────────────────────────────────────────────────────────────

def main():
    while True:
        exibir_menu()
        opcao = input("\nSelecione um arquivo para inspecionar: ").strip()

        if opcao == '0':
            print("\nEncerrando inspetor.")
            break

        try:
            op_int = int(opcao)
            selecionado = next((a for a in ARQUIVOS if a["id"] == op_int), None)
            
            if selecionado:
                inspecionar_arquivo(selecionado)
            else:
                print("\n⚠️  Opção inválida.")
        except ValueError:
            print("\n⚠️  Digite um número válido.")
        except KeyboardInterrupt:
            print("\n\nEncerrando.")
            break

if __name__ == '__main__':
    main()
