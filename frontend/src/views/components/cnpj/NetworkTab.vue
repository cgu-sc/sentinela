<script setup>
import {
  ref,
  computed,
  watch,
  onMounted,
  onBeforeUnmount,
  onActivated,
  onDeactivated,
  nextTick,
} from "vue";
import { storeToRefs } from "pinia";
import { useCnpjDetailStore } from "@/stores/cnpjDetail";
import { useFilterParameters } from "@/composables/useFilterParameters";
import { useRoute } from "vue-router";
import cytoscape from "cytoscape";
import TabPlaceholder from "./TabPlaceholder.vue";
import NetworkAlertsOverlay from "./network/NetworkAlertsOverlay.vue";
import NetworkLayerFiltersMenu from "./network/NetworkLayerFiltersMenu.vue";
import NetworkLevelControls from "./network/NetworkLevelControls.vue";
import NetworkLegendItems from "./network/NetworkLegendItems.vue";
import NetworkNodeDetailPanel from "./network/NetworkNodeDetailPanel.vue";
import NetworkSearchBox from "./network/NetworkSearchBox.vue";
import NetworkStatsOverlay from "./network/NetworkStatsOverlay.vue";
import NetworkZoomControls from "./network/NetworkZoomControls.vue";
import {
  NETWORK_NODE_STYLES,
  NETWORK_TYPE_LABELS,
} from "@/utils/network/networkConstants";
import {
  createNetworkLayouts,
  getDenseLayoutScale,
  sortGraphNodes,
} from "@/utils/network/networkLayouts";
import { computeAnchoredFanPosition } from "@/utils/network/networkLayoutEngine";
import {
  buildNetworkNodeVisualData,
  getNodeClasses,
  isTruthyFlag,
  normalizeSearchText,
  truncateLabel,
} from "@/utils/network/networkNodeUtils";
import { buildNetworkStylesheet } from "@/utils/network/networkStylesheet";
import { createCnpjPerfSession, logCnpjPerf } from "@/utils/cnpjPerfLogger";

const route = useRoute();
const cnpj = computed(() => route.params.cnpj);
const cnpjDetailStore = useCnpjDetailStore();
const { getApiParams } = useFilterParameters();
const { networkData, networkLoading, networkError } =
  storeToRefs(cnpjDetailStore);

function getNetworkPeriod() {
  const { inicio, fim } = getApiParams();
  return { inicio, fim };
}

function fetchPeriodNetworkLevel(level) {
  const { inicio, fim } = getNetworkPeriod();
  return cnpjDetailStore.fetchNetworkLevel(cnpj.value, level, inicio, fim);
}

function fetchPeriodNetworkExpansion(nodeId) {
  const { inicio, fim } = getNetworkPeriod();
  return cnpjDetailStore.expandNetworkNode(
    cnpj.value,
    nodeId,
    inicio,
    fim,
  );
}

// ── Cytoscape instance & container ─────────────────────────────────────────
const cyContainer = ref(null);
let cy = null;
let resizeObserver = null;
let currentLayout = null;
let graphPresentationSaveFrame = null;

// ── Controle de UI ──────────────────────────────────────────────────────────
const selectedNode = ref(null);
const previewedAlertNodeId = ref(null);
const zoom = ref(1);
const copiedKey = ref(null);

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

const getPersonAlertName = (node) =>
  node.nome_socio || node.fullLabel || node.label || node.id;

const getCompanyAlertName = (node) =>
  node.nome_fantasia || node.razao_social || node.fullLabel || node.label || node.id;

const readAlertNodes = () => {
  if (graphReady.value && cy) {
    return cy
      .nodes(":visible")
      .map((node) => ({
        id: node.id(),
        type: node.data("type"),
        nome_socio: node.data("nome_socio"),
        nome_fantasia: node.data("nome_fantasia"),
        razao_social: node.data("razao_social"),
        fullLabel: node.data("fullLabel"),
        label: node.data("label"),
        is_falecido: node.data("is_falecido"),
        is_cadunico: node.data("is_cadunico"),
        is_esocial: node.data("is_esocial"),
        is_cnae_farmacia_ausente: node.data("is_cnae_farmacia_ausente"),
        is_par: node.data("is_par"),
        qtd_processos_par: node.data("qtd_processos_par"),
      }));
  }

  return (networkData.value?.nodes || []).map((node) => ({
    ...node,
    fullLabel: node.label,
  }));
};

const networkAlertGroups = computed(() => {
  graphCounts.value;
  const alertNodes = readAlertNodes();
  const people = alertNodes
    .filter((node) => (node.type || "PF") === "PF")
    .map((node) => ({
      id: node.id,
      name: getPersonAlertName(node),
      is_falecido: isTruthyFlag(node.is_falecido),
      is_cadunico: isTruthyFlag(node.is_cadunico),
      is_esocial: isTruthyFlag(node.is_esocial),
    }))
    .sort((a, b) => String(a.name).localeCompare(String(b.name), "pt-BR"));
  const companies = alertNodes
    .filter((node) => (node.type || "PF") !== "PF")
    .map((node) => ({
      id: node.id,
      name: getCompanyAlertName(node),
      is_cnae_farmacia_ausente: isTruthyFlag(node.is_cnae_farmacia_ausente),
      is_par: isTruthyFlag(node.is_par),
      qtd_processos_par: node.qtd_processos_par || 0,
    }))
    .sort((a, b) => String(a.name).localeCompare(String(b.name), "pt-BR"));

  return [
    {
      key: "cnae-ausente",
      label: "CNAE ausente",
      icon: "legend-cnae-alert",
      items: companies.filter((node) => node.is_cnae_farmacia_ausente),
    },
    {
      key: "par",
      label: "PAR",
      icon: "legend-par-alert",
      items: companies.filter((node) => node.is_par),
    },
    {
      key: "falecidos",
      label: "Falecidos",
      icon: "legend-deceased-cross",
      items: people.filter((node) => node.is_falecido),
    },
    {
      key: "cadunico",
      label: "CadÚnico",
      icon: "legend-cadunico-ring",
      items: people.filter((node) => node.is_cadunico),
    },
    {
      key: "esocial",
      label: "eSocial",
      icon: "legend-esocial-ring",
      items: people.filter((node) => node.is_esocial),
    },
  ].filter((group) => group.items.length > 0);
});

const hasNetworkAlerts = computed(() => networkAlertGroups.value.length > 0);

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
  exSociosAlvo: true,
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
const nextReorganizeMode = ref({
  N2: "radial",
  N3: "radial",
  N4: "community",
});
const reorganizeTooltip = computed(() => {
  if (currentLevel.value === "N4") return "Reorganizar por comunidades";
  if (currentLevel.value === "N2" || currentLevel.value === "N3") {
    const mode = nextReorganizeMode.value[currentLevel.value];
    if (mode === "community") return "Reorganizar por comunidades";
    if (mode === "ring") return "Reorganizar em anéis";
    return "Reorganizar radial";
  }
  return "Reorganizar";
});

const getLayerFilterSnapshot = () => ({ ...layerFilters.value });

const restoreLayerFilterSnapshot = (snapshot) => {
  layerFilters.value = {
    ...layerFilters.value,
    ...snapshot,
  };
};

const isValidGraphPosition = (position) =>
  Number.isFinite(position?.x) && Number.isFinite(position?.y);

function mergeNetworkPayloads(...payloads) {
  const nodeById = new Map();
  const edgeById = new Map();

  payloads.filter(Boolean).forEach((payload) => {
    (payload.nodes || []).forEach((node) => {
      if (!nodeById.has(node.id)) nodeById.set(node.id, node);
    });
    (payload.edges || []).forEach((edge) => {
      if (!edgeById.has(edge.id)) edgeById.set(edge.id, edge);
    });
  });

  return {
    nodes: Array.from(nodeById.values()),
    edges: Array.from(edgeById.values()),
  };
}

function getCompatiblePresentationState(state, data) {
  if (!state?.nodePositions || !data?.nodes?.length) return null;
  const hasEveryNodePosition = data.nodes.every((node) =>
    isValidGraphPosition(state.nodePositions[node.id]),
  );
  return hasEveryNodePosition ? state : null;
}

function getGraphPresentationState() {
  if (!cy) return null;

  const nodePositions = {};
  cy.nodes().forEach((node) => {
    const position = node.position();
    nodePositions[node.id()] = { x: position.x, y: position.y };
  });

  return {
    level: currentLevel.value,
    zoom: cy.zoom(),
    pan: { ...cy.pan() },
    nodePositions,
    expandedNodeIds: Array.from(expandedNodes.value),
    layerFilters: getLayerFilterSnapshot(),
    nextReorganizeMode: { ...nextReorganizeMode.value },
  };
}

function saveGraphPresentationState() {
  const state = getGraphPresentationState();
  if (state) cnpjDetailStore.saveNetworkPresentationState(cnpj.value, state);
}

function scheduleGraphPresentationStateSave() {
  if (graphPresentationSaveFrame) {
    window.cancelAnimationFrame(graphPresentationSaveFrame);
  }
  graphPresentationSaveFrame = window.requestAnimationFrame(() => {
    graphPresentationSaveFrame = null;
    saveGraphPresentationState();
  });
}

function restorePresentationUiState(state) {
  if (!state) return;
  if (state.level) currentLevel.value = state.level;
  if (Array.isArray(state.expandedNodeIds)) {
    expandedNodes.value = new Set(state.expandedNodeIds);
  }
  if (state.layerFilters) restoreLayerFilterSnapshot(state.layerFilters);
  if (state.nextReorganizeMode) {
    nextReorganizeMode.value = {
      ...nextReorganizeMode.value,
      ...state.nextReorganizeMode,
    };
  }
}

async function getGraphDataForPresentationState(state) {
  if (!networkData.value) return null;
  if (state?.level === "N3") {
    const dataN3 = await fetchPeriodNetworkLevel(3);
    return mergeNetworkPayloads(networkData.value, dataN3);
  }
  if (state?.level === "N4") {
    const [dataN3, dataN4] = await Promise.all([
      fetchPeriodNetworkLevel(3),
      fetchPeriodNetworkLevel(4),
    ]);
    return mergeNetworkPayloads(networkData.value, dataN3, dataN4);
  }
  return networkData.value;
}

async function getInitialGraphBuildPayload() {
  const presentationState = cnpjDetailStore.getNetworkPresentationState(cnpj.value);
  const graphData = await getGraphDataForPresentationState(presentationState);
  const restorableState = getCompatiblePresentationState(
    presentationState,
    graphData,
  );

  return {
    graphData: restorableState ? graphData : networkData.value,
    presentationState: restorableState,
  };
}

const updateLayerFilter = (key, value) => {
  layerFilters.value = {
    ...layerFilters.value,
    [key]: value,
  };
};

const toggleLevelHelpMenu = () => {
  showLevelHelpMenu.value = !showLevelHelpMenu.value;
  showFiltersMenu.value = false;
  showLegendMenu.value = false;
};

const networkLayouts = createNetworkLayouts({
  getCy: () => cy,
  getContainer: () => cyContainer.value,
  getCurrentLevel: () => currentLevel.value,
  getCurrentLayout: () => currentLayout,
  setCurrentLayout: (layout) => {
    currentLayout = layout;
  },
  getHasActiveSearch: () => hasActiveSearch.value,
  fitGraphToView: (...args) => fitGraphToView(...args),
  applyGraphHighlights: () => applyGraphHighlights(),
  applyVisibilityFilters: () => applyVisibilityFilters(),
  getGraphRightReservePx: (width) => getGraphRightReservePx(width),
  initialFitPadding: 48,
});

const rememberPresentationZoom = networkLayouts.rememberPresentationZoom;
const applyRadialView = networkLayouts.applyRadialView;
const applyLayeredRadialView = networkLayouts.applyLayeredRadialView;
const applyRingView = networkLayouts.applyRingView;
const applyN4CommunityGridView = networkLayouts.applyN4CommunityGridView;
const runGraphLayout = networkLayouts.runGraphLayout;

const INCREMENTAL_CORRIDOR_MIN_SPAN = 190;
const INCREMENTAL_CORRIDOR_NODE_GAP = 96;
const INCREMENTAL_CORRIDOR_GROUP_GAP = 56;
const INCREMENTAL_CORRIDOR_BASE_DISTANCE = 270;
const INCREMENTAL_CORRIDOR_CURVE_FACTOR = 0.24;

function getIncrementalAnchorSide(anchor, center) {
  const dx = anchor.x - center.x;
  const dy = anchor.y - center.y;
  if (Math.abs(dx) >= Math.abs(dy)) return dx >= 0 ? "right" : "left";
  return dy >= 0 ? "bottom" : "top";
}

function getIncrementalLaneSpan(count) {
  return Math.max(
    INCREMENTAL_CORRIDOR_MIN_SPAN,
    (Math.max(1, count) - 1) * INCREMENTAL_CORRIDOR_NODE_GAP + 120,
  );
}

function computeIncrementalCorridorPosition({ layout, index, count }) {
  const safeCount = Math.max(1, count || 1);
  const safeIndex = Math.max(0, Math.min(index || 0, safeCount - 1));
  const slot = safeCount === 1 ? 0 : safeIndex / (safeCount - 1) - 0.5;
  const laneOffset = slot * Math.max(0, layout.laneSpan - 70);

  if (layout.side === "right" || layout.side === "left") {
    const direction = layout.side === "right" ? 1 : -1;
    const y = layout.laneCenter + laneOffset;
    const x =
      layout.anchor.x +
      direction *
        (INCREMENTAL_CORRIDOR_BASE_DISTANCE +
          Math.abs(y - layout.anchor.y) * INCREMENTAL_CORRIDOR_CURVE_FACTOR);
    return { x, y };
  }

  const direction = layout.side === "bottom" ? 1 : -1;
  const x = layout.laneCenter + laneOffset;
  const y =
    layout.anchor.y +
    direction *
      (INCREMENTAL_CORRIDOR_BASE_DISTANCE +
        Math.abs(x - layout.anchor.x) * INCREMENTAL_CORRIDOR_CURVE_FACTOR);
  return { x, y };
}

function allocateIncrementalCorridors(groups, center) {
  const layoutByGroup = new Map();
  const groupsBySide = new Map();

  groups.forEach((group) => {
    const side = getIncrementalAnchorSide(group.anchor, center);
    if (!groupsBySide.has(side)) groupsBySide.set(side, []);
    groupsBySide.get(side).push({
      ...group,
      side,
      preferredLaneCenter:
        side === "right" || side === "left" ? group.anchor.y : group.anchor.x,
      span: getIncrementalLaneSpan(group.nodeIds.length),
    });
  });

  groupsBySide.forEach((entries) => {
    entries.sort((a, b) => a.preferredLaneCenter - b.preferredLaneCenter);
    let previousEnd = -Infinity;
    let preferredSum = 0;
    let packedSum = 0;

    entries.forEach((entry) => {
      const halfSpan = entry.span / 2;
      entry.laneCenter = Math.max(
        entry.preferredLaneCenter,
        previousEnd + INCREMENTAL_CORRIDOR_GROUP_GAP + halfSpan,
      );
      previousEnd = entry.laneCenter + halfSpan;
      preferredSum += entry.preferredLaneCenter;
      packedSum += entry.laneCenter;
    });

    const recenterOffset = (preferredSum - packedSum) / Math.max(entries.length, 1);
    entries.forEach((entry) => {
      layoutByGroup.set(entry.key, {
        anchor: entry.anchor,
        side: entry.side,
        laneCenter: entry.laneCenter + recenterOffset,
        laneSpan: entry.span,
      });
    });
  });

  return layoutByGroup;
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
  const incrementalGroups = [];

  if (placeNewNodesNearAnchors) {
    anchorGroups.forEach((nodeIds, key) => {
      if (key === "__center__") return;
      const anchor = cy.getElementById(key);
      if (!anchor?.length || anchor.hidden()) return;
      incrementalGroups.push({
        key,
        anchor: anchor.position(),
        nodeIds,
      });
    });
  }

  const incrementalCorridors = allocateIncrementalCorridors(
    incrementalGroups,
    graphCenter,
  );

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
    const corridor = anchorId ? incrementalCorridors.get(anchorId) : null;
    const targetPosition = corridor
      ? computeIncrementalCorridorPosition({
          layout: corridor,
          index: groupIndex,
          count: group.length,
        })
      : computeAnchoredFanPosition({
          anchor: basePosition,
          anchorAngle: baseAngle,
          index: groupIndex,
          count: group.length,
        });
    const startAngle = Math.atan2(
      targetPosition.y - basePosition.y,
      targetPosition.x - basePosition.x,
    );
    const startRadius = 28;
    const position = {
      x: basePosition.x + Math.cos(startAngle) * startRadius,
      y: basePosition.y + Math.sin(startAngle) * startRadius,
    };
    targetPositions.set(n.id, targetPosition);

    cy.add({
      group: "nodes",
      classes: [fadeInNewElements ? "entering" : "", getNodeClasses(n)]
        .filter(Boolean)
        .join(" "),
      data: {
        ...n,
        ...buildNetworkNodeVisualData(n, 20),
        situacao_rf: n.situacao_rf,
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

  const dataN3 = await fetchPeriodNetworkLevel(3);
  (dataN3?.nodes || []).forEach((node) => ids.nodeIds.add(node.id));
  (dataN3?.edges || []).forEach((edge) => ids.edgeIds.add(edge.id));

  if (level === "N3") return ids;

  const dataN4 = await fetchPeriodNetworkLevel(4);
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

const expandBatch = async (mode) => {
  if (isBatchExpanding.value) return;
  if (currentLevel.value === mode) return;
  const preservedLayerFilters = getLayerFilterSnapshot();

  try {
    isBatchExpanding.value = true;
    loadingLevel.value = mode;
    showLevelHelpMenu.value = false;
    if (mode === "N3") {
      const dataN3 = await fetchPeriodNetworkLevel(3);

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
        const dataN3 = await fetchPeriodNetworkLevel(3);
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

      const dataN4 = await fetchPeriodNetworkLevel(4);
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

function selectGraphNode(nodeId) {
  if (!cy || !nodeId) return;
  const node = cy.getElementById(nodeId);
  if (!node.length || node.hidden()) return;
  selectedNode.value = buildSelectedNodePayload(node);
  applyGraphHighlights();
}

function previewAlertNode(nodeId) {
  if (!cy || !nodeId) return;
  const node = cy.getElementById(nodeId);
  if (!node.length || node.hidden()) return;
  previewedAlertNodeId.value = nodeId;
  applyGraphHighlights();
}

function clearAlertNodePreview(nodeId) {
  if (previewedAlertNodeId.value !== nodeId) return;
  previewedAlertNodeId.value = null;
  applyGraphHighlights();
}

const clearGraphHighlights = () => {
  if (!cy) return;
  cy.elements().removeClass("faded highlighted");
};

const applyNodeHighlight = (nodeId) => {
  if (!cy || !nodeId) return false;

  const node = cy.getElementById(nodeId);
  if (!node.length || node.hidden()) return false;

  const neighborhood = node.closedNeighborhood().filter(":visible");
  cy.elements(":visible").not(neighborhood).addClass("faded");
  neighborhood.addClass("highlighted");
  return true;
};

const applySelectedHighlight = () => {
  applyNodeHighlight(selectedNode.value?.id);
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

  if (previewedAlertNodeId.value) {
    if (applyNodeHighlight(previewedAlertNodeId.value)) return;
    previewedAlertNodeId.value = null;
  }

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
    if (!layerFilters.value.exSociosAlvo) {
      cy.nodes('[type="PF"]')
        .filter((node) =>
          node.connectedEdges().filter((edge) => {
            const isDirectTargetLink =
              edge.source().data("type") === "PJ_ALVO" ||
              edge.target().data("type") === "PJ_ALVO";

            return (
              isDirectTargetLink &&
              edge.data("is_ativo") === false &&
              edge.data("type") !== "representante"
            );
          }).length > 0,
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

  if (previewedAlertNodeId.value) {
    const previewed = cy.getElementById(previewedAlertNodeId.value);
    if (!previewed.length || previewed.hidden()) previewedAlertNodeId.value = null;
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
    const style = NETWORK_NODE_STYLES[type];
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
const GRAPH_RIGHT_OVERLAY_GAP = 24;
const GRAPH_RIGHT_RESERVE_MAX_RATIO = 0.32;

function getGraphRightReservePx(containerWidth) {
  if (!cyContainer.value || !containerWidth) return 0;

  const wrapper = cyContainer.value.parentElement;
  if (!wrapper) return 0;

  const overlaySelectors = [
    ".node-detail-panel",
    ".graph-alerts-overlay",
    ".graph-stats-overlay",
    ".graph-controls",
  ];
  const overlayWidth = overlaySelectors.reduce((maxWidth, selector) => {
    const element = wrapper.querySelector(selector);
    if (!element) return maxWidth;
    return Math.max(maxWidth, element.getBoundingClientRect().width || 0);
  }, 0);

  if (!overlayWidth) return 0;

  return Math.min(
    overlayWidth + GRAPH_RIGHT_OVERLAY_GAP,
    containerWidth * GRAPH_RIGHT_RESERVE_MAX_RATIO,
  );
}

function getGraphFitViewport(elements, padding, rightReserve = 0) {
  if (!cy || !cyContainer.value || elements.empty()) return null;

  const { clientWidth, clientHeight } = cyContainer.value;
  if (!clientWidth || !clientHeight) return null;

  const leftPadding = padding;
  const rightPadding = padding + rightReserve;
  const topPadding = padding;
  const bottomPadding = padding;
  const availableWidth = Math.max(80, clientWidth - leftPadding - rightPadding);
  const availableHeight = Math.max(80, clientHeight - topPadding - bottomPadding);
  const box = elements.boundingBox({ includeLabels: true });
  const boxWidth = Math.max(1, box.w);
  const boxHeight = Math.max(1, box.h);
  const zoom = Math.max(
    cy.minZoom(),
    Math.min(cy.maxZoom(), Math.min(availableWidth / boxWidth, availableHeight / boxHeight)),
  );
  const graphCenter = {
    x: box.x1 + boxWidth / 2,
    y: box.y1 + boxHeight / 2,
  };
  const viewportCenter = {
    x: leftPadding + availableWidth / 2,
    y: topPadding + availableHeight / 2,
  };

  return {
    zoom,
    pan: {
      x: viewportCenter.x - graphCenter.x * zoom,
      y: viewportCenter.y - graphCenter.y * zoom,
    },
  };
}

// ── Inicializa / Destrói o grafo ────────────────────────────────────────────
async function buildGraph(data, { presentationState = null } = {}) {
  if (!cyContainer.value || !data) return;
  const restoredPresentation = getCompatiblePresentationState(
    presentationState,
    data,
  );
  if (restoredPresentation) restorePresentationUiState(restoredPresentation);

  const perfSession = createCnpjPerfSession(cnpj.value);
  logCnpjPerf(perfSession, "network_graph_build_started", {
    nodes: data.nodes?.length ?? 0,
    edges: data.edges?.length ?? 0,
  });
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
    saveGraphPresentationState();
    try {
      cy.stop();
    } catch (e) {}
    // Drena RAFs pendentes antes de destruir para evitar callbacks em instâncias antigas.
    await new Promise((resolve) => requestAnimationFrame(resolve));
    try {
      cy.destroy();
    } catch (e) {}
    cy = null;
    graphReady.value = false;
  }

  const elements = [
    ...data.nodes.map((n) => {
      const element = {
        classes: getNodeClasses(n),
        data: {
          id: n.id,
          ...buildNetworkNodeVisualData(n, 22),
          type: n.type,
          municipio: n.municipio,
          uf: n.uf,
          situacao_rf: n.situacao_rf,
          nome_socio: n.nome_socio,
          razao_social: n.razao_social,
          nome_fantasia: n.nome_fantasia,
          id_cnae_principal: n.id_cnae_principal,
          cnae_principal: n.cnae_principal,
          id_cnae_secundario: n.id_cnae_secundario,
          cnae_secundario: n.cnae_secundario,
          is_falecido: isTruthyFlag(n.is_falecido),
          is_cadunico: isTruthyFlag(n.is_cadunico),
          is_esocial: isTruthyFlag(n.is_esocial),
          is_cnae_farmacia_ausente: isTruthyFlag(n.is_cnae_farmacia_ausente),
          is_par: isTruthyFlag(n.is_par),
          qtd_processos_par: n.qtd_processos_par || 0,
          par_situacoes: n.par_situacoes,
          par_primeira_instauracao: n.par_primeira_instauracao,
          par_ultima_instauracao: n.par_ultima_instauracao,
          par_ultima_conclusao: n.par_ultima_conclusao,
        },
      };
      const savedPosition = restoredPresentation?.nodePositions?.[n.id];
      if (isValidGraphPosition(savedPosition)) {
        element.position = { ...savedPosition };
      }
      return element;
    }),
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
  logCnpjPerf(perfSession, "network_graph_elements_built", {
    elements: elements.length,
  });

  // Oculta o canvas até o layout terminar — evita flash de nós empilhados em (0,0)
  if (cyContainer.value) cyContainer.value.style.opacity = "0";

  cy = cytoscape({
    container: cyContainer.value,
    elements,
    style: buildNetworkStylesheet(),
    layout: { name: "preset" },
    minZoom: 0.18,
    maxZoom: 3,
  });
  const graphInstance = cy;
  graphReady.value = true;
  bindGraphCountUpdates();
  logCnpjPerf(perfSession, "network_graph_cytoscape_created", {
    elements: elements.length,
  });

  // Força o reconhecimento do tamanho do container
  cy.resize();
  applyVisibilityFilters();
  scheduleGraphCountsUpdate();

  cy.ready(() => {
    requestAnimationFrame(() => {
      if (!cy || cy !== graphInstance) return;

      if (restoredPresentation) {
        if (Number.isFinite(restoredPresentation.zoom)) {
          cy.zoom(restoredPresentation.zoom);
        }
        if (restoredPresentation.pan) {
          cy.pan({ ...restoredPresentation.pan });
        }
        zoom.value = Math.round(cy.zoom() * 100);
        logCnpjPerf(perfSession, "network_graph_presentation_restored", {
          nodes: cy?.nodes()?.length ?? 0,
          edges: cy?.edges()?.length ?? 0,
          level: currentLevel.value,
        });
      } else {
        applyRadialView({ rememberN2Zoom: true });
        logCnpjPerf(perfSession, "network_graph_radial_applied", {
          nodes: cy?.nodes()?.length ?? 0,
          edges: cy?.edges()?.length ?? 0,
        });
      }
      if (hasActiveSearch.value) {
        applyGraphHighlights();
      }

      if (cyContainer.value && cy === graphInstance) {
        cyContainer.value.style.opacity = "";
        cyContainer.value.style.pointerEvents = "";
      }
    });
  });

  // Eventos interativos
  cy.on("tap", "node", (e) => {
    const node = e.target;
    selectGraphNode(node.id());
  });

  cy.on("tap", (e) => {
    if (e.target === cy) {
      selectedNode.value = null;
      applyGraphHighlights();
    }
  });

  cy.on("zoom", () => {
    zoom.value = Math.round(cy.zoom() * 100);
    scheduleGraphPresentationStateSave();
  });

  cy.on("pan", () => {
    scheduleGraphPresentationStateSave();
  });

  if (!restoredPresentation) zoom.value = 100;
}

// ── Lógica de Expansão (Nível 3) ─────────────────────────────────────────────
async function expandNode(nodeId) {
  if (isExpanding.value || expandedNodes.value.has(nodeId)) return;

  isExpanding.value = true;
  try {
    const expansionData = await fetchPeriodNetworkExpansion(nodeId);

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
            ...buildNetworkNodeVisualData(n, 20),
            type: n.type || "PF",
            is_expanded_node: true,
            expansion_level: expansionLevel,
            nome_socio: n.nome_socio,
            razao_social: n.razao_social,
            nome_fantasia: n.nome_fantasia,
            id_cnae_principal: n.id_cnae_principal,
            cnae_principal: n.cnae_principal,
            id_cnae_secundario: n.id_cnae_secundario,
            cnae_secundario: n.cnae_secundario,
            municipio: n.municipio,
            uf: n.uf,
            situacao_rf: n.situacao_rf,
            is_falecido: isTruthyFlag(n.is_falecido),
            is_cadunico: isTruthyFlag(n.is_cadunico),
            is_esocial: isTruthyFlag(n.is_esocial),
            is_cnae_farmacia_ausente: isTruthyFlag(n.is_cnae_farmacia_ausente),
            is_par: isTruthyFlag(n.is_par),
            qtd_processos_par: n.qtd_processos_par || 0,
            par_situacoes: n.par_situacoes,
            par_primeira_instauracao: n.par_primeira_instauracao,
            par_ultima_instauracao: n.par_ultima_instauracao,
            par_ultima_conclusao: n.par_ultima_conclusao,
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

      const animationDuration = 620;
      const anchorPosition = anchorNode.position();
      const visibleBox = cy.nodes(":visible").boundingBox({
        includeLabels: false,
      });
      const graphCenter = {
        x: (visibleBox.x1 + visibleBox.x2) / 2,
        y: (visibleBox.y1 + visibleBox.y2) / 2,
      };
      const addedNodes = sortGraphNodes(added.nodes().toArray());
      const corridor = allocateIncrementalCorridors(
        [
          {
            key: nodeId,
            anchor: anchorPosition,
            nodeIds: addedNodes.map((node) => node.id()),
          },
        ],
        graphCenter,
      ).get(nodeId);

      addedNodes.forEach((node, index) => {
        const position = corridor
          ? computeIncrementalCorridorPosition({
              layout: corridor,
              index,
              count: addedNodes.length,
            })
          : computeAnchoredFanPosition({
              anchor: anchorPosition,
              anchorAngle: Math.atan2(
                anchorPosition.y - graphCenter.y,
                anchorPosition.x - graphCenter.x,
              ),
              index,
              count: addedNodes.length,
            });
        node.animate(
          { position },
          { duration: animationDuration, easing: "ease-out-cubic" },
        );
      });

      // Destaca vizinhos do nó expandido
      applyVisibilityFilters();
      if (!hasActiveSearch.value) {
        fitGraphToView(INITIAL_FIT_PADDING, {
          animate: true,
          duration: Math.min(650, animationDuration),
        });
        window.setTimeout(() => {
          fitGraphToView(INITIAL_FIT_PADDING, { animate: true, duration: 360 });
          rememberPresentationZoom(expansionLevel);
        }, animationDuration + 40);
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
  const rightReserve = getGraphRightReservePx(clientWidth);
  const targetViewport = getGraphFitViewport(visibleElements, padding, rightReserve);
  if (!targetViewport) return;

  if (animate) {
    cy.animate(
      targetViewport,
      {
        duration,
        complete: () => {
          zoom.value = Math.round(cy.zoom() * 100);
        },
      },
    );
    return;
  }
  cy.viewport(targetViewport);
  zoom.value = Math.round(cy.zoom() * 100);
}

function observeGraphContainer() {
  if (!cyContainer.value || resizeObserver) return;

  resizeObserver = new ResizeObserver(() => {
    cy?.resize();
    if (hasActiveSearch.value) {
      applyGraphHighlights();
    }
  });
  resizeObserver.observe(cyContainer.value);
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
    if (nextReorganizeMode.value.N2 === "radial") {
      applyRadialView({ rememberN2Zoom: true });
      nextReorganizeMode.value.N2 = "ring";
    } else {
      applyRingView({ rememberLevel: "N2" });
      nextReorganizeMode.value.N2 = "radial";
    }
    return;
  }
  if (currentLevel.value === "N3") {
    if (nextReorganizeMode.value.N3 === "radial") {
      applyLayeredRadialView({ rememberLevel: "N3" });
      nextReorganizeMode.value.N3 = "ring";
    } else {
      applyRingView({ rememberLevel: "N3" });
      nextReorganizeMode.value.N3 = "radial";
    }
    return;
  }
  applyN4CommunityGridView({ rememberLevel: "N4" });
}

// ── Watchers ────────────────────────────────────────────────────────────────
watch(
  networkData,
  async (data) => {
    if (isBatchExpanding.value) return;
    if (data) {
      await nextTick();
      const payload = cy
        ? { graphData: data, presentationState: null }
        : await getInitialGraphBuildPayload();
      await buildGraph(payload.graphData || data, {
        presentationState: payload.presentationState,
      });
    }
  },
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

  const levelHelpRoot = levelHelpMenuRoot.value?.$el || levelHelpMenuRoot.value;
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
    const { inicio, fim } = getNetworkPeriod();
    cnpjDetailStore.fetchNetwork(cnpj.value, inicio, fim);
  } else {
    await nextTick();
    observeGraphContainer();
    const payload = await getInitialGraphBuildPayload();
    await buildGraph(payload.graphData || networkData.value, {
      presentationState: payload.presentationState,
    });
  }
});

onBeforeUnmount(() => {
  saveGraphPresentationState();
  document.removeEventListener("click", handleFiltersMenuOutsideClick);
  resizeObserver?.disconnect();
  resizeObserver = null;
  if (graphCountUpdateFrame) {
    window.cancelAnimationFrame(graphCountUpdateFrame);
    graphCountUpdateFrame = null;
  }
  if (graphPresentationSaveFrame) {
    window.cancelAnimationFrame(graphPresentationSaveFrame);
    graphPresentationSaveFrame = null;
  }
  cy?.destroy();
  cy = null;
  graphReady.value = false;
  updateGraphCounts();
});

onDeactivated(() => {
  saveGraphPresentationState();
});

onActivated(() => {
  if (cy) {
    cy.resize();
    if (hasActiveSearch.value) applyGraphHighlights();
  }
});

const typeLabels = NETWORK_TYPE_LABELS;
</script>

<template>
  <div class="network-tab tab-content">
    <!-- Estados ──────────────────────────────────────────────── -->
    <div
      v-if="networkLoading && !networkData && !networkError"
      class="network-initial-loading-sentinel"
      aria-hidden="true"
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
            <NetworkLevelControls
              ref="levelHelpMenuRoot"
              :current-level="currentLevel"
              :loading-level="loadingLevel"
              :is-batch-expanding="isBatchExpanding"
              :show-help="showLevelHelpMenu"
              @reset-n2="resetToN2"
              @expand="expandBatch"
              @toggle-help="toggleLevelHelpMenu"
            />

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

                <NetworkLayerFiltersMenu
                  v-if="showFiltersMenu"
                  :filters="layerFilters"
                  @update-filter="updateLayerFilter"
                />
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
            <NetworkSearchBox
              v-model="networkSearch"
              :match-count="searchMatchCount"
              :has-active-search="hasActiveSearch"
              :search-has-no-match="searchHasNoMatch"
              @clear="clearNodeSearch"
            />

            <NetworkZoomControls
              variant="pill"
              :zoom="zoom"
              :reorganize-tooltip="reorganizeTooltip"
              @zoom-in="zoomIn"
              @zoom-out="zoomOut"
              @fit="fitGraph"
              @reset-layout="resetLayout"
            />

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
                  <NetworkLegendItems :type-labels="typeLabels" />
                </div>
              </div>
            </div>
          </div>

          <NetworkStatsOverlay
            :total-nodes="totalNodes"
            :total-edges="totalEdges"
            :summary="networkData?.summary"
          />

          <NetworkAlertsOverlay
            v-if="hasNetworkAlerts"
            :groups="networkAlertGroups"
            :selected-node-id="selectedNode?.id"
            :previewed-node-id="previewedAlertNodeId"
            @preview="previewAlertNode"
            @clear-preview="clearAlertNodePreview"
            @select="selectGraphNode"
          />

          <NetworkZoomControls
            :zoom="zoom"
            :reorganize-tooltip="reorganizeTooltip"
            @zoom-in="zoomIn"
            @zoom-out="zoomOut"
            @fit="fitGraph"
            @reset-layout="resetLayout"
          />

          <!-- Legenda ───────────────────────────────────────── -->
          <div class="graph-legend">
            <NetworkLegendItems :type-labels="typeLabels" />
          </div>
        </div>

        <NetworkNodeDetailPanel
          v-if="selectedNode"
          :node="selectedNode"
          :type-labels="typeLabels"
          :copied-key="copiedKey"
          :can-expand="canExpand"
          :is-expanding="isExpanding"
          :is-expanded="expandedNodes.has(selectedNode.id)"
          :expansion-label="expansionLabel"
          @close="closeSelectedNode"
          @copy="copyAndSignal"
          @expand="expandNode"
        />
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
  --graph-side-panel-width: 156px;
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

.pill-sep {
  width: 1px;
  height: 16px;
  background: rgba(255, 255, 255, 0.1);
  margin: 0 2px;
  flex-shrink: 0;
}

/* Controles de Zoom (canto inferior direito) ──────── */
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

</style>





