/**
 * Configuração de UI para Indicadores e KPIs.
 * Permite associar ícones e cores aos IDs retornados pela API.
 */
import { PALETTE, RISK_COLORS } from './colors.js';

export const KPI_CONFIGS = {
  'Total CNPJs':             { icon: 'pi pi-id-card',              color: PALETTE.blue[500]    },
  'VALOR TOTAL DE VENDAS':   { icon: 'pi pi-money-bill',           color: PALETTE.emerald[500] },
  'TOTAL DE MEDICAMENTOS':   { icon: 'pi pi-box',                  color: PALETTE.violet[500]  },
  'VALOR SEM COMPROVAÇÃO':   { icon: 'pi pi-exclamation-triangle', color: RISK_COLORS.HIGH     },
  '% SEM COMPROVAÇÃO':       { icon: 'pi pi-percentage',           color: PALETTE.amber[500]   },
};

/** Fallback para KPIs não mapeados */
export const DEFAULT_KPI_STYLE = {
  icon:  'pi pi-chart-line',
  color: PALETTE.slate[500],
};
