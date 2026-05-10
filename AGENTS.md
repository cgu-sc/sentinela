<claude-mem-context>
# Memory Context

# [sentinela] recent context, 2026-05-09 11:45pm GMT-3

Legend: 🎯session 🔴bugfix 🟣feature 🔄refactor ✅change 🔵discovery ⚖️decision 🚨security_alert 🔐security_note
Format: ID TIME TYPE TITLE
Fetch details: get_observations([IDs]) | Search: mem-search skill

Stats: 50 obs (17.176t read) | 676.951t work | 97% savings

### May 9, 2026
136 11:06a 🔵 `analytics` Services Package Structure and `get_dashboard_data` Implementation Confirmed
137 " 🔵 `AnalyticsService` Wiring Confirmed Correct — Error Must Be Inside Function Body
138 " 🔵 Two Separate Dashboard Services Serve Different Endpoints
139 11:08a 🔴 Fixed Type Annotations for `cnpjs` and `regiao_id` Parameters in `get_dashboard_data`
140 11:09a 🔵 Same `Optional` Annotation Bug Found in `get_fator_risco_data`
141 " 🔴 Fixed `Optional[int]` Annotation for `regiao_id` in `get_fator_risco_data` and Revealed Additional Affected Functions
142 11:10a 🔵 Full Scope of `Optional` Annotation Bug Mapped Across `regional.py`
143 " 🔴 Fixed `Optional` Annotations on `get_regional_benchmarking` — All Four Params Updated
144 " 🔴 Fixed `id_regiao` Local Variable Typing in `get_regional_benchmarking`
145 " 🔴 Completed `Optional` Annotation Fixes Across All Regional Service Functions
146 11:11a 🔴 Completed `Optional` Annotation Fixes for All Functions in `analytics/regional.py`
147 11:54a 🔵 Data Source Materialization Timeout Investigation
148 11:57a 🔵 SQL Materialization Query for CRM Movement Data by UF
149 12:02p 🔵 SQL Script Fails with Subquery-in-Scalar-Context Errors
150 2:04p 🔵 CNPJ Network Materialized Data Statistics
151 2:34p ✅ Data Materialization MS Executed Successfully
152 3:59p 🔵 SQL Materialization Benchmark — Script-Style Approach
153 4:00p 🟣 Per-Stage Timing Instrumentation Added to CRM Concentration Pipelines
154 4:09p 🔵 SQL Server CRM Multi-CRM Temporal Concentration Detection Pipeline
155 4:34p 🔵 NetworkTab.vue Level 4 Display Bug Identified
156 " 🔵 NetworkTab.vue Architecture and Level 4 Bug Root Cause Analysis
157 4:36p 🔵 N4 Backend Architecture: Per-CNPJ Parquet Cache Files Required
158 4:37p 🔵 N4 Cache Generation Depends on cpfs_n3_trigger from df_exp_filtered
159 4:41p 🔵 Network Graph Schema and Cache Architecture for Corporate Network
160 4:45p 🔴 Fix Level 4 network graph visualization by triggering layout on edge additions
161 4:55p ✅ Add currentLayout variable to NetworkTab.vue for layout state management
162 4:56p 🔴 Prevent layout callbacks from firing on destroyed Cytoscape instance
163 " ✅ Track layout references in mergeNetworkData for consistent cleanup
164 " ✅ Apply consistent layout tracking to expandNode function
165 " ✅ Complete layout tracking refactor in resetLayout function
166 " 🔴 Fix state inconsistency when switching from N4 to N3 expansion level
167 4:58p 🔴 Fix resetToN2 null check and filter variable references
S82 Behavior analysis of "Sócios Inativos" toggle — does it filter by CNPJ or globally? (May 9, 5:07 PM)
S83 Debug discrepancy between DB source and frontend for active socios of CNPJ 02162827000127 (May 9, 5:23 PM)
168 5:29p 🔵 Frontend/DB Discrepancy in Active Socios for CNPJ 02162827000127
S84 Debug why inactive partner nodes in a graph visualization incorrectly disappear when filtering by "Sócios Inativos" — root cause analysis of node vs edge is_ativo mismatch (May 9, 5:30 PM)
169 5:33p 🔵 AnalyticsService.get_dashboard_data Signature Mismatch Error
S85 Verify that the edge-based visibility filter fix in NetworkTab.vue is complete and correct after implementation (May 9, 5:34 PM)
170 5:34p 🔵 toggleInactivePartners Filters on Node is_ativo, Not Edge is_ativo
171 5:35p 🔴 Graph Visibility Filter Refactored to Operate on Edges Instead of Nodes
S86 Comportamento do filtro de grafo quando sócio tem vínculo ativo em uma empresa e inativo em outra (May 9, 5:37 PM)
172 5:41p 🔵 Sócio com Múltiplos Vínculos: Comportamento Ativo/Inativo
S87 Generate commit message for Sentinela — Cytoscape lifecycle fix, visibility filter refactor, and N4 network expansion bugfix (May 9, 5:41 PM)
173 5:46p 🔵 Sentinela Pre-Commit Changeset Summary
174 5:47p 🔴 NetworkTab.vue: Cytoscape Layout Lifecycle Overhaul
175 " 🔄 NetworkTab.vue: Unified Visibility Filter Logic
176 " 🔴 Network Sync N4 Trigger Fixed to Use All N3 Partners
177 " ✅ Emoji Removed from Backend Log Messages
S88 NetworkTab.vue toolbar UX review — proposal to split investigation controls from visibility filters into two separate pill components (May 9, 5:47 PM)
178 5:48p 🟣 New CRM Concentration SQL Test Files for Temporal Validation
S89 NetworkTab.vue toolbar redesign + font-weight normalization across all CSS selectors (May 9, 5:49 PM)
179 5:52p 🟣 NetworkTab Toolbar Split into Two Semantic Pills
180 " 🟣 Depth Level State Machine Wired into expandBatch and resetToN2
181 5:53p 🟣 Final Toolbar Template Replaced: toolbar-overlay with Two toolbar-pill Components
S90 Sentinela UI: Redesign confusing pill filters + add "Apenas Farmácias" and "Localizar Nó" features (May 9, 5:53 PM)
182 5:59p 🟣 UI Pill Filter Redesign + Two New Network Graph Features Planned
183 6:04p ⚖️ NetworkTab.vue Feature Plan: Pharmacy Filter + Node Locator
184 " 🟣 NetworkTab.vue Toolbar Redesigned: Segmented Pills + Active Level Tracking
185 " 🔵 NetworkTab.vue: Node Data Model and Pharmacy Classification Logic
S91 Analysis of crms_detalhado_test.sql and its relationship to the loteado/pre_global pipeline scripts (May 9, 11:25 PM)
**Investigated**: - Full content of src/indicadores/crms_detalhado_test.sql (1300 lines, v5)
    - First 220 lines of src/indicadores/crms_detalhado_pre_global_test.sql
    - First 260 lines of src/indicadores/crms_detalhado_loteado_test.sql
    - Cross-references between all CRM-related SQL scripts using rg searches
    - All files under src/indicadores/ containing "crm" or "crms" in the filename

**Learned**: - crms_detalhado_test.sql is the MONOLITHIC version (v5): reads directly from temp_CGUSC.fp.teste_mov_SC (single-state test table), processes the entire dataset at once in temp tables (#base_horaria_mestra, etc.), and produces all outputs in one shot
    - The PIPELINE has been split into 3 scripts:
      1. crms_detalhado_pre_global_test.sql — creates dados_medico and crm_prescricoes_todos_estabelecimentos nationally
      2. crms_detalhado_loteado_test.sql — processes CNPJs by UF with checkpoint/resume logic via crm_pipeline_uf_controle, materializes crm_mov_fonte_atual per UF, builds dados_crm_detalhado incrementally
      3. A post-global script (referenced but not read) — creates alertas_crm_geografico, alertas_crm_registro, alertas_crm, crm_export, benchmarks
    - crms_detalhado_test.sql still references teste_mov_SC (legacy test table), while the loteado version uses crm_mov_fonte_atual (proper UF-materialized source from Relatorio_movimentacaoFP + carga_2024)
    - The temporal concentration tables (crm_concentracao_unico_alertas, crm_concentracao_multiplo_alertas) are EXTERNAL prerequisites produced by crm_concentracao_unico_temporal_test.sql and crm_concentracao_multiplo_temporal_test.sql — those were completed in a prior session
    - alertas_crm uses BIT flags (flag_concentracao, flag_geografico, flag_registro) rather than text columns — this is a v5 refactor
    - HHI (Herfindahl-Hirschman Index) is computed per pharmacy for concentration risk matrix, with benchmarks at UF, health region, and national level
    - Modified Z-Score (MZS > 4.5, volume >= 10) used for hourly anomaly detection on prescription bursts

**Completed**: - Full structural analysis of crms_detalhado_test.sql completed
    - Identified that crms_detalhado_test.sql is the monolithic predecessor to the loteado pipeline
    - Confirmed the 3-script pipeline structure: pre_global → loteado → pos_global
    - Confirmed temporal concentration tables are already prerequisites (produced by earlier scripts that ran successfully)

**Next Steps**: - Claude is about to compare crms_detalhado_test.sql (monolithic) with the loteado pipeline to identify what differences/improvements need to be made or validated
    - The goal appears to be understanding whether crms_detalhado_test.sql needs to be updated to use crm_mov_fonte_atual instead of teste_mov_SC, or whether the loteado pipeline is the canonical path forward
    - Likely next: read the post-global script and assess the full pipeline completeness


Access 677k tokens of past work via get_observations([IDs]) or mem-search skill.
</claude-mem-context>
# ID-FIRST REGIONAL POLICY
- **PROIBIDO**: no_regiao_saude em lógica, filtros ou parâmetros.
- **OBRIGATÓRIO**: id_regiao_saude em todas as funções e integrações.
