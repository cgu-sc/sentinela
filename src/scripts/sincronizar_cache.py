"""
sincronizar_cache.py
--------------------
Script interativo para sincronizar módulos do cache Sentinela com o CGUData.
Permite escolher exatamente quais módulos atualizar, sem precisar rodar tudo.

Uso:
    python src/scripts/sincronizar_cache.py

Dependências:
    pip install sqlalchemy pyodbc pandas polars
"""

import sys
import os
import time

# Adiciona o backend ao path para importar data_cache e database
ROOT_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(ROOT_DIR, 'backend'))

from database import engine
from data_cache import (
    _sync_localidades,
    _sync_rede,
    _sync_matriz_risco,
    _sync_falecidos,
    _sync_crms_detalhado,
    _sync_top20_crms,
    _sync_dados_farmacia,
    _sync_movimentacao,
)

# ── Módulos disponíveis ────────────────────────────────────────────────────────

MODULOS = [
    {"id": 1, "name": "Localidades (IBGE)",      "func": _sync_localidades,    "peso": "~rápido"},
    {"id": 2, "name": "Rede de Estabelecimentos","func": _sync_rede,           "peso": "~rápido"},
    {"id": 3, "name": "Matriz de Risco",         "func": _sync_matriz_risco,   "peso": "~médio"},
    {"id": 4, "name": "Falecidos por Farmácia",  "func": _sync_falecidos,      "peso": "~médio"},
    {"id": 5, "name": "Indicador CRM Detalhado", "func": _sync_crms_detalhado, "peso": "~médio"},
    {"id": 6, "name": "Top 20 CRMs (Médicos)",   "func": _sync_top20_crms,     "peso": "~pesado"},
    {"id": 7, "name": "Dados das Farmácias",     "func": _sync_dados_farmacia, "peso": "~médio"},
    {"id": 8, "name": "Movimentação Mensal",     "func": _sync_movimentacao,   "peso": "~muito pesado"},
]

# ── Menu ───────────────────────────────────────────────────────────────────────

def exibir_menu():
    print("\n" + "=" * 55)
    print("   SENTINELA — SINCRONIZAÇÃO SELETIVA DE CACHE")
    print("=" * 55)
    for m in MODULOS:
        print(f"  [{m['id']}] {m['name']:<25} {m['peso']}")
    print("-" * 55)
    print("  [0] Sincronizar TODOS os módulos")
    print("=" * 55)

def selecionar_modulos() -> list[dict]:
    exibir_menu()
    entrada = input("\nDigite os números separados por vírgula (ex: 1,3,7): ").strip()

    if entrada == '0':
        return MODULOS

    ids_validos = {m["id"] for m in MODULOS}
    selecionados = []
    erros = []

    for parte in entrada.split(','):
        parte = parte.strip()
        if not parte:
            continue
        try:
            num = int(parte)
            if num in ids_validos:
                selecionados.append(next(m for m in MODULOS if m["id"] == num))
            else:
                erros.append(parte)
        except ValueError:
            erros.append(parte)

    if erros:
        print(f"\n⚠️  Opções ignoradas (inválidas): {', '.join(erros)}")

    # Mantém a ordem original dos módulos
    ordem = {m["id"]: i for i, m in enumerate(MODULOS)}
    return sorted(selecionados, key=lambda m: ordem[m["id"]])

# ── Execução ───────────────────────────────────────────────────────────────────

def confirmar(selecionados: list[dict]) -> bool:
    print("\nMódulos selecionados para sincronização:")
    for m in selecionados:
        print(f"  • {m['name']}")
    resposta = input("\nConfirmar? [S/n]: ").strip().lower()
    return resposta in ('', 's', 'sim', 'y', 'yes')

def progresso_console(nome: str, p: int):
    barra = int(p / 5)
    print(f"\r  {'█' * barra}{'░' * (20 - barra)} {p:>3}%  {nome}", end='', flush=True)

def executar(selecionados: list[dict]):
    total = len(selecionados)
    print(f"\n🚀 Iniciando sincronização de {total} módulo(s)...\n")
    t_inicio = time.perf_counter()

    for i, modulo in enumerate(selecionados, 1):
        nome = modulo["name"]
        print(f"[{i}/{total}] {nome}")

        def callback(p, _nome=nome):
            progresso_console(_nome, p)

        t0 = time.perf_counter()
        try:
            modulo["func"](engine, callback)
            elapsed = time.perf_counter() - t0
            print(f"\r  ✅ {nome:<25} concluído em {elapsed:.1f}s")
        except Exception as e:
            print(f"\r  ❌ {nome:<25} ERRO: {e}")

    total_elapsed = time.perf_counter() - t_inicio
    print(f"\n{'=' * 55}")
    print(f"  Sincronização concluída em {total_elapsed:.1f}s")
    print(f"{'=' * 55}\n")

# ── Main ───────────────────────────────────────────────────────────────────────

def main():
    try:
        selecionados = selecionar_modulos()

        if not selecionados:
            print("\n⚠️  Nenhum módulo selecionado. Encerrando.")
            return

        if not confirmar(selecionados):
            print("\n⛔ Operação cancelada.")
            return

        executar(selecionados)

    except KeyboardInterrupt:
        print("\n\n⛔ Interrompido pelo usuário.")


if __name__ == '__main__':
    main()
