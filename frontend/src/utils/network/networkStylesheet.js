import { NETWORK_NODE_STYLES } from "./networkConstants";

export function buildNetworkStylesheet() {
  const styles = [];
  const deceasedMarker = `url("data:image/svg+xml;utf8,${encodeURIComponent(`
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
      <defs>
        <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%">
          <feDropShadow dx="0" dy="2" stdDeviation="2" flood-color="#020617" flood-opacity="0.7"/>
        </filter>
      </defs>
      <path d="M25 8v31M15 19h21" fill="none" stroke="#f8fafc" stroke-width="7" stroke-linecap="round" filter="url(#shadow)"/>
      <path d="M25 8v31M15 19h21" fill="none" stroke="#64748b" stroke-width="3" stroke-linecap="round"/>
    </svg>
  `)}")`;

  Object.entries(NETWORK_NODE_STYLES).forEach(([type, s]) => {
    styles.push({
      selector: `node[type="${type}"]`,
      style: {
        "background-color": s.bg,
        "border-color": s.border,
        "border-width": 2,
        shape: s.shape,
        width: s.size,
        height: s.shape === "ellipse" ? s.size * 0.78 : s.size * 0.68,
        label: "data(label)",
        "text-valign": "bottom",
        "text-halign": "center",
        "font-size": "12px",
        "font-family": "Inter, system-ui, sans-serif",
        "font-weight": "600",
        color: "#e2e8f0",
        "text-outline-width": 2,
        "text-outline-color": "#0f172a",
        "text-margin-y": 4,
        "transition-property": "opacity, border-width, background-color",
        "transition-duration": "0.2s",
      },
    });
  });

  styles.push({
    selector: 'node[type="PJ_ALVO"]',
    style: {
      "border-width": 5,
      "border-color": "#fca5a5",
      "z-index": 20,
    },
  });

  styles.push({
    selector: "edge",
    style: {
      "curve-style": "bezier",
      width: 1.5,
      "line-color": "#334155",
      "target-arrow-color": "#334155",
      "target-arrow-shape": "triangle",
      "arrow-scale": 0.8,
      label: "data(label)",
      "font-size": "8px",
      color: "#94a3b8",
      "text-outline-width": 1.5,
      "text-outline-color": "#0f172a",
      "text-rotation": "autorotate",
      "transition-property": "opacity, line-color",
      "transition-duration": "0.2s",
    },
  });

  styles.push({
    selector: 'node[type="PJ"]',
    style: {
      "background-color": "#a855f7",
      "border-color": "#d8b4fe",
      shape: "roundrectangle",
      width: 54,
      height: 54 * 0.68,
    },
  });

  styles.push({
    selector: "node.cadunico-pf",
    style: {
      "border-width": 4,
      "border-color": "#f59e0b",
      "border-style": "double",
      "z-index": 11,
    },
  });

  styles.push({
    selector: "node.deceased-pf",
    style: {
      opacity: 0.68,
      "border-width": 4,
      "border-color": "#64748b",
      "border-style": "double",
      "background-blacken": 0.42,
      "background-image": deceasedMarker,
      "background-fit": "none",
      "background-width": "72%",
      "background-height": "72%",
      "background-position-x": "50%",
      "background-position-y": "50%",
      "background-offset-x": 0,
      "background-offset-y": 0,
      "background-opacity": 0.98,
      "text-outline-color": "#1e293b",
      "z-index": 12,
    },
  });

  styles.push({
    selector: 'edge[type="representante"]',
    style: {
      "line-style": "dotted",
      "line-color": "#f59e0b",
      "target-arrow-color": "#f59e0b",
      "font-size": "12px",
      "font-weight": "700",
    },
  });

  styles.push({
    selector: "node.inactive-company",
    style: {
      opacity: 0.35,
      "border-width": 3,
      "border-style": "dashed",
      "border-color": "#ef4444",
    },
  });

  styles.push({
    selector: "edge[!is_ativo]",
    style: {
      "line-style": "dotted",
      "line-color": "#ef4444",
      "target-arrow-color": "#ef4444",
      color: "#fca5a5",
      opacity: 0.65,
    },
  });

  styles.push({
    selector: ".faded",
    style: { opacity: 0.08 },
  });
  styles.push({
    selector: ".highlighted",
    style: { opacity: 1, "border-width": 3 },
  });
  styles.push({
    selector: "node.deceased-pf.highlighted",
    style: { opacity: 0.82, "border-width": 4 },
  });
  styles.push({
    selector: ".entering",
    style: { opacity: 0 },
  });

  return styles;
}
