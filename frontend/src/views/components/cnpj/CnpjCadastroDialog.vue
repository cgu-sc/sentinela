<script setup>
import { computed } from "vue";
import Dialog from "primevue/dialog";
import { useFormatting } from "@/composables/useFormatting";

const props = defineProps({
  visible: { type: Boolean, default: false },
  cnpj: { type: String, required: true },
  cadastro: { type: Object, default: null },
  cnpjData: { type: Object, default: null },
  geoData: { type: Object, default: null },
});

const emit = defineEmits(["update:visible"]);

const { formatCurrencyFull, formatCnpj } = useFormatting();

const dialogVisible = computed({
  get: () => props.visible,
  set: (value) => emit("update:visible", value),
});

const emptyValue = "—";

const displayValue = (value) => {
  if (value === null || value === undefined || value === "") return emptyValue;
  return value;
};

const formatDate = (value) => {
  if (!value) return emptyValue;
  const dateText = String(value).slice(0, 10);
  const match = dateText.match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!match) return String(value);
  return `${match[3]}/${match[2]}/${match[1]}`;
};

const formatCnae = (id, descricao) => {
  const code = id ? String(id) : emptyValue;
  return descricao ? `${code} — ${descricao}` : code;
};

const formatPercent = (value) =>
  `${Number(value ?? 0).toLocaleString("pt-BR", {
    minimumFractionDigits: 1,
    maximumFractionDigits: 1,
  })}%`;

const formattedAddress = computed(() => {
  const cadastro = props.cadastro;
  if (!cadastro) return emptyValue;

  const main = [cadastro.tipo_logradouro, cadastro.logradouro].filter(Boolean).join(" ");
  const number = cadastro.numero ? `, ${cadastro.numero}` : "";
  const complement = cadastro.complemento ? ` — ${cadastro.complemento}` : "";
  const neighborhood = cadastro.bairro ? ` · ${cadastro.bairro}` : "";
  const cep = cadastro.cep ? ` · CEP ${cadastro.cep}` : "";
  const address = `${main}${number}${complement}${neighborhood}${cep}`.trim();

  return address || emptyValue;
});

const cnaesSecundarios = computed(() => props.cadastro?.cnaes_secundarios ?? []);

const estabelecimentoTipo = computed(() => {
  if (props.cadastro?.is_matriz === true) return "Matriz";
  if (props.cadastro?.is_matriz === false) return "Filial";
  return emptyValue;
});

const cnaeCompativel = computed(() =>
  !props.cadastro?.is_cnae_incompativel_farmaceutico,
);


</script>

<template>
  <Dialog
    v-model:visible="dialogVisible"
    modal
    :style="{ width: '820px', maxWidth: '95vw' }"
    class="cnpj-cadastro-dialog"
    :pt="{
      header: { class: 'cadastro-dialog-header-slot' },
    }"
  >
    <template #header>
      <div class="dialog-custom-header">
        <div class="dialog-header-icon">
          <i class="pi pi-id-card" />
        </div>
        <div class="dialog-header-text">
          <span class="dialog-header-title">Dados Cadastrais</span>
          <span class="dialog-header-cnpj">{{ formatCnpj(cnpj) }}</span>
        </div>
      </div>
    </template>

    <div class="cadastro-dialog">

      <!-- ── SEÇÃO 1: IDENTIFICAÇÃO ─────────────────────── -->
      <section class="cadastro-section">
        <div class="section-heading">
          <i class="pi pi-building" />
          <span>Identificação</span>
        </div>

        <div class="field-grid">
          <div class="field-card">
            <span class="field-label">CNPJ</span>
            <strong class="field-value field-value--mono">{{ formatCnpj(cnpj) }}</strong>
          </div>
          <div class="field-card">
            <span class="field-label">Tipo</span>
            <div class="field-badge-wrap">
              <span class="field-badge field-badge--neutral">{{ estabelecimentoTipo }}</span>
            </div>
          </div>
          <div class="field-card field-card--wide">
            <span class="field-label">Razão Social</span>
            <strong class="field-value">{{ displayValue(cadastro?.razao_social) }}</strong>
          </div>
          <div class="field-card field-card--wide">
            <span class="field-label">Nome Fantasia</span>
            <strong class="field-value">{{ displayValue(cadastro?.nome_fantasia) }}</strong>
          </div>
        </div>
      </section>

      <!-- ── SEÇÃO 2: SITUAÇÃO E PORTE ──────────────────── -->
      <section class="cadastro-section">
        <div class="section-heading">
          <i class="pi pi-chart-bar" />
          <span>Situação e Porte</span>
        </div>

        <div class="field-grid">
          <div class="field-card">
            <span class="field-label">Receita Federal</span>
            <div class="field-badge-wrap">
              <span
                class="field-badge"
                :class="
                  (cadastro?.situacao_rf ?? cnpjData?.situacao_rf) === 'ATIVA'
                    ? 'field-badge--success'
                    : 'field-badge--warning'
                "
              >
                {{ displayValue(cadastro?.situacao_rf ?? cnpjData?.situacao_rf) }}
              </span>
            </div>
          </div>
          <div class="field-card">
            <span class="field-label">Porte</span>
            <strong class="field-value">{{ displayValue(cadastro?.porte_empresa ?? cnpjData?.porte_empresa) }}</strong>
          </div>
          <div class="field-card">
            <span class="field-label">Grande Rede</span>
            <div class="field-badge-wrap">
              <span
                class="field-badge"
                :class="cnpjData?.is_grande_rede ? 'field-badge--info' : 'field-badge--neutral'"
              >
                <i :class="cnpjData?.is_grande_rede ? 'pi pi-sitemap' : 'pi pi-minus-circle'" />
                {{ cnpjData?.is_grande_rede ? 'Sim' : 'Não' }}
              </span>
            </div>
          </div>
          <div class="field-card">
            <span class="field-label">Estabelecimentos na Rede</span>
            <strong class="field-value">
              {{ cnpjData?.qtd_estabelecimentos_rede != null ? cnpjData.qtd_estabelecimentos_rede : emptyValue }}
            </strong>
          </div>
          <div class="field-card">
            <span class="field-label">Natureza Jurídica</span>
            <strong class="field-value">{{ displayValue(cadastro?.natureza_juridica) }}</strong>
          </div>
          <div class="field-card">
            <span class="field-label">Data de Abertura</span>
            <strong class="field-value">{{ formatDate(cadastro?.data_abertura) }}</strong>
          </div>
          <div class="field-card">
            <span class="field-label">Capital Social</span>
            <strong class="field-value">
              {{ cadastro?.capital_social == null ? emptyValue : formatCurrencyFull(cadastro.capital_social) }}
            </strong>
          </div>
          <div class="field-card">
            <span class="field-label">Classificação CNAE</span>
            <div class="field-badge-wrap">
              <span
                class="field-badge"
                :class="cnaeCompativel ? 'field-badge--success' : 'field-badge--danger'"
              >
                <i :class="cnaeCompativel ? 'pi pi-check' : 'pi pi-times'" />
                {{ cnaeCompativel ? "Compatível" : "Incompatível" }}
              </span>
            </div>
          </div>
        </div>
      </section>

      <!-- ── SEÇÃO 3: LOCALIZAÇÃO ────────────────────────── -->
      <section class="cadastro-section">
        <div class="section-heading">
          <i class="pi pi-map-marker" />
          <span>Localização</span>
        </div>

        <div class="field-card field-card--address">
          <span class="field-label">Endereço completo</span>
          <strong class="field-value field-value--address">
            <i class="pi pi-home" />
            {{ formattedAddress }}
          </strong>
        </div>

        <div class="field-grid field-grid--mt">
          <div class="field-card">
            <span class="field-label">Município</span>
            <strong class="field-value">{{ displayValue(geoData?.no_municipio ?? cadastro?.municipio) }}</strong>
          </div>
          <div class="field-card">
            <span class="field-label">UF</span>
            <strong class="field-value">{{ displayValue(geoData?.sg_uf ?? cadastro?.uf) }}</strong>
          </div>
          <div class="field-card">
            <span class="field-label">Código IBGE</span>
            <strong class="field-value field-value--mono">{{ displayValue(geoData?.id_ibge7 ?? cadastro?.id_ibge7) }}</strong>
          </div>
          <div class="field-card">
            <span class="field-label">Região de Saúde</span>
            <strong class="field-value">{{ displayValue(geoData?.no_regiao_saude) }}</strong>
          </div>

        </div>
      </section>

      <!-- ── SEÇÃO 4: CNAEs ──────────────────────────────── -->
      <section class="cadastro-section">
        <div class="section-heading">
          <i class="pi pi-list" />
          <span>CNAEs</span>
        </div>

        <div class="cnae-block">
          <div class="field-card field-card--wide">
            <span class="field-label">Principal</span>
            <strong class="field-value">{{ formatCnae(cadastro?.id_cnae_principal, cadastro?.cnae_principal) }}</strong>
          </div>

          <div class="cnae-secondary-block">
            <span class="field-label">CNAEs Secundários</span>
            <div v-if="cnaesSecundarios.length" class="secondary-cnae-list">
              <span
                v-for="cnae in cnaesSecundarios"
                :key="cnae.id_cnae"
                class="secondary-cnae-item"
              >
                {{ formatCnae(cnae.id_cnae, cnae.descricao) }}
              </span>
            </div>
            <strong v-else class="field-value">{{ emptyValue }}</strong>
          </div>
        </div>
      </section>

      <!-- ── SEÇÃO 5: CONTATO ────────────────────────────── -->
      <section class="cadastro-section cadastro-section--last">
        <div class="section-heading">
          <i class="pi pi-phone" />
          <span>Contato</span>
        </div>

        <div class="field-grid">
          <div class="field-card">
            <span class="field-label">Telefone 1</span>
            <strong class="field-value field-value--mono">{{ displayValue(cadastro?.telefone_1) }}</strong>
          </div>
          <div class="field-card">
            <span class="field-label">Telefone 2</span>
            <strong class="field-value field-value--mono">{{ displayValue(cadastro?.telefone_2) }}</strong>
          </div>
          <div class="field-card field-card--wide">
            <span class="field-label">E-mail</span>
            <strong class="field-value">{{ displayValue(cadastro?.email) }}</strong>
          </div>
        </div>
      </section>

    </div>
  </Dialog>
</template>

<style scoped>
/* ── HEADER CUSTOMIZADO ──────────────────────────────── */
.dialog-custom-header {
  display: flex;
  align-items: center;
  gap: 0.85rem;
}

.dialog-header-icon {
  display: flex;
  align-items: center;
  justify-content: center;
  width: 38px;
  height: 38px;
  border-radius: 10px;
  background: linear-gradient(
    135deg,
    color-mix(in srgb, var(--primary-color) 18%, transparent),
    color-mix(in srgb, var(--primary-color) 8%, transparent)
  );
  border: 1px solid color-mix(in srgb, var(--primary-color) 25%, transparent);
  flex-shrink: 0;
}

.dialog-header-icon i {
  font-size: 1.1rem;
  color: var(--primary-color);
}

.dialog-header-text {
  display: flex;
  flex-direction: column;
  gap: 0.05rem;
}

.dialog-header-title {
  font-size: 1rem;
  font-weight: 700;
  color: var(--text-color-85);
  letter-spacing: -0.01em;
}

.dialog-header-cnpj {
  font-size: 0.75rem;
  font-weight: 600;
  color: var(--text-muted);
  font-family: "Inter", monospace;
  letter-spacing: 0.03em;
}

/* ── CORPO DO DIÁLOGO ────────────────────────────────── */
.cadastro-dialog {
  display: flex;
  flex-direction: column;
  gap: 0;
  padding-bottom: 0.25rem;
}

/* ── SEÇÕES ──────────────────────────────────────────── */
.cadastro-section {
  display: flex;
  flex-direction: column;
  gap: 0.55rem;
  padding: 0.7rem 0;
  border-bottom: 1px solid var(--card-border);
  position: relative;
}

.cadastro-section--last {
  border-bottom: none;
  padding-bottom: 0;
}

.section-heading {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.72rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.07em;
  color: var(--text-muted);
}

.section-heading i {
  font-size: 0.82rem;
  color: var(--primary-color);
  opacity: 0.8;
}

/* ── GRADE DE CAMPOS ─────────────────────────────────── */
.field-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0.4rem;
}

.field-grid--mt {
  margin-top: 0;
}

/* ── CARD DE CAMPO ───────────────────────────────────── */
.field-card {
  display: flex;
  flex-direction: column;
  gap: 0.2rem;
  padding: 0.4rem 0.65rem;
  background: color-mix(in srgb, var(--text-muted) 4%, transparent);
  border: 1px solid color-mix(in srgb, var(--card-border) 70%, transparent);
  border-radius: 7px;
  transition: border-color 0.2s ease;
}

.field-card:hover {
  border-color: color-mix(in srgb, var(--primary-color) 20%, var(--card-border));
}

.field-card--wide {
  grid-column: span 2;
}

.field-card--address {
  width: 100%;
}

/* ── LABELS ──────────────────────────────────────────── */
.field-label {
  color: var(--text-muted);
  font-size: 0.66rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.05em;
  white-space: nowrap;
}

/* ── VALORES ─────────────────────────────────────────── */
.field-value {
  color: var(--text-color-85);
  font-size: 0.85rem;
  font-weight: 600;
  line-height: 1.4;
  overflow-wrap: anywhere;
}

.field-value--mono {
  font-family: "Inter", monospace;
  letter-spacing: 0.03em;
}

.field-value--address {
  display: flex;
  align-items: flex-start;
  gap: 0.45rem;
}

.field-value--address i {
  font-size: 0.78rem;
  color: var(--primary-color);
  opacity: 0.7;
  margin-top: 0.15rem;
  flex-shrink: 0;
}

/* ── BADGES DE STATUS ────────────────────────────────── */
.field-badge-wrap {
  display: flex;
  align-items: center;
}

.field-badge {
  display: inline-flex;
  align-items: center;
  gap: 0.3rem;
  padding: 0.2rem 0.55rem;
  border-radius: 5px;
  font-size: 0.73rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
  border: 1px solid transparent;
  white-space: nowrap;
}

.field-badge i {
  font-size: 0.65rem;
}

.field-badge--success {
  color: var(--risk-low);
  background: color-mix(in srgb, var(--risk-low) 10%, transparent);
  border-color: color-mix(in srgb, var(--risk-low) 25%, transparent);
}

.field-badge--warning {
  color: var(--risk-medium);
  background: color-mix(in srgb, var(--risk-medium) 10%, transparent);
  border-color: color-mix(in srgb, var(--risk-medium) 25%, transparent);
}

.field-badge--danger {
  color: var(--risk-high);
  background: color-mix(in srgb, var(--risk-high) 10%, transparent);
  border-color: color-mix(in srgb, var(--risk-high) 25%, transparent);
}

.field-badge--neutral {
  color: var(--text-secondary);
  background: color-mix(in srgb, var(--text-muted) 10%, transparent);
  border-color: color-mix(in srgb, var(--text-muted) 20%, transparent);
}

.field-badge--info {
  color: var(--primary-color);
  background: color-mix(in srgb, var(--primary-color) 10%, transparent);
  border-color: color-mix(in srgb, var(--primary-color) 25%, transparent);
}

/* ── BLOCO DE CNAEs ──────────────────────────────────── */
.cnae-block {
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
}

.cnae-secondary-block {
  display: flex;
  flex-direction: column;
  gap: 0.3rem;
}

.secondary-cnae-list {
  display: flex;
  flex-wrap: wrap;
  gap: 0.3rem;
}

.secondary-cnae-item {
  display: inline-flex;
  align-items: center;
  padding: 0.16rem 0.45rem;
  border: 1px solid var(--card-border);
  border-radius: 5px;
  background: color-mix(in srgb, var(--text-muted) 5%, transparent);
  color: var(--text-color-85);
  font-size: 0.72rem;
  font-weight: 600;
  overflow-wrap: anywhere;
  transition: border-color 0.2s ease, background 0.2s ease;
}

.secondary-cnae-item:hover {
  border-color: color-mix(in srgb, var(--primary-color) 30%, transparent);
  background: color-mix(in srgb, var(--primary-color) 5%, transparent);
}
</style>
