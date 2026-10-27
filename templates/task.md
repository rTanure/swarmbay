---
id: T-000
titulo: 
tipo: feature        # feature | fix | refactor | init | design-system
etapa: spec          # spec | design | testes | validar-testes | dev | revisoes | aprovacao | concluida
frontend: false      # true => exige a etapa design (aprovada pelo humano) antes dos testes
design:              # URL do artefato Claude Design (obrigatório se frontend: true)
estado: pendente     # pendente | em-andamento | bloqueada | concluida
depende_de: []
spec: .swarm/specs/<slug>.md
areas: []            # caminhos que a tarefa toca
rodadas: { revisao: 0, auditoria: 0 }   # contadores dos loops (tetos: 2 e 2)
branch: 
commits: {}          # spec: <sha>, testes: <sha>, ...
---

## Objetivo

## Critérios de aceite
(referencie os CA-N da spec)

## Registro
(mais recente no topo: data, agente, o que fez, decisões, resultado dos testes)

## Bloqueios / perguntas ao humano

## Custo
(preenchido ao concluir a tarefa: `python3 scripts/swarm-report.py --task T-NNN --md`)

## Próximo passo
(concreto o bastante para outro agente executar sem contexto)
