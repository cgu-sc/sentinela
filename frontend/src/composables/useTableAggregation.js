import { computed } from 'vue';

/**
 * Agrega totais e percentuais para o footer de uma tabela de forma genérica.
 *
 * @param {Ref<Array>} rowsRef - Ref reativo com as linhas da tabela
 * @param {Object} schema
 * @param {string[]} schema.sums - Campos a somar (ex: ['cnpjs', 'valSemComp'])
 * @param {Array<{field, numerator, denominator}>} [schema.percents] - Percentuais derivados
 *
 * @returns {{ totals: ComputedRef<Object> }} totals com os valores brutos somados e percentuais calculados
 *
 * @example
 * const { totals } = useTableAggregation(filteredData, {
 *   sums: ['cnpjs', 'valSemComp', 'totalMov', 'qtdeSemComp', 'totalQtde'],
 *   percents: [
 *     { field: 'percValSemComp', numerator: 'valSemComp', denominator: 'totalMov' },
 *     { field: 'percQtdeSemComp', numerator: 'qtdeSemComp', denominator: 'totalQtde' },
 *   ],
 * });
 * // totals.value.cnpjs => número bruto, totals.value.percValSemComp => percentual (0-100)
 */
export function useTableAggregation(rowsRef, schema) {
  const totals = computed(() => {
    const rows = rowsRef.value;
    if (!rows || rows.length === 0) return {};

    const result = {};

    for (const field of schema.sums) {
      result[field] = rows.reduce((sum, row) => sum + (row[field] || 0), 0);
    }

    for (const { field, numerator, denominator } of (schema.percents || [])) {
      const num = result[numerator] ?? 0;
      const den = result[denominator] ?? 0;
      result[field] = den > 0 ? (num / den) * 100 : 0;
    }

    return result;
  });

  return { totals };
}
