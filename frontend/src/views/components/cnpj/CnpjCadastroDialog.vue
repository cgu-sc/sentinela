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
  return descricao ? `${code} - ${descricao}` : code;
};

const formattedAddress = computed(() => {
  const cadastro = props.cadastro;
  if (!cadastro) return emptyValue;

  const main = [cadastro.tipo_logradouro, cadastro.logradouro].filter(Boolean).join(" ");
  const number = cadastro.numero ? `, ${cadastro.numero}` : "";
  const complement = cadastro.complemento ? ` - ${cadastro.complemento}` : "";
  const neighborhood = cadastro.bairro ? ` · ${cadastro.bairro}` : "";
  const cep = cadastro.cep ? ` · CEP: ${cadastro.cep}` : "";
  const address = `${main}${number}${complement}${neighborhood}${cep}`.trim();

  return address || emptyValue;
});

const cnaesSecundarios = computed(() => props.cadastro?.cnaes_secundarios ?? []);

const estabelecimentoTipo = computed(() => {
  if (props.cadastro?.is_matriz === true) return "Matriz";
  if (props.cadastro?.is_matriz === false) return "Filial";
  return emptyValue;
});

const cnaeAlertLabel = computed(() =>
  props.cadastro?.is_cnae_farmacia_ausente
    ? "CNAE incompatível com atividade farmacêutica"
    : "CNAE compatível identificado",
);
</script>

<template>
  <Dialog
    v-model:visible="dialogVisible"
    modal
    header="Dados cadastrais"
    :style="{ width: '780px' }"
    class="cnpj-cadastro-dialog"
  >
    <div class="cadastro-dialog">
      <section class="cadastro-section">
        <div class="section-heading">
          <i class="pi pi-building" />
          <span>Identificação</span>
        </div>

        <div class="field-grid">
          <div class="field-item">
            <span>CNPJ</span>
            <strong>{{ formatCnpj(cnpj) }}</strong>
          </div>
          <div class="field-item">
            <span>Tipo</span>
            <strong>{{ estabelecimentoTipo }}</strong>
          </div>
          <div class="field-item field-item--wide">
            <span>Razão social</span>
            <strong>{{ displayValue(cadastro?.razao_social) }}</strong>
          </div>
          <div class="field-item field-item--wide">
            <span>Nome fantasia</span>
            <strong>{{ displayValue(cadastro?.nome_fantasia) }}</strong>
          </div>
        </div>
      </section>

      <section class="cadastro-section">
        <div class="section-heading">
          <i class="pi pi-id-card" />
          <span>Situação e porte</span>
        </div>

        <div class="field-grid">
          <div class="field-item">
            <span>Receita Federal</span>
            <strong>{{ displayValue(cadastro?.situacao_rf ?? cnpjData?.situacao_rf) }}</strong>
          </div>
          <div class="field-item">
            <span>Porte</span>
            <strong>{{ displayValue(cadastro?.porte_empresa ?? cnpjData?.porte_empresa) }}</strong>
          </div>
          <div class="field-item">
            <span>Natureza jurídica</span>
            <strong>{{ displayValue(cadastro?.natureza_juridica) }}</strong>
          </div>
          <div class="field-item">
            <span>Data de abertura</span>
            <strong>{{ formatDate(cadastro?.data_abertura) }}</strong>
          </div>
          <div class="field-item">
            <span>Capital social</span>
            <strong>{{ cadastro?.capital_social == null ? emptyValue : formatCurrencyFull(cadastro.capital_social) }}</strong>
          </div>
          <div class="field-item">
            <span>Classificação CNAE</span>
            <strong
              class="cnae-status"
              :class="{ 'cnae-status--alert': cadastro?.is_cnae_farmacia_ausente }"
            >
              {{ cnaeAlertLabel }}
            </strong>
          </div>
        </div>
      </section>

      <section class="cadastro-section">
        <div class="section-heading">
          <i class="pi pi-map-marker" />
          <span>Localização</span>
        </div>

        <div class="field-grid">
          <div class="field-item field-item--wide">
            <span>Endereço</span>
            <strong>{{ formattedAddress }}</strong>
          </div>
          <div class="field-item">
            <span>Município</span>
            <strong>{{ displayValue(geoData?.no_municipio ?? cadastro?.municipio) }}</strong>
          </div>
          <div class="field-item">
            <span>UF</span>
            <strong>{{ displayValue(geoData?.sg_uf ?? cadastro?.uf) }}</strong>
          </div>
          <div class="field-item">
            <span>IBGE</span>
            <strong>{{ displayValue(geoData?.id_ibge7 ?? cadastro?.id_ibge7) }}</strong>
          </div>
          <div class="field-item">
            <span>Região de saúde</span>
            <strong>{{ displayValue(geoData?.no_regiao_saude) }}</strong>
          </div>
        </div>
      </section>

      <section class="cadastro-section">
        <div class="section-heading">
          <i class="pi pi-list" />
          <span>CNAEs</span>
        </div>

        <div class="cnae-block">
          <div class="field-item field-item--wide">
            <span>Principal</span>
            <strong>{{ formatCnae(cadastro?.id_cnae_principal, cadastro?.cnae_principal) }}</strong>
          </div>

          <div class="secondary-cnaes">
            <span>CNAEs secundários</span>
            <div v-if="cnaesSecundarios.length" class="secondary-cnae-list">
              <span
                v-for="cnae in cnaesSecundarios"
                :key="cnae.id_cnae"
                class="secondary-cnae-item"
              >
                {{ formatCnae(cnae.id_cnae, cnae.descricao) }}
              </span>
            </div>
            <strong v-else>{{ emptyValue }}</strong>
          </div>
        </div>
      </section>

      <section class="cadastro-section">
        <div class="section-heading">
          <i class="pi pi-phone" />
          <span>Contato</span>
        </div>

        <div class="field-grid">
          <div class="field-item">
            <span>Telefone 1</span>
            <strong>{{ displayValue(cadastro?.telefone_1) }}</strong>
          </div>
          <div class="field-item">
            <span>Telefone 2</span>
            <strong>{{ displayValue(cadastro?.telefone_2) }}</strong>
          </div>
          <div class="field-item field-item--wide">
            <span>E-mail</span>
            <strong>{{ displayValue(cadastro?.email) }}</strong>
          </div>
        </div>
      </section>
    </div>
  </Dialog>
</template>

<style scoped>
.cadastro-dialog {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.cadastro-section {
  display: flex;
  flex-direction: column;
  gap: 0.65rem;
  padding-bottom: 0.85rem;
  border-bottom: 1px solid var(--card-border);
}

.cadastro-section:last-child {
  padding-bottom: 0;
  border-bottom: 0;
}

.section-heading {
  display: inline-flex;
  align-items: center;
  gap: 0.45rem;
  color: var(--text-color);
  font-size: 0.78rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.section-heading i {
  color: var(--primary-color);
  font-size: 0.85rem;
}

.field-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 0.7rem 1rem;
}

.field-item,
.secondary-cnaes {
  display: flex;
  min-width: 0;
  flex-direction: column;
  gap: 0.25rem;
}

.field-item--wide {
  grid-column: span 2;
}

.field-item span,
.secondary-cnaes > span {
  color: var(--text-muted);
  font-size: 0.68rem;
  font-weight: 700;
  text-transform: uppercase;
  letter-spacing: 0.04em;
}

.field-item strong,
.secondary-cnaes strong {
  color: var(--text-color);
  font-size: 0.84rem;
  font-weight: 600;
  line-height: 1.35;
  overflow-wrap: anywhere;
}

.cnae-status {
  color: var(--risk-low);
}

.cnae-status--alert {
  color: var(--risk-high);
}

.cnae-block {
  display: flex;
  flex-direction: column;
  gap: 0.8rem;
}

.secondary-cnae-list {
  display: flex;
  flex-wrap: wrap;
  gap: 0.45rem;
}

.secondary-cnae-item {
  display: inline-flex;
  align-items: center;
  max-width: 100%;
  min-height: 26px;
  padding: 0.25rem 0.45rem;
  border: 1px solid var(--card-border);
  border-radius: 6px;
  background: color-mix(in srgb, var(--text-muted) 5%, transparent);
  color: var(--text-color);
  font-size: 0.75rem;
  font-weight: 600;
  overflow-wrap: anywhere;
}
</style>
