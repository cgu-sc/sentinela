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

export function isParCompanyNode(node) {
  return node?.type !== "PF" && isTruthyFlag(node?.is_par);
}

export function getNodeClasses(node) {
  return [
    isCompanyNodeInactive(node) ? "inactive-company" : "",
    isParCompanyNode(node) ? "par-company" : "",
    isCadunicoPersonNode(node) ? "cadunico-pf" : "",
    isDeceasedPersonNode(node) ? "deceased-pf" : "",
  ]
    .filter(Boolean)
    .join(" ");
}

export function truncateLabel(text, maxLen) {
  if (!text) return "—";
  return text.length > maxLen ? `${text.slice(0, maxLen)}…` : text;
}
