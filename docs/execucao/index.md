# Execução do Sistema

Esta seção contém as instruções para configurar o ambiente e executar o Sistema Sentinela.

---

## Navegação

<div class="grid cards" markdown>

- :material-list-status:{ .lg .middle } **Pré-requisitos**

  ***

  Software e dados necessários para executar o sistema.

  [:octicons-arrow-right-24: Ver pré-requisitos](pre-requisitos.md)

- :material-play-circle:{ .lg .middle } **Guia de Execução**

  ***

  Instruções passo a passo para executar cada fase.

  [:octicons-arrow-right-24: Ver guia](guia-execucao.md)

</div>

---

## Visão Geral do Processo

```mermaid
flowchart LR
    A[1. Configurar<br/>Ambiente] --> B[2. Preparar<br/>Banco SQL]
    B --> C[3. Executar<br/>Python]
    C --> D[4. Pós-<br/>Processamento]
    D --> E[5. Verificar<br/>Resultados]
```

---

## Tempo Estimado

| Fase                     | Tempo Estimado | Observação             |
| ------------------------ | -------------- | ---------------------- |
| Configuração do ambiente | 30 min         | Uma única vez          |
| Fase 1 (SQL)             | 2-4 horas      | Depende do volume      |
| Fase 2 (Python)          | Vários dias    | ~34.000 CNPJs          |
| Fase 4 (SQL)             | 1-2 horas      | Após Python terminar   |
| Verificação              | 30 min         | Consultas de validação |

---

## Próximos Passos

1. Verifique os [Pré-requisitos](pre-requisitos.md)
2. Siga o [Guia de Execução](guia-execucao.md)
