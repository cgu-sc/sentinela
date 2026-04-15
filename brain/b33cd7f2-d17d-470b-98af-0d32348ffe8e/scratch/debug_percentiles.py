import polars as pl
import os

path = r'd:\sentinela\sentinela_cache\matriz_risco.parquet'
if not os.path.exists(path):
    print(f"File not found: {path}")
else:
    df = pl.read_parquet(path)
    df = df.rename({c: c.lower() for c in df.columns})
    
    subset = df.select(['cnpj', 'razaosocial', 'score_risco_final', 'pct_auditado']).sort('pct_auditado', descending=True).head(10)
    
    with open(r'd:\sentinela\brain\b33cd7f2-d17d-470b-98af-0d32348ffe8e\scratch\debug_results.txt', 'w', encoding='utf-8') as f:
        f.write("TOP 10 PCT_AUDITADO:\n")
        f.write(str(subset))
        f.write("\n\nSTATISTICS:\n")
        f.write(str(df.select('pct_auditado').describe()))
        pct_cols = [c for c in df.columns if 'pct' in c or 'percent' in c]
        f.write(f"\n\nPERCENTAGE-LIKE COLUMNS: {pct_cols}")
    print("Results saved to debug_results.txt")
