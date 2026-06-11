import { PALETTE, RISK_COLORS } from "@/config/colors";

export const NETWORK_TYPE_LABELS = {
  PJ_ALVO: { label: "CNPJ em Análise", color: "#ef4444" },
  PF: { label: "Pessoa Física", color: "#0ea5e9" },
  PJ_FARMACIA_POPULAR: { label: "Farmácia Popular", color: "#10b981" },
  PJ_OUTRAS_FARMACIAS: { label: "Farmácia (Não FP)", color: "#f59e0b" },
  PJ_DEMAIS_EMPRESAS: { label: "Outros Segmentos", color: "#a855f7" },
};

export const NETWORK_RISK_BORDER_COLORS = {
  NORMAL: PALETTE.emerald[300],
  ATTENTION: RISK_COLORS.MEDIUM,
  CRITICAL: RISK_COLORS.CRITICAL,
};

export const NETWORK_NODE_STYLES = {
  PJ_ALVO: {
    bg: "#ef4444",
    border: "#fca5a5",
    shape: "roundrectangle",
    size: 85,
  },
  PF: { bg: "#0ea5e9", border: "#38bdf8", shape: "ellipse", size: 52 },
  PJ_FARMACIA_POPULAR: {
    bg: "#10b981",
    border: NETWORK_RISK_BORDER_COLORS.NORMAL,
    shape: "roundrectangle",
    size: 55,
  },
  PJ_OUTRAS_FARMACIAS: {
    bg: "#f59e0b",
    border: "#fbbf24",
    shape: "roundrectangle",
    size: 52,
  },
  PJ_DEMAIS_EMPRESAS: {
    bg: "#a855f7",
    border: "#d8b4fe",
    shape: "roundrectangle",
    size: 52,
  },
  PJ: { bg: "#a855f7", border: "#d8b4fe", shape: "roundrectangle", size: 46 },
  ES: { bg: "#475569", border: "#64748b", shape: "ellipse", size: 52 },
};
