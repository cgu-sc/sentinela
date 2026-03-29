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
    return value.includes('|') ? value.split('|')[0] : value;
}

/**
 * Extrai o CNPJ raiz (primeiros 8 dígitos numéricos) de um CNPJ completo.
 * Remove formatação (pontos, barras, hífens) antes de extrair.
 * @param {string} cnpj - CNPJ completo, com ou sem formatação
 * @returns {string|null} CNPJ raiz com 8 dígitos, ou null se inválido
 */
export function extractCnpjRaiz(cnpj) {
    return cnpj?.replace(/\D/g, '').slice(0, CNPJ_RAIZ_LENGTH) || null;
}
