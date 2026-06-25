# Changelog

Todas as mudanças relevantes do Sentinela serão registradas neste arquivo.

O versionamento segue o padrão SemVer: `MAJOR.MINOR.PATCH`.


## [1.5.0] - 2026-06-25

### Adicionado
- **Pre-visualizacao interna da Nota Tecnica no Sentinela Desktop.** Apos gerar e salvar o `.docx` na pasta `notas_tecnicas`, o aplicativo converte automaticamente uma copia para PDF usando Microsoft Word via `docx2pdf`/`pywin32`. O toast de sucesso passa a exibir o botao **Visualizar**, abrindo o PDF dentro do proprio Sentinela em um modal dedicado.
- **Modal global de visualizacao de documentos PDF** em `frontend/src/views/components/DocumentPreviewDialog.vue`, com opcao de abrir o arquivo externamente quando necessario.
- **Ponte nativa segura no PyWebView** para conversao DOCX/PDF e leitura do PDF em base64, restrita a pasta `notas_tecnicas`, evitando leitura arbitraria do disco.
- **Selecao de formatos de saida na Nota Tecnica.** O modal de dados da NT passa a exibir a secao **Formatos de saida**, deixando claro que a versao Word editavel sempre sera gerada e permitindo ao usuario optar por gerar ou nao a versao PDF para visualizacao.
- **Logs de desempenho da Nota Tecnica.** A geracao do DOCX agora registra `nota_tecnica_docx` com tempo em milissegundos no log de requisicoes, e a conversao DOCX/PDF no Desktop registra o tempo da conversao no log `sentinela_*.log`.

### Alterado
- **Toasts de documentos salvos** agora podem oferecer visualizacao interna quando houver PDF disponivel. O Relatorio PDF tambem passa a expor o botao **Visualizar** no modo Desktop.
- **Dependencias desktop atualizadas** com `docx2pdf` e `pywin32` para suportar a conversao fiel do DOCX usando o Microsoft Word instalado no ambiente.
- **Numero do processo SEI no modal da Nota Tecnica** agora limita a entrada aos 17 digitos obrigatorios e aplica a mascara `00000.000000/0000-00`, evitando que o usuario digite um processo maior que o contrato aceito pelo backend.
- **Toasts de sucesso para arquivos salvos** deixam de fechar automaticamente, mantendo as acoes de abrir/visualizar o documento disponiveis ate o usuario encerrar a notificacao.


## [1.4.1] - 2026-06-25

### Alterado
- **Tela de bloqueio administrativo dedicada** em `frontend/src/views/components/ExecutionBlocker.vue`. A 1.4.0 compartilhava a `UpdateBlocker.vue` entre `update_required` e `execution_blocked`; o teste de UX mostrou que a tela única confundia o operador, porque "atualização necessária" e "decisão administrativa" são contextos diferentes. A nova tela tem visual institucional e sóbrio (escuro, ícone escudo/X, eyebrow `Decisão administrativa`, pill `Bloqueado desde`, versão instalada como referência), sem a tabela de versões que só fazia sentido em `update_required`. Ações: **Verificar novamente** (primária), **Ver alterações** e **Baixar atualização** (secundárias, condicionais), **Sair** (ghost, só desktop).
- **Tela de atualização obrigatória isolada** em `frontend/src/views/components/UpdateBlocker.vue`. Voltou a ser exclusiva para `update_required`, com a tabela de versões (Sua versão / Versão mínima / Versão mais recente) e os 3 botões originais (Baixar, Ver alterações, Sair).
- `App.vue` passou a rotear o status para a tela certa:
  - `update_required` → `<UpdateBlocker />`
  - `execution_blocked` → `<ExecutionBlocker />`


## [1.4.0] - 2026-06-25

### Adicionado
- **Bloqueio administrativo de execução via manifesto assinado.** O `manifest.json` passa a aceitar um bloco `execution_policy` com a flag `blocked_execution`, título, mensagem e timestamp opcionais (`blocked_since`). Quando a flag vem `true` em um manifesto com assinatura Ed25519 válida, o backend devolve status `execution_blocked` e o frontend exibe uma tela de bloqueio fullscreen sem confirmação do usuário. O desbloqueio é automático na próxima checagem (15 min ou botão "Verificar agora") quando o manifesto volta para `blocked_execution: false`.
- **Schema do manifesto atualizado** com `ExecutionPolicy` (Pydantic) em `backend/api/schemas/system_update.py`. O campo `execution_policy` é obrigatório a partir desta versão: manifestos sem o bloco falham a validação de schema, sem fallback silencioso.
- **Status `execution_blocked`** no contrato de `UpdateStatusResponse`, propagado por `check_for_updates()` e `initialize_update_check()` em ambos os caminhos (remoto e cache offline). O cache local com assinatura válida continua aplicando o bloqueio mesmo sem rede, evitando que o usuário se proteja via desligamento de internet.
- **Tela dedicada de bloqueio administrativo** em `frontend/src/views/components/ExecutionBlocker.vue`. Visual institucional e sóbrio: tom vermelho escuro, ícone de escudo/X maior, eyebrow `Decisão administrativa` em caps, data `Bloqueado desde` em pill, versão instalada como referência. Sem tabela de versões (que não faz sentido fora do contexto de `update_required`). Ações: **Verificar novamente** (primária), **Ver alterações** e **Baixar atualização** (secundárias, condicionais), **Sair** (ghost, só desktop).
- **Tela de atualização obrigatória isolada** em `frontend/src/views/components/UpdateBlocker.vue`. Voltou a ser exclusiva para `update_required`, com a tabela de versões (Sua versão / Versão mínima / Versão mais recente) e os 3 botões originais.
- `App.vue` passou a rotear o status para a tela certa:
  - `update_required` → `<UpdateBlocker />`
  - `execution_blocked` → `<ExecutionBlocker />`
- **Store `systemUpdate.js`**: `blockTitle`, `blockMessage` e `blockedSince` permanecem como campos consumidos pela `ExecutionBlocker.vue`; `isExecutionBlocked` é o gatilho de renderização.
- **Helpers de mensagem** `_manifest_status()` e `_manifest_message()` em `backend/api/services/system_update.py` centralizam a derivação do status final e da mensagem, garantindo que o bloqueio administrativo tenha prioridade sobre `update_required`/`update_available`/`current`.

### Alterado
- **Card "Sistema" da HomeView** passa a refletir o status `execution_blocked` com tom `critical` e label "Execução bloqueada" no lugar de "Atualização obrigatória" quando o motivo do bloqueio é administrativo, evitando confundir o operador.
- **Contrato do manifesto é breaking**: campo `execution_policy` agora é obrigatório. Manifestos antigos sem o bloco serão rejeitados pela validação Pydantic, e o sistema cai em `verification_unavailable` (sem bloquear, apenas sem garantia online) até a próxima publicação já com o novo formato.


## [1.3.1] - 2026-06-25

### Alterado
- **SentinelaUpdater.exe com visual mais neutro e alinhado à identidade do Sentinela**: o ícone azul genérico do topo foi substituído pelo ícone oficial do Sentinela, embutido no HTML do updater. O botão `Fechar` deixou de usar fundo azul em degradê e passou a usar estilo neutro translúcido, com borda sutil e hover discreto. Textos das etapas e status final ficaram mais claros no tema escuro; o status de conclusão agora usa tom de sucesso.
- **Sidebar inicia sempre em estado previsível**: o grupo `Geral` abre por padrão e o grupo `Alertas` inicia fechado sempre que o sistema é carregado. A persistência do estado do acordeão da sidebar em `localStorage` foi removida; o usuário ainda pode abrir/fechar os grupos normalmente durante a sessão.


## [1.3.0] - 2026-06-25

### Adicionado
- **Novo alerta "CNPJ Nível 2 da Teia com PAR"** no card **Integridade / Quadro de Alertas** da HomeView. O alerta conta CNPJs alvo que possuem ao menos um CNPJ vinculado no nível 2 da teia societária com registro em Processo Administrativo de Responsabilização (PAR), usando o cache global `par_teia_alvos.smod` e a coluna obrigatória `has_par_n2`. Ao clicar no alerta, o sistema ativa automaticamente o filtro da sidebar `CNPJs com PAR = CNPJ Nível 2 da Teia com PAR`.

### Alterado
- **Filtro "CNPJs com PAR" refinado na sidebar**: removida a opção `Alvo com PAR`, que não possuía resultado útil para o fluxo atual. Os labels foram ajustados para `CNPJ Nível 2 da Teia com PAR`, `CNPJ Nível 4 da Teia com PAR` e `Qualquer CNPJ com PAR`.
- **Labels dos filtros de integridade societária ajustados** para linguagem mais curta e direta: `Apenas CNPJs com CNAE incompatível`, `Apenas sócios < 21 ou > 80 anos` e `Apenas CNPJs com sócio falecido`.
- **Labels do card Integridade atualizados**: `Sócio em programa social (CadÚnico/Defeso)` passou a `Sócio inscrito no CadÚnico/Defeso`, e `Sócio com idade atípica (< 21 ou > 80 anos)` passou a `Sócios < 21 ou > 80 anos`.


## [1.2.3] - 2026-06-24

### Adicionado
- **Reorganização da sidebar em 2 grupos consolidados** (AppSidebar.vue). As antigas 4 seções (`Escopo`, `Cadastro`, `Integridade societária`, `Parâmetros`) foram consolidadas em apenas 2: **Geral** (filtros de localização + cadastro + parâmetros de auditoria, com 15 filtros) e **Alertas** (sinais de risco societário e operacional, com 8 filtros). A seção `Integridade societária` foi renomeada para `Alertas` com ícone `pi pi-bell`. O filtro `Aumento Semestral Atípico` foi movido de `Parâmetros` para `Alertas` por ser um sinal de comportamento suspeito (crescimento semestral anormal de faturamento).
- **Acordeão exclusivo** entre os 2 grupos: ao abrir um, o outro fecha automaticamente. Implementado em `toggleSection(id)` usando o conjunto `SECTION_IDS = ['geral', 'integridade']` — quando o usuário clica num heading fechado, o `Set` de seções colapsadas recebe todos os outros IDs (forçando o fechamento deles). Comportamento padrão de Material Design / Linear / Notion.
- **Busca suspende o acordeão durante a digitação**. O estado manual do acordeão (`collapsedSections`) é persistido em `localStorage`, e o estado efetivo usado pelo template (`effectiveCollapsed`) é um `computed` derivado: durante a busca, qualquer seção que tenha matches é forçada a abrir (remove do Set), independente do estado manual. Ao limpar a busca, o estado manual do acordeão é restaurado automaticamente. Assim, ambos os grupos podem ficar abertos simultaneamente se a busca tiver matches em ambos.

### Corrigido
- **Filtros da seção `Cadastro` sumiam** (primeira tentativa) quando os 2 grupos estavam colapsados. Causa raiz: os 2 `<div class="grid-filters">` da seção Cadastro (que envolvem os pares Situação RF+Conexão MS e Porte CNPJ+Grande Rede) eram filhos diretos do `.sidebar-content` (`gap: 0.5rem`), mas só os `.filter-section` dentro tinham `v-show` baseado no estado de colapso. Os wrappers `.grid-filters` em si continuavam com `display: grid` no DOM, gerando espaçamento residual. Fix: adicionado `v-show="!isSectionCollapsed('geral')"` nos wrappers `.grid-filters` da seção Geral (que unificou Cadastro+Escopo+Parâmetros).
- **Bug de espaçamento**: quando a seção `Cadastro` era a única fechada, ela ganhava padding extra em relação às outras seções colapsadas (cerca de 8px), por causa do `gap: 0.5rem` do `.sidebar-content` somado aos wrappers `.grid-filters` residuais. Resolvido junto com o fix acima.
- **Bug de posicionamento dos 4 filtros de Parâmetros** (Percentual, Período, Valor Mínimo, Aumento Semestral): ao mover de Parâmetros para Geral, os filter-sections foram parar DEPOIS do heading de Alertas no DOM, fazendo eles aparecerem visualmente após o Alertas. Reorganização do template colocou os 4 dentro de um wrapper `<div v-show="!isSectionCollapsed('geral')">` posicionado entre o último filter-section de Cadastro (cnpjRaiz) e o heading de Alertas.
- **Migração automática do localStorage** ao abrir a página: usuários com chaves `['escopo']`, `['cadastro']` ou `['parametros']` salvas de versões anteriores (1.2.0 e 1.2.1) são migradas automaticamente para `['geral']` em `loadCollapsedFromStorage()`. Garante que o estado de colapso continue funcionando após o release.

### Alterado
- **Badge de contagem de matches/filtros** nos headings das seções reposicionado da esquerda para o canto direito (antes do chevron), usando `position: absolute; right: 1.8rem`. Antes, o badge aparecia entre o nome da seção e o chevron, deslocando o texto quando o badge aparecia (ao digitar na busca). Agora, o nome "Geral"/"Alertas" permanece fixo à esquerda, o badge "flutua" no canto direito reservado, e o chevron fica no canto extremo direito (`margin-left: auto`).
- **Altura do input de busca** da sidebar alinhada com a altura do filtro "Estabelecimento" (32px, `font-size: 0.75rem`), igual aos demais `.filter-input` da sidebar. Antes, o input tinha padding vertical próprio que resultava em ~35px.
- **Fundo do input de busca** no estado normal agora usa `var(--sidebar-input-bg)` (mesmo fundo dos outros inputs da sidebar) em vez de `color-mix(--sidebar-bg 60%, white 8%)`, mantendo coerência visual com o resto da sidebar. O estado focus usa o mesmo `var(--sidebar-input-bg)` (diferença fica no border-color `--primary-color` e no box-shadow `0 0 0 1px --primary-color, 0 4px 12px rgba(0,0,0,0.05)`).
- **Espaçamento entre cards de filtro** (12px). O `.sidebar-content` tem `gap: 0.75rem` e o novo wrapper `.sidebar-section-body` (que envolve os filter-sections de cada grupo colapsável) tem `gap: 0.75rem` e `display: flex; flex-direction: column`. O `margin-bottom: 0.15rem` legado do `.filter-section` foi removido (redundante com o gap). Cards ficam visualmente separados sem ficar "colados" nem "esparsos".
- **Destaque dos headings das seções** (Geral e Alertas) com `background: color-mix(--primary-color 6%, transparent)`, cor do texto 100% opacidade (em vez de 74%), e `border-top` sutil removido. O fundo azulado sutil torna os 2 grupos visualmente identificáveis como "blocos" no flow da sidebar. Hover mantém o fundo `--primary-color` 8% (já existente). `min-height` aumentado de 1.45rem para 2rem (32px), igualando à altura dos inputs.
- **Espaçamento entre label e input** dos filtros aumentado de `margin-bottom: 0.25rem` (4px) para `0.5rem` (8px) no `.filter-label`. Mais respiro entre o título do filtro e o componente.
- **Busca só ativa com 2+ caracteres**. O `computed searchTerm` retorna `""` quando o termo normalizado tem menos de 2 caracteres, fazendo `filterMatchesSearch` retornar `true` para todos os filtros (estado normal) e o badge `searchTerm` não aparecer. Evita ruído de matches com 1 letra (que retorna quase todos os grupos).
- **Filtro "Sócio em Programa Social" renomeado para "Sócio no CadÚnico/Defeso"** no `FILTER_INDEX`, alinhando com o título visível no template. Keywords ajustadas: removido "programa social" (que continha "gra" como substring, gerando match falso ao buscar "gra") e adicionado "seguro defeso" e "pobreza" (termos mais específicos do CadÚnico/Defeso).

## [1.2.2] - 2026-06-24

### Adicionado
- **Botão flutuante de "Limpar todos os filtros"** na sidebar (AppSidebar.vue), posicionado acima do badge de filtros ativos. Aparece somente quando `activeFilterCount > 0` e chama `filterStore.resetFilters()`. Visual consistente com os outros botões flutuantes (`sidebar-float-btn`, `sidebar-lock-btn`, `sidebar-filter-count-btn`), mas com tom `--risk-high` para reforçar a ação destrutiva. Ícone `pi pi-eraser`. Gap uniforme de 6px entre todos os 4 botões flutuantes da sidebar.
- **Reorganização da sidebar com acordeão colapsável + busca textual** (AppSidebar.vue). As 4 seções (`Escopo`, `Cadastro`, `Integridade societária`, `Parâmetros`) agora são `<button>` clicáveis com chevron rotativo (`pi-chevron-down` ↔ `pi-chevron-up`), estado persistido em `localStorage` (chave `sentinela_sidebar_collapsed`), e `aria-expanded`/`aria-controls` para acessibilidade. Novo input "Buscar filtro..." no topo da sidebar filtra os 23 filtros em tempo real via índice declarativo `FILTER_INDEX` (label + keywords por filtro), com normalização de acentos (`NFD` + remoção de diacríticos). Quando a busca está ativa, o badge em cada seção mostra a contagem de matches em vez da contagem de filtros ativos, e seções sem matches somem. Hover dos headings ganha fundo suave `--primary-color` 8%, focus-visible com outline `--primary-color` 2px.

### Alterado
- **Limiar do alerta "Vendas para UFs sem fronteira"** subiu de 5% para 10%: constante `LIMIAR_ALERTA_UF_NAO_VIZINHA_PCT` em `backend/api/services/analytics/geografico.py` foi de 5.0 para 10.0. Texto do tooltip do alerta (HomeView) e default do filtro da sidebar (`DISPERSAO_UF_SEM_FRONTEIRA_PERCENTUAL` em `constants.js`) ajustados para 10. Chip de quick-select no AppSidebar.vue: `[5, 10, 20, 50]` → `[10, 20, 30, 50]` (5 substituído por 30).

### Corrigido
- **Filtros de integridade não ativavam a alça "Filtros ativos"** na sidebar. Os checkboxes `Sócio com vínculo eSocial` e `Sócio em programa social` eram contados normalmente, mas `Sócio ativo falecido`, `Sócio com idade atípica` e `Farmácia com CNAE incompatível` não faziam aparecer nem o badge com a contagem nem o botão de limpar todos. Causa raiz: o array `fields` do `computed activeFilterCount` em `AppSidebar.vue:448` não incluía `selectedSocioFalecido`, `selectedSocioIdadeAtipica` nem `selectedCnaeIncompativel` — a função `isFilterActive` (`AppSidebar.vue:400`) já dava suporte aos 3, mas eles nunca eram contados. Adicionados os 3 campos ao array, na mesma família de filtros de integridade (logo após `selectedSocioEsocial`).
- **Tooltips nativos (`title=""`) nos 4 botões flutuantes da sidebar** (`sidebar-clear-btn`, `sidebar-filter-count-btn`, `sidebar-float-btn`, `sidebar-lock-btn`) trocados pela diretiva `v-tooltip.right` do PrimeVue, alinhando com o restante do projeto (que usa `v-tooltip.right="'Limpar filtro'"` nos chips de filtro ativos desde a v1.1.x). Antes, os tooltips dos 4 botões que ficam colados na borda lateral da sidebar apareciam com o estilo nativo do browser (lento, sem fade, com delay alto) e o do botão de limpar não aparecia de jeito nenhum em alguns browsers.

## [1.2.1] - 2026-06-24

### Adicionado
- **Alertas do card Integridade (HomeView) são clicáveis.** Cada alerta no panorama de alertas é agora um botão que, ao clicar, ativa/desativa o filtro correspondente na sidebar (mapeamento `alerta.tipo` → `filterStore.selectedXxx` em `ALERTA_TIPO_PARA_FILTRO`). Comportamento de toggle: clique 1 ativa, clique 2 desativa. Para os filtros dropdown (`Sócio em programa social` e `Sócio com vínculo eSocial`) o valor aplicado é `direto`. Hover deixa o card levemente mais saturado e com lift de 1px; o estado ativo (filtro ligado) ganha bg/border mais saturados, `box-shadow` interna e tom da cor de risco correspondente (`--risk-high` para crítico, `--risk-medium` para atenção). Acessibilidade: `aria-pressed` reflete o estado e `aria-label` descreve a ação.

### Corrigido
- **Filtro "Sócio ativo falecido" não restringia a tabela "Farmácias por Indicador"** em `/estabelecimentos` (`/api/v1/analytics/indicadores-analise/cnpjs`). O card Escopo, Produção e Integridade e o endpoint `/resumo` reagem normalmente, mas a tabela de CNPJs por indicador mantinha o total sem filtro quando o checkbox de sócio falecido era marcado. Causa raiz: o campo `socio_falecido` não estava declarado em `_INDICADOR_SCOPE_FILTER_FIELDS` (`backend/api/services/analytics/indicadores.py`), então a função `_build_indicador_dataset_cached` filtrava o parâmetro fora do `filters` dict antes de passar para `_build_indicador_scope_base`, mesmo com a assinatura da função aceitando o parâmetro. Adicionado `("socio_falecido", _normalize_cache_bool)` à tupla, e os kwargs `socio_falecido=socio_falecido` nos 2 call sites de `_build_indicador_dataset_cached` que faltavam (no commit `084a5dc` o `replaceAll` só pegou 1 dos 3 call sites por causa de indentação diferente).

## [1.2.0] - 2026-06-24

### Adicionado
- **Filtro "Sócio ativo falecido"** na sidebar do dashboard, exibido logo após o filtro de idade atípica, permitindo restringir o dashboard a estabelecimentos com ao menos um sócio pessoa física com vínculo societário ativo identificado como falecido na base de óbitos. Reage em todos os cards (Escopo, Produção, Integridade) e KPIs. Fonte: coluna `is_falecido` de `dados_socios.parquet` (materializada no ETL do SQL Server a partir do cruzamento do CPF do sócio com a base de óbitos).
- Filtro integrado em todos os endpoints: `/resumo`, `/faixas-risco`, `/producao-semestral`, `/alertas-panorama`, `/indicadores-analise` e `/indicadores-analise/cnpjs`.
- `build_perfil_filtrado` em `alertas_alvos.py` agora aceita o parâmetro `socio_falecido: bool = False` aplicando `semi join` com `dados_socios` filtrado por `indicador_socio == 'PF'` + `data_exclusao_sociedade IS NULL` + `is_falecido == True`.

## [1.1.8] - 2026-06-24

### Adicionado
- **Filtro "Sócio com idade atípica (< 21 ou > 80 anos)"** na sidebar, permitindo restringir o dashboard a estabelecimentos com sócios PF ativos em idade fora do padrão.
- **Indicador `socio_idade_atipica`** no card Integridade do dashboard, com tooltip descritivo e contagem no panorama de alertas.
- Filtro integrado em todos os endpoints: `/resumo`, `/faixas-risco`, `/producao-semestral`, `/alertas-panorama`, `/indicadores-analise` e `/indicadores-analise/cnpjs`.
- Cache do filtro nos indicadores para recálculo automático via `_INDICADOR_SCOPE_FILTER_FIELDS`.
- Checkbox com destaque visual (clear button, `filter-active-box`, `integrityFilterCount`) consistente com os demais filtros de integridade.
- Função `build_perfil_filtrado` em `alertas_alvos.py` aplicando par_teia, socio_beneficio, socio_esocial, cnae_incompativel, socio_idade_atipica e volume_atipico em sequência, compartilhada por dashboard, fator_risco, indicadores e alertas_panorama.

### Corrigido
- **Card Integridade (HomeView) não reagia aos filtros da sidebar.** O endpoint `/alertas-panorama` e a função `get_alertas_panorama` recebiam apenas filtros geográficos e `dispersao_uf_sem_fronteira`; demais filtros da sidebar (CNAE, sócio CadÚnico/Defeso, sócio eSocial, sócio idade atípica, PAR, volume atípico) eram ignorados. O endpoint e o service agora aceitam todos os filtros globais e a função `fetchAlertasPanorama` no frontend usa `buildAnalyticsParams` para enviá-los, refletindo as contagens do card em tempo real quando o usuário marca/desmarca qualquer filtro.
- `_filtrar_id_cnpjs_por_escopo` em `alertas_panorama.py` retornava `None` (interpretado como "Brasil inteiro") sempre que não havia filtro geográfico, descartando todos os filtros de integridade aplicados via `build_perfil_filtrado`. Agora retorna os `id_cnpj` do `perfil_df` filtrado (ou `None` apenas quando o filtro atual não casa com nenhum CNPJ), refletindo corretamente o subconjunto da sidebar no card.

### Alterado
- Cálculo de idade do sócio passa a ser **on-demand** a partir de `dados_socios.parquet` (mesma lógica do `alertas_panorama`), em vez de coluna materializada `has_socio_idade_atipica` em `perfil_consolidado_estabelecimento`. Garante consistência quando um sócio cruza a fronteira dos 21 ou 80 anos após a geração do Parquet.
- Data de referência para o cálculo da idade é `data_fim` do período selecionado (com fallback para `date.today()`), alinhada ao card Integridade.
- Filtro `volume_atipico` aplicado uniformemente no `perfil_filtrado` em todos os call sites (antes era aplicado direto no `period_df` em alguns e no perfil em outros, com duplicação quando passava pelos dois caminhos).

## [1.1.7] - 2026-06-24

### Adicionado
- **Botão de refresh para verificação manual de atualizações** ao lado do label "Atualização" no card Sistema (HomeView).
  - Ícone 🔄 permite forçar verificação imediata sem aguardar os 15 minutos do polling automático.
  - Desabilitado durante a verificação com feedback visual de carregamento (ícone gira).
  - Aciona requisição POST para `/api/v1/system/check-update`.
- **Cor da barra de título da janela desktop** personalizada via `pywinstyles` (Windows 10/11): barra escura (`#1a1a1a`) alinhada ao tema visual do Sentinela.
- **Cor da barra de título do SentinelaUpdater** personalizada (`#080d1a`), alinhada ao fundo da janela de atualização.
- **Verificação automática de atualizações a cada 15 minutos** em segundo plano, sem intervenção do usuário.
- **Script `release_granian.ps1`** equivalente ao `release.ps1` para builds com Granian.

### Alterado
- **Proporcionalidade dos cards no dashboard (HomeView)**:
  - Card Sistema aumentado (0.88fr → 1fr) para melhor destaque.
  - Card Produção reduzido (1fr → 0.9fr) para melhor equilíbrio visual.
- **Ícone de atualização aumentado em tamanho** (1rem → 1.15rem, font-size: 0.6rem) para melhor visibilidade.
- **Label do filtro "Atualização"** agora exibe ícone de refresh inline usando `display: flex` com alinhamento horizontal.
- **`release.ps1`**: limpeza de tag/release anterior agora é sempre executada, independente de a tag existir localmente — corrige falha ao recriar releases.
- **`build_pywebview_granian.ps1`**: adicionado passo de build do `SentinelaUpdater.exe` antes do executável principal, garantindo que o updater seja embutido corretamente.
- **`sentinela_server2.spec`**: adicionado `SentinelaUpdater.exe` nos `datas` e nome do executável alterado para `Sentinela` (igual ao uvicorn).
- **Documentação** (`mkdocs.yml`): removida dependência do `polyfill.io` que causava prompt de login ao acessar o GitHub Pages.

## [1.1.6] - 2026-06-23

### Adicionado
- Novo filtro **"Farmácia com CNAE Incompatível"** na sidebar do dashboard para filtrar estabelecimentos com incompatibilidade de CNAE (Classificação Nacional de Atividade Econômica).
- Checkbox interativo com comportamento idêntico a outros filtros (Grande Rede, PAR, etc.), aplicando filtro em tempo real aos KPIs e tabelas.
- Filtro integrado em todos os endpoints de analytics: `/resumo`, `/faixas-risco`, `/producao-semestral`, `/indicadores-analise` e `/indicadores-analise/cnpjs`.
- Suporte completo do filtro em todas as views: Dashboard Nacional, Dashboard Regional, Estabelecimentos e Indicadores.
- Implementação de cache do filtro em indicadores para otimizar performance.

### Alterado
- Estilos de checkbox: texto alinhado com cor e peso de fonte dos labels de filtro (`--sidebar-text`, font-weight: 400).
- Integração do filtro CNAE em `_INDICADOR_SCOPE_FILTER_FIELDS` para recalcular cache automaticamente quando filtro muda.

## [1.1.5] - 2026-06-23

### Corrigido
- Nota Técnica: Tabela 8 (Repasses Anuais) centralizada corretamente no documento Word.
- Nota Técnica: remoção de bold nas linhas de dados da Tabela 9 (Indicadores Críticos) — bold mantido apenas no cabeçalho.
- Nota Técnica: apenas a palavra 'ATENÇÃO!' permanece em negrito no texto de conclusão; restante do parágrafo sem formatação especial.
- Nota Técnica: removido espaço extra antes de 'ATENÇÃO!' na capa.
- Nota Técnica: largura da Tabela 8 equalizada à Tabela 7 (7,30 polegadas no total).
- Nota Técnica: ajustes de tipagem e formatação geral nos relatórios.

### Alterado
- Aba Financeiro: visualizações de Vendas e Repasses unificadas em layout único, eliminando alternância entre abas separadas.
- Aba Financeiro: removido modal de zoom do gráfico mensal.
- Card Sistema: ícone de download pulsante exibido ao lado do label "Atualização" quando há versão disponível ou atualização obrigatória, indicando que o card é clicável.
- Dashboard: proporções dos cards ajustadas — card Sistema levemente menor, card Integridade levemente maior.

## [1.1.4] - 2026-06-20

### Adicionado
- Sistema de atualização automática no modo Desktop: ao clicar no card de Atualização, o aplicativo baixa o novo executável diretamente da release do GitHub com barra de progresso em tempo real, fecha o processo atual e reinicia automaticamente na nova versão via script auxiliar (`update.bat`).
- Modal `UpdateDialog` com barra de progresso animada, status reativo (baixando, preparando arquivos, reiniciando) e botão de tentar novamente em caso de falha.
- Endpoints internos `POST /api/v1/system/download-update` e `GET /api/v1/system/download-progress` para orquestrar e monitorar o download.

### Alterado
- Em modo Web (servidor de desenvolvimento), o card de atualização continua abrindo a página de downloads do GitHub no navegador (comportamento anterior mantido).

## [1.1.3] - 2026-06-20

### Corrigido
- Perda e não carregamento das preferências e watchlist no modo Desktop (EXE congelado), redirecionando a escrita e leitura do `preferences.json` para o diretório de dados persistentes `%LOCALAPPDATA%\Sentinela\preferences\`.

## [1.1.2] - 2026-06-20

### Corrigido
- Falha ao gerar Nota Técnica em modo Desktop (Frozen/EXE) causada por caminho de resolução incorreto para o GeoJSON `brasil-uf.json` na geração dos mapas.

## [1.1.1] - 2026-06-20

### Adicionado
- Comportamento clicável no card de atualização (HomeView) quando o sistema não está atualizado, redirecionando para a página oficial do GitHub Pages para baixar a nova versão.
- Efeito de carregamento visual premium (brilho pulsante com animação de respiração scale e onda de expansão ripple) nos botões de "Gerar Relatório PDF" e "Gerar Nota Técnica" durante a compilação/exportação dos dados.

## [1.1.0] - 2026-06-20

### Adicionado
- Sistema de verificação automática de atualizações com assinatura Ed25519 e manifesto público no GitHub Pages.
- Tela de bloqueio profissional exibida quando a versão instalada está abaixo da versão mínima suportada.
- Cache local offline do manifesto validado em `%LOCALAPPDATA%\Sentinela\updates\` com proteção anti-downgrade.
- Card Sistema expandido com linha de status de atualização (Atualizado, Atualização disponível, Verificação offline, Não verificado) e tooltip com data da última verificação.
- Link para documentação do sistema (`https://cgu-sc.github.io/sentinela/`) na barra de navegação.
- Endpoints `GET /api/v1/system/update-status` e `POST /api/v1/system/check-update`.
- Fonte única de versão do produto em `version.json` na raiz do projeto.

### Alterado
- Seletor de aparência simplificado: removida a seleção de paleta de cores; o tema Carbon Gold passa a ser fixo e apenas o alternador claro/escuro permanece na navbar.
- Linha "Atualizado" (data do cache de dados) removida do card Sistema para reduzir redundância.

## [1.0.0] - 2026-06-20

### Adicionado
- Primeira versão estável oficial do Sentinela.
- Execução web e desktop com empacotamento PyWebView.
- Geração de Nota Técnica e Relatório PDF.
- Dashboard com KPIs operacionais, produção, escopo monitorado e quadro de alertas.
- Detalhamento de estabelecimento com abas de movimentação, diagnóstico de risco, memória de cálculo, indicadores, autorizações, quadro societário, teia societária e região de saúde.
- Caches locais em módulos `.smod` para operação com dados materializados.

### Corrigido
- Correção da porta dinâmica no executável desktop quando `8002` já está ocupada.
- Correção de salvamento local de documentos gerados no executável desktop.
- Correção de altura da aba Teia Societária após inclusão de overlay de carregamento por aba.

### Alterado
- Card Sistema passa a exibir a versão atual da aplicação.
