# Changelog

Todas as mudanças relevantes do Sentinela serão registradas neste arquivo.

O versionamento segue o padrão SemVer: `MAJOR.MINOR.PATCH`.

## [1.1.19] - 2026-06-22

### Alterado
- Remoção do contador regressivo e botão de cancelar no diálogo de atualização — atualização é aplicada automaticamente ao término do download.

## [1.1.18] - 2026-06-22

### Adicionado
- Novo atualizador gráfico (SentinelaUpdater.exe) com interface PyWebView mostrando progresso das etapas de instalação.

## [1.1.17] - 2026-06-22

### Corrigido
- Ajuste fino adicional na rotina de verificação e download do novo executável.

## [1.1.16] - 2026-06-22

### Corrigido
- Ajustes finos adicionais na liberação de processos no auto-update.

## [1.1.15] - 2026-06-22

### Corrigido
- Uso do ProcessStartInfo do .NET no PowerShell para remoção forçada e explícita do _MEIPASS do bloco de ambiente no reinício do executável.

## [1.1.14] - 2026-06-22

### Corrigido
- Implementação de inicialização desvinculada (ShellExecute/explorer.exe) no PowerShell para prevenir herança indesejada de processos e ambientes no reinício automático do aplicativo.
- Otimização do rótulo do botão de cancelamento para "Cancelar".

## [1.1.13] - 2026-06-22

### Corrigido
- Implementação de inicialização desvinculada (ShellExecute/explorer.exe) no PowerShell para prevenir herança indesejada de processos e ambientes no reinício automático do aplicativo.

## [1.1.12] - 2026-06-22

### Corrigido
- Refinamento da limpeza de ambiente no PowerShell para garantir que variáveis internas do PyInstaller sejam totalmente removidas nativamente no processo do Windows.
- Otimização do rótulo do botão de cancelamento para "Cancelar".

## [1.1.11] - 2026-06-22

### Corrigido
- Exibição de progresso no script PowerShell `sentinela_update.ps1` (removido `$ErrorActionPreference = 'SilentlyContinue'` silencioso e adicionados tratamentos robustos de erro).
- Falha de cache do PyInstaller ao reiniciar: agora a variável de ambiente `_MEIPASS` é limpa no PowerShell antes da reinicialização, garantindo que o novo executável carregue a versão correta.
- Ajustado o tamanho visual do botão "Cancelar atualização" na tela de progresso.
- Título do card de produção semestral alterado para "VALOR SEM COMPROVAÇÃO E % SEM COMPROVAÇÃO POR SEMESTRE".

## [1.1.10] - 2026-06-20

### Adicionado
- Sistema de verificação automática de atualizações com assinatura Ed25519 e manifesto público no GitHub Pages.
- Tela de bloqueio profissional exibida quando a versão instalada está abaixo da versão mínima suportada.
- Cache local offline do manifesto validado em `%LOCALAPPDATA%\Sentinela\updates\` com proteção anti-downgrade.
- Card Sistema expandido com linha de status de atualização (Atualizado, Atualização disponível, Verificação offline, Não verificado) e tooltip com data da última verificação.
- Link para documentação do sistema (`https://cgu-sc.github.io/sentinela/`) na barra de navegação.
- Endpoints `GET /api/v1/system/update-status` e `POST /api/v1/system/check-update`.
- Fonte única de versão do produto em `version.json` na raiz do projeto.


### Adicionado
- Sistema de verificação automática de atualizações com assinatura Ed25519 e manifesto público no GitHub Pages.
- Tela de bloqueio profissional exibida quando a versão instalada está abaixo da versão mínima suportada.
- Cache local offline do manifesto validado em `%LOCALAPPDATA%\Sentinela\updates\` com proteção anti-downgrade.
- Card Sistema expandido com linha de status de atualização (Atualizado, Atualização disponível, Verificação offline, Não verificado) e tooltip com data da última verificação.
- Link para documentação do sistema (`https://cgu-sc.github.io/sentinela/`) na barra de navegação.
- Endpoints `GET /api/v1/system/update-status` e `POST /api/v1/system/check-update`.
- Fonte única de versão do produto em `version.json` na raiz do projeto.












## [1.1.9] - 2026-06-22

### Adicionado
- Teste de funcionalidade de atualização automática do aplicativo desktop via release.ps1 (versão 1.1.9 para teste de update da 1.1.8).

## [1.1.8] - 2026-06-22

### Adicionado
- Teste de funcionalidade de atualização automática do aplicativo desktop via release.ps1.

## [1.1.7] - 2026-06-22

### Adicionado
- Teste de funcionalidade de atualização automática do aplicativo desktop via release.ps1.

## [1.1.6] - 2026-06-22

### Corrigido
- Gráfico "Repasses por Semestre" sem destaque visual ao clicar: barras agora aplicam opacidade reduzida nos semestres não selecionados, igual ao comportamento do "Volume de Vendas por Semestre".
- Gráfico "Histórico Mensal de Repasses" sem destaque dos meses do semestre selecionado: agora aplica opacidade reduzida nos meses fora do semestre clicado.
- Coluna "Programa" na tabela de detalhamento mensal de repasses exibia texto em caixa baixa; agora é formatada em TitleCase via `formatTitleCase`.

## [1.1.5] - 2026-06-22

### Corrigido
- Gráfico "Repasses por Semestre" sem destaque visual ao clicar: barras agora aplicam opacidade reduzida nos semestres não selecionados, igual ao comportamento do "Volume de Vendas por Semestre".
- Gráfico "Histórico Mensal de Repasses" sem destaque dos meses do semestre selecionado: agora aplica opacidade reduzida nos meses fora do semestre clicado.
- Coluna "Programa" na tabela de detalhamento mensal de repasses exibia texto em caixa baixa; agora é formatada em TitleCase via `formatTitleCase`.

### Adicionado
- Badge no header do card "Histórico Mensal de Repasses" exibindo o semestre atualmente selecionado.

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
