# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## REGRA CRÍTICA: Autorização Antes de Qualquer Alteração

**NUNCA edite, crie ou delete arquivos sem antes apresentar o plano ao usuário e receber autorização explícita.**

Antes de qualquer mudança de código:
1. Explique o que precisa ser feito e por quê.
2. Descreva quais arquivos serão afetados e o que mudará em cada um.
3. Aguarde o usuário dizer "ok", "pode fazer", "sim" ou equivalente.
4. Só então execute as alterações.

Diagnóstico e investigação (leitura de arquivos, buscas, análise) podem ser feitos livremente. A trava é apenas para **escrita**.

## Project Overview

**Sentinela** is an automated audit system for detecting irregularities in Brazil's Popular Pharmacy Program (PFPB), developed by CGU. It is a hybrid Web/Desktop application (Vue 3 SPA + FastAPI + PyWebView desktop wrapper).

---

## Commands

### Backend
```bash
# Install dependencies (Python 3.10+, requires ODBC Driver 17 for SQL Server)
pip install -r requirements.txt

# Run development server (port 8002)
python backend/main.py

# Health check
curl http://127.0.0.1:8002/saude
```

### Frontend
```bash
cd frontend

# Install dependencies
npm install

# Development server (port 5173, with hot reload)
npm run dev

# Production build → frontend/dist/
npm run build

# Preview production build
npm run preview
```

### Desktop Build
```bash
# Bundle into single .exe via PyInstaller
pyinstaller Sentinela.spec
```

There are no automated test suites defined; validation is done manually via the dev servers.

---

## Architecture

### Request Flow
```
Vue 3 SPA (port 5173)
  → Axios HTTP → FastAPI (port 8002)
    → Services (business logic)
      → SQLAlchemy → SQL Server (SDH-DIE-BD / temp_CGUSC, Windows Auth)
```

In production/desktop mode, the frontend is served as static files by FastAPI itself (from `frontend/dist/`).

### Backend Layers (`backend/`)
- `main.py` — FastAPI app setup, CORS, static file serving, cache preload on startup (`lifespan`)
- `database.py` — SQLAlchemy connection pool (10 connections, max overflow 20), ODBC Driver 17, Windows Trusted Auth
- `data_cache.py` — In-memory data cache loaded at startup to avoid repeated heavy queries
- `api/router.py` — Aggregates all sub-routers under `/api/v1/`
- `api/endpoints/` — HTTP route handlers (thin layer, only request/response)
- `api/services/` — All business logic and SQL queries (e.g., `analytics.py` is ~50KB of KPI calculations)
- `api/schemas/` — Pydantic models for request validation and response serialization

### Frontend Layers (`frontend/src/`)
- `config/` — **Single source of truth for all constants** (see Zero Hardcoding below)
- `stores/` — Pinia global state: `analytics`, `filters`, `geo`, `theme`, `cnpjNav`, `farmaciaLists`
- `composables/` — Reusable logic hooks (data fetching, formatting, filter sync, risk metrics, chart theming)
- `views/consolidated/` — Main navigation hierarchy: National → Regional → Municipality → CNPJ Detail (7 sub-tabs) → Indicators
- `router/` — Vue Router, history mode, single catch-all route for SPA

### View Hierarchy
The application has a drill-down structure:
1. `NationalAnalysisView` — National KPIs and map
2. `RegionalAnalysisView` — Per-UF breakdown
3. `MunicipalityAnalysisView` — Per-municipality analysis
4. `CnpjDetailView` — Pharmacy-level audit (7 sub-tabs: dispensações, risco, prescrições, etc.)
5. `IndicadoresAnalysisView` — Cross-cutting risk indicator analysis

---

## 1. Arquitetura Fullstack e Tech Stack
- **Frontend**: Vue 3 (Composition API) + Pinia + PrimeVue 3 + ECharts.
- **Backend**: FastAPI (Python 3.10+) + SQLAlchemy + Pydantic.
- **Ambiente**: Híbrido (Web + Desktop). Priorize compatibilidade com Windows e caminhos de rede.

## 2. Zero Hardcoding: O Ecossistema de Configurações
NUNCA utilize valores fixos nos componentes. Consulte sempre o arquivo correspondente em `frontend/src/config/`:

- **API (`api.js`)**: Todos os endpoints devem ser registrados aqui. Use a versão exportada (`API_ENDPOINTS`).
- **Constantes Gerais (`constants.js`)**: Fonte para labels (KPI_LABEL_MAP), prioridades (KPI_PRIORITY_ORDER) e timings do sistema.
- **Temas de Interface (`themeConfig.js`)**: Definições de cores de superfície (Light/Dark) e paletas de cores primárias.
- **Estilo de KPIs (`uiConfig.js`)**: Mapeamento de ícones e cores específicas para cada métrica estratégia (ex: 'VALOR TOTAL DE VENDAS').
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
- **RESTRIÇÕES DE FONTE**: NUNCA utilize fontes BOLD (`font-weight: 700`, `font-weight: 800`, `bold`). O peso máximo permitido é Semi-Bold (`600`) ou Medium (`500`). NUNCA utilize fontes do tipo MONO ou monospaced (ex: `font-variant-numeric: tabular-nums`, `font-family: monospace`), a não ser que explicitamente exigido para código puro.
- **Arbflow Design**: Mantenha a estética de glassmorphism, bordas suaves e as animações definidas em `animations.css`.
- **Feedback**: Utilize `ToastService` para mensagens do sistema e estados de loading durante requisições de API.

## 5. Padrões de Backend (Python/FastAPI)
- **Camadas**: Separação clara entre `endpoints`, `services` e `schemas` (Pydantic).
- **Tipagem e Documentação**: SEMPRE utilize Type Hinting. Use Docstrings no estilo Google/NumPy para explicar parâmetros e retornos.

## 6. Git e Padronização
- **Nomenclatura**: PascalCase para componentes Vue, snake_case para arquivos/funções Python.
- **Commits**: Utilize Conventional Commits (`feat:`, `fix:`, `refactor:`, `docs:`).
- **Documentação**: Use JSDoc para funções JS críticas, focando no "porquê" de lógicas complexas.
