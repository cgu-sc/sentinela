# CHANGELOG - Gerador de Relatórios do Sentinela v3

Este arquivo registra todas as mudanças notáveis feitas no projeto Sentinela. O formato é baseado em [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [3.1.0] - 2026-02-26
### Adicionado
- **Interface de Detecção de Versão:** Implementada janela personalizada (Dark Theme) para alertar usuários sobre versões obsoletas.
- **Botão de Download Direto:** Adicionado botão "📥 Baixar Nova Versão" que abre o SharePoint automaticamente.
- **Trava de Segurança:** O aplicativo agora consulta o SQL Server (`fp.config_sistema`) na inicialização para validar se a versão atual é permitida.
- **Controle via Banco de Dados:** Criado script `config_sistema.sql` para gerenciar a versão mínima obrigatória centralizadamente.
- **Log de Mudanças:** Criação deste arquivo `CHANGELOG.md` para rastreio de evolução do software.

### Alterado
- **Otimização de Build:** Script `build_exe.py` atualizado para remover o flag `--clean` e adicionar exclusões de módulos desnecessários, tornando a compilação mais rápida.
- **Resiliência de Inicialização:** Importação do `pyodbc` movida para dentro da função de verificação para evitar crashes silenciosos em ambientes sem o driver.

---
## [3.0.0] - Versão Base (2025/2026)
### Adicionado
- Versão inicial do Gerador de Relatórios v3.
- Suporte a relatórios de CRMs e Indicadores Detalhados.
- Integração com banco de dados SQL Server para cruzamentos de dados históricos.
- Interface gráfica em Python/Tkinter com tema escuro personalizado.
