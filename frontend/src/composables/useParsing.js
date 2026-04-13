/**
 * Funções utilitárias de parsing de dados do domínio Sentinela.
 * Centraliza transformações de strings recorrentes para evitar duplicação.
 */
import { CNPJ_RAIZ_LENGTH } from '@/config/constants';

/**
 * Extrai o nome do município a partir do valor armazenado no filtro.
 * O formato interno é "NomeMunicipio|UF" para garantir unicidade.
 * @param {string} value - Valor do filtro (ex: "Goiânia|GO")
 * @returns {string} Nome do município sem o sufixo UF
 */
export function parseMunicipio(value) {
    if (!value) return '';
    if (typeof value === 'number') return String(value);
    return value.includes('|') ? value.split('|')[0] : value;
}

/**
 * Extrai o CNPJ raiz (primeiros 8 dígitos numéricos) de um CNPJ completo.
 * Usado ao clicar em badges de rede — sempre retorna a raiz para buscar toda a rede.
 * @param {string} cnpj - CNPJ completo, com ou sem formatação
 * @returns {string|null} CNPJ raiz com 8 dígitos, ou null se inválido
 */
export function extractCnpjRaiz(cnpj) {
    return cnpj?.replace(/\D/g, '').slice(0, CNPJ_RAIZ_LENGTH) || null;
}

/**
 * Extrai o valor de filtro CNPJ a partir de uma entrada livre (campo de texto).
 * - ≥ 14 dígitos → retorna CNPJ completo (14 dígitos) → filtro por estabelecimento exato
 * - ≥ 8 dígitos  → retorna raiz (8 dígitos)           → filtro por toda a rede
 * - < 8 dígitos  → retorna null                        → não filtra (digitação incompleta)
 * @param {string} value - Valor digitado pelo usuário, com ou sem formatação
 * @returns {string|null}
 */
export function extractCnpjFilter(value) {
    const digits = value?.replace(/\D/g, '') || '';
    if (digits.length >= 14) return digits.slice(0, 14);
    if (digits.length >= CNPJ_RAIZ_LENGTH) return digits.slice(0, CNPJ_RAIZ_LENGTH);
    return null;
}
