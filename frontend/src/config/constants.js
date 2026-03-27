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
