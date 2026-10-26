---
design_system: none            # URL do artefato Claude Design System, ou none
design_system_estado: none     # none | proposta | aprovado | implementado
design_system_codigo:          # onde vivem os tokens/tema/componentes base no código
---

# Designs (Claude Design)

Índice do design system e das telas do projeto com os artefatos do Claude Design que os representam. O orquestrador consulta este arquivo antes de qualquer tarefa de frontend:

1. Se o design system não está `aprovado`/`implementado`, ele é criado primeiro (tarefa `design-system`) e toda tarefa de frontend depende dele.
2. Se a tela não está na tabela, ela é copiada para o Claude Design primeiro (como está hoje) e só então editada.

## Telas

| tela / componente | código (arquivos) | artefato Claude Design | estado |
|---|---|---|---|

`estado`: `baseline` (cópia fiel do que existe) · `proposta T-NNN` (aguardando aprovação) · `aprovado T-NNN` · `implementado T-NNN`
