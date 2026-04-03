# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
npm run dev       # Start dev server (Vite, default port 5173)
npm run build     # Production build
npm run preview   # Preview production build
```

No test runner is configured. There is no lint script.

The backend API defaults to `http://127.0.0.1:8002`. Override with `VITE_API_URL` env var.

## Architecture

**SENTINELA** is a corporate audit analytics dashboard for pharmaceutical benefit auditing. It is a Vue 3 SPA using Vite, Pinia, Vue Router, PrimeVue (UI), and ECharts (charts).

### Two top-level modules (routes)

- **Consolidado** (`/`, `/dispersao`, `/municipio`, `/cnpj`, `/regional`, `/estabelecimento/:cnpj`) — Analysis views organized by geography and entity (national → UF → municipality → CNPJ/pharmacy).
- **Alvos** (`/alvos/cluster`, `/alvos/situacao`, `/alvos/variacao`, `/alvos/rede`) — Target identification and partner network analysis.

All routes are children of `AppLayout`, which provides the sidebar navigation, global filter panel, and a period slider.

### Boot sequence

`App.vue` runs a synchronization check on startup before rendering any view:
1. Polls `GET /api/v1/cache/status` — if idle, triggers `POST /api/v1/cache/refresh`
2. Polls until sync completes (1s interval)
3. Loads Pinia stores: analytics summary, risk factors, geo data, resultados
4. Shows `<router-view>` after an 800ms delay

### Pinia stores (`src/stores/`)

| Store | Purpose |
|---|---|
| `analytics.js` | KPI data, regional/municipality/CNPJ aggregates, financial evolution, risk factors |
| `filters.js` | All global filters (UF, região, município, porte, situação RF, etc.) with localStorage persistence and cascading reset logic |
| `theme.js` | Dark/light mode + palette ("azul" or "carbon"), applies CSS custom properties to `:root` |
| `geo.js` | Geographic data (states, health regions, municipalities) from `/api/v1/geo/localidades`; handles homonym disambiguation with "Nome\|UF" format |
| `resultados.js` | Full `resultado_sentinela` dataset cached in memory |
| `cnpjNav.js` | CNPJ navigation context between views |

### Composables (`src/composables/`)

Business logic is extracted into composables so views stay thin. Key ones:
- `useFetchAnalytics.js` — Orchestrates analytics API calls based on active filters
- `useSyncManager.js` — Manages data reload when filters change
- `useFilterParameters.js` — Builds query params from filter store state
- `useFormatting.js` / `useParsing.js` — Currency, percentage, date formatting
- `useChartStyles.js` — ECharts theme-aware styling helpers
- Domain-specific: `useEvolucaoFinanceira`, `useFalecidos`, `useIndicadores`, `usePrescritores`, `useRegional`, `useRiskMetrics`, `useMultiCnpjTimeline`, `useTableAggregation`, `useSliderPeriodLogic`

### Configuration (`src/config/`)

| File | Contents |
|---|---|
| `api.js` | All API endpoint URLs; dynamic endpoints are factory functions |
| `constants.js` | Audit period (Jul 2015–Dec 2024), filter defaults, timing constants, KPI label/icon/priority maps |
| `themeConfig.js` | Palette definitions (azul/carbon, light/dark variants) and CSS custom property tokens |
| `colors.js` | Shared color references |
| `riskConfig.js` | Risk band thresholds and display config |
| `filterOptions.js` | Dropdown option lists for filter controls |
| `uiConfig.js` | UI layout constants |
| `chartTheme.js` | ECharts global theme registration |

### Theme system

CSS custom properties are set on `:root` by `stores/theme.js`. Components reference variables like `var(--bg-color)`, `var(--text-primary)`, `var(--card-bg)`, etc. defined in `themeConfig.js`. The two palettes are **azul** (blue) and **carbon** (gold accents). Styles live in `src/assets/styles/` — `variables.css` defines base tokens, `global.css` resets, `components.css` component styles, `animations.css` boot overlay effects.

### View/component layout

Views under `src/views/consolidated/` use components from `src/views/consolidated/components/`. The CNPJ detail view (`CnpjDetailView.vue`) is tab-based with one component per tab (`CnpjTab*.vue`). PrimeVue's `DataTable` is the standard table component throughout.
