export function useFormatting() {
  /**
   * Formatação monetária compacta padrão Sentinela.
   * Ex: 1.500.000.000 -> R$ 1,5B | 927.000.000 -> R$ 927M | 1.500 -> 1K
   * @param {number} val - Valor financeiro bruto
   */
  const formatBRL = (val) => {
    if (val >= 1000000000) return `R$ ${(val / 1000000000).toFixed(1).replace('.', ',')}B`;
    if (val >= 1000000) return `R$ ${(val / 1000000).toFixed(1).replace('.', ',')}M`;
    if (val >= 1000) return `${Math.floor(val / 1000)}K`;
    return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(val);
  };

  /**
   * Formatação numérica compacta para quantidades.
   * @param {number} val - Quantidade bruta
   */
  const formatNumber = (val) => {
    if (val >= 1000000) return `${(val / 1000000).toFixed(1).replace('.', ',')}M`;
    if (val >= 1000) return `${Math.floor(val / 1000)}K`;
    return new Intl.NumberFormat('pt-BR').format(val);
  };

  /**
   * Formatação de percentual padrão brasileiro (vírgula).
   * @param {number} val - Percentual (ex: 15.6)
   */
  const formatPercent = (val) => {
    if (val === undefined || val === null) return '0,00%';
    return val.toFixed(2).replace('.', ',') + '%';
  };

  /**
   * Formatação completa de moeda (sem sufixos K/M/B) para detalhes e tooltips.
   */
  const formatCurrencyFull = (val) => {
    return new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' }).format(val);
  };

  return {
    formatBRL,
    formatNumber,
    formatPercent,
    formatCurrencyFull
  };
}
