/**
 * Constantes de Tempo e Períodos para o Projeto Sentinela.
 * Centralizar aqui facilita a manutenção de datas, módulos e rótulos do sistema.
 */

export const SYSTEM_MODULES = [
    { name: 'Sentinela', value: 'consolidado', icon: 'pi pi-chart-bar' },
    { name: 'Alvos', value: 'alvos', icon: 'pi pi-compass' }
];

export const MONTH_LABELS = ['JAN', 'FEV', 'MAR', 'ABR', 'MAI', 'JUN', 'JUL', 'AGO', 'SET', 'OUT', 'NOV', 'DEZ'];

/**
 * Gera a lista de meses disponíveis para o filtro temporal (2015 a 2024).
 * A auditoria do Farmácia Popular no sistema inicia em Julho de 2015 (índice 6).
 */
const generateAvailableMonths = () => {
    const months = [];
    for (let y = 2015; y <= 2024; y++) {
        const startMonth = (y === 2015) ? 6 : 0;
        for (let m = startMonth; m <= 11; m++) {
            months.push({ 
                label: `${MONTH_LABELS[m]}/${y.toString().slice(-2)}`, 
                date: new Date(y, m, 1) 
            });
        }
    }
    return months;
};

export const AVAILABLE_MONTHS = generateAvailableMonths();

/**
 * Padrões de Filtros Globais para o Dashboard.
 * Centralizar aqui garante consistência entre a Store e a Interface.
 */
/** Anos disponíveis para atalho rápido no filtro de período. */
export const ANALYSIS_YEARS = [2015, 2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024];

/** Valor padrão para filtros de seleção — fonte única para evitar string 'Todos' hardcoded. */
export const FILTER_ALL_VALUE = 'Todos';

export const FILTER_DEFAULTS = {
    UF: FILTER_ALL_VALUE,
    REGIAO: FILTER_ALL_VALUE,
    MUNICIPIO: FILTER_ALL_VALUE,
    SITUACAO: FILTER_ALL_VALUE,
    MS: FILTER_ALL_VALUE,
    PORTE: FILTER_ALL_VALUE,
    GRANDE_REDE: FILTER_ALL_VALUE,
    PERCENTUAL_RANGE: [0, 100],
    VALOR_MIN: 0,
    VALOR_MAX: 1000000,
    CLUSTER: FILTER_ALL_VALUE,
    STATUS: FILTER_ALL_VALUE,
    RFA: FILTER_ALL_VALUE,
    SEARCH: '',
    // Auditoria inicia em Julho de 2015 (Índices e Datas)
    DATE_RANGE: [new Date(2015, 6, 1), new Date(2024, 11, 31)],
    SLIDER_INDEX_RANGE: [0, 113] // Corresponde aos 114 meses de index 0 a 113
};
