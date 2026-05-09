<claude-mem-context>
# Memory Context

# [sentinela] recent context, 2026-05-09 4:12pm GMT-3

Legend: 🎯session 🔴bugfix 🟣feature 🔄refactor ✅change 🔵discovery ⚖️decision 🚨security_alert 🔐security_note
Format: ID TIME TYPE TITLE
Fetch details: get_observations([IDs]) | Search: mem-search skill

Stats: 50 obs (19.069t read) | 597.167t work | 97% savings

### May 7, 2026
105 11:40a 🔵 Nota Técnica Generation: Full Architecture of nota_tecnica.py
106 " 🔵 Frontend Wiring: generateNote Event Bubbles to Parent Component
107 " 🔵 preparação_dados.sql Already Contains fp.dados_socios Creation Script
108 11:44a 🔴 Added DISTINCT to fp.dados_socios Creation Query
109 11:50a 🔴 Fixed Incorrect Column Reference in fp.dados_socios Municipality Lookup
110 11:51a ✅ fp.dados_socios Now Includes Former Partners (dataExclusaoSociedade Filter Removed)
111 11:52a ✅ fp.dados_socios: WHERE Clause Removed Entirely — All Partners of All Pharmacies
112 12:02p 🔵 Nota Técnica Feature Needs Quadro Societário Integration
113 12:04p 🟣 fp.dados_socios Table Created with Optimized Column Types in preparação_dados.sql
114 12:07p 🔵 Analysis Request: Extend data_cache.py to Load dados_socios Data
115 12:08p 🔵 data_cache.py Architecture: Full Cache System Mapped
116 5:17p ⚖️ UF-partitioned batch processing strategy for Brazil-wide Farmácia Popular data
117 5:18p 🟣 CRM pipeline migrated to UF-partitioned source materialization
118 5:35p 🟣 crms_detalhado_loteado_test.sql gained auto-materialization of UF source
119 " 🔄 Pipeline versioning unified to single @pipeline_versao across all CRM scripts
120 " 🔄 Source table reference migrated from teste_mov_SC to crm_mov_fonte_atual throughout loteado script
121 " 🔵 crm_materializa_movimentacao_uf_test.sql is a new untracked file in the sentinela repo
122 6:23p 🔄 CRM Pre-Global Script Migrated from UF-Scoped Materialized Source to Full National Source
123 8:07p ✅ SQL Script: Change Column Type to SMALLINT
124 " ✅ SQL Column Cast Changed from INT to SMALLINT
125 " ✅ Additional INT→SMALLINT Cast for nu_prescricoes_medico_em_todos_estabelecimentos
126 8:09p 🔵 id_medico VARCHAR(20) Pattern Across Multiple SQL Scripts
127 " ✅ id_medico Column Size Reduced from VARCHAR(20) to VARCHAR(13) Across CRM Scripts
128 8:14p 🟣 SQL Test Extended to crm_prescricoes_todos_estabelecimentos
129 8:35p 🔵 CRM Único Temporal SQL Script — UF Handling Architecture
130 8:36p 🔵 CRM Único Temporal Script — UF Handling via Materialized Source Table
131 " 🟣 CRM Único Temporal Script Upgraded to Self-Contained Multi-UF National Pipeline
132 8:37p 🔵 Git Diff Reveals v1→v2 Migration: Source Changed from SC Test Table to National Sources
133 8:40p 🔴 UF Selection Query Wrapped in sp_executesql to Bypass Compile-Time GOTO Validation
### May 9, 2026
134 11:05a 🔵 Duplicate `get_dashboard_data` Functions in Two Service Files
135 " 🔵 Analytics Endpoint `/resumo` Signature Confirmed
136 11:06a 🔵 `analytics` Services Package Structure and `get_dashboard_data` Implementation Confirmed
137 " 🔵 `AnalyticsService` Wiring Confirmed Correct — Error Must Be Inside Function Body
138 " 🔵 Two Separate Dashboard Services Serve Different Endpoints
139 11:08a 🔴 Fixed Type Annotations for `cnpjs` and `regiao_id` Parameters in `get_dashboard_data`
140 11:09a 🔵 Same `Optional` Annotation Bug Found in `get_fator_risco_data`
141 " 🔴 Fixed `Optional[int]` Annotation for `regiao_id` in `get_fator_risco_data` and Revealed Additional Affected Functions
S59 Fix all `Optional` type annotation errors across analytics service functions — systemic `type = None` without `Optional` wrapper (May 9, 11:09 AM)
142 11:10a 🔵 Full Scope of `Optional` Annotation Bug Mapped Across `regional.py`
143 " 🔴 Fixed `Optional` Annotations on `get_regional_benchmarking` — All Four Params Updated
144 " 🔴 Fixed `id_regiao` Local Variable Typing in `get_regional_benchmarking`
S60 Fix all `Optional` type annotation errors across analytics services — systemic `type = None` without `Optional` wrapper (May 9, 11:10 AM)
145 " 🔴 Completed `Optional` Annotation Fixes Across All Regional Service Functions
S61 Fix Pyrefly type checker errors — bare `T = None` parameter annotations missing `Optional` wrapper across analytics service modules (May 9, 11:11 AM)
146 11:11a 🔴 Completed `Optional` Annotation Fixes for All Functions in `analytics/regional.py`
S62 Fix Pyrefly type checker errors in analytics package — bare `T = None` annotations missing `Optional` wrapper, plus inline import cleanup in dashboard.py (May 9, 11:11 AM)
S63 Fix all Pyrefly type checker errors across the analytics package in d:\sentinela\backend\ (May 9, 11:13 AM)
S64 Fix all Pyrefly type checker errors across the analytics package in d:\sentinela\backend\ (May 9, 11:13 AM)
S65 Fix all Pyrefly type checker errors in the analytics package (backend/api/services/analytics/) (May 9, 11:15 AM)
S66 Fix all Pyrefly type checker errors in the analytics package (backend/api/services/analytics/) (May 9, 11:16 AM)
S67 Fix Pyrefly type checker errors in analytics package — nota_tecnica.py final fixes: Emu import, column width type, and capital_social parameter type (May 9, 11:18 AM)
S68 Fix Pyrefly type checker errors in analytics package — repeated stale-file edits for Emu import, column width type, and _add_quadro_identificacao parameter type (May 9, 11:20 AM)
147 11:54a 🔵 Data Source Materialization Timeout Investigation
148 11:57a 🔵 SQL Materialization Query for CRM Movement Data by UF
149 12:02p 🔵 SQL Script Fails with Subquery-in-Scalar-Context Errors
150 2:04p 🔵 CNPJ Network Materialized Data Statistics
151 2:34p ✅ Data Materialization MS Executed Successfully
152 3:59p 🔵 SQL Materialization Benchmark — Script-Style Approach
153 4:00p 🟣 Per-Stage Timing Instrumentation Added to CRM Concentration Pipelines
154 4:09p 🔵 SQL Server CRM Multi-CRM Temporal Concentration Detection Pipeline

Access 597k tokens of past work via get_observations([IDs]) or mem-search skill.
</claude-mem-context>
# ID-FIRST REGIONAL POLICY
- **PROIBIDO**: no_regiao_saude em lógica, filtros ou parâmetros.
- **OBRIGATÓRIO**: id_regiao_saude em todas as funções e integrações.
