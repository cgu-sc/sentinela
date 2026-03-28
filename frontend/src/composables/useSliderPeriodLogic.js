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

  // ── Multi-seleção de anos (intervalo contíguo) ────────────────────────────
  const selectedYears = ref(new Set());

  const applyYearSelection = (s) => {
    const minYear  = Math.min(...s);
    const maxYear  = Math.max(...s);
    const startIdx = availableMonths.findIndex(
      m => m.date.getFullYear() === minYear && m.date.getMonth() === (minYear === 2015 ? 6 : 0)
    );
    const endIdx = availableMonths.findLastIndex(m => m.date.getFullYear() === maxYear);
    timeSliderValue.value = [
      startIdx === -1 ? 0 : startIdx,
      endIdx   === -1 ? availableMonths.length - 1 : endIdx,
    ];
    applySliderPeriod(timeSliderValue.value);
  };

  const toggleYear = (year) => {
    const s = new Set(selectedYears.value);
    if (s.size === 0) {
      s.add(year);
    } else {
      const minY = Math.min(...s);
      const maxY = Math.max(...s);
      if (year === minY || year === maxY) {
        s.delete(year);
        if (s.size === 0) { selectedYears.value = s; return; }
      } else if (year === minY - 1 || year === maxY + 1) {
        s.add(year);
      } else {
        return;
      }
    }
    selectedYears.value = s;
    applyYearSelection(s);
  };

  const isYearActive   = (year) => selectedYears.value.has(year);
  const isYearDisabled = (year) => {
    const s = selectedYears.value;
    if (s.size === 0) return false;
    const minY = Math.min(...s);
    const maxY = Math.max(...s);
    return !(year === minY || year === maxY || year === minY - 1 || year === maxY + 1);
  };

  const resetYears = () => { selectedYears.value = new Set(); };

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
    selectedYears,
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
