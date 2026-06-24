# Changelog

Todas as mudanças relevantes do Sentinela serão registradas neste arquivo.

O versionamento segue o padrão SemVer: `MAJOR.MINOR.PATCH`.


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
