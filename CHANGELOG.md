# Changelog

Todas as mudanças relevantes do Sentinela serão registradas neste arquivo.

O versionamento segue o padrão SemVer: `MAJOR.MINOR.PATCH`.


## [1.1.22] - 2026-06-22

### Alterado
- Versão de teste para validação do script PowerShell de atualização automática e ajustes visuais do card Sistema.

## [1.1.21] - 2026-06-22

### Alterado
- Versão de teste para validação do script PowerShell de atualização automática e ajustes visuais do card Sistema.

## [1.1.20] - 2026-06-22

### Corrigido
- Script de atualização automática substituído de `.bat` para PowerShell (`.ps1`): aguarda encerramento dos processos, verifica liberação das portas 8002–8010 antes de copiar o exe e lançar a nova versão, com log detalhado em `sentinela_update.log`.
- Versão exibida no card Sistema agora vem da API em tempo de execução (`currentVersion`) em vez do valor estático compilado no bundle JS, garantindo exibição correta após atualização automática.

## [1.1.19] - 2026-06-22

### Alterado
- Versão de teste para validação do fluxo completo de atualização automática.

## [1.1.18] - 2026-06-22

### Adicionado
- Modal de atualização exibe contagem regressiva de 10 segundos após o download concluir, com botão "Cancelar atualização" para interromper o processo antes de fechar.

## [1.1.17] - 2026-06-22

### Alterado
- Versão de teste para validação do fluxo completo de atualização automática.

## [1.1.16] - 2026-06-22

### Corrigido
- Atualização automática não reabrindo o aplicativo: bat gerado agora salvo na pasta do exe e lançado com `CREATE_NEW_CONSOLE` em vez de `DETACHED_PROCESS`, garantindo sessão de desktop para o `start` funcionar corretamente.

## [1.1.15] - 2026-06-21

### Alterado
- Versão de teste para validação do fluxo completo de atualização automática.

## [1.1.14] - 2026-06-21

### Alterado
- Versão de teste para validação do fluxo completo de atualização automática.

## [1.1.13] - 2026-06-21

### Alterado
- Versão de teste para validação do fluxo completo de atualização automática.

## [1.1.12] - 2026-06-21

### Corrigido
- Atualização automática simplificada: removidas tentativas de `explorer.exe` e `powershell`; o `update.bat` aguarda ambos os processos (servidor e janela) encerrarem via kill explícito antes de copiar o exe e reabrir com `start`.

## [1.1.11] - 2026-06-21

### Corrigido
- Aplicativo não reabrindo após atualização automática: substituído `explorer.exe` por `powershell Start-Process` no `update.bat`, que executa o novo executável corretamente a partir de um processo desvinculado.

## [1.1.10] - 2026-06-21

### Corrigido
- Aplicativo não reabrindo após atualização automática: o `update.bat` agora usa `explorer.exe` para lançar o novo executável, garantindo acesso à sessão de desktop quando iniciado a partir de um processo desvinculado.

## [1.1.9] - 2026-06-21

### Corrigido
- Atualização automática não reiniciava o aplicativo: o script `update.bat` agora aguarda tanto o processo servidor (FastAPI) quanto o processo janela (PyWebView) encerrarem antes de substituir o executável, e o servidor encerra o processo janela programaticamente antes de sair.
- Barra de progresso travada em 0% ao tentar baixar uma atualização pela segunda vez na mesma sessão.

## [1.1.8] - 2026-06-21

### Adicionado
- Versão de teste para validação do modal de download automático.

## [1.1.7] - 2026-06-21

### Corrigido
- Falha ao gerar `update.bat` com `UnicodeEncodeError` causada por caractere em dash (`—`) no comentário do script, impedindo a aplicação da atualização automática após o download.

## [1.1.6] - 2026-06-20

### Corrigido
- Verificação de atualização retornava "Verificação offline" por campo `release_notes_url` ausente no manifesto, causando falha de validação do schema Pydantic.
- Modal de progresso de download não aparecia ao iniciar atualização a partir de telas fora da Home (`UpdateDialog` movido para `App.vue`).

### Alterado
- Executável renomeado de `sentinela_server1.exe` para `Sentinela.exe` em todos os scripts de build e release.
- Card Sistema exibe link discreto para a release no GitHub quando há atualização disponível ou obrigatória, permitindo download manual caso a atualização automática falhe.

## [1.1.5] - 2026-06-20

### Alterado
- Ajustado o rótulo do alerta de integridade de sócio falecido para "Sócio Ativo Falecido".

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
