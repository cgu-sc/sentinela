<claude-mem-context>
# Memory Context

# [sentinela] recent context, 2026-05-10 1:00am GMT-3

Legend: 🎯session 🔴bugfix 🟣feature 🔄refactor ✅change 🔵discovery ⚖️decision 🚨security_alert 🔐security_note
Format: ID TIME TYPE TITLE
Fetch details: get_observations([IDs]) | Search: mem-search skill

Stats: 50 obs (19.750t read) | 1.462.833t work | 99% savings

### May 9, 2026
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
186 11:45p 🔵 CRM Detalhado Loteado Pipeline Architecture
187 11:46p 🔵 CRM Detalhado Loteado: Output Tables Schema and Batch Loop Config
188 11:55p 🔵 CRM SQL Script Review: Movimentação Now Saved to Temp Table
189 11:56p 🔵 CRM Pipeline Scripts Now Self-Materialize Source Data Into Session Temp Tables
### May 10, 2026
190 12:04a 🔄 crms_detalhado_loteado refatorado para usar tabela temporária de sessão e controle unificado por UF
191 12:06a 🔵 crm_concentracao_multiplo_temporal tem lote-log persistente; crms_detalhado_loteado não
192 12:09a 🟣 crms_detalhado_loteado ganhou tabela de etapa_log persistente para rastreio granular de performance
193 12:10a 🟣 crms_detalhado_loteado ganhou crm_detalhado_lote_log com rastreio por lote e seção de resultados expandida
194 " ⚖️ Complete Review Requested for crms_detalhado_loteado_test.sql Refactor
195 12:16a 🔴 etapa_log Pattern Changed from INSERT-only to INSERT-at-start + UPDATE-at-end
196 " 🔴 Added Early Prerequisite Guard for Explicit @uf_farmacia_alvo Selection
197 " 🔴 Reset Block Now Includes crm_detalhado_lote_log and Clears crm_detalhado_lote_etapa_log by Period
198 " 🔵 Final State: crms_detalhado_loteado_test.sql at +529/-155 After Full Review Pass
199 12:18a 🔴 Pre-batch Migration Block Added to Prevent SQL Server Compile-time Column Resolution Errors
200 12:27a 🟣 Network Graph Layer Filter Menu — Refactor Plan for NetworkTab.vue
201 12:28a 🔄 NetworkTab.vue Layer Filter Menu — Refactor Completed and Built
202 12:29a 🔴 Filters Dropdown Theme Colors Fixed
203 12:33a 🔴 Filters Menu Background Simplified to var(--card-bg)
204 12:34a 🟣 Filters Dropdown Click-Outside-to-Close Behavior Added

Access 1463k tokens of past work via get_observations([IDs]) or mem-search skill.
</claude-mem-context>
# ID-FIRST REGIONAL POLICY
- **PROIBIDO**: no_regiao_saude em lógica, filtros ou parâmetros.
- **OBRIGATÓRIO**: id_regiao_saude em todas as funções e integrações.
