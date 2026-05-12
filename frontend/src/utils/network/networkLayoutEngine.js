const DENSE_GRAPH_NODE_THRESHOLD = 28;
const MAX_DENSE_LAYOUT_SCALE = 2.8;

function getDenseLayoutScale(nodeCount) {
  if (nodeCount <= DENSE_GRAPH_NODE_THRESHOLD) return 1;
  return Math.min(
    MAX_DENSE_LAYOUT_SCALE,
    Math.sqrt(nodeCount / DENSE_GRAPH_NODE_THRESHOLD),
  );
}

function getNodeLabel(node) {
  return node.fullLabel || node.label || node.id;
}

function sortNodes(nodes) {
  return [...nodes].sort((a, b) =>
    String(getNodeLabel(a)).localeCompare(String(getNodeLabel(b)), "pt-BR"),
  );
}

function positionOnEllipse(center, radiusX, radiusY, angle) {
  return {
    x: center.x + Math.cos(angle) * radiusX,
    y: center.y + Math.sin(angle) * radiusY,
  };
}

function circularMeanAngle(angles) {
  if (!angles.length) return 0;
  const sum = angles.reduce(
    (acc, angle) => ({
      x: acc.x + Math.cos(angle),
      y: acc.y + Math.sin(angle),
    }),
    { x: 0, y: 0 },
  );
  return Math.atan2(sum.y, sum.x);
}

function createAdjacency(edges) {
  const adjacency = new Map();
  edges.forEach((edge) => {
    if (!adjacency.has(edge.source)) adjacency.set(edge.source, new Set());
    if (!adjacency.has(edge.target)) adjacency.set(edge.target, new Set());
    adjacency.get(edge.source).add(edge.target);
    adjacency.get(edge.target).add(edge.source);
  });
  return adjacency;
}

export function computeRadialNetworkLayout({ nodes, edges, width, height }) {
  const positions = new Map();
  if (!nodes?.length || !width || !height) return positions;

  const root = nodes.find((node) => node.type === "PJ_ALVO");
  if (!root) return positions;

  const center = { x: width / 2, y: height * 0.54 };
  positions.set(root.id, center);

  const rootId = root.id;
  const nodeById = new Map(nodes.map((node) => [node.id, node]));
  const adjacency = createAdjacency(edges);
  const rootNeighbors = adjacency.get(rootId) || new Set();
  const directPartners = sortNodes(
    Array.from(rootNeighbors)
      .map((nodeId) => nodeById.get(nodeId))
      .filter(Boolean),
  );

  const partnerIds = new Set(directPartners.map((node) => node.id));
  const partnerAngle = new Map();
  const densityScale = getDenseLayoutScale(nodes.length);
  const innerDensityScale = Math.max(1, Math.sqrt(densityScale));
  const innerRadiusX =
    Math.max(230, Math.min(width * 0.24, 380)) * innerDensityScale;
  const innerRadiusY =
    Math.max(120, Math.min(height * 0.24, 190)) * innerDensityScale;

  directPartners.forEach((node, index) => {
    const angle =
      -Math.PI / 2 + (Math.PI * 2 * index) / Math.max(directPartners.length, 1);
    partnerAngle.set(node.id, angle);
    positions.set(node.id, positionOnEllipse(center, innerRadiusX, innerRadiusY, angle));
  });

  const outerNodes = sortNodes(
    nodes.filter((node) => node.id !== rootId && !partnerIds.has(node.id)),
  );
  const outerRadiusX =
    Math.max(420, Math.min(width * 0.43, 760)) * densityScale;
  const outerRadiusY =
    Math.max(200, Math.min(height * 0.36, 310)) * densityScale;
  const groupedByAngle = new Map();

  outerNodes.forEach((node, fallbackIndex) => {
    const connectedAngles = Array.from(adjacency.get(node.id) || [])
      .filter((nodeId) => partnerIds.has(nodeId))
      .map((nodeId) => partnerAngle.get(nodeId))
      .filter((angle) => Number.isFinite(angle));
    const baseAngle = connectedAngles.length
      ? circularMeanAngle(connectedAngles)
      : -Math.PI / 2 +
        (Math.PI * 2 * fallbackIndex) / Math.max(outerNodes.length, 1);
    const key = String(Math.round(baseAngle * 100) / 100);
    if (!groupedByAngle.has(key)) groupedByAngle.set(key, []);
    groupedByAngle.get(key).push({ node, baseAngle });
  });

  groupedByAngle.forEach((group) => {
    const spread = Math.min(0.7, Math.max(0.22, group.length * 0.14));
    group.forEach(({ node, baseAngle }, index) => {
      const offset =
        group.length === 1 ? 0 : -spread / 2 + (spread * index) / (group.length - 1);
      positions.set(
        node.id,
        positionOnEllipse(center, outerRadiusX, outerRadiusY, baseAngle + offset),
      );
    });
  });

  return positions;
}
