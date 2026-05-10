<script setup>
import {
  ref,
  computed,
  watch,
  onMounted,
  onBeforeUnmount,
  onActivated,
  nextTick,
} from "vue";
import { storeToRefs } from "pinia";
import { useCnpjDetailStore } from "@/stores/cnpjDetail";
import { useRoute } from "vue-router";
import cytoscape from "cytoscape";
import TabPlaceholder from "./TabPlaceholder.vue";

const route = useRoute();
const cnpj = computed(() => route.params.cnpj);
const cnpjDetailStore = useCnpjDetailStore();
const { networkData, networkLoading, networkError } =
  storeToRefs(cnpjDetailStore);

// ── Cytoscape instance & container ─────────────────────────────────────────
const cyContainer = ref(null);
let cy = null;
let resizeObserver = null;
let currentLayout = null;
let n2PresentationZoom = null;
let n3PresentationZoom = null;
let n4PresentationZoom = null;

// ── Controle de UI ──────────────────────────────────────────────────────────
const selectedNode = ref(null);
const zoom = ref(1);
const copiedKey = ref(null);

const formatCpfCnpj = (v) => {
  if (!v) return "—";
  const clean = v.replace(/\D/g, "");
  if (clean.length === 11)
    return clean.replace(/^(\d{3})(\d{3})(\d{3})(\d{2})$/, "$1.$2.$3-$4");
  if (clean.length === 14)
    return clean.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2})$/, "$1.$2.$3/$4-$5");
  return v;
};

const formatSocietyDate = (value) => {
  if (!value) return "—";
  const dateText = String(value).slice(0, 10);
  const match = dateText.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (match) return `${match[3]}/${match[2]}/${match[1]}`;
  return String(value);
};

const copyAndSignal = (text, key) => {
  if (!text) return;
  navigator.clipboard.writeText(text);
  copiedKey.value = key;
  setTimeout(() => { if (copiedKey.value === key) copiedKey.value = null; }, 2000);
};
const graphReady = ref(false);
const graphCounts = ref({ nodes: 0, edges: 0 });
let graphCountUpdateFrame = null;
const baseTotalNodes = computed(() => networkData.value?.nodes?.length || 0);
const baseTotalEdges = computed(() => networkData.value?.edges?.length || 0);
const totalNodes = computed(() =>
  graphReady.value ? graphCounts.value.nodes : baseTotalNodes.value,
);
const totalEdges = computed(() =>
  graphReady.value ? graphCounts.value.edges : baseTotalEdges.value,
);

// Expansão
const isExpanding = ref(false);
const isBatchExpanding = ref(false);
const expandedNodes = ref(new Set());

// Filtros de visibilidade
const showFiltersMenu = ref(false);
const showLegendMenu = ref(false);
const showLevelHelpMenu = ref(false);
const layersMenuRoot = ref(null);
const legendMenuRoot = ref(null);
const levelHelpMenuRoot = ref(null);
const layerFilters = ref({
  fp: true,
  outrasFarmacias: true,
  outrosSegmentos: true,
  sociosAtuais: true,
  sociosInativos: true,
  representantes: true,
  empresasInativas: true,
});
const hiddenLayerCount = computed(
  () => Object.values(layerFilters.value).filter((isVisible) => !isVisible).length,
);
const networkSearch = ref("");
const searchMatchCount = ref(0);
const hasActiveSearch = computed(() => networkSearch.value.trim().length > 0);
const searchHasNoMatch = computed(
  () => hasActiveSearch.value && searchMatchCount.value === 0,
);

// Nível de profundidade ativo no grafo
const currentLevel = ref("N2");
const loadingLevel = ref(null);

const getLayerFilterSnapshot = () => ({ ...layerFilters.value });

const restoreLayerFilterSnapshot = (snapshot) => {
  layerFilters.value = {
    ...layerFilters.value,
    ...snapshot,
  };
};

function getLayoutBoundingBox() {
  if (!cy || !cyContainer.value) return undefined;

  const width = cyContainer.value.clientWidth || cy.width();
  const height = cyContainer.value.clientHeight || cy.height();
  if (!width || !height) return undefined;

  return {
    x1: -width * 0.15,
    y1: height * 0.04,
    w: width * 1.3,
    h: height * 0.82,
  };
}

// ── Funções de Utilitário para o Grafo ──────────────────────────────────
function sortGraphNodes(nodes) {
  return nodes.sort((a, b) => {
    const labelA = a.data("fullLabel") || a.data("label") || a.id();
    const labelB = b.data("fullLabel") || b.data("label") || b.id();
    return String(labelA).localeCompare(String(labelB), "pt-BR");
  });
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

function rememberN2PresentationZoom() {
  if (!cy || currentLevel.value !== "N2") return;
  n2PresentationZoom = cy.zoom();
}

function rememberPresentationZoom(level) {
  if (!cy) return;
  if (level === "N2") n2PresentationZoom = cy.zoom();
  if (level === "N3") n3PresentationZoom = cy.zoom();
  if (level === "N4") n4PresentationZoom = cy.zoom();
}

function getPresentationZoom(level) {
  const rememberedZoom = {
    N2: n2PresentationZoom,
    N3: n3PresentationZoom,
    N4: n4PresentationZoom,
  }[level];
  return Math.max(1, Math.min(rememberedZoom || 1.08, 1.16));
}

function applyRadialView({
  rememberN2Zoom = false,
  rememberLevel = null,
} = {}) {
  applyN2RadialLayout();
  fitGraphToView(INITIAL_FIT_PADDING);
  if (rememberN2Zoom) {
    rememberN2PresentationZoom();
  }
  if (rememberLevel) {
    rememberPresentationZoom(rememberLevel);
  }
}

function normalizeLayoutScale(level = "N2") {
  if (!cy || !cyContainer.value) return;

  const visibleNodes = cy.nodes(":visible");
  if (visibleNodes.empty()) return;
  const denseTargetZoom = 1 / getDenseLayoutScale(visibleNodes.length);
  const targetZoom = Math.min(getPresentationZoom(level), denseTargetZoom);
  const root = visibleNodes
    .filter((node) => node.data("type") === "PJ_ALVO")
    .first();
  if (!root.length) return;

  const { clientWidth, clientHeight } = cyContainer.value;
  if (!clientWidth || !clientHeight) return;

  const rootPosition = root.position();
  const targetCenter = {
    x: clientWidth / 2,
    y: clientHeight * 0.54,
  };
  const available = {
    left: Math.max(80, (targetCenter.x - INITIAL_FIT_PADDING) / targetZoom),
    right: Math.max(
      80,
      (clientWidth - targetCenter.x - INITIAL_FIT_PADDING) / targetZoom,
    ),
    top: Math.max(80, (targetCenter.y - INITIAL_FIT_PADDING) / targetZoom),
    bottom: Math.max(
      80,
      (clientHeight - targetCenter.y - INITIAL_FIT_PADDING) / targetZoom,
    ),
  };
  const extents = visibleNodes.reduce(
    (acc, node) => {
      const position = node.position();
      const dx = position.x - rootPosition.x;
      const dy = position.y - rootPosition.y;
      return {
        left: Math.max(acc.left, Math.max(0, -dx)),
        right: Math.max(acc.right, Math.max(0, dx)),
        top: Math.max(acc.top, Math.max(0, -dy)),
        bottom: Math.max(acc.bottom, Math.max(0, dy)),
      };
    },
    { left: 0, right: 0, top: 0, bottom: 0 },
  );
  const scale = Math.min(
    1,
    extents.left ? available.left / extents.left : 1,
    extents.right ? available.right / extents.right : 1,
    extents.top ? available.top / extents.top : 1,
    extents.bottom ? available.bottom / extents.bottom : 1,
  );
  if (scale >= 0.98) return;

  visibleNodes.positions((node) => {
    const position = node.position();
    return {
      x: rootPosition.x + (position.x - rootPosition.x) * scale,
      y: rootPosition.y + (position.y - rootPosition.y) * scale,
    };
  });
}

function applyN2RadialLayout() {
  if (!cy || !cyContainer.value) return;

  const width = cyContainer.value.clientWidth || cy.width();
  const height = cyContainer.value.clientHeight || cy.height();
  if (!width || !height) return;

  const visibleNodes = cy.nodes(":visible");
  if (visibleNodes.empty()) return;

  const root = visibleNodes
    .filter((node) => node.data("type") === "PJ_ALVO")
    .first();
  if (!root.length) return;

  const center = { x: width / 2, y: height * 0.54 };
  root.position(center);

  const rootId = root.id();
  const directPartners = sortGraphNodes(
    root
      .connectedEdges(":visible")
      .connectedNodes(":visible")
      .filter((node) => node.id() !== rootId)
      .toArray(),
  );

  const partnerIds = new Set(directPartners.map((node) => node.id()));
  const partnerAngle = new Map();
  const densityScale = getDenseLayoutScale(visibleNodes.length);
  const innerDensityScale = Math.max(1, Math.sqrt(densityScale));
  const innerRadiusX =
    Math.max(230, Math.min(width * 0.24, 380)) * innerDensityScale;
  const innerRadiusY =
    Math.max(120, Math.min(height * 0.24, 190)) * innerDensityScale;

  directPartners.forEach((node, index) => {
    const angle =
      -Math.PI / 2 + (Math.PI * 2 * index) / Math.max(directPartners.length, 1);
    partnerAngle.set(node.id(), angle);
    node.position(positionOnEllipse(center, innerRadiusX, innerRadiusY, angle));
  });

  const outerNodes = sortGraphNodes(
    visibleNodes
      .filter((node) => node.id() !== rootId && !partnerIds.has(node.id()))
      .toArray(),
  );

  const outerRadiusX =
    Math.max(420, Math.min(width * 0.43, 760)) * densityScale;
  const outerRadiusY =
    Math.max(200, Math.min(height * 0.36, 310)) * densityScale;
  const groupedByAngle = new Map();

  outerNodes.forEach((node, fallbackIndex) => {
    const connectedAngles = node
      .connectedEdges(":visible")
      .connectedNodes(":visible")
      .filter((other) => partnerIds.has(other.id()))
      .map((other) => partnerAngle.get(other.id()))
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
        group.length === 1
          ? 0
          : -spread / 2 + (spread * index) / (group.length - 1);
      node.position(
        positionOnEllipse(
          center,
          outerRadiusX,
          outerRadiusY,
          baseAngle + offset,
        ),
      );
    });
  });
}

function runGraphLayout(preset = "base", options = {}) {
  if (!cy) return;

  const {
    hideDuringLayout = false,
    fitAfter = true,
    animationDuration = preset === "expanded" ? 700 : 800,
  } = options;

  if (currentLayout) {
    try {
      currentLayout.stop();
    } catch (e) {}
  }

  const layoutOptions = (() => {
    if (preset === "expanded")
      return {
        nodeRepulsion: () => 8000,
        idealEdgeLength: () => 120,
        gravity: 1.2,
        numIter: 900,
        randomize: true,
      };

    if (preset === "n2")
      return {
        nodeRepulsion: () => 11000,
        idealEdgeLength: () => 96,
        gravity: 1.05,
        numIter: 800,
        randomize: true,
        componentSpacing: 90,
        nodeOverlap: 18,
      };

    if (preset === "n3")
      return {
        nodeRepulsion: () => 9000,
        idealEdgeLength: () => 110,
        gravity: 1.15,
        numIter: 850,
        randomize: true,
        componentSpacing: 95,
        nodeOverlap: 18,
      };

    return {
      nodeRepulsion: () => 8500,
      idealEdgeLength: () => 58,
      gravity: 1.35,
      numIter: 900,
      randomize: true,
    };
  })();

  if (hideDuringLayout && cyContainer.value) {
    cyContainer.value.style.opacity = "0";
  }

  currentLayout = cy.elements(":visible").layout({
    name: "cose",
    animate: true,
    animationDuration,
    fit: false,
    initialTemp: 1000,
    coolingFactor: 0.99,
    minTemp: 1.0,
    boundingBox: getLayoutBoundingBox(),
    ...layoutOptions,
  });

  cy.one("layoutstop", () => {
    if (cyContainer.value) {
      cyContainer.value.style.opacity = "";
      cyContainer.value.style.pointerEvents = "";
    }

    applyVisibilityFilters();
    if (preset === "n2" || preset === "n3") {
      normalizeLayoutScale(preset === "n3" ? "N3" : "N2");
    }
    if (fitAfter && !hasActiveSearch.value) {
      fitGraphToView(INITIAL_FIT_PADDING);
    }
  });

  currentLayout.run();
}

const mergeNetworkData = (newData, options = {}) => {
  if (!cy || !newData) return false;
  const {
    layoutPreset = "expanded",
    hideDuringLayout = true,
    animationDuration = 700,
    rememberLevel = null,
    expansionLevel = rememberLevel,
    placeNewNodesNearAnchors = false,
    fadeInNewElements = false,
  } = options;

  // Evitar duplicados
  const existingNodes = new Set(cy.nodes().map((n) => n.id()));
  const existingEdges = new Set(cy.edges().map((e) => e.id()));

  const newNodes = (newData.nodes || []).filter(
    (n) => !existingNodes.has(n.id),
  );
  const newEdges = (newData.edges || []).filter(
    (e) => !existingEdges.has(e.id),
  );

  const visibleNodesBeforeMerge = cy.nodes(":visible");
  const visibleBox = visibleNodesBeforeMerge.length
    ? visibleNodesBeforeMerge.boundingBox({ includeLabels: false })
    : { x1: 0, x2: cy.width(), y1: 0, y2: cy.height() };
  const graphCenter = {
    x: (visibleBox.x1 + visibleBox.x2) / 2,
    y: (visibleBox.y1 + visibleBox.y2) / 2,
  };
  const anchorByNodeId = new Map();
  if (placeNewNodesNearAnchors) {
    (newData.edges || []).forEach((edge) => {
      if (existingNodes.has(edge.source) && !existingNodes.has(edge.target)) {
        anchorByNodeId.set(edge.target, edge.source);
      }
      if (existingNodes.has(edge.target) && !existingNodes.has(edge.source)) {
        anchorByNodeId.set(edge.source, edge.target);
      }
    });
  }
  const anchorGroups = new Map();
  if (placeNewNodesNearAnchors) {
    newNodes.forEach((node) => {
      const groupKey = anchorByNodeId.get(node.id) || "__center__";
      if (!anchorGroups.has(groupKey)) anchorGroups.set(groupKey, []);
      anchorGroups.get(groupKey).push(node.id);
    });
  }
  const targetPositions = new Map();

  // Adicionar nós
  newNodes.forEach((n, index) => {
    const anchorId = anchorByNodeId.get(n.id);
    const anchor = anchorId ? cy.getElementById(anchorId) : null;
    const groupKey = anchorId || "__center__";
    const group = anchorGroups.get(groupKey) || newNodes.map((node) => node.id);
    const groupIndex = Math.max(0, group.indexOf(n.id));
    const basePosition =
      anchor?.length && !anchor.hidden() ? anchor.position() : graphCenter;
    const baseAngle =
      anchor?.length && !anchor.hidden()
        ? Math.atan2(basePosition.y - graphCenter.y, basePosition.x - graphCenter.x)
        : (Math.PI * 2 * index) / Math.max(newNodes.length, 1);
    const spread = Math.min(Math.PI * 1.05, Math.max(0.32, (group.length - 1) * 0.28));
    const angle =
      group.length <= 1
        ? baseAngle
        : baseAngle - spread / 2 + (spread * groupIndex) / (group.length - 1);
    const targetRadius = Math.min(280, 125 + Math.sqrt(group.length) * 42);
    const startRadius = 28;
    const position = {
      x: basePosition.x + Math.cos(angle) * startRadius,
      y: basePosition.y + Math.sin(angle) * startRadius,
    };
    targetPositions.set(n.id, {
      x: basePosition.x + Math.cos(angle) * targetRadius,
      y: basePosition.y + Math.sin(angle) * targetRadius,
    });

    cy.add({
      group: "nodes",
      classes: [fadeInNewElements ? "entering" : "", getNodeClasses(n)]
        .filter(Boolean)
        .join(" "),
      data: {
        ...n,
        label: truncateLabel(n.label, 20),
        fullLabel: n.label,
        is_expanded_node: true,
        expansion_level: expansionLevel,
      },
      position,
    });
  });

  // Adicionar arestas
  newEdges.forEach((e) => {
    cy.add({
      group: "edges",
      classes: fadeInNewElements ? "entering" : "",
      data: { ...e, expansion_level: expansionLevel },
    });
  });

  applyVisibilityFilters();
  scheduleGraphCountsUpdate();

  if (newNodes.length > 0 || newEdges.length > 0) {
    if (layoutPreset === "anchored") {
      targetPositions.forEach((position, nodeId) => {
        const node = cy.getElementById(nodeId);
        if (!node.length) return;
        if (node.hidden()) {
          node.position(position);
          return;
        }
        node.animate(
          { position },
          { duration: animationDuration, easing: "ease-out-cubic" },
        );
      });
      if (!hasActiveSearch.value) {
        fitGraphToView(INITIAL_FIT_PADDING, {
          animate: true,
          duration: Math.min(650, animationDuration),
        });
        window.setTimeout(() => {
          fitGraphToView(INITIAL_FIT_PADDING, { animate: true, duration: 360 });
          if (rememberLevel) rememberPresentationZoom(rememberLevel);
        }, animationDuration + 40);
      }
    } else if (layoutPreset === "radial") {
      applyRadialView({ rememberLevel });
    } else {
      runGraphLayout(layoutPreset, { hideDuringLayout, animationDuration });
    }

    if (fadeInNewElements) {
      window.setTimeout(() => {
        if (!cy) return;
        cy.elements(".entering").removeClass("entering");
        scheduleGraphCountsUpdate();
      }, 80);
    }
  }

  scheduleGraphCountsUpdate();
  return newNodes.length > 0 || newEdges.length > 0;
};

const wait = (duration) =>
  new Promise((resolve) => window.setTimeout(resolve, duration));

function getBaseGraphIds() {
  return {
    nodeIds: new Set((networkData.value?.nodes || []).map((node) => node.id)),
    edgeIds: new Set((networkData.value?.edges || []).map((edge) => edge.id)),
  };
}

async function getGraphIdsForLevel(level) {
  const ids = getBaseGraphIds();

  if (level === "N2") return ids;

  const dataN3 = await cnpjDetailStore.fetchNetworkLevel(cnpj.value, 3);
  (dataN3?.nodes || []).forEach((node) => ids.nodeIds.add(node.id));
  (dataN3?.edges || []).forEach((edge) => ids.edgeIds.add(edge.id));

  if (level === "N3") return ids;

  const dataN4 = await cnpjDetailStore.fetchNetworkLevel(cnpj.value, 4);
  (dataN4?.nodes || []).forEach((node) => ids.nodeIds.add(node.id));
  (dataN4?.edges || []).forEach((edge) => ids.edgeIds.add(edge.id));

  return ids;
}

function addDataToGraphIds(ids, data) {
  (data?.nodes || []).forEach((node) => ids.nodeIds.add(node.id));
  (data?.edges || []).forEach((edge) => ids.edgeIds.add(edge.id));
  return ids;
}

function getCollapseTargetPosition(node, allowedNodeIds) {
  const allowedNeighbors = node
    .connectedEdges()
    .connectedNodes()
    .filter(
      (neighbor) =>
        allowedNodeIds.has(neighbor.id()) && neighbor.id() !== node.id(),
    );

  if (allowedNeighbors.length) {
    const positionSum = allowedNeighbors.reduce(
      (acc, neighbor) => ({
        x: acc.x + neighbor.position("x"),
        y: acc.y + neighbor.position("y"),
      }),
      { x: 0, y: 0 },
    );
    return {
      x: positionSum.x / allowedNeighbors.length,
      y: positionSum.y / allowedNeighbors.length,
    };
  }

  const root = cy
    ?.nodes('[type="PJ_ALVO"]')
    .first();
  if (root?.length) return root.position();

  return {
    x: cy?.width() ? cy.width() / 2 : 0,
    y: cy?.height() ? cy.height() / 2 : 0,
  };
}

async function collapseToGraphLevel(targetLevel, allowedIds = null) {
  if (!cy || !networkData.value) return false;

  const { nodeIds: allowedNodeIds, edgeIds: allowedEdgeIds } =
    allowedIds || (await getGraphIdsForLevel(targetLevel));
  const nodesToRemove = cy
    .nodes()
    .filter((node) => !allowedNodeIds.has(node.id()));
  const nodeIdsToRemove = new Set(nodesToRemove.map((node) => node.id()));
  const edgesToRemove = cy
    .edges()
    .filter(
      (edge) =>
        !allowedEdgeIds.has(edge.id()) ||
        nodeIdsToRemove.has(edge.source().id()) ||
        nodeIdsToRemove.has(edge.target().id()),
    );
  const elementsToRemove = nodesToRemove.union(edgesToRemove);

  if (elementsToRemove.empty()) return false;

  if (currentLayout) {
    try {
      currentLayout.stop();
    } catch (e) {}
  }

  const collapseDuration = 420;
  cy.elements().stop();
  clearGraphHighlights();

  edgesToRemove.animate(
    { style: { opacity: 0 } },
    { duration: collapseDuration * 0.75, easing: "ease-out-cubic" },
  );

  nodesToRemove.forEach((node) => {
    node.animate(
      {
        position: getCollapseTargetPosition(node, allowedNodeIds),
        style: { opacity: 0 },
      },
      { duration: collapseDuration, easing: "ease-in-out-cubic" },
    );
  });

  await wait(collapseDuration + 40);
  if (!cy) return true;

  elementsToRemove.remove();
  currentLevel.value = targetLevel;
  if (targetLevel === "N2") {
    expandedNodes.value = new Set();
  }
  applyVisibilityFilters();
  scheduleGraphCountsUpdate();

  if (!hasActiveSearch.value) {
    fitGraphToView(INITIAL_FIT_PADDING, { animate: true, duration: 520 });
    await wait(560);
    rememberPresentationZoom(targetLevel);
  }

  return true;
}

const resetToN2 = async () => {
  if (!networkData.value) return;
  if (isBatchExpanding.value) return;
  const preservedLayerFilters = getLayerFilterSnapshot();

  try {
    isBatchExpanding.value = true;
    loadingLevel.value = "N2";
    currentLevel.value = "N2";
    showFiltersMenu.value = false;
    showLegendMenu.value = false;
    showLevelHelpMenu.value = false;
    networkSearch.value = "";
    searchMatchCount.value = 0;
    selectedNode.value = null;
    restoreLayerFilterSnapshot(preservedLayerFilters);

    const collapsed = await collapseToGraphLevel("N2");
    if (!collapsed) {
      await buildGraph(networkData.value);
      restoreLayerFilterSnapshot(preservedLayerFilters);
      applyVisibilityFilters();
      expandedNodes.value = new Set();
    }
  } finally {
    loadingLevel.value = null;
    isBatchExpanding.value = false;
  }
};

function markExpandedNodesFromData(data) {
  (data?.nodes || []).forEach((node) => {
    if (
      [
        "PJ_FARMACIA_POPULAR",
        "PJ_OUTRAS_FARMACIAS",
        "PJ_DEMAIS_EMPRESAS",
        "PJ",
        "PF",
      ].includes(node.type)
    ) {
      expandedNodes.value.add(node.id);
    }
  });
}

function getExpansionRingSizes(nodeCount) {
  if (nodeCount <= 0) return [];
  if (nodeCount <= 8) return [nodeCount];

  const ringCount = Math.ceil(nodeCount / 6);
  const baseSize = Math.floor(nodeCount / ringCount);
  const extra = nodeCount % ringCount;

  return Array.from(
    { length: ringCount },
    (_, index) => baseSize + (index < extra ? 1 : 0),
  );
}

const expandBatch = async (mode) => {
  if (isBatchExpanding.value) return;
  const preservedLayerFilters = getLayerFilterSnapshot();

  try {
    isBatchExpanding.value = true;
    loadingLevel.value = mode;
    showLevelHelpMenu.value = false;
    if (mode === "N3") {
      const dataN3 = await cnpjDetailStore.fetchNetworkLevel(cnpj.value, 3);

      if (currentLevel.value === "N4" && cy) {
        const allowedIds = addDataToGraphIds(getBaseGraphIds(), dataN3);
        await collapseToGraphLevel("N3", allowedIds);
        expandedNodes.value = new Set();
        markExpandedNodesFromData(dataN3);
      } else {
        if (currentLevel.value !== "N2" || !cy) {
          await buildGraph(networkData.value);
          restoreLayerFilterSnapshot(preservedLayerFilters);
        }
        expandedNodes.value = new Set();
        currentLevel.value = "N3";
        if (dataN3)
          mergeNetworkData(dataN3, {
            layoutPreset: "anchored",
            hideDuringLayout: false,
            animationDuration: 900,
            rememberLevel: "N3",
            expansionLevel: "N3",
            placeNewNodesNearAnchors: true,
            fadeInNewElements: true,
          });
        markExpandedNodesFromData(dataN3);
      }
    } else if (mode === "N4") {
      const shouldMergeN3First = !cy || currentLevel.value === "N2";
      // N3 é pré-requisito do N4: carrega os dois em sequência
      if (!cy) {
        await buildGraph(networkData.value);
        restoreLayerFilterSnapshot(preservedLayerFilters);
      }

      currentLevel.value = "N4";
      restoreLayerFilterSnapshot(preservedLayerFilters);

      if (shouldMergeN3First) {
        expandedNodes.value = new Set();
        const dataN3 = await cnpjDetailStore.fetchNetworkLevel(cnpj.value, 3);
        const mergedN3 = mergeNetworkData(dataN3, {
          layoutPreset: "anchored",
          hideDuringLayout: false,
          animationDuration: 760,
          rememberLevel: "N3",
          expansionLevel: "N3",
          placeNewNodesNearAnchors: true,
          fadeInNewElements: true,
        });
        markExpandedNodesFromData(dataN3);
        if (mergedN3) await wait(1180);
      }

      const dataN4 = await cnpjDetailStore.fetchNetworkLevel(cnpj.value, 4);
      if (dataN4)
        mergeNetworkData(dataN4, {
          layoutPreset: "anchored",
          hideDuringLayout: false,
          animationDuration: 900,
          rememberLevel: "N4",
          expansionLevel: "N4",
          placeNewNodesNearAnchors: true,
          fadeInNewElements: true,
        });
      markExpandedNodesFromData(dataN4);
    }

    currentLevel.value = mode;
    restoreLayerFilterSnapshot(preservedLayerFilters);
    applyVisibilityFilters();
  } catch (err) {
    console.error("Erro na expansão em lote:", err);
  } finally {
    isBatchExpanding.value = false;
    loadingLevel.value = null;
  }
};

const hideEdgesTouchingHiddenNodes = () => {
  cy.edges()
    .filter((e) => e.source().style('display') === 'none' || e.target().style('display') === 'none')
    .hide();
};

const readGraphCounts = () =>
  cy
    ? {
        nodes: cy.nodes(":visible").length,
        edges: cy.edges(":visible").length,
      }
    : {
        nodes: networkData.value?.nodes?.length || 0,
        edges: networkData.value?.edges?.length || 0,
      };

const updateGraphCounts = () => {
  graphCounts.value = readGraphCounts();
};

function scheduleGraphCountsUpdate() {
  if (graphCountUpdateFrame) {
    window.cancelAnimationFrame(graphCountUpdateFrame);
  }

  graphCountUpdateFrame = window.requestAnimationFrame(() => {
    graphCountUpdateFrame = null;
    updateGraphCounts();
  });
}

function bindGraphCountUpdates() {
  if (!cy) return;

  cy.off("add remove show hide", scheduleGraphCountsUpdate);
  cy.on("add remove show hide", scheduleGraphCountsUpdate);
}

const normalizeSearchText = (value) =>
  String(value || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]/g, "");

function isInactiveCompanyStatus(value) {
  const situacao = normalizeSearchText(value);
  return [
    "baixad",
    "inapt",
    "suspens",
    "nula",
    "inativ",
  ].some((status) => situacao.includes(status));
}

function isCompanyNodeInactive(node) {
  if (!node || node.type === "PF") return false;
  return isInactiveCompanyStatus(node.situacao_rf || node.situacao);
}

function getNodeClasses(node) {
  return isCompanyNodeInactive(node) ? "inactive-company" : "";
}

const getNodeSearchText = (node) =>
  normalizeSearchText(
    [
      node.id(),
      node.data("fullLabel"),
      node.data("label"),
      node.data("nome_socio"),
      node.data("razao_social"),
      node.data("nome_fantasia"),
    ]
      .filter(Boolean)
      .join(" "),
  );

const getNodePanelName = (node) =>
  node.data("nome_socio") ||
  node.data("nome_fantasia") ||
  node.data("razao_social") ||
  node.data("fullLabel") ||
  node.data("label") ||
  node.id();

const buildSelectedNodePayload = (node) => {
  const selectedId = node.id();
  const societyLinks = node
    .connectedEdges()
    .filter((edge) => edge.data("type") === "socio")
    .map((edge) => {
      const source = edge.source();
      const target = edge.target();
      const other = source.id() === selectedId ? target : source;

      return {
        id: edge.id(),
        label: edge.data("label"),
        is_ativo: edge.data("is_ativo") !== false,
        data_entrada_sociedade: edge.data("data_entrada_sociedade"),
        data_exclusao_sociedade: edge.data("data_exclusao_sociedade"),
        otherId: other.id(),
        otherName: getNodePanelName(other),
        otherType: other.data("type"),
      };
    })
    .sort((a, b) => {
      if (a.is_ativo !== b.is_ativo) return a.is_ativo ? -1 : 1;
      return String(b.data_entrada_sociedade || "").localeCompare(
        String(a.data_entrada_sociedade || ""),
      );
    });

  return {
    ...node.data(),
    societyLinks,
  };
};

const clearGraphHighlights = () => {
  if (!cy) return;
  cy.elements().removeClass("faded highlighted");
};

const applySelectedHighlight = () => {
  if (!cy || !selectedNode.value?.id) return;

  const node = cy.getElementById(selectedNode.value.id);
  if (!node.length || node.hidden()) return;

  const neighborhood = node.closedNeighborhood().filter(":visible");
  cy.elements(":visible").not(neighborhood).addClass("faded");
  neighborhood.addClass("highlighted");
};

const applySearchHighlight = () => {
  if (!cy) return;

  const query = normalizeSearchText(networkSearch.value);
  searchMatchCount.value = 0;
  if (!query) return;

  const visibleNodes = cy.nodes(":visible");
  const matches = visibleNodes.filter((node) =>
    getNodeSearchText(node).includes(query),
  );
  searchMatchCount.value = matches.length;

  if (matches.empty()) {
    cy.elements(":visible").addClass("faded");
    return;
  }

  const connectedEdges = matches.connectedEdges(":visible");
  const focusElements = matches.union(connectedEdges);
  cy.elements(":visible").not(focusElements).addClass("faded");
  focusElements.addClass("highlighted");
};

const applyGraphHighlights = () => {
  if (!cy) return;
  clearGraphHighlights();

  if (hasActiveSearch.value) {
    applySearchHighlight();
    return;
  }

  searchMatchCount.value = 0;
  applySelectedHighlight();
};

const applyVisibilityFilters = () => {
  if (!cy) return;

  cy.batch(() => {
    cy.elements().show();

    if (!layerFilters.value.fp) {
      cy.nodes('[type="PJ_FARMACIA_POPULAR"]').hide();
    }
    if (!layerFilters.value.outrasFarmacias) {
      cy.nodes('[type="PJ_OUTRAS_FARMACIAS"]').hide();
    }
    if (!layerFilters.value.outrosSegmentos) {
      cy.nodes('[type="PJ_DEMAIS_EMPRESAS"], [type="PJ"]').hide();
    }
    if (!layerFilters.value.sociosAtuais) {
      cy.edges()
        .filter(
          (edge) =>
            edge.data("is_ativo") === true &&
            edge.data("type") !== "representante" &&
            (edge.source().data("type") === "PF" ||
              edge.target().data("type") === "PF"),
        )
        .hide();
    }
    if (!layerFilters.value.empresasInativas) {
      cy.nodes(".inactive-company")
        .filter((node) => node.data("type") !== "PJ_ALVO")
        .hide();
    }

    if (!layerFilters.value.sociosInativos) {
      cy.edges()
        .filter(
          (edge) =>
            edge.data("is_ativo") === false &&
            edge.data("type") !== "representante" &&
            (edge.source().data("type") === "PF" ||
              edge.target().data("type") === "PF"),
        )
        .hide();
    }
    if (!layerFilters.value.representantes) {
      cy.edges('[type="representante"]').hide();
    }

    hideEdgesTouchingHiddenNodes();
    cy.nodes('[type != "PJ_ALVO"]')
      .filter((node) => node.connectedEdges().filter(e => e.style('display') !== 'none').length === 0)
      .hide();
    hideEdgesTouchingHiddenNodes();
  });

  if (selectedNode.value?.id) {
    const selected = cy.getElementById(selectedNode.value.id);
    if (!selected.length || selected.hidden()) selectedNode.value = null;
  }

  applyNodeDensitySizing();
  scheduleGraphCountsUpdate();
  applyGraphHighlights();
};

watch(layerFilters, () => {
  applyVisibilityFilters();
}, { deep: true });

const clearNodeSearch = () => {
  networkSearch.value = "";
  selectedNode.value = null;
  clearGraphHighlights();
  searchMatchCount.value = 0;
  fitGraphToView(INITIAL_FIT_PADDING);
};

const closeSelectedNode = () => {
  selectedNode.value = null;
  applyGraphHighlights();
};

const exportPng = () => {
  if (!cy) return;
  const options = {
    bg: "#0f172a",
    full: true,
    scale: 2,
    maxWidth: 2000,
  };
  const pngData = cy.png(options);
  const link = document.createElement("a");
  link.href = pngData;
  link.download = `teia_${cnpj.value}_${new Date().toISOString().slice(0, 10)}.png`;
  link.click();
};

const canExpand = computed(() => {
  if (!selectedNode.value) return false;
  const { type, id } = selectedNode.value;
  // Empresas podem expandir (para N3) exceto a principal (que já vem aberta)
  // Incluímos 'PJ' (tipo genérico para sócios PJ) na lista
  if (
    [
      "PJ_FARMACIA_POPULAR",
      "PJ_OUTRAS_FARMACIAS",
      "PJ_DEMAIS_EMPRESAS",
      "PJ",
    ].includes(type) &&
    id !== cnpj.value
  )
    return true;
  // Pessoas (Sócios) podem expandir (para N4)
  if (type === "PF") return true;
  return false;
});

const expansionLabel = computed(() => {
  if (!selectedNode.value) return "";
  if (expandedNodes.value.has(selectedNode.value.id)) return "Já Expandido";
  if (
    [
      "PJ_FARMACIA_POPULAR",
      "PJ_OUTRAS_FARMACIAS",
      "PJ_DEMAIS_EMPRESAS",
      "PJ",
    ].includes(selectedNode.value.type)
  )
    return "Expandir Sócios (N3)";
  if (selectedNode.value.type === "PF") return "Expandir Empresas (N4)";
  return "Expandir";
});

// ── Paleta de cores por tipo de nó ─────────────────────────────────────────
const NODE_STYLES = {
  PJ_ALVO: {
    bg: "#ef4444",
    border: "#fca5a5",
    shape: "roundrectangle",
    size: 85,
  },
  PF: { bg: "#0ea5e9", border: "#38bdf8", shape: "ellipse", size: 52 },
  PJ_FARMACIA_POPULAR: {
    bg: "#10b981",
    border: "#34d399",
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

function getNodeDensityScale() {
  if (!cy) return 1;

  const visibleCount = cy.nodes(":visible").length;
  if (visibleCount <= 20) return 1;
  if (visibleCount <= 40) return 0.8;
  if (visibleCount <= 80) return 0.7;
  return 0.5;
}

function applyNodeDensitySizing() {
  if (!cy) return;

  const densityScale = getNodeDensityScale();
  cy.nodes().forEach((node) => {
    const type = node.data("type");
    const style = NODE_STYLES[type];
    if (!style) return;
    const nodeScale =
      type === "PJ_ALVO" ? Math.max(0.88, densityScale) : densityScale;
    const size = Math.round(style.size * nodeScale);

    node.style({
      width: size,
      height: style.shape === "ellipse" ? size * 0.78 : size * 0.68,
      "font-size": Math.max(9, Math.round(12 * densityScale)),
      "text-margin-y": Math.max(2, Math.round(4 * densityScale)),
    });
  });
}

const INITIAL_FIT_PADDING = 48;
const REFIT_DELAY_MS = 80;
const DENSE_GRAPH_NODE_THRESHOLD = 28;
const MAX_DENSE_LAYOUT_SCALE = 2.8;

function getDenseLayoutScale(nodeCount) {
  if (nodeCount <= DENSE_GRAPH_NODE_THRESHOLD) return 1;
  return Math.min(
    MAX_DENSE_LAYOUT_SCALE,
    Math.sqrt(nodeCount / DENSE_GRAPH_NODE_THRESHOLD),
  );
}

// ── Inicializa / Destrói o grafo ────────────────────────────────────────────
async function buildGraph(data) {
  if (!cyContainer.value || !data) return;
  observeGraphContainer();

  if (cyContainer.value) cyContainer.value.style.pointerEvents = "none";

  // Para o layout — impede que agende novos RAFs
  if (currentLayout) {
    try {
      currentLayout.stop();
    } catch (e) {}
    currentLayout = null;
  }
  if (cy) {
    try {
      cy.stop();
    } catch (e) {}
    // Drena o RAF pendente antes de destruir: o callback do cose já agendado
    // executa aqui, vê que está parado e encerra — sem acessar _private nulo
    await new Promise((resolve) => requestAnimationFrame(resolve));
    try {
      cy.destroy();
    } catch (e) {}
    cy = null;
    graphReady.value = false;
  }

  const elements = [
    ...data.nodes.map((n) => ({
      classes: getNodeClasses(n),
      data: {
        id: n.id,
        label: truncateLabel(n.label, 22),
        fullLabel: n.label,
        type: n.type,
        municipio: n.municipio,
        uf: n.uf,
        situacao: n.situacao_rf,
        nome_socio: n.nome_socio,
        razao_social: n.razao_social,
        nome_fantasia: n.nome_fantasia,
        id_cnae_principal: n.id_cnae_principal,
      },
    })),
    ...data.edges.map((e) => ({
      data: {
        id: e.id,
        source: e.source,
        target: e.target,
        label: e.label || "",
        type: e.type,
        is_ativo: e.is_ativo,
        data_entrada_sociedade: e.data_entrada_sociedade,
        data_exclusao_sociedade: e.data_exclusao_sociedade,
      },
    })),
  ];

  // Oculta o canvas até o layout terminar — evita flash de nós empilhados em (0,0)
  if (cyContainer.value) cyContainer.value.style.opacity = "0";

  cy = cytoscape({
    container: cyContainer.value,
    elements,
    style: buildStylesheet(),
    layout: { name: "preset" }, // sem auto-layout — controlamos manualmente via currentLayout
    minZoom: 0.18,
    maxZoom: 3,
  });
  graphReady.value = true;
  bindGraphCountUpdates();

  // Força o reconhecimento do tamanho do container
  cy.resize();
  applyVisibilityFilters();
  scheduleGraphCountsUpdate();

  // Layout manual rastreado em currentLayout para poder ser cancelado antes do destroy
  currentLayout = cy.layout({
    name: "cose",
    animate: true,
    animationDuration: 800,
    nodeRepulsion: () => 8500,
    idealEdgeLength: () => 58,
    gravity: 1.35,
    numIter: 900,
    initialTemp: 1000,
    coolingFactor: 0.99,
    minTemp: 1.0,
    boundingBox: getLayoutBoundingBox(),
    fit: false,
    randomize: true,
  });

  cy.one("layoutstop", () => {
    // Revela o grafo e reabilita eventos apenas após o layout terminar
    if (cyContainer.value) {
      cyContainer.value.style.opacity = "";
      cyContainer.value.style.pointerEvents = "";
    }
    if (hasActiveSearch.value) {
      applyGraphHighlights();
    } else {
      applyRadialView({ rememberN2Zoom: true });
    }
  });
  currentLayout.run();

  cy.ready(() => {
    setTimeout(() => {
      if (hasActiveSearch.value) {
        applyGraphHighlights();
      } else {
        applyRadialView({ rememberN2Zoom: true });
      }
    }, REFIT_DELAY_MS);
  });

  // Eventos interativos
  cy.on("tap", "node", (e) => {
    const node = e.target;
    selectedNode.value = buildSelectedNodePayload(node);
    applyGraphHighlights();
  });

  cy.on("tap", (e) => {
    if (e.target === cy) {
      selectedNode.value = null;
      applyGraphHighlights();
    }
  });

  cy.on("zoom", () => {
    zoom.value = Math.round(cy.zoom() * 100);
  });

  zoom.value = 100;
}

// ── Lógica de Expansão (Nível 3) ─────────────────────────────────────────────
async function expandNode(nodeId) {
  if (isExpanding.value || expandedNodes.value.has(nodeId)) return;

  isExpanding.value = true;
  try {
    const expansionData = await cnpjDetailStore.expandNetworkNode(
      cnpj.value,
      nodeId,
    );

    if (
      !expansionData ||
      !expansionData.nodes ||
      expansionData.nodes.length === 0
    ) {
      expandedNodes.value.add(nodeId);
      return;
    }

    const anchorNode = cy.getElementById(nodeId);
    const expansionLevel = anchorNode.data("type") === "PF" ? "N4" : "N3";
    const newElements = [];
    expansionData.nodes.forEach((n) => {
      if (!cy.getElementById(n.id).length) {
        newElements.push({
          group: "nodes",
          classes: getNodeClasses(n),
          data: {
            id: n.id,
            label: truncateLabel(n.label, 20),
            fullLabel: n.label,
            type: n.type || "PF",
            is_expanded_node: true,
            expansion_level: expansionLevel,
            nome_socio: n.nome_socio,
            razao_social: n.razao_social,
            nome_fantasia: n.nome_fantasia,
            id_cnae_principal: n.id_cnae_principal,
            municipio: n.municipio,
            uf: n.uf,
            situacao: n.situacao_rf,
            situacao_rf: n.situacao_rf,
          },
          position: { ...cy.getElementById(nodeId).position() },
        });
      }
    });

    expansionData.edges.forEach((e) => {
      if (!cy.getElementById(e.id).length) {
        newElements.push({
          group: "edges",
          data: {
            id: e.id,
            source: e.source,
            target: e.target,
            label: e.label,
            type: e.type,
            is_ativo: e.is_ativo,
            data_entrada_sociedade: e.data_entrada_sociedade,
            data_exclusao_sociedade: e.data_exclusao_sociedade,
            expansion_level: expansionLevel,
          },
        });
      }
    });

    if (newElements.length > 0) {
      const added = cy.add(newElements);
      if (currentLayout) {
        try {
          currentLayout.stop();
        } catch (e) {}
      }
      currentLayout = null;

      const anchorPosition = anchorNode.position();
      const visibleBox = cy.nodes(":visible").boundingBox({
        includeLabels: false,
      });
      const graphCenter = {
        x: (visibleBox.x1 + visibleBox.x2) / 2,
        y: (visibleBox.y1 + visibleBox.y2) / 2,
      };
      const baseAngle =
        Math.abs(anchorPosition.x - graphCenter.x) +
          Math.abs(anchorPosition.y - graphCenter.y) >
        12
          ? Math.atan2(
              anchorPosition.y - graphCenter.y,
              anchorPosition.x - graphCenter.x,
            )
          : -Math.PI / 2;
      const addedNodes = sortGraphNodes(added.nodes().toArray());
      const addedNodeCount = addedNodes.length;
      const ringSizes = getExpansionRingSizes(addedNodeCount);
      const fanSpread = Math.min(
        Math.PI * 1.65,
        Math.max(Math.PI * 0.55, addedNodeCount * 0.32),
      );
      const baseRadius = Math.min(
        220,
        Math.max(118, 82 + addedNodeCount * 14),
      );
      const ringGap = Math.min(
        130,
        Math.max(72, 48 + addedNodeCount * 7),
      );
      const animationDuration = 620;
      let nodeIndex = 0;

      ringSizes.forEach((ringSize, ring) => {
        const ringSpread =
          ringSizes.length === 1
            ? fanSpread
            : Math.min(
                fanSpread,
                Math.max(Math.PI * 0.5, ringSize * 0.42),
              );
        const radius = baseRadius + ring * ringGap;
        const stagger =
          ring > 0 && ringSize > 1 ? ringSpread / Math.max(ringSize * 2, 2) : 0;

        for (let indexInRing = 0; indexInRing < ringSize; indexInRing += 1) {
          const node = addedNodes[nodeIndex];
          nodeIndex += 1;
          const angle =
            ringSize === 1
              ? baseAngle
              : baseAngle -
                ringSpread / 2 +
                (ringSpread * indexInRing) / Math.max(ringSize - 1, 1) +
                stagger;

          node.animate(
            {
              position: {
                x: anchorPosition.x + Math.cos(angle) * radius,
                y: anchorPosition.y + Math.sin(angle) * radius,
              },
            },
            { duration: animationDuration, easing: "ease-out-cubic" },
          );
        }
      });

      // Destaca vizinhos do nó expandido
      applyVisibilityFilters();
      if (!hasActiveSearch.value) {
        window.setTimeout(() => {
          fitGraphToView(INITIAL_FIT_PADDING, {
            animate: true,
            duration: 420,
          });
        }, 140);
        window.setTimeout(() => {
          fitGraphToView(INITIAL_FIT_PADDING, {
            animate: true,
            duration: 420,
          });
          rememberPresentationZoom(expansionLevel);
        }, animationDuration + 80);
      }
    }
    expandedNodes.value.add(nodeId);
  } catch (error) {
    console.error("Falha na expansão:", error);
  } finally {
    isExpanding.value = false;
  }
}

function fitGraphToView(
  padding = INITIAL_FIT_PADDING,
  { animate = false, duration = 420 } = {},
) {
  if (!cy || !cyContainer.value || cy.elements().empty()) return;

  const { clientWidth, clientHeight } = cyContainer.value;
  if (!clientWidth || !clientHeight) return;

  const visibleElements = cy.elements(":visible");
  if (visibleElements.empty()) return;

  cy.resize();
  if (animate) {
    cy.animate(
      { fit: { eles: visibleElements, padding } },
      {
        duration,
        complete: () => {
          zoom.value = Math.round(cy.zoom() * 100);
        },
      },
    );
    return;
  }
  cy.fit(visibleElements, padding);
  cy.center(visibleElements);
  zoom.value = Math.round(cy.zoom() * 100);
}

function observeGraphContainer() {
  if (!cyContainer.value || resizeObserver) return;

  resizeObserver = new ResizeObserver(() => {
    if (hasActiveSearch.value) {
      applyGraphHighlights();
    } else {
      fitGraphToView(INITIAL_FIT_PADDING);
    }
  });
  resizeObserver.observe(cyContainer.value);
}

function buildStylesheet() {
  const styles = [];

  // Estilo base de nós por tipo
  Object.entries(NODE_STYLES).forEach(([type, s]) => {
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

  // Nó alvo maior
  styles.push({
    selector: 'node[type="PJ_ALVO"]',
    style: {
      "border-width": 5,
      "border-color": "#fca5a5",
      "z-index": 20,
    },
  });

  // Arestas
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

  // Estilo específico para Sócios PJ (para não ficarem sem estilo se vierem como 'PJ')
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

  // Arestas de representante
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

  // Empresas Baixadas/Inativas (Mantém a cor original, mas fica transparente com borda tracejada vermelha)
  styles.push({
    selector: "node.inactive-company",
    style: {
      opacity: 0.35,
      "border-width": 3,
      "border-style": "dashed",
      "border-color": "#ef4444", // Borda vermelha para destacar a inatividade
    },
  });

  // Vínculos Inativos (Ex-sócios)
  styles.push({
    selector: "edge[!is_ativo]",
    style: {
      "line-style": "dotted", // Volta para o pontilhado original (mais sutil)
      "line-color": "#ef4444", // Mas agora em vermelho
      "target-arrow-color": "#ef4444",
      color: "#fca5a5",
      opacity: 0.65, // Mantém a transparência suave
    },
  });

  // Estados: faded / highlighted
  styles.push({
    selector: ".faded",
    style: { opacity: 0.08 },
  });
  styles.push({
    selector: ".highlighted",
    style: { opacity: 1, "border-width": 3 },
  });
  styles.push({
    selector: ".entering",
    style: { opacity: 0 },
  });

  return styles;
}

function truncateLabel(text, maxLen) {
  if (!text) return "—";
  return text.length > maxLen ? text.slice(0, maxLen) + "…" : text;
}

// ── Controles de zoom ───────────────────────────────────────────────────────
function zoomIn() {
  cy?.zoom({
    level: cy.zoom() * 1.25,
    renderedPosition: {
      x: cyContainer.value.clientWidth / 2,
      y: cyContainer.value.clientHeight / 2,
    },
  });
}
function zoomOut() {
  cy?.zoom({
    level: cy.zoom() * 0.8,
    renderedPosition: {
      x: cyContainer.value.clientWidth / 2,
      y: cyContainer.value.clientHeight / 2,
    },
  });
}
function fitGraph() {
  if (hasActiveSearch.value) {
    applyGraphHighlights();
    return;
  }
  fitGraphToView(80);
}
function resetLayout() {
  if (!cy) return;
  if (currentLevel.value === "N2") {
    runGraphLayout("n2", { animationDuration: 650 });
    return;
  }
  if (currentLevel.value === "N3") {
    runGraphLayout("n3", { animationDuration: 650 });
    return;
  }
  runGraphLayout("expanded", { animationDuration: 600 });
}

// ── Watchers ────────────────────────────────────────────────────────────────
watch(
  networkData,
  async (data) => {
    if (isBatchExpanding.value) return;
    if (data) {
      await nextTick();
      await buildGraph(data);
    }
  },
  { immediate: true },
);

watch(networkSearch, () => {
  applyGraphHighlights();
});

function handleFiltersMenuOutsideClick(event) {
  const layersRoot = layersMenuRoot.value;
  if (
    showFiltersMenu.value &&
    layersRoot &&
    !layersRoot.contains(event.target)
  ) {
    showFiltersMenu.value = false;
  }

  const legendRoot = legendMenuRoot.value;
  if (
    showLegendMenu.value &&
    legendRoot &&
    !legendRoot.contains(event.target)
  ) {
    showLegendMenu.value = false;
  }

  const levelHelpRoot = levelHelpMenuRoot.value;
  if (
    showLevelHelpMenu.value &&
    levelHelpRoot &&
    !levelHelpRoot.contains(event.target)
  ) {
    showLevelHelpMenu.value = false;
  }
}

onMounted(async () => {
  document.addEventListener("click", handleFiltersMenuOutsideClick);

  if (!networkData.value) {
    cnpjDetailStore.fetchNetwork(cnpj.value);
  } else {
    await nextTick();
    observeGraphContainer();
    await buildGraph(networkData.value);
  }
});

onBeforeUnmount(() => {
  document.removeEventListener("click", handleFiltersMenuOutsideClick);
  resizeObserver?.disconnect();
  resizeObserver = null;
  if (graphCountUpdateFrame) {
    window.cancelAnimationFrame(graphCountUpdateFrame);
    graphCountUpdateFrame = null;
  }
  cy?.destroy();
  cy = null;
  graphReady.value = false;
  updateGraphCounts();
});

onActivated(() => {
  if (cy) {
    cy.resize();
    if (hasActiveSearch.value) applyGraphHighlights();
  }
});

const typeLabels = {
  PJ_ALVO: { label: "CNPJ em Análise", color: "#ef4444" },
  PF: { label: "Pessoa Física", color: "#0ea5e9" },
  PJ_FARMACIA_POPULAR: { label: "Farmácia Popular", color: "#10b981" },
  PJ_OUTRAS_FARMACIAS: { label: "Farmácia (Não FP)", color: "#f59e0b" },
  PJ_DEMAIS_EMPRESAS: { label: "Outros Segmentos", color: "#a855f7" },
};
</script>

<template>
  <div class="network-tab tab-content">
    <!-- Estados ──────────────────────────────────────────────── -->
    <TabPlaceholder
      v-if="networkLoading"
      variant="loading"
      title="Construindo a Teia Societária"
      description="Mapeando conexões e participações societárias…"
    />
    <TabPlaceholder
      v-else-if="networkError"
      variant="error"
      icon="pi-exclamation-circle"
      title="Erro ao carregar teia"
      :description="networkError"
    />
    <TabPlaceholder
      v-else-if="!networkData || baseTotalNodes === 0"
      icon="pi-share-alt"
      title="Nenhuma conexão encontrada"
      description="Não foram encontrados relacionamentos societários para este estabelecimento."
    />

    <!-- Painel principal ─────────────────────────────────────── -->
    <div v-else class="network-layout animate-fade-in">
      <!-- Cabeçalho ─────────────────────────────────────────── -->
      <!-- Conteúdo principal ────────────────────────────────── -->
      <div class="network-body">
        <!-- Grafo ─────────────────────────────────────────────── -->
        <div class="graph-wrapper">
          <div ref="cyContainer" class="cy-canvas"></div>
          <!-- Toolbar (topo esquerdo) ─────────────────────── -->
          <div class="toolbar-overlay">
            <!-- Pill de profundidade -->
            <div class="toolbar-pill">
              <button
                class="seg-btn"
                :class="{ 'seg-active': currentLevel === 'N2' }"
                @click="resetToN2"
                :disabled="isBatchExpanding"
              >
                <i class="pi pi-refresh" />
                <span>Nível 2</span>
              </button>
              <div class="pill-sep"></div>
              <button
                class="seg-btn"
                :class="{ 'seg-active': currentLevel === 'N3' }"
                @click="expandBatch('N3')"
                :disabled="isBatchExpanding"
              >
                <i
                  :class="
                    loadingLevel === 'N3'
                      ? 'pi pi-spin pi-spinner'
                      : 'pi pi-users'
                  "
                />
                <span>Nível 3</span>
              </button>
              <button
                class="seg-btn"
                :class="{ 'seg-active': currentLevel === 'N4' }"
                @click="expandBatch('N4')"
                :disabled="isBatchExpanding"
              >
                <i
                  :class="
                    loadingLevel === 'N4'
                      ? 'pi pi-spin pi-spinner'
                      : 'pi pi-sitemap'
                  "
                />
                <span>Nível 4</span>
              </button>
              <div class="pill-sep"></div>
              <div ref="levelHelpMenuRoot" class="level-help-menu-root">
                <button
                  class="seg-btn level-help-btn"
                  :class="{ 'seg-active': showLevelHelpMenu }"
                  type="button"
                  aria-label="Ajuda sobre níveis"
                  @click="
                    showLevelHelpMenu = !showLevelHelpMenu;
                    showFiltersMenu = false;
                    showLegendMenu = false;
                  "
                >
                  <i class="pi pi-question-circle" />
                </button>

                <div v-if="showLevelHelpMenu" class="level-help-menu" @click.stop>
                  <div class="level-help-item">
                    <strong>Nível 2</strong>
                    <span>CNPJ em análise, sócios diretos e empresas ligadas a esses sócios.</span>
                  </div>
                  <div class="level-help-item">
                    <strong>Nível 3</strong>
                    <span>Adiciona os sócios das empresas encontradas no nível 2.</span>
                  </div>
                  <div class="level-help-item">
                    <strong>Nível 4</strong>
                    <span>Adiciona empresas ligadas aos sócios encontrados no nível 3.</span>
                  </div>
                </div>
              </div>
            </div>

            <!-- Pill de filtros + export -->
            <div class="toolbar-pill layers-pill">
              <div ref="layersMenuRoot" class="layers-menu-root">
                <button
                  class="filter-btn layer-menu-btn"
                  :class="{ filtering: hiddenLayerCount > 0 || showFiltersMenu }"
                  type="button"
                  @click="
                    showFiltersMenu = !showFiltersMenu;
                    showLegendMenu = false;
                    showLevelHelpMenu = false;
                  "
                  v-tooltip.bottom="'Controle de camadas e filtros'"
                >
                  <i class="pi pi-sliders-h" />
                  <span>Camadas</span>
                  <span v-if="hiddenLayerCount" class="layer-count">{{
                    hiddenLayerCount
                  }}</span>
                  <i
                    :class="
                      showFiltersMenu
                        ? 'pi pi-chevron-up state-icon'
                        : 'pi pi-chevron-down state-icon'
                    "
                  />
                </button>

                <div v-if="showFiltersMenu" class="filters-menu" @click.stop>
                  <div class="filters-section">
                    <div class="filters-section-title">Tipos de Empresa</div>
                    <label class="filter-option" :class="{ muted: !layerFilters.fp }">
                      <input v-model="layerFilters.fp" type="checkbox" />
                      <span>Farmácia Popular</span>
                    </label>
                    <label
                      class="filter-option"
                      :class="{ muted: !layerFilters.outrasFarmacias }"
                    >
                      <input v-model="layerFilters.outrasFarmacias" type="checkbox" />
                      <span>Outras Farmácias</span>
                    </label>
                    <label
                      class="filter-option"
                      :class="{ muted: !layerFilters.outrosSegmentos }"
                    >
                      <input v-model="layerFilters.outrosSegmentos" type="checkbox" />
                      <span>Outros Segmentos</span>
                    </label>
                  </div>

                  <div class="filters-section">
                    <div class="filters-section-title">Pessoas e Vínculos</div>
                    <label
                      class="filter-option"
                      :class="{ muted: !layerFilters.sociosAtuais }"
                    >
                      <input v-model="layerFilters.sociosAtuais" type="checkbox" />
                      <span>Sócios Atuais</span>
                    </label>
                    <label
                      class="filter-option"
                      :class="{ muted: !layerFilters.sociosInativos }"
                    >
                      <input v-model="layerFilters.sociosInativos" type="checkbox" />
                      <span>Sócios Inativos</span>
                    </label>
                    <label
                      class="filter-option"
                      :class="{ muted: !layerFilters.representantes }"
                    >
                      <input v-model="layerFilters.representantes" type="checkbox" />
                      <span>Representantes Legais</span>
                    </label>
                  </div>

                  <div class="filters-section">
                    <div class="filters-section-title">Status Cadastral</div>
                    <label
                      class="filter-option"
                      :class="{ muted: !layerFilters.empresasInativas }"
                    >
                      <input v-model="layerFilters.empresasInativas" type="checkbox" />
                      <span>Empresas Inativas</span>
                    </label>
                  </div>
                </div>
              </div>
              <div class="pill-sep"></div>
              <button
                class="filter-btn icon-only"
                type="button"
                @click="exportPng"
                v-tooltip.bottom="'Exportar PNG'"
              >
                <i class="pi pi-camera" />
              </button>
            </div>
            <!-- Busca de nó -->
            <div
              class="toolbar-pill search-pill"
              :class="{
                searching: hasActiveSearch,
                'no-match': searchHasNoMatch,
              }"
            >
              <i class="pi pi-search search-icon" />
              <input
                v-model="networkSearch"
                class="node-search-input"
                type="text"
                placeholder="Localizar nó"
                aria-label="Localizar nó por CNPJ, CPF ou nome"
                @keydown.esc="clearNodeSearch"
              />
              <span v-if="hasActiveSearch" class="search-count">{{
                searchMatchCount
              }}</span>
              <button
                v-if="hasActiveSearch"
                class="search-clear-btn"
                type="button"
                @click="clearNodeSearch"
                v-tooltip.bottom="'Limpar busca'"
              >
                <i class="pi pi-times" />
              </button>
            </div>

            <div class="toolbar-pill zoom-pill">
              <button class="ctrl-btn" @click="zoomIn" v-tooltip.bottom="'Ampliar'">
                <i class="pi pi-plus" />
              </button>
              <span class="zoom-level">{{ zoom }}%</span>
              <button
                class="ctrl-btn"
                @click="zoomOut"
                v-tooltip.bottom="'Reduzir'"
              >
                <i class="pi pi-minus" />
              </button>
              <div class="pill-sep"></div>
              <button
                class="ctrl-btn"
                @click="fitGraph"
                v-tooltip.bottom="'Ajustar à tela'"
              >
                <i class="pi pi-arrows-alt" />
              </button>
              <button
                class="ctrl-btn"
                @click="resetLayout"
                v-tooltip.bottom="'Reorganizar'"
              >
                <i class="pi pi-sync" />
              </button>
            </div>

            <div class="toolbar-pill legend-pill">
              <div ref="legendMenuRoot" class="legend-menu-root">
                <button
                  class="filter-btn legend-menu-btn"
                  :class="{ filtering: showLegendMenu }"
                  type="button"
                  @click="
                    showLegendMenu = !showLegendMenu;
                    showFiltersMenu = false;
                    showLevelHelpMenu = false;
                  "
                  v-tooltip.bottom="'Legenda do grafo'"
                >
                  <i class="pi pi-info-circle" />
                  <span>Legenda</span>
                  <i
                    :class="
                      showLegendMenu
                        ? 'pi pi-chevron-up state-icon'
                        : 'pi pi-chevron-down state-icon'
                    "
                  />
                </button>

                <div v-if="showLegendMenu" class="legend-menu" @click.stop>
                  <div
                    v-for="(t, key) in typeLabels"
                    :key="key"
                    class="legend-item"
                  >
                    <span
                      class="legend-dot"
                      :style="{ background: t.color }"
                    ></span>
                    <span class="legend-label">{{ t.label }}</span>
                  </div>
                  <div class="legend-item">
                    <span class="legend-line" style="border-top: 2px dotted #f59e0b; width: 14px; margin-right: 6px; background: transparent; height: 0;"></span>
                    <span class="legend-label">Representante</span>
                  </div>
                  <div class="legend-item">
                    <span class="legend-line" style="border-top: 2px dotted #ef4444; width: 14px; margin-right: 6px; background: transparent; height: 0;"></span>
                    <span class="legend-label">Vínculo Inativo</span>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div class="graph-stats-overlay" aria-label="Resumo da rede">
            <div class="stat-item">
              <span class="stat-value">{{ totalNodes }}</span>
              <span class="stat-label">Entidades</span>
            </div>
            <div class="stat-divider"></div>
            <div class="stat-item">
              <span class="stat-value">{{ totalEdges }}</span>
              <span class="stat-label">Vínculos</span>
            </div>
          </div>

          <!-- Controles de Zoom (canto inferior direito) ───── -->
          <div class="graph-controls">
            <button class="ctrl-btn" @click="zoomIn" v-tooltip.left="'Ampliar'">
              <i class="pi pi-plus" />
            </button>
            <span class="zoom-level">{{ zoom }}%</span>
            <button
              class="ctrl-btn"
              @click="zoomOut"
              v-tooltip.left="'Reduzir'"
            >
              <i class="pi pi-minus" />
            </button>
            <div class="ctrl-sep"></div>
            <button
              class="ctrl-btn"
              @click="fitGraph"
              v-tooltip.left="'Ajustar à tela'"
            >
              <i class="pi pi-arrows-alt" />
            </button>
            <button
              class="ctrl-btn"
              @click="resetLayout"
              v-tooltip.left="'Reorganizar'"
            >
              <i class="pi pi-sync" />
            </button>
          </div>

          <!-- Legenda ───────────────────────────────────────── -->
          <div class="graph-legend">
            <div v-for="(t, key) in typeLabels" :key="key" class="legend-item">
              <span class="legend-dot" :style="{ background: t.color }"></span>
              <span class="legend-label">{{ t.label }}</span>
            </div>
            <div class="legend-item">
              <span class="legend-line" style="border-top: 2px dotted #f59e0b; width: 14px; margin-right: 6px; background: transparent; height: 0;"></span>
              <span class="legend-label">Representante</span>
            </div>
            <div class="legend-item">
              <span
                class="legend-line"
                style="
                  border-top: 2px dotted #ef4444;
                  width: 14px;
                  margin-right: 6px;
                "
              ></span>
              <span class="legend-label">Vínculo Inativo</span>
            </div>
          </div>
        </div>

        <!-- Painel de detalhe do nó selecionado ──────────────── -->
        <transition name="slide-in">
          <div v-if="selectedNode" class="node-detail-panel">
            <div class="panel-header">
              <div
                class="panel-type-badge"
                :style="{ background: typeLabels[selectedNode.type]?.color }"
              >
                {{ typeLabels[selectedNode.type]?.label || selectedNode.type }}
              </div>
              <button class="close-btn" @click="closeSelectedNode">
                <i class="pi pi-times" />
              </button>
            </div>
            <div class="panel-names">
              <h3 class="panel-main-name">
                {{
                  selectedNode.nome_socio ||
                  selectedNode.nome_fantasia ||
                  selectedNode.razao_social ||
                  selectedNode.fullLabel
                }}
              </h3>
              <div
                v-if="selectedNode.nome_fantasia && selectedNode.razao_social"
                class="panel-sub-name"
              >
                {{ selectedNode.razao_social }}
              </div>
            </div>
            <div class="panel-id">
              <span class="panel-id-label">{{ selectedNode.id?.replace(/\D/g, '').length === 11 ? 'CPF' : 'CNPJ' }}</span>
              <span class="panel-id-value">{{ formatCpfCnpj(selectedNode.id) }}</span>
              <i
                :class="['pi', copiedKey === selectedNode.id ? 'pi-check' : 'pi-copy', 'copy-btn', copiedKey === selectedNode.id ? 'text-success' : '']"
                v-tooltip.top="'Copiar'"
                @click="copyAndSignal(selectedNode.id, selectedNode.id)"
              />
            </div>
            <div class="panel-fields">
              <div v-if="selectedNode.municipio" class="panel-field mt-1">
                <i class="pi pi-map-marker" />
                <span
                  >{{ selectedNode.municipio }} / {{ selectedNode.uf }}</span
                >
              </div>
              <div v-if="selectedNode.situacao" class="panel-field">
                <i class="pi pi-info-circle" />
                <span>Situação RF: {{ selectedNode.situacao }}</span>
              </div>
            </div>

            <!-- Vínculos societários -->
            <div
              v-if="selectedNode.societyLinks?.length"
              class="panel-relationships"
            >
              <div class="panel-section-title">Vínculos societários</div>
              <div
                v-for="link in selectedNode.societyLinks"
                :key="link.id"
                class="relationship-card"
              >
                <div class="relationship-header">
                  <span class="relationship-name">{{ link.otherName }}</span>
                  <span
                    class="relationship-status"
                    :class="{ inactive: !link.is_ativo }"
                  >
                    {{ link.is_ativo ? "Ativo" : "Inativo" }}
                  </span>
                </div>
                <div class="relationship-meta">
                  <span>{{ formatCpfCnpj(link.otherId) }}</span>
                  <span v-if="link.label">{{ link.label }}</span>
                </div>
                <div class="relationship-dates">
                  <div>
                    <span class="field-label">Entrada</span>
                    <span class="field-value">{{
                      formatSocietyDate(link.data_entrada_sociedade)
                    }}</span>
                  </div>
                  <div>
                    <span class="field-label">Saída</span>
                    <span class="field-value">{{
                      formatSocietyDate(link.data_exclusao_sociedade)
                    }}</span>
                  </div>
                </div>
              </div>
            </div>

            <!-- Ações de Expansão -->
            <div v-if="canExpand" class="panel-actions mt-3">
              <button
                class="expand-btn"
                :disabled="isExpanding || expandedNodes.has(selectedNode.id)"
                @click="expandNode(selectedNode.id)"
              >
                <i
                  :class="
                    isExpanding ? 'pi pi-spin pi-spinner' : 'pi pi-plus-circle'
                  "
                />
                <span>{{ expansionLabel }}</span>
              </button>
            </div>

            <div class="panel-hint">
              <i class="pi pi-mouse" /> Clique no fundo para fechar
            </div>
          </div>
        </transition>
      </div>
    </div>
  </div>
</template>

<style scoped>
.network-tab {
  height: 100%;
  display: flex;
  flex-direction: column;
}

/* Resumo flutuante ─────────────────────────────────── */
.graph-stats-overlay {
  position: absolute;
  top: 1rem;
  right: 1rem;
  z-index: 10;
  display: flex;
  align-items: center;
  gap: 0.9rem;
  padding: 0.45rem 0.65rem;
  background: color-mix(in srgb, var(--card-bg) 88%, transparent);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid var(--tabs-border);
  border-radius: 12px;
  box-shadow: 0 8px 24px -4px rgba(0, 0, 0, 0.45);
  pointer-events: none;
}

.stat-item {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
}

.stat-value {
  font-size: 1rem;
  font-weight: 600;
  color: var(--primary-color);
  line-height: 1;
}

.stat-label {
  font-size: 0.56rem;
  text-transform: uppercase;
  font-weight: 500;
  color: var(--text-muted);
  letter-spacing: 0.04em;
}

.stat-divider {
  width: 1px;
  height: 1.65rem;
  background: var(--tabs-border);
  opacity: 0.5;
}

/* Layout principal ─────────────────────────────────── */
.network-layout {
  display: flex;
  flex-direction: column;
  height: 100%;
  gap: 0;
}

.network-body {
  position: relative;
  display: flex;
  flex: 1;
  gap: 1rem;
  min-height: 520px;
}

/* Canvas do grafo ──────────────────────────────────── */
.graph-wrapper {
  flex: 1;
  position: relative;
  background: var(--bg-secondary);
  border-radius: 12px;
  border: 1px solid var(--tabs-border);
  overflow: hidden;
}

.cy-canvas {
  width: 100%;
  height: 100%;
  min-height: 520px;
}

/* Toolbar Overlay ──────────────────────────────────── */
.toolbar-overlay {
  position: absolute;
  top: 1rem;
  left: 1rem;
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 0.5rem;
  z-index: 10;
  max-width: calc(100% - 12rem);
}

.toolbar-pill {
  display: flex;
  align-items: center;
  gap: 2px;
  background: color-mix(in srgb, var(--card-bg) 88%, transparent);
  backdrop-filter: blur(12px);
  -webkit-backdrop-filter: blur(12px);
  border: 1px solid var(--tabs-border);
  border-radius: 50px;
  padding: 4px 6px;
  box-shadow: 0 8px 24px -4px rgba(0, 0, 0, 0.35);
}

/* Botões de profundidade (segmented control) */
.seg-btn {
  background: transparent;
  border: none;
  color: var(--text-secondary);
  padding: 5px 11px;
  border-radius: 20px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 5px;
  font-size: 0.71rem;
  font-weight: 500;
  transition:
    background 0.18s,
    color 0.18s,
    box-shadow 0.18s;
  white-space: nowrap;
}

.seg-btn:hover:not(:disabled) {
  background: rgba(255, 255, 255, 0.07);
  color: #94a3b8;
}

.seg-btn.seg-active {
  background: var(--primary-color);
  color: #fff;
  box-shadow: 0 2px 10px rgba(99, 102, 241, 0.38);
}

.seg-btn:disabled {
  opacity: 0.38;
  cursor: not-allowed;
}

.level-help-menu-root {
  position: relative;
  display: inline-flex;
}

.level-help-btn {
  width: 28px;
  height: 28px;
  justify-content: center;
  padding: 0;
}

.level-help-menu {
  position: absolute;
  top: calc(100% + 0.55rem);
  left: 0;
  z-index: 40;
  width: 286px;
  display: flex;
  flex-direction: column;
  gap: 0.6rem;
  padding: 0.8rem 0.9rem;
  background: var(--card-bg);
  border: 1px solid var(--tabs-border);
  border-radius: 10px;
  box-shadow:
    0 18px 42px rgba(0, 0, 0, 0.38),
    0 0 0 1px color-mix(in srgb, var(--tabs-border) 34%, transparent);
}

.level-help-item {
  display: grid;
  gap: 0.18rem;
  color: var(--text-secondary);
  font-size: 0.72rem;
  line-height: 1.35;
}

.level-help-item strong {
  color: var(--text-primary);
  font-size: 0.75rem;
  font-weight: 650;
}

/* Botões de filtro */
.filter-btn {
  background: transparent;
  border: none;
  color: var(--text-secondary);
  padding: 5px 10px;
  border-radius: 20px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 0.71rem;
  font-weight: 500;
  transition:
    background 0.18s,
    color 0.18s;
  white-space: nowrap;
}

.filter-btn.icon-only {
  padding: 5px 8px;
}

.filter-btn:hover {
  background: rgba(255, 255, 255, 0.07);
  color: #94a3b8;
}

.filter-btn .state-icon {
  font-size: 0.6rem;
  opacity: 0.55;
}

.filter-btn.filtering {
  color: var(--primary-color);
}

.filter-btn.filtering .state-icon {
  opacity: 1;
}

.layers-pill {
  position: relative;
}

.layers-menu-root {
  position: relative;
  display: inline-flex;
}

.legend-pill {
  position: relative;
}

.legend-menu-root {
  position: relative;
  display: inline-flex;
}

.layer-menu-btn {
  min-width: 104px;
}

.legend-menu-btn {
  min-width: 92px;
}

.layer-count {
  min-width: 1rem;
  height: 1rem;
  padding: 0 0.28rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 999px;
  background: color-mix(in srgb, var(--primary-color) 20%, transparent);
  color: var(--primary-color);
  font-size: 0.58rem;
  font-weight: 700;
  line-height: 1;
}

.filters-menu {
  position: absolute;
  top: calc(100% + 0.55rem);
  left: 0;
  z-index: 40;
  width: 244px;
  padding: 0.45rem;
  background: var(--card-bg);
  border: 1px solid var(--tabs-border);
  border-radius: 10px;
  box-shadow:
    0 18px 42px rgba(0, 0, 0, 0.38),
    0 0 0 1px color-mix(in srgb, var(--tabs-border) 34%, transparent);
}

.legend-menu {
  position: absolute;
  top: calc(100% + 0.55rem);
  left: 0;
  z-index: 40;
  width: 218px;
  display: flex;
  flex-direction: column;
  gap: 0.45rem;
  padding: 0.75rem 0.85rem;
  background: var(--card-bg);
  border: 1px solid var(--tabs-border);
  border-radius: 10px;
  box-shadow:
    0 18px 42px rgba(0, 0, 0, 0.38),
    0 0 0 1px color-mix(in srgb, var(--tabs-border) 34%, transparent);
}

.filters-section {
  padding: 0.45rem 0.35rem;
}

.filters-section + .filters-section {
  border-top: 1px solid color-mix(in srgb, var(--tabs-border) 76%, transparent);
}

.filters-section-title {
  margin-bottom: 0.35rem;
  color: var(--text-muted);
  font-size: 0.58rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  line-height: 1;
  text-transform: uppercase;
}

.filter-option {
  min-height: 1.75rem;
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.25rem 0.3rem;
  border-radius: 6px;
  color: var(--text-secondary);
  cursor: pointer;
  font-size: 0.72rem;
  font-weight: 500;
  transition:
    background 0.18s,
    color 0.18s,
    opacity 0.18s;
}

.filter-option:hover {
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  color: var(--text-color);
}

.filter-option.muted {
  color: var(--text-muted);
  opacity: 0.74;
}

.filter-option input {
  width: 0.95rem;
  height: 0.95rem;
  accent-color: var(--primary-color);
  cursor: pointer;
  flex-shrink: 0;
}

.search-pill {
  gap: 6px;
  min-width: 210px;
  max-width: 280px;
  padding: 4px 8px;
  transition:
    border-color 0.18s,
    box-shadow 0.18s;
}

.search-pill.searching {
  border-color: rgba(56, 189, 248, 0.35);
  box-shadow:
    0 8px 24px -4px rgba(0, 0, 0, 0.45),
    0 0 0 1px rgba(56, 189, 248, 0.1);
}

.search-pill.no-match {
  border-color: rgba(251, 191, 36, 0.45);
}

.search-icon {
  color: #64748b;
  font-size: 0.75rem;
  flex-shrink: 0;
}

.node-search-input {
  width: 100%;
  min-width: 0;
  height: 24px;
  background: transparent;
  border: none;
  outline: none;
  color: #e2e8f0;
  font-size: 0.72rem;
  font-weight: 500;
}

.node-search-input::placeholder {
  color: #64748b;
  opacity: 1;
}

.search-count {
  min-width: 1rem;
  height: 1rem;
  padding: 0 0.28rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border-radius: 999px;
  background: rgba(56, 189, 248, 0.14);
  color: #7dd3fc;
  font-size: 0.6rem;
  font-weight: 700;
  line-height: 1;
}

.search-pill.no-match .search-count {
  background: rgba(251, 191, 36, 0.14);
  color: #fbbf24;
}

.search-clear-btn {
  width: 1.35rem;
  height: 1.35rem;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  border: none;
  border-radius: 999px;
  background: rgba(255, 255, 255, 0.06);
  color: #94a3b8;
  cursor: pointer;
  font-size: 0.58rem;
  flex-shrink: 0;
  transition:
    background 0.18s,
    color 0.18s;
}

.search-clear-btn:hover {
  background: rgba(255, 255, 255, 0.12);
  color: #e2e8f0;
}

.pill-sep {
  width: 1px;
  height: 16px;
  background: rgba(255, 255, 255, 0.1);
  margin: 0 2px;
  flex-shrink: 0;
}

.zoom-pill {
  gap: 3px;
}

.zoom-pill .ctrl-btn {
  width: 1.65rem;
  height: 1.65rem;
}

.zoom-pill .zoom-level {
  width: 2.15rem;
}

/* Controles de Zoom (canto inferior direito) ──────── */
.graph-controls {
  position: absolute;
  bottom: 1.5rem;
  right: 1.5rem;
  z-index: 10;
  display: flex;
  flex-direction: column;
  align-items: center;
  background: color-mix(in srgb, var(--card-bg) 85%, transparent);
  backdrop-filter: blur(10px);
  border: 1px solid var(--tabs-border);
  border-radius: 12px;
  padding: 0.5rem;
  gap: 0.4rem;
  box-shadow: 0 8px 24px -4px rgba(0, 0, 0, 0.35);
}

.graph-controls {
  display: none;
}

.ctrl-btn {
  width: 2rem;
  height: 2rem;
  display: flex;
  align-items: center;
  justify-content: center;
  background: transparent;
  border: none;
  border-radius: 6px;
  color: var(--text-secondary);
  cursor: pointer;
  font-size: 0.75rem;
  transition:
    background 0.2s,
    color 0.2s;
}

.ctrl-btn:hover {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  color: var(--primary-color);
}

.zoom-level {
  font-size: 0.65rem;
  font-weight: 500;
  color: var(--text-muted);
  width: 2rem;
  text-align: center;
}

.ctrl-sep {
  width: 1.5rem;
  height: 1px;
  background: var(--tabs-border);
  opacity: 0.5;
  margin: 0.1rem 0;
}

/* Legenda ──────────────────────────────────────────── */
.graph-legend {
  position: absolute;
  bottom: 1rem;
  left: 1rem;
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
  background: var(--card-bg);
  border: 1px solid var(--tabs-border);
  border-radius: 10px;
  padding: 0.7rem 1rem;
  backdrop-filter: blur(8px);
  z-index: 10;
}

.graph-legend {
  display: none;
}

.legend-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

.legend-dot {
  width: 10px;
  height: 10px;
  border-radius: 50%;
  flex-shrink: 0;
}

.legend-line {
  width: 18px;
  height: 2px;
  background: #f59e0b;
  flex-shrink: 0;
}

.legend-line.dashed {
  background: repeating-linear-gradient(
    to right,
    #f59e0b 0px,
    #f59e0b 4px,
    transparent 4px,
    transparent 8px
  );
}

.legend-label {
  font-size: 0.68rem;
  color: var(--text-secondary);
  font-weight: 600;
}

/* Painel de detalhe ────────────────────────────────── */
.node-detail-panel {
  position: absolute;
  top: 1rem;
  right: 1rem;
  z-index: 1000;
  width: 280px; /* Levemente maior para acomodar melhor os nomes */
  background: color-mix(in srgb, var(--card-bg) 92%, transparent);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  border: 1px solid var(--tabs-border);
  border-radius: 12px;
  padding: 1.25rem;
  display: flex;
  flex-direction: column;
  gap: 0.8rem;
  max-height: calc(100% - 2rem);
  overflow-y: auto;
  box-shadow: 0 8px 32px rgba(0, 0, 0, 0.25);
  pointer-events: auto;
}

.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.panel-type-badge {
  font-size: 0.62rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  color: #fff;
  padding: 0.2rem 0.6rem;
  border-radius: 99px;
}

.close-btn {
  background: transparent;
  border: none;
  color: var(--text-muted);
  cursor: pointer;
  font-size: 0.75rem;
  padding: 0.2rem;
  border-radius: 4px;
  transition: color 0.2s;
}

.close-btn:hover {
  color: var(--text-color);
}

.panel-names {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
}

.panel-main-name {
  margin: 0;
  font-size: 1rem;
  font-weight: 600;
  color: var(--text-color);
  line-height: 1.2;
}

.panel-sub-name {
  font-size: 0.75rem;
  font-weight: 500;
  color: var(--text-muted);
  line-height: 1.3;
  opacity: 0.8;
}

.panel-id {
  font-size: 0.75rem;
  color: var(--text-muted);
  background: var(--bg-secondary);
  border-radius: 6px;
  padding: 0.3rem 0.5rem;
  display: flex;
  align-items: center;
  gap: 0.4rem;
}

.panel-id-label {
  font-size: 0.65rem;
  font-weight: 600;
  color: var(--text-muted);
  opacity: 0.7;
  flex-shrink: 0;
}

.panel-id-value {
  flex: none;
}

.copy-btn {
  font-size: 0.85rem;
  cursor: pointer;
  color: var(--text-muted);
  opacity: 0.4;
  transition: all 0.2s;
  width: 1.4rem;
  display: inline-flex;
  justify-content: center;
  flex-shrink: 0;
}

.copy-btn.text-success {
  color: #10b981 !important;
  opacity: 1 !important;
}

.copy-btn:hover {
  opacity: 1 !important;
  color: var(--primary-color);
  transform: scale(1.1);
}

.copy-btn:active {
  transform: scale(0.9);
}

.panel-fields {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.panel-relationships {
  display: flex;
  flex-direction: column;
  gap: 0.45rem;
}

.panel-section-title {
  font-size: 0.6rem;
  text-transform: uppercase;
  font-weight: 600;
  color: var(--text-muted);
  letter-spacing: 0.03em;
}

.relationship-card {
  display: flex;
  flex-direction: column;
  gap: 0.35rem;
  padding: 0.55rem;
  background: var(--bg-secondary);
  border: 1px solid color-mix(in srgb, var(--tabs-border) 72%, transparent);
  border-radius: 6px;
}

.relationship-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 0.5rem;
}

.relationship-name {
  min-width: 0;
  color: var(--text-color);
  font-size: 0.74rem;
  font-weight: 650;
  line-height: 1.25;
  overflow-wrap: anywhere;
}

.relationship-status {
  flex-shrink: 0;
  padding: 0.12rem 0.42rem;
  border-radius: 999px;
  background: rgba(16, 185, 129, 0.14);
  color: #34d399;
  font-size: 0.58rem;
  font-weight: 700;
}

.relationship-status.inactive {
  background: rgba(239, 68, 68, 0.14);
  color: #fca5a5;
}

.relationship-meta {
  display: flex;
  flex-wrap: wrap;
  gap: 0.35rem;
  color: var(--text-muted);
  font-size: 0.65rem;
  font-weight: 500;
}

.relationship-dates {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 0.45rem;
}

.relationship-dates > div {
  display: flex;
  flex-direction: column;
  gap: 0.08rem;
}

.panel-field {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.78rem;
  color: var(--text-secondary);
}

.panel-field i {
  color: var(--primary-color);
  font-size: 0.75rem;
  flex-shrink: 0;
}

.info-block {
  flex-direction: column;
  align-items: flex-start !important;
  gap: 0.1rem !important;
  background: var(--bg-secondary);
  padding: 0.5rem;
  border-radius: 6px;
}

.field-label {
  font-size: 0.6rem;
  text-transform: uppercase;
  font-weight: 500;
  color: var(--text-muted);
  letter-spacing: 0.02em;
}

.field-value {
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--text-color);
  line-height: 1.2;
}

.mt-1 {
  margin-top: 0.25rem;
}

.panel-hint {
  font-size: 0.65rem;
  color: var(--text-muted);
  opacity: 0.6;
  display: flex;
  align-items: center;
  gap: 0.3rem;
  margin-top: auto;
}

/* Botão de Expansão Estilizado */
.expand-btn {
  width: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 0.6rem;
  padding: 0.75rem;
  background: var(--primary-color);
  color: white;
  border: none;
  border-radius: 8px;
  font-size: 0.75rem;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.2s;
  box-shadow: 0 4px 12px
    color-mix(in srgb, var(--primary-color) 30%, transparent);
}
.expand-btn:hover:not(:disabled) {
  background: color-mix(in srgb, var(--primary-color) 85%, black);
  transform: translateY(-1px);
}
.expand-btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
  background: var(--text-muted);
  box-shadow: none;
}

.mt-3 {
  margin-top: 0.75rem;
}

/* Animações ────────────────────────────────────────── */
.animate-fade-in {
  animation: fadeIn 0.4s ease-out;
}

@keyframes fadeIn {
  from {
    opacity: 0;
    transform: translateY(10px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.slide-in-enter-active,
.slide-in-leave-active {
  transition:
    opacity 0.25s,
    transform 0.25s;
}

.slide-in-enter-from,
.slide-in-leave-to {
  opacity: 0;
  transform: translateX(20px);
}
</style>
