import polars as pl
import os
import sys

def format_size(size_bytes):
    if size_bytes < 0: return "-" + format_size(abs(size_bytes))
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size_bytes < 1024: return f"{size_bytes:.2f} {unit}"
        size_bytes /= 1024
    return f"{size_bytes:.2f} TB"

def run_comparison(new_path, old_path, label):
    print("\n" + "="*80)
    print(f"COMPARANDO: {label}")
    print("="*80)
    
    if not os.path.exists(new_path):
        print(f"ERRO: Arquivo NOVO nao encontrado: {new_path}")
        return
    if not os.path.exists(old_path):
        print(f"ERRO: Arquivo ANTIGO nao encontrado: {old_path}")
        return

    # Tamanho em disco
    s_old = os.path.getsize(old_path)
    s_new = os.path.getsize(new_path)
    diff_s = s_new - s_old
    pct_s = (s_new/s_old - 1) * 100 if s_old > 0 else 0
    
    print(f"TAMANHO EM DISCO:")
    print(f"   - Antigo: {format_size(s_old)}")
    print(f"   - Novo:   {format_size(s_new)}")
    print(f"   - Reducao: {format_size(abs(diff_s))} ({pct_s:+.1f}%)")

    # Carregar Dados
    df_old = pl.read_parquet(old_path)
    df_new = pl.read_parquet(new_path)
    
    l_old = len(df_old)
    l_new = len(df_new)
    
    print(f"\nCONTAGEM DE LINHAS:")
    print(f"   - Antigo: {l_old:,}")
    print(f"   - Novo:   {l_new:,}")
    print(f"   - Diferenca: {l_new - l_old:+,} linhas")
    
    print(f"\nCOLUNAS NO NOVO:")
    print(f"   {df_new.columns}")
    
    print(f"\nCOLUNAS NO ANTIGO:")
    print(f"   {df_old.columns}")

if __name__ == "__main__":
    cache_dir = r"d:\sentinela\sentinela_cache"
    
    targets = [
        ("bench_crm_br.parquet", "bench_crm_br_old.parquet", "Nacional"),
        ("bench_crm_uf.parquet", "bench_crm_uf_old.parquet", "Estadual"),
        ("bench_crm_regiao.parquet", "bench_crm_regiao_old.parquet", "Regional"),
    ]
    
    for new_f, old_f, label in targets:
        run_comparison(
            os.path.join(cache_dir, new_f),
            os.path.join(cache_dir, old_f),
            label
        )
