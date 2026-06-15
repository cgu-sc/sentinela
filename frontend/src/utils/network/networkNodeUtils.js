import { NETWORK_RISK_BORDER_COLORS } from "./networkConstants";

export const normalizeSearchText = (value) =>
  String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");

export function isInactiveCompanyStatus(value) {
  const situacao = normalizeSearchText(value);
  return ["baixad", "inapt", "suspens", "nula", "inativ"].some((status) =>
    situacao.includes(status),
  );
}

export function isCompanyNodeInactive(node) {
  if (!node || node.type === "PF") return false;
  return isInactiveCompanyStatus(node.situacao_rf);
}

export function isTruthyFlag(value) {
  if (typeof value === "string") {
    return ["1", "true", "t", "sim", "yes"].includes(value.trim().toLowerCase());
  }
  return Boolean(value);
}

export function isDeceasedPersonNode(node) {
  return (node?.type || "PF") === "PF" && isTruthyFlag(node?.is_falecido);
}

export function isCadunicoPersonNode(node) {
  return (node?.type || "PF") === "PF" && isTruthyFlag(node?.is_cadunico);
}

export function isEsocialPersonNode(node) {
  return (node?.type || "PF") === "PF" && isTruthyFlag(node?.is_esocial);
}

export function isSeguroDefesoPersonNode(node) {
  return (node?.type || "PF") === "PF" && isTruthyFlag(node?.is_seguro_defeso);
}

export function isParCompanyNode(node) {
  return node?.type !== "PF" && isTruthyFlag(node?.is_par);
}

export function getNodeClasses(node) {
  return [
    isCompanyNodeInactive(node) ? "inactive-company" : "",
    isParCompanyNode(node) ? "par-company" : "",
    isCadunicoPersonNode(node) ? "cadunico-pf" : "",
    isEsocialPersonNode(node) ? "esocial-pf" : "",
    isSeguroDefesoPersonNode(node) ? "seguro-defeso-pf" : "",
    isDeceasedPersonNode(node) ? "deceased-pf" : "",
  ]
    .filter(Boolean)
    .join(" ");
}

export function truncateLabel(text, maxLen) {
  if (!text) return "—";
  return text.length > maxLen ? `${text.slice(0, maxLen)}…` : text;
}

export function getNetworkRiskBorderColor(criticidade) {
  if (criticidade === "CRÍTICO") return NETWORK_RISK_BORDER_COLORS.CRITICAL;
  if (criticidade === "ATENÇÃO") return NETWORK_RISK_BORDER_COLORS.ATTENTION;
  if (criticidade === "NORMAL") return NETWORK_RISK_BORDER_COLORS.NORMAL;
  throw new Error("Criticidade de nao comprovacao invalida na teia.");
}

export function buildNetworkNodeLabel(node, maxLen) {
  const baseLabel = truncateLabel(node?.label, maxLen);
  if (node?.type !== "PJ_FARMACIA_POPULAR") return baseLabel;

  const percentual = Number(node.percentual_nao_comprovacao);
  if (!Number.isFinite(percentual)) {
    throw new Error(
      `Farmacia Popular ${node?.id || ""} sem percentual de nao comprovacao.`,
    );
  }

  const formatted = percentual.toLocaleString("pt-BR", {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  });
  return `${baseLabel}\n${formatted}% não comp.`;
}

export function buildNetworkNodeVisualData(node, maxLen) {
  const isFarmaciaPopular = node?.type === "PJ_FARMACIA_POPULAR";
  return {
    label: buildNetworkNodeLabel(node, maxLen),
    fullLabel: node?.label,
    percentual_nao_comprovacao: node?.percentual_nao_comprovacao,
    criticidade_nao_comprovacao: node?.criticidade_nao_comprovacao,
    conexao_ms: node?.conexao_ms,
    risk_border_color: isFarmaciaPopular
      ? getNetworkRiskBorderColor(node.criticidade_nao_comprovacao)
      : null,
  };
}
