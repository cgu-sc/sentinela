export function useFormatting() {
  /**
   * Formatação monetária compacta padrão Sentinela.
   * Ex: 1.500.000.000 -> R$ 1,5B | 927.000.000 -> R$ 927M | 1.500 -> 1K
   * @param {number} val - Valor financeiro bruto
   */
  const formatBRL = (val) => {
    if (val >= 1000000000) return `R$ ${(val / 1000000000).toFixed(1).replace('.', ',')}B`;
    if (val >= 1000000) return `R$ ${(val / 1000000).toFixed(1).replace('.', ',')}M`;
    if (val >= 1000) return `R$ ${Math.floor(val / 1000)}K`;
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

  /**
   * Formatação numérica completa para quantidades sem abreviações (ex: 18.522)
   * @param {number} val - Quantidade bruta
   */
  const formatNumberFull = (val) => {
    return new Intl.NumberFormat('pt-BR').format(val);
  };

  /**
   * Converte uma Date para string YYYY-MM-DD sem shift de timezone.
   * @param {Date} date
   * @returns {string|null}
   */
  const toLocalISO = (date) => {
    if (!date || !(date instanceof Date)) return null;
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  };

  /**
   * Formatar data do formato YYYY-MM-DD para DD/MM/YYYY
   * @param {string} dataStr 
   * @returns {string}
   */
  const formatarData = (dataStr) => {
    if (!dataStr) return '—';
    const partes = dataStr.toString().split('-');
    if (partes.length !== 3) return dataStr; // Retorna original se não for o formato esperado
    return `${partes[2]}/${partes[1]}/${partes[0]}`;
  };

  return {
    formatBRL,
    formatNumber,
    formatNumberFull,
    formatPercent,
    formatCurrencyFull,
    toLocalISO,
    formatarData
  };
}
