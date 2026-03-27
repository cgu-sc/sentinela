/**
 * Configuração de UI para Indicadores e KPIs.
 * Permite associar ícones e cores aos IDs retornados pela API.
 */

export const KPI_CONFIGS = {
  // Exemplo de mapeamento por ID ou Label (dependendo de como o backend retorna)
  'Total CNPJs': {
    icon: 'pi pi-id-card',
    color: '#3b82f6' // Blue
  },
  'Valor Total Movimentado': {
    icon: 'pi pi-money-bill',
    color: '#10b981' // Green
  },
  'Quantidade de Medicamentos': {
    icon: 'pi pi-box',
    color: '#8b5cf6' // Purple
  },
  'Valor sem Comprovação': {
    icon: 'pi pi-exclamation-triangle',
    color: '#ef4444' // Red
  },
  'Quantidade sem Comprovação': {
    icon: 'pi pi-info-circle',
    color: '#f59e0b' // Amber
  }
};

/**
 * Fallback para KPIs não mapeados
 */
export const DEFAULT_KPI_STYLE = {
  icon: 'pi pi-chart-line',
  color: '#64748b'
};
