<script setup>
import { ref, computed, watch, onMounted, onBeforeUnmount, onActivated, nextTick } from 'vue';
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
let currentLayout = null;

// ── Controle de UI ──────────────────────────────────────────────────────────
const selectedNode = ref(null);
const zoom = ref(1);
const totalNodes = computed(() => networkData.value?.nodes?.length || 0);
const totalEdges = computed(() => networkData.value?.edges?.length || 0);

// Expansão
const isExpanding = ref(false);
const isBatchExpanding = ref(false);
const expandedNodes = ref(new Set());

// Filtros de visibilidade
const showInactiveCompanies = ref(true); // Ocultar empresas inativas (PJ)
const showInactivePartners  = ref(true); // Ocultar sócios inativos (PF)

// ── Funções de Utilitário para o Grafo ──────────────────────────────────
const mergeNetworkData = (newData) => {
  if (!cy || !newData) return;
  
  // Evitar duplicados
  const existingNodes = new Set(cy.nodes().map(n => n.id()));
  const existingEdges = new Set(cy.edges().map(e => e.id()));

  const newNodes = (newData.nodes || []).filter(n => !existingNodes.has(n.id));
  const newEdges = (newData.edges || []).filter(e => !existingEdges.has(e.id));

  // Adicionar nós
  newNodes.forEach(n => {
    cy.add({
      group: 'nodes',
      data: {
        ...n,
        label: truncateLabel(n.label, 20),
        fullLabel: n.label,
        is_expanded_node: true
      },
      // Posição inicial próxima ao centro para batch expansion
      position: { x: cy.width() / 2, y: cy.height() / 2 }
    });
  });

  // Adicionar arestas
  newEdges.forEach(e => {
    cy.add({ group: 'edges', data: { ...e } });
  });

  if (newNodes.length > 0 || newEdges.length > 0) {
    if (currentLayout) { try { currentLayout.stop(); } catch (e) {} }
    // animate: false → layout instantâneo, sem flash de nós empilhados
    if (cyContainer.value) cyContainer.value.style.opacity = '0';
    currentLayout = cy.layout({
      name: 'cose',
      animate: false,
      randomize: false,
      fit: true,
      padding: 50,
      nodeRepulsion: 8000,
      idealEdgeLength: 100
    });
    cy.one('layoutstop', () => {
      if (cyContainer.value) cyContainer.value.style.opacity = '';
      fitGraphToView(INITIAL_FIT_PADDING);
    });
    currentLayout.run();
  }
};

const resetToN2 = async () => {
  if (!networkData.value) return;
  await buildGraph(networkData.value);
  expandedNodes.value = new Set();
  selectedNode.value = null;
  showInactiveCompanies.value = true;
  showInactivePartners.value = true;
};

const expandBatch = async (mode) => {
  if (isBatchExpanding.value) return;
  
  try {
    isBatchExpanding.value = true;
    let data = null;
    
    if (mode === 'N3') {
      // Sempre reconstrói do N2 para limpar estado de N4 anterior
      await buildGraph(networkData.value);
      expandedNodes.value = new Set();
      data = await cnpjDetailStore.fetchNetworkLevel(cnpj.value, 3);
      if (data) mergeNetworkData(data);

    } else if (mode === 'N4') {
      // N3 é pré-requisito do N4: carrega os dois em sequência
      const dataN3 = await cnpjDetailStore.fetchNetworkLevel(cnpj.value, 3);
      if (dataN3) mergeNetworkData(dataN3);

      const dataN4 = await cnpjDetailStore.fetchNetworkLevel(cnpj.value, 4);
      if (dataN4) mergeNetworkData(dataN4);
      data = dataN4;
    }

    // Marcar nós como expandidos para evitar botões redundantes no painel lateral
    if (data?.nodes) {
      data.nodes.forEach(n => {
        if (['PJ_FARMACIA', 'PJ_FARMACIA_EXT', 'PJ_OUTRA', 'PJ', 'PF'].includes(n.type)) {
          expandedNodes.value.add(n.id);
        }
      });
    }
  } catch (err) {
    console.error("Erro na expansão em lote:", err);
  } finally {
    isBatchExpanding.value = false;
  }
};

const PJ_FILTERABLE = ['PJ_FARMACIA', 'PJ_FARMACIA_EXT', 'PJ_OUTRA', 'PJ'];

const applyVisibilityFilters = () => {
  if (!cy) return;

  // Parte do estado limpo a cada re-aplicação
  cy.elements().show();

  if (!showInactiveCompanies.value) {
    // Oculta arestas inativas conectadas a empresas (não-alvo)
    cy.edges()
      .filter(e => !e.data('is_ativo') && (
        PJ_FILTERABLE.includes(e.source().data('type')) ||
        PJ_FILTERABLE.includes(e.target().data('type'))
      ))
      .hide();
    // Oculta empresas que ficaram sem nenhuma aresta visível
    cy.nodes()
      .filter(n => PJ_FILTERABLE.includes(n.data('type')) && n.connectedEdges(':visible').length === 0)
      .hide();
  }

  if (!showInactivePartners.value) {
    // Oculta arestas inativas conectadas a pessoas físicas
    cy.edges()
      .filter(e => !e.data('is_ativo') && (
        e.source().data('type') === 'PF' ||
        e.target().data('type') === 'PF'
      ))
      .hide();
    // Oculta PFs que ficaram sem nenhuma aresta visível
    cy.nodes()
      .filter(n => n.data('type') === 'PF' && n.connectedEdges(':visible').length === 0)
      .hide();
  }
};

const toggleInactiveCompanies = () => {
  showInactiveCompanies.value = !showInactiveCompanies.value;
  applyVisibilityFilters();
};

const toggleInactivePartners = () => {
  showInactivePartners.value = !showInactivePartners.value;
  applyVisibilityFilters();
};

const exportPng = () => {
  if (!cy) return;
  const options = {
    bg: '#0f172a',
    full: true,
    scale: 2,
    maxWidth: 2000,
  };
  const pngData = cy.png(options);
  const link = document.createElement('a');
  link.href = pngData;
  link.download = `teia_${cnpj.value}_${new Date().toISOString().slice(0,10)}.png`;
  link.click();
};

const canExpand = computed(() => {
  if (!selectedNode.value) return false;
  const { type, id } = selectedNode.value;
  // Empresas podem expandir (para N3) exceto a principal (que já vem aberta)
  // Incluímos 'PJ' (tipo genérico para sócios PJ) na lista
  if (['PJ_FARMACIA', 'PJ_FARMACIA_EXT', 'PJ_OUTRA', 'PJ'].includes(type) && id !== cnpj.value) return true;
  // Pessoas (Sócios) podem expandir (para N4)
  if (type === 'PF') return true;
  return false;
});

const expansionLabel = computed(() => {
  if (!selectedNode.value) return '';
  if (expandedNodes.value.has(selectedNode.value.id)) return 'Já Expandido';
  if (['PJ_FARMACIA', 'PJ_FARMACIA_EXT', 'PJ_OUTRA', 'PJ'].includes(selectedNode.value.type)) return 'Expandir Sócios (N3)';
  if (selectedNode.value.type === 'PF') return 'Expandir Empresas (N4)';
  return 'Expandir';
});

// ── Paleta de cores por tipo de nó ─────────────────────────────────────────
const NODE_STYLES = {
  PJ_ALVO:     { bg: '#6366f1', border: '#818cf8', shape: 'roundrectangle', size: 88 },
  PF:          { bg: '#0ea5e9', border: '#38bdf8', shape: 'ellipse',        size: 64 },
  PJ_FARMACIA: { bg: '#10b981', border: '#34d399', shape: 'roundrectangle', size: 68 },
  PJ_FARMACIA_EXT: { bg: '#f59e0b', border: '#fbbf24', shape: 'roundrectangle', size: 64 },
  PJ_OUTRA:    { bg: '#d946ef', border: '#c026d3', shape: 'roundrectangle', size: 64 },
  EXPANDED:    { bg: '#64748b', border: '#94a3b8', shape: 'ellipse',        size: 52 }, 
  ES:          { bg: '#475569', border: '#64748b', shape: 'ellipse',        size: 64 },
};

const INITIAL_FIT_PADDING = 40; // Reduzido para aproveitar o máximo da largura do card
const REFIT_DELAY_MS = 80;

// ── Inicializa / Destrói o grafo ────────────────────────────────────────────
async function buildGraph(data) {
  if (!cyContainer.value || !data) return;
  observeGraphContainer();

  if (cyContainer.value) cyContainer.value.style.pointerEvents = 'none';

  // Para o layout — impede que agende novos RAFs
  if (currentLayout) {
    try { currentLayout.stop(); } catch (e) {}
    currentLayout = null;
  }
  if (cy) {
    try { cy.stop(); } catch (e) {}
    // Drena o RAF pendente antes de destruir: o callback do cose já agendado
    // executa aqui, vê que está parado e encerra — sem acessar _private nulo
    await new Promise(resolve => requestAnimationFrame(resolve));
    try { cy.destroy(); } catch (e) {}
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
        is_ativo: n.is_ativo,
      }
    })),
    ...data.edges.map(e => ({
      data: {
        id: e.id,
        source: e.source,
        target: e.target,
        label: e.label || '',
        type: e.type,
        is_ativo: e.is_ativo,
      }
    })),
  ];

  // Oculta o canvas até o layout terminar — evita flash de nós empilhados em (0,0)
  if (cyContainer.value) cyContainer.value.style.opacity = '0';

  cy = cytoscape({
    container: cyContainer.value,
    elements,
    style: buildStylesheet(),
    layout: { name: 'preset' }, // sem auto-layout — controlamos manualmente via currentLayout
    minZoom: 0.35,
    maxZoom: 3,
  });

  // Força o reconhecimento do tamanho do container
  cy.resize();

  // Layout manual rastreado em currentLayout para poder ser cancelado antes do destroy
  currentLayout = cy.layout({
    name: 'cose',
    animate: true,
    animationDuration: 800,
    nodeRepulsion: () => 15000,
    idealEdgeLength: () => 80,
    gravity: 0.9,
    numIter: 1000,
    initialTemp: 1000,
    coolingFactor: 0.99,
    minTemp: 1.0,
    fit: false,
    randomize: true,
  });

  cy.one('layoutstop', () => {
    // Revela o grafo e reabilita eventos apenas após o layout terminar
    if (cyContainer.value) {
      cyContainer.value.style.opacity = '';
      cyContainer.value.style.pointerEvents = '';
    }
    fitGraphToView(INITIAL_FIT_PADDING);
  });
  currentLayout.run();

  cy.ready(() => {
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

// ── Lógica de Expansão (Nível 3) ─────────────────────────────────────────────
async function expandNode(nodeId) {
  if (isExpanding.value || expandedNodes.value.has(nodeId)) return;

  isExpanding.value = true;
  try {
    const expansionData = await cnpjDetailStore.expandNetworkNode(cnpj.value, nodeId);
    
    if (!expansionData || !expansionData.nodes || expansionData.nodes.length === 0) {
      expandedNodes.value.add(nodeId);
      return;
    }

    const newElements = [];
    expansionData.nodes.forEach(n => {
      if (!cy.getElementById(n.id).length) {
        newElements.push({
          group: 'nodes',
          data: {
            id: n.id,
            label: truncateLabel(n.label, 20),
            fullLabel: n.label,
            type: n.type || 'PF',
            is_expanded_node: true,
            is_ativo: n.is_ativo,
            razao_social: n.razao_social,
            municipio: n.municipio,
            uf: n.uf,
            situacao_rf: n.situacao_rf
          },
          position: { ...cy.getElementById(nodeId).position() }
        });
      }
    });

    expansionData.edges.forEach(e => {
      if (!cy.getElementById(e.id).length) {
        newElements.push({
          group: 'edges',
          data: {
            id: e.id,
            source: e.source,
            target: e.target,
            label: e.label,
            type: e.type,
            is_ativo: e.is_ativo
          }
        });
      }
    });

    if (newElements.length > 0) {
      const added = cy.add(newElements);
      if (currentLayout) { try { currentLayout.stop(); } catch (e) {} }
      currentLayout = added.union(cy.getElementById(nodeId)).layout({
        name: 'cose',
        animate: true,
        animationDuration: 600,
        randomize: false,
        fit: false,
        nodeRepulsion: () => 8000,
        idealEdgeLength: () => 60,
      });
      currentLayout.run();
      
      // Destaca vizinhos do nó expandido
      cy.elements().removeClass('faded highlighted');
      const neighborhood = cy.getElementById(nodeId).closedNeighborhood();
      cy.elements().not(neighborhood).addClass('faded');
      neighborhood.addClass('highlighted');
    }
    expandedNodes.value.add(nodeId);
  } catch (error) {
    console.error("Falha na expansão:", error);
  } finally {
    isExpanding.value = false;
  }
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

  // Estilo específico para Sócios PJ (para não ficarem sem estilo se vierem como 'PJ')
  styles.push({
    selector: 'node[type="PJ"]',
    style: {
      'background-color': '#d946ef',
      'border-color': '#c026d3',
      'shape': 'roundrectangle',
      'width': 64,
      'height': 64 * 0.68,
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
  if (!cy) return;
  if (currentLayout) { try { currentLayout.stop(); } catch (e) {} }
  currentLayout = cy.layout({
    name: 'cose', animate: true, animationDuration: 600,
    nodeRepulsion: () => 8000, idealEdgeLength: () => 120,
    gravity: 1.2, numIter: 800, fit: false,
  });
  currentLayout.run();
  cy.one('layoutstop', () => fitGraphToView(INITIAL_FIT_PADDING));
}

// ── Watchers ────────────────────────────────────────────────────────────────
watch(networkData, async (data) => {
  if (data) {
    await nextTick();
    await buildGraph(data);
  }
}, { immediate: true });

onMounted(async () => {
  if (!networkData.value) {
    cnpjDetailStore.fetchNetwork(cnpj.value);
  } else {
    await nextTick();
    observeGraphContainer();
    await buildGraph(networkData.value);
  }
});

onBeforeUnmount(() => {
  resizeObserver?.disconnect();
  resizeObserver = null;
  cy?.destroy();
  cy = null;
});

onActivated(() => {
  if (cy) {
    cy.resize();
  }
});



const typeLabels = {
  PJ_ALVO:     { label: 'CNPJ em Análise', color: '#6366f1' },
  PF:          { label: 'Pessoa Física',   color: '#0ea5e9' },
  PJ_FARMACIA: { label: 'Farmácia FP',     color: '#10b981' },
  PJ_FARMACIA_EXT: { label: 'Outra Farmácia (Não FP)', color: '#f59e0b' },
  PJ_OUTRA:    { label: 'Outra Empresa',   color: '#d946ef' }, 
  PJ:          { label: 'Sócio PJ (Holding)', color: '#d946ef' },
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

          <!-- Toolbar de Investigação (canto superior esquerdo) -->
          <div class="toolbar-batch">
            <button class="tool-btn" @click="resetToN2" :disabled="isBatchExpanding" v-tooltip.bottom="'Voltar ao estado inicial (apenas N2)'">
               <i class="pi pi-refresh" />
               <span>Nível 2</span>
            </button>
            <div class="tool-sep"></div>
            <button class="tool-btn main" @click="expandBatch('N3')" :disabled="isBatchExpanding" v-tooltip.bottom="'Carregar sócios das empresas (N3)'">
               <i :class="isBatchExpanding ? 'pi pi-spin pi-spinner' : 'pi pi-users'" />
               <span>Nível 3</span>
            </button>
            <button class="tool-btn main" @click="expandBatch('N4')" :disabled="isBatchExpanding" v-tooltip.bottom="'Carregar sócios N3 + empresas deles (N4)'">
               <i :class="isBatchExpanding ? 'pi pi-spin pi-spinner' : 'pi pi-building'" />
               <span>Nível 4</span>
            </button>
            <div class="tool-sep"></div>
            <button class="tool-btn" :class="{ 'active': !showInactiveCompanies }" @click="toggleInactiveCompanies" v-tooltip.bottom="'Ocultar empresas baixadas/inativas (PJ)'">
               <i :class="showInactiveCompanies ? 'pi pi-building' : 'pi pi-building'" />
               <span>{{ showInactiveCompanies ? 'Emp. Inativas' : 'Emp. Inativas ✔' }}</span>
            </button>
            <button class="tool-btn" :class="{ 'active': !showInactivePartners }" @click="toggleInactivePartners" v-tooltip.bottom="'Ocultar sócios sem vínculo ativo (PF)'">
               <i class="pi pi-user" />
               <span>{{ showInactivePartners ? 'Sócios Inativos' : 'Sócios Inativos ✔' }}</span>
            </button>
            <button class="tool-btn" @click="exportPng" v-tooltip.bottom="'Exportar imagem PNG'">
               <i class="pi pi-camera" />
            </button>
          </div>

          <!-- Controles de Zoom (canto inferior direito) ───── -->
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
            
            <!-- Ações de Expansão -->
            <div v-if="canExpand" class="panel-actions mt-3">
              <button 
                class="expand-btn" 
                :disabled="isExpanding || expandedNodes.has(selectedNode.id)"
                @click="expandNode(selectedNode.id)"
              >
                <i :class="isExpanding ? 'pi pi-spin pi-spinner' : 'pi pi-plus-circle'" />
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

/* Toolbar de Investigação (topo central) ──────────── */
.toolbar-batch {
  position: absolute;
  top: 1rem;
  left: 1rem;
  transform: none;
  background: rgba(15, 23, 42, 0.88);
  backdrop-filter: blur(10px);
  border: 1px solid rgba(255, 255, 255, 0.1);
  border-radius: 50px;
  padding: 6px 10px;
  display: flex;
  align-items: center;
  gap: 4px;
  box-shadow: 0 8px 24px -4px rgba(0, 0, 0, 0.4);
  z-index: 10;
  white-space: nowrap;
}

.tool-btn {
  background: transparent;
  border: none;
  color: #94a3b8;
  padding: 6px 12px;
  border-radius: 20px;
  cursor: pointer;
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 0.72rem;
  font-weight: 600;
  transition: all 0.2s ease;
  white-space: nowrap;
}

.tool-btn:hover:not(:disabled) {
  background: rgba(255, 255, 255, 0.08);
  color: white;
}

.tool-btn.main {
  background: var(--primary-color);
  color: white;
  box-shadow: 0 4px 12px rgba(99, 102, 241, 0.35);
}

.tool-btn.main:hover:not(:disabled) {
  background: #818cf8;
  transform: translateY(-1px);
  box-shadow: 0 6px 16px rgba(99, 102, 241, 0.45);
}

.tool-btn.active {
  background: rgba(239, 68, 68, 0.15);
  color: #f87171;
}

.tool-sep {
  width: 1px;
  height: 18px;
  background: rgba(255, 255, 255, 0.12);
  margin: 0 2px;
}

.tool-btn:disabled {
  opacity: 0.45;
  cursor: not-allowed;
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
  background: rgba(15, 23, 42, 0.85);
  backdrop-filter: blur(10px);
  border: 1px solid var(--tabs-border);
  border-radius: 12px;
  padding: 0.5rem;
  gap: 0.4rem;
  box-shadow: 0 8px 24px -4px rgba(0, 0, 0, 0.35);
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
  box-shadow: 0 8px 32px rgba(0,0,0,0.25);
  pointer-events: auto;
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
  font-weight: 700;
  cursor: pointer;
  transition: all 0.2s;
  box-shadow: 0 4px 12px color-mix(in srgb, var(--primary-color) 30%, transparent);
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

.mt-3 { margin-top: 0.75rem; }

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
