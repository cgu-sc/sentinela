# Sentinela - Advanced Development Guidelines

## 1. Arquitetura Fullstack e Tech Stack
- **Frontend**: Vue 3 (Composition API) + Pinia + PrimeVue 3 + ECharts.
- **Backend**: FastAPI (Python 3.10+) + SQLAlchemy + Pydantic.
- **Ambiente**: Híbrido (Web + Desktop). Priorize compatibilidade com Windows e caminhos de rede.

## 2. Zero Hardcoding: O Ecossistema de Configurações
NUNCA utilize valores fixos nos componentes. Consulte sempre o arquivo correspondente em `frontend/src/config/`:

- **API (`api.js`)**: Todos os endpoints devem ser registrados aqui. Use a versão exportada (`API_ENDPOINTS`).
- **Constantes Gerais (`constants.js`)**: Fonte para labels (KPI_LABEL_MAP), prioridades (KPI_PRIORITY_ORDER) e timings do sistema.
- **Temas de Interface (`themeConfig.js`)**: Definições de cores de superfície (Light/Dark) e paletas de cores primárias.
- **Estilo de KPIs (`uiConfig.js`)**: Mapeamento de ícones e cores específicas para cada métrica estratécia (ex: 'VALOR TOTAL DE VENDAS').
- **Risco e Performance (`riskConfig.js`)**: Única fonte de verdade para thresholds de risco (Critical, High, Medium, Low) e suas cores associadas em badges e alertas.
- **Gráficos (`chartTheme.js`)**: SEMPRE use o hook `useChartTheme` para configurar ECharts. Ele garante que os gráficos mudem de cor automaticamente ao trocar o tema do sistema.
- **Opções de Filtro (`filterOptions.js`)**: Contém as listas estáticas para os Dropdowns (Situação RF, Porte, Grande Rede, etc.).

## 3. Reutilização de Código: Composables e Stores
- **Composables**: Utilize os hooks em `frontend/src/composables/`. 
  - `useFilterParameters`: Obrigatório para sincronizar filtros da UI com requisições de API.
- **Pinia Stores**: Utilize as stores em `src/stores/` para estado global. 
  - **DICA**: Getters reativos (como `enrichedKpis`) devem ser usados para injetar ícones e cores configurados no `uiConfig.js` nos dados brutos da API.

## 4. UI/UX e Design System
- **Variáveis CSS**: Use `var(--bg-color)`, `var(--text-color)`, `var(--primary-color)`. Não use hexadecimais no CSS dos componentes.
- **Arbflow Design**: Mantenha a estética de glassmorphism, bordas suaves e as animações definidas em `animations.css`.
- **Feedback**: Utilize `ToastService` para mensagens do sistema e estados de loading durante requisições de API.

## 5. Padrões de Backend (Python/FastAPI)
- **Camadas**: Separação clara entre `endpoints`, `services` e `schemas` (Pydantic). 
- **Tipagem e Documentação**: SEMPRE utilize Type Hinting. Use Docstrings no estilo Google/NumPy para explicar parâmetros e retornos.

## 6. Git e Padronização
- **Nomenclatura**: PascalCase para componentes Vue, snake_case para arquivos/funções Python.
- **Commits**: Utilize Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`).
- **Documentação**: Use JSDoc para funções JS críticas, focando no "porquê" de lógicas complexas.
