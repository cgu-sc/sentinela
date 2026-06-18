import polars as pl
import os
import sys

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT_DIR, "backend"))

from cache_files import MOVIMENTACAO_PARQUET

def format_size(size_bytes):
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size_bytes < 1024: return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024

def compare_parquets(file_new, file_old):
    print("="*95)
    print(f"🔬 AUDITORIA COMPARATIVA: {file_old} vs {file_new}")
    print("="*95)

    # 1. Tamanho em Disco
    size_old = os.path.getsize(file_old)
    size_new = os.path.getsize(file_new)
    print(f"📦 TAMANHO EM DISCO:")
    print(f"   - Old: {format_size(size_old)}")
    print(f"   - New: {format_size(size_new)}")
    diff_disk = size_new - size_old
    sign = "+" if diff_disk > 0 else ""
    print(f"   - Diferença: {sign}{format_size(diff_disk)} ({((size_new/size_old)-1)*100:+.1f}%)")

    # Carregar dados
    df_old = pl.read_parquet(file_old)
    df_new = pl.read_parquet(file_new)

    # 2. Contagem de Linhas
    len_old = len(df_old)
    len_new = len(df_new)
    print(f"\n🔢 CONTAGEM DE LINHAS:")
    print(f"   - Old: {len_old:,}")
    print(f"   - New: {len_new:,}")
    if len_new != len_old:
        diff_rows = len_new - len_old
        print(f"   - Diferença: {diff_rows:+,} linhas")

    # 3. Tabela Comparativa de Colunas
    print(f"\n📊 COMPARAÇÃO DE COLUNAS (TIPO | MEMÓRIA ESTIMADA):")
    print(f"{'Coluna':<28} | {'Tipo Old':<12} | {'Tipo New':<12} | {'Mem Old':<10} | {'Mem New':<10}")
    print("-" * 95)

    todas_colunas = sorted(list(set(df_old.columns) | set(df_new.columns)))

    for col in todas_colunas:
        # Dados Old
        if col in df_old.columns:
            type_old = str(df_old.schema[col])
            mem_old = df_old[col].to_numpy().nbytes if hasattr(df_old[col].to_numpy(), 'nbytes') else 0
            fmt_mem_old = format_size(mem_old)
        else:
            type_old = "---"
            fmt_mem_old = "---"

        # Dados New
        if col in df_new.columns:
            type_new = str(df_new.schema[col])
            mem_new = df_new[col].to_numpy().nbytes if hasattr(df_new[col].to_numpy(), 'nbytes') else 0
            fmt_mem_new = format_size(mem_new)
        else:
            type_new = "---"
            fmt_mem_new = "---"

        # Highlight se mudou o tipo
        alerta = " ⚠️" if type_old != type_new and type_old != "---" and type_new != "---" else ""
        
        print(f"{col:<28} | {type_old:<12} | {type_new:<12} | {fmt_mem_old:<10} | {fmt_mem_new:<10}{alerta}")

    # 4. Potencial de Categorização (Apenas no New)
    print(f"\n🔤 ANÁLISE DE STRINGS NO ARQUIVO NOVO:")
    for col in df_new.columns:
        if df_new.schema[col] == pl.String:
            unique_count = df_new[col].n_unique()
            print(f"   - {col:<25}: {unique_count:,} valores únicos em {len_new:,} linhas.")

if __name__ == "__main__":
    stem, ext = os.path.splitext(MOVIMENTACAO_PARQUET)
    path_old = f"{stem}_old{ext}"
    path_new = MOVIMENTACAO_PARQUET
    
    if os.path.exists(path_old) and os.path.exists(path_new):
        compare_parquets(path_new, path_old)
    else:
        print("❌ Arquivos não encontrados no diretório atual.")
