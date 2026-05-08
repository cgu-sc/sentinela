<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { storeToRefs } from 'pinia';
import { useCnpjDetailStore } from '@/stores/cnpjDetail';
import { useRoute } from 'vue-router';
import cytoscape from 'cytoscape';
import TabPlaceholder from './TabPlaceholder.vue';

const route = useRoute();
const cnpj = computed(() => route.params.cnpj);
const cnpjDetailStore = useCnpjDetailStore();
const { networkData, networkLoading, networkError } = storeToRefs(cnpjDetailStore);

// ── Cytoscape instance & container ─────────────────────────────────────────
const cyContainer = ref(null);
let cy = null;
let resizeObserver = null;

// ── Controle de UI ──────────────────────────────────────────────────────────
const selectedNode = ref(null);
const zoom = ref(1);
const totalNodes = computed(() => networkData.value?.nodes?.length || 0);
const totalEdges = computed(() => networkData.value?.edges?.length || 0);

// ── Paleta de cores por tipo de nó ─────────────────────────────────────────
const NODE_STYLES = {
  PJ_ALVO:     { bg: '#6366f1', border: '#818cf8', shape: 'roundrectangle', size: 88 },
  PF:          { bg: '#0ea5e9', border: '#38bdf8', shape: 'ellipse',        size: 64 },
  PJ_FARMACIA: { bg: '#10b981', border: '#34d399', shape: 'roundrectangle', size: 68 },
  PJ_OUTRA:    { bg: '#64748b', border: '#94a3b8', shape: 'roundrectangle', size: 64 },
};

const INITIAL_FIT_PADDING = 120;
const REFIT_DELAY_MS = 80;

// ── Inicializa / Destrói o grafo ────────────────────────────────────────────
function buildGraph(data) {
  if (!cyContainer.value || !data) return;
  observeGraphContainer();

  // Destrói instância anterior com limpeza profunda
  if (cy) {
    try {
      cy.stop();
      cy.destroy();
    } catch (e) {
      console.warn("Erro ao destruir cytoscape:", e);
    }
    cy = null;
  }

  const elements = [
    ...data.nodes.map(n => ({
      data: {
        id: n.id,
        label: truncateLabel(n.label, 22),
        fullLabel: n.label,
        type: n.type,
        municipio: n.municipio,
        uf: n.uf,
        situacao: n.situacao_rf,
        razao_social: n.razao_social,
        nome_fantasia: n.nome_fantasia,
      }
    })),
    ...data.edges.map(e => ({
      data: {
        id: e.id,
        source: e.source,
        target: e.target,
        label: e.label || '',
        type: e.type,
      }
    })),
  ];

  cy = cytoscape({
    container: cyContainer.value,
    elements,
    style: buildStylesheet(),
    layout: {
      name: 'cose',
      animate: true,
      animationDuration: 800,
      nodeRepulsion: () => 8000,
      idealEdgeLength: () => 100,
      gravity: 1.2,
      numIter: 1000,
      initialTemp: 1000,
      coolingFactor: 0.99,
      minTemp: 1.0,
      fit: false,
      randomize: true, // Garante que não comece tudo no (0,0)
    },
    minZoom: 0.35,
    maxZoom: 3,
  });

  // Força o reconhecimento do tamanho do container
  cy.resize();

  // Garante centralização após renderizar
  cy.one('layoutstop', () => fitGraphToView(INITIAL_FIT_PADDING));

  cy.ready(() => {
    fitGraphToView(INITIAL_FIT_PADDING);
    setTimeout(() => fitGraphToView(INITIAL_FIT_PADDING), REFIT_DELAY_MS);
  });

  // Eventos interativos
  cy.on('tap', 'node', e => {
    const node = e.target;
    selectedNode.value = node.data();
    // Destaca vizinhos
    cy.elements().removeClass('faded highlighted');
    const neighborhood = node.closedNeighborhood();
    cy.elements().not(neighborhood).addClass('faded');
    neighborhood.addClass('highlighted');
  });

  cy.on('tap', e => {
    if (e.target === cy) {
      // Clique no fundo: remove destaques
      cy.elements().removeClass('faded highlighted');
      selectedNode.value = null;
    }
  });

  cy.on('zoom', () => {
    zoom.value = Math.round(cy.zoom() * 100);
  });

  zoom.value = 100;
}

function fitGraphToView(padding = INITIAL_FIT_PADDING) {
  if (!cy || !cyContainer.value || cy.elements().empty()) return;

  const { clientWidth, clientHeight } = cyContainer.value;
  if (!clientWidth || !clientHeight) return;

  cy.resize();
  cy.fit(cy.elements(), padding);
  cy.center(cy.elements());
  zoom.value = Math.round(cy.zoom() * 100);
}

function observeGraphContainer() {
  if (!cyContainer.value || resizeObserver) return;

  resizeObserver = new ResizeObserver(() => fitGraphToView(INITIAL_FIT_PADDING));
  resizeObserver.observe(cyContainer.value);
}

function buildStylesheet() {
  const styles = [];

  // Estilo base de nós por tipo
  Object.entries(NODE_STYLES).forEach(([type, s]) => {
    styles.push({
      selector: `node[type="${type}"]`,
      style: {
        'background-color': s.bg,
        'border-color': s.border,
        'border-width': 2,
        'shape': s.shape,
        'width': s.size,
        'height': s.shape === 'ellipse' ? s.size * 0.78 : s.size * 0.68,
        'label': 'data(label)',
        'text-valign': 'bottom',
        'text-halign': 'center',
        'font-size': '10px',
        'font-family': 'Inter, system-ui, sans-serif',
        'font-weight': '600',
        'color': '#e2e8f0',
        'text-outline-width': 2,
        'text-outline-color': '#0f172a',
        'text-margin-y': 4,
        'transition-property': 'opacity, border-width, background-color',
        'transition-duration': '0.2s',
      }
    });
  });

  // Nó alvo maior
  styles.push({
    selector: 'node[type="PJ_ALVO"]',
    style: {
      'border-width': 4,
      'border-color': '#818cf8',
    }
  });

  // Arestas
  styles.push({
    selector: 'edge',
    style: {
      'curve-style': 'bezier',
      'width': 1.5,
      'line-color': '#334155',
      'target-arrow-color': '#334155',
      'target-arrow-shape': 'triangle',
      'arrow-scale': 0.8,
      'label': 'data(label)',
      'font-size': '8px',
      'color': '#94a3b8',
      'text-outline-width': 1.5,
      'text-outline-color': '#0f172a',
      'text-rotation': 'autorotate',
      'transition-property': 'opacity, line-color',
      'transition-duration': '0.2s',
    }
  });

  // Arestas de representante
  styles.push({
    selector: 'edge[type="representante"]',
    style: { 'line-style': 'dashed', 'line-color': '#f59e0b', 'target-arrow-color': '#f59e0b' }
  });

  // Estados: faded / highlighted
  styles.push({
    selector: '.faded',
    style: { 'opacity': 0.08 }
  });
  styles.push({
    selector: '.highlighted',
    style: { 'opacity': 1, 'border-width': 3 }
  });

  return styles;
}

function truncateLabel(text, maxLen) {
  if (!text) return '—';
  return text.length > maxLen ? text.slice(0, maxLen) + '…' : text;
}

// ── Controles de zoom ───────────────────────────────────────────────────────
function zoomIn()  { cy?.zoom({ level: cy.zoom() * 1.25, renderedPosition: { x: cyContainer.value.clientWidth / 2, y: cyContainer.value.clientHeight / 2 } }); }
function zoomOut() { cy?.zoom({ level: cy.zoom() * 0.8,  renderedPosition: { x: cyContainer.value.clientWidth / 2, y: cyContainer.value.clientHeight / 2 } }); }
function fitGraph() { fitGraphToView(80); }
function resetLayout() {
  cy?.layout({
    name: 'cose', animate: true, animationDuration: 600,
    nodeRepulsion: () => 8000, idealEdgeLength: () => 120,
    gravity: 1.2, numIter: 800, fit: false,
  }).run();
  cy?.one('layoutstop', () => fitGraphToView(INITIAL_FIT_PADDING));
}

// ── Watchers ────────────────────────────────────────────────────────────────
watch(networkData, async (data) => {
  if (data) {
    await nextTick();
    buildGraph(data);
  }
}, { immediate: true });

onMounted(async () => {
  if (!networkData.value) {
    cnpjDetailStore.fetchNetwork(cnpj.value);
  } else {
    await nextTick();
    observeGraphContainer();
    buildGraph(networkData.value);
  }
});

onBeforeUnmount(() => {
  resizeObserver?.disconnect();
  resizeObserver = null;
  cy?.destroy();
  cy = null;
});

// ── Label do tipo de nó ─────────────────────────────────────────────────────
const typeLabels = {
  PJ_ALVO:     { label: 'CNPJ em Análise', color: '#6366f1' },
  PF:          { label: 'Pessoa Física',   color: '#0ea5e9' },
  PJ_FARMACIA: { label: 'Farmácia FP',     color: '#10b981' },
  PJ_OUTRA:    { label: 'Outra Empresa',   color: '#64748b' },
};
</script>

<template>
  <div class="network-tab tab-content">

    <!-- Estados ──────────────────────────────────────────────── -->
    <TabPlaceholder v-if="networkLoading" variant="loading"
      title="Construindo a Teia Societária"
      description="Mapeando conexões e participações societárias…"
    />
    <TabPlaceholder v-else-if="networkError" variant="error" icon="pi-exclamation-circle"
      title="Erro ao carregar teia" :description="networkError"
    />
    <TabPlaceholder v-else-if="!networkData || totalNodes === 0"
      icon="pi-share-alt"
      title="Nenhuma conexão encontrada"
      description="Não foram encontrados relacionamentos societários para este estabelecimento."
    />

    <!-- Painel principal ─────────────────────────────────────── -->
    <div v-else class="network-layout animate-fade-in">

      <!-- Cabeçalho ─────────────────────────────────────────── -->
      <div class="network-header">
        <div class="header-info">
          <i class="pi pi-share-alt" />
          <div>
            <h2 class="title">TEIA SOCIETÁRIA</h2>
            <p class="subtitle">Grafo de relacionamentos e participações societárias identificadas</p>
          </div>
        </div>
        <div class="header-stats">
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
      </div>

      <!-- Conteúdo principal ────────────────────────────────── -->
      <div class="network-body">

        <!-- Grafo ─────────────────────────────────────────────── -->
        <div class="graph-wrapper">
          <div ref="cyContainer" class="cy-canvas"></div>

          <!-- Controles flutuantes ──────────────────────────── -->
          <div class="graph-controls">
            <button class="ctrl-btn" @click="zoomIn"     v-tooltip.left="'Ampliar'">
              <i class="pi pi-plus" />
            </button>
            <span class="zoom-level">{{ zoom }}%</span>
            <button class="ctrl-btn" @click="zoomOut"    v-tooltip.left="'Reduzir'">
              <i class="pi pi-minus" />
            </button>
            <div class="ctrl-sep"></div>
            <button class="ctrl-btn" @click="fitGraph"   v-tooltip.left="'Ajustar ao ecrã'">
              <i class="pi pi-expand" />
            </button>
            <button class="ctrl-btn" @click="resetLayout" v-tooltip.left="'Reorganizar'">
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
              <span class="legend-line dashed"></span>
              <span class="legend-label">Representante</span>
            </div>
          </div>
        </div>

        <!-- Painel de detalhe do nó selecionado ──────────────── -->
        <transition name="slide-in">
          <div v-if="selectedNode" class="node-detail-panel">
            <div class="panel-header">
              <div class="panel-type-badge" :style="{ background: typeLabels[selectedNode.type]?.color }">
                {{ typeLabels[selectedNode.type]?.label || selectedNode.type }}
              </div>
              <button class="close-btn" @click="selectedNode = null; cy?.elements().removeClass('faded highlighted')">
                <i class="pi pi-times" />
              </button>
            </div>
            <div class="panel-names">
              <h3 class="panel-main-name">
                {{ selectedNode.nome_fantasia || selectedNode.razao_social || selectedNode.fullLabel }}
              </h3>
              <div v-if="selectedNode.nome_fantasia && selectedNode.razao_social" class="panel-sub-name">
                {{ selectedNode.razao_social }}
              </div>
            </div>
            <div class="panel-id">{{ selectedNode.id }}</div>
            <div class="panel-fields">
              <div v-if="selectedNode.municipio" class="panel-field mt-1">
                <i class="pi pi-map-marker" />
                <span>{{ selectedNode.municipio }} / {{ selectedNode.uf }}</span>
              </div>
              <div v-if="selectedNode.situacao" class="panel-field">
                <i class="pi pi-info-circle" />
                <span>Situação RF: {{ selectedNode.situacao }}</span>
              </div>
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

/* Header ───────────────────────────────────────────── */
.network-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  padding-bottom: 1rem;
  margin-bottom: 1rem;
  border-bottom: 1px solid var(--tabs-border);
}

.header-info {
  display: flex;
  align-items: center;
  gap: 1rem;
}

.header-info i {
  font-size: 1.1rem;
  color: var(--primary-color);
}

.title {
  margin: 0;
  font-size: 0.85rem;
  font-weight: 700;
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--text-color);
  opacity: 0.85;
}

.subtitle {
  margin: 0.1rem 0 0;
  font-size: 0.8rem;
  color: var(--text-muted);
}

.header-stats {
  display: flex;
  align-items: center;
  gap: 1.5rem;
}

.stat-item {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
}

.stat-value {
  font-size: 1.3rem;
  font-weight: 800;
  color: var(--primary-color);
  line-height: 1;
}

.stat-label {
  font-size: 0.6rem;
  text-transform: uppercase;
  font-weight: 700;
  color: var(--text-muted);
  letter-spacing: 0.04em;
}

.stat-divider {
  width: 1px;
  height: 2.2rem;
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

/* Controles flutuantes ─────────────────────────────── */
.graph-controls {
  position: absolute;
  top: 1rem;
  right: 1rem;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 0.3rem;
  background: var(--card-bg);
  border: 1px solid var(--tabs-border);
  border-radius: 10px;
  padding: 0.5rem;
  backdrop-filter: blur(8px);
  z-index: 10;
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
  transition: background 0.2s, color 0.2s;
}

.ctrl-btn:hover {
  background: color-mix(in srgb, var(--primary-color) 15%, transparent);
  color: var(--primary-color);
}

.zoom-level {
  font-size: 0.65rem;
  font-weight: 700;
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
    to right, #f59e0b 0px, #f59e0b 4px, transparent 4px, transparent 8px
  );
}

.legend-label {
  font-size: 0.68rem;
  color: var(--text-secondary);
  font-weight: 600;
}

/* Painel de detalhe ────────────────────────────────── */
.node-detail-panel {
  width: 260px;
  flex-shrink: 0;
  background: var(--card-bg);
  border: 1px solid var(--tabs-border);
  border-radius: 12px;
  padding: 1.2rem;
  display: flex;
  flex-direction: column;
  gap: 0.8rem;
  align-self: flex-start;
}

.panel-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}

.panel-type-badge {
  font-size: 0.62rem;
  font-weight: 700;
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

.close-btn:hover { color: var(--text-color); }

.panel-names {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
}

.panel-main-name {
  margin: 0;
  font-size: 1rem;
  font-weight: 800;
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
  font-family: var(--font-mono, monospace);
  color: var(--text-muted);
  background: var(--bg-secondary);
  border-radius: 6px;
  padding: 0.3rem 0.5rem;
}

.panel-fields {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
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
  font-weight: 700;
  color: var(--text-muted);
  letter-spacing: 0.02em;
}

.field-value {
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--text-color);
  line-height: 1.2;
}

.mt-1 { margin-top: 0.25rem; }

.panel-hint {
  font-size: 0.65rem;
  color: var(--text-muted);
  opacity: 0.6;
  display: flex;
  align-items: center;
  gap: 0.3rem;
  margin-top: auto;
}

/* Animações ────────────────────────────────────────── */
.animate-fade-in { animation: fadeIn 0.4s ease-out; }

@keyframes fadeIn {
  from { opacity: 0; transform: translateY(10px); }
  to   { opacity: 1; transform: translateY(0); }
}

.slide-in-enter-active, .slide-in-leave-active {
  transition: opacity 0.25s, transform 0.25s;
}

.slide-in-enter-from, .slide-in-leave-to {
  opacity: 0;
  transform: translateX(20px);
}
</style>
