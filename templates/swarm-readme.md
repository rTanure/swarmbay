# .swarm

Estado do [swarmbay](https://github.com/) neste repositório. Versionado de propósito: permite que outro agente (ou pessoa) continue o trabalho de onde parou.

| Caminho | Conteúdo |
|---|---|
| `map.md` | mapa do repositório: stack, estrutura, comandos de build/teste, convenções, lacunas de teste. Tem `mapped_at_commit` no cabeçalho. |
| `map/` | mapas parciais por área (usados em repositórios grandes e consolidados em `map.md`) |
| `specs/` | specs aprovadas, uma por funcionalidade/correção |
| `tasks/` | tarefas atômicas `T-NNN-*.md` com etapa, estado e "Próximo passo" |
| `templates/` | modelos de spec e tarefa |

Fluxo de cada tarefa: spec → testes → validar testes → dev → revisões → aprovação humana, um commit por etapa.

Comandos úteis: `/swarm status`, `/swarm resume T-NNN`, `/swarm map` (refaz o mapa).
