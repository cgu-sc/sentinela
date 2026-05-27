const DENSE_GRAPH_NODE_THRESHOLD = 28;
const MAX_DENSE_LAYOUT_SCALE = 2.8;
const MIN_OUTER_GROUP_GAP_PX = 90;
const OUTER_GROUP_LABEL_FACTOR = 1.15;
const MAX_OUTER_GROUP_SPREAD = Math.PI * 0.85;
const OUTER_GROUP_RADIUS_Y_RATIO = 0.72;
const ANCHORED_FAN_BASE_DISTANCE = 260;
const ANCHORED_FAN_NODE_GAP = 130;
const ANCHORED_FAN_MIN_SPREAD = Math.PI * 0.16;
const ANCHORED_FAN_MAX_SPREAD = Math.PI * 0.78;

export function computeAnchoredFanPosition({
  anchor,
  anchorAngle,
  index,
  count,
  maxSpread = ANCHORED_FAN_MAX_SPREAD,
  minSpread = ANCHORED_FAN_MIN_SPREAD,
}) {
  const safeCount = Math.max(1, count || 1);
  const safeIndex = Math.max(0, Math.min(index || 0, safeCount - 1));
  const effectiveMaxSpread = Math.max(0.08, maxSpread || ANCHORED_FAN_MAX_SPREAD);
  const effectiveMinSpread = Math.min(
    effectiveMaxSpread,
    Math.max(0, minSpread || 0),
  );
  const desiredArcLength =
    (safeCount - 1) * ANCHORED_FAN_NODE_GAP * OUTER_GROUP_LABEL_FACTOR;
  const radius =
    safeCount === 1
      ? ANCHORED_FAN_BASE_DISTANCE
      : Math.max(
          ANCHORED_FAN_BASE_DISTANCE,
          desiredArcLength / effectiveMaxSpread,
        );
  const spread =
    safeCount === 1
      ? 0
      : Math.min(
          effectiveMaxSpread,
          Math.max(effectiveMinSpread, desiredArcLength / radius),
        );
  const offset =
    safeCount === 1 ? 0 : -spread / 2 + (spread * safeIndex) / (safeCount - 1);
  const angle = anchorAngle + offset;

  return {
    x: anchor.x + Math.cos(angle) * radius,
    y: anchor.y + Math.sin(angle) * radius,
  };
}

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
  const partnerPosition = new Map();
  const densityScale = getDenseLayoutScale(nodes.length);
  const innerDensityScale = Math.max(1, Math.sqrt(densityScale));
  const innerRadiusX =
    Math.max(230, Math.min(width * 0.24, 380)) * innerDensityScale;
  const innerRadiusY =
    Math.max(120, Math.min(height * 0.24, 190)) * innerDensityScale;

  directPartners.forEach((node, index) => {
    const angle =
      -Math.PI / 2 + (Math.PI * 2 * index) / Math.max(directPartners.length, 1);
    const position = positionOnEllipse(center, innerRadiusX, innerRadiusY, angle);
    partnerAngle.set(node.id, angle);
    partnerPosition.set(node.id, position);
    positions.set(node.id, position);
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
    const connectedPartnerIds = Array.from(adjacency.get(node.id) || [])
      .filter((nodeId) => partnerIds.has(nodeId))
      .sort((a, b) =>
        String(getNodeLabel(nodeById.get(a) || { id: a })).localeCompare(
          String(getNodeLabel(nodeById.get(b) || { id: b })),
          "pt-BR",
        ),
      );
    const connectedAngles = connectedPartnerIds
      .map((nodeId) => partnerAngle.get(nodeId))
      .filter((angle) => Number.isFinite(angle));
    const baseAngle = connectedAngles.length
      ? circularMeanAngle(connectedAngles)
      : -Math.PI / 2 +
        (Math.PI * 2 * fallbackIndex) / Math.max(outerNodes.length, 1);
    const primaryPartnerId = connectedPartnerIds[0] || null;
    const key = primaryPartnerId || String(Math.round(baseAngle * 100) / 100);
    if (!groupedByAngle.has(key)) groupedByAngle.set(key, []);
    groupedByAngle.get(key).push({ node, baseAngle, primaryPartnerId });
  });

  groupedByAngle.forEach((group) => {
    const primaryPartnerId = group.find((item) => item.primaryPartnerId)?.primaryPartnerId;
    const anchor = primaryPartnerId ? partnerPosition.get(primaryPartnerId) : null;
    const anchorAngle = primaryPartnerId ? partnerAngle.get(primaryPartnerId) : null;

    if (anchor && Number.isFinite(anchorAngle)) {
      group.forEach(({ node }, index) => {
        positions.set(
          node.id,
          computeAnchoredFanPosition({
            anchor,
            anchorAngle,
            index,
            count: group.length,
          }),
        );
      });
      return;
    }

    const desiredArcLength =
      (group.length - 1) * MIN_OUTER_GROUP_GAP_PX * OUTER_GROUP_LABEL_FACTOR;
    const minRadiusForGap = desiredArcLength / MAX_OUTER_GROUP_SPREAD;
    const groupRadiusScale =
      1 + Math.min(0.45, Math.max(0, group.length - 6) * 0.04);
    const groupRadiusX = Math.max(outerRadiusX * groupRadiusScale, minRadiusForGap);
    const groupRadiusY = Math.max(
      outerRadiusY * groupRadiusScale,
      minRadiusForGap * OUTER_GROUP_RADIUS_Y_RATIO,
    );
    const referenceRadius = Math.max(1, Math.min(groupRadiusX, groupRadiusY));
    const neededArc = desiredArcLength / referenceRadius;
    const spread = Math.min(
      MAX_OUTER_GROUP_SPREAD,
      Math.max(0.35, neededArc),
    );

    group.forEach(({ node, baseAngle }, index) => {
      const offset =
        group.length === 1 ? 0 : -spread / 2 + (spread * index) / (group.length - 1);
      positions.set(
        node.id,
        positionOnEllipse(center, groupRadiusX, groupRadiusY, baseAngle + offset),
      );
    });
  });

  return positions;
}
