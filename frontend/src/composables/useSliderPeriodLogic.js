/**
 * Encapsula toda a lógica do slider de período temporal:
 * - Conversão índice ↔ data
 * - Multi-seleção de anos contíguos
 * - Tooltips flutuantes
 * - Sincronização com filterStore.periodo
 */
import { ref, computed, watch } from 'vue';
import { useFilterStore } from '@/stores/filters';
import { AVAILABLE_MONTHS as availableMonths, ANALYSIS_YEARS } from '@/config/constants';

export function useSliderPeriodLogic() {
  const filterStore = useFilterStore();

  // ── Slider sincronizado com a store ──────────────────────────────────────
  const timeSliderValue = computed({
    get: () => filterStore.sliderValue,
    set: (val) => { filterStore.sliderValue = val; },
  });

  const applySliderPeriod = (indices) => {
    const startDate  = availableMonths[indices[0]].date;
    const rawEndDate = availableMonths[indices[1]].date;
    const endDate    = new Date(rawEndDate.getFullYear(), rawEndDate.getMonth() + 1, 0);
    if (
      filterStore.periodo[0]?.getTime() !== startDate.getTime() ||
      filterStore.periodo[1]?.getTime() !== endDate.getTime()
    ) {
      filterStore.periodo = [startDate, endDate];
    }
  };

  // ── Atalhos de Ano (Seleção Única) ───────────────────────────────────────
  const toggleYear = (year) => {
    const startIdx = availableMonths.findIndex(m => m.date.getFullYear() === year);
    const endIdx   = availableMonths.findLastIndex(m => m.date.getFullYear() === year);
    
    if (startIdx !== -1 && endIdx !== -1) {
      timeSliderValue.value = [startIdx, endIdx];
      applySliderPeriod(timeSliderValue.value);
    }
  };

  const isYearActive = (year) => {
    const [start, end] = timeSliderValue.value;
    const s = availableMonths[start].date;
    const e = availableMonths[end].date;
    
    // Um ano é considerado "ativo" se o range selecionado for EXATAMENTE o ano inteiro
    const isSameYear = s.getFullYear() === year && e.getFullYear() === year;
    const isFullYear = s.getMonth() === (year === 2015 ? 6 : 0) && e.getMonth() === 11;
    
    return isSameYear && isFullYear;
  };

  const isYearDisabled = () => false; 

  const resetYears = () => {
     // Reseta para o período total (Início 2015 até Fim 2024)
     timeSliderValue.value = [0, availableMonths.length - 1];
     applySliderPeriod(timeSliderValue.value);
  };

  // ── Tooltips flutuantes ───────────────────────────────────────────────────
  const startMonthLabel = computed(() => availableMonths[timeSliderValue.value[0]]?.label);
  const endMonthLabel   = computed(() => availableMonths[timeSliderValue.value[1]]?.label);
  const startPos        = computed(() => (timeSliderValue.value[0] / (availableMonths.length - 1)) * 100);
  const endPos          = computed(() => (timeSliderValue.value[1] / (availableMonths.length - 1)) * 100);
  const startTransform  = computed(() => startPos.value < 8  ? 'translateX(0%)'    : 'translateX(-50%)');
  const endTransform    = computed(() => endPos.value   > 92 ? 'translateX(-100%)' : 'translateX(-50%)');

  // ── Sincronização reversa: periodo → slider ───────────────────────────────
  watch(() => filterStore.periodo, (newVal) => {
    if (!newVal || newVal.length < 2 || !newVal[0] || !newVal[1]) return;
    const startIdx = availableMonths.findIndex(
      m => m.date.getFullYear() === newVal[0].getFullYear() && m.date.getMonth() === newVal[0].getMonth()
    );
    const endIdx = availableMonths.findIndex(
      m => m.date.getFullYear() === newVal[1].getFullYear() && m.date.getMonth() === newVal[1].getMonth()
    );
    if (startIdx !== -1 && endIdx !== -1) {
      if (startIdx !== timeSliderValue.value[0] || endIdx !== timeSliderValue.value[1]) {
        timeSliderValue.value = [startIdx, endIdx];
      }
    }
  }, { deep: true });

  const isAllSelected = computed(() =>
    timeSliderValue.value[0] === 0 && timeSliderValue.value[1] === availableMonths.length - 1
  );

  return {
    availableMonths,
    ANALYSIS_YEARS,
    timeSliderValue,
    applySliderPeriod,
    toggleYear,
    isYearActive,
    isYearDisabled,
    resetYears,
    startMonthLabel,
    endMonthLabel,
    startPos,
    endPos,
    startTransform,
    endTransform,
    isAllSelected,
  };
}
