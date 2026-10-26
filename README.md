# swarmbay

Plugin do Claude Code que transforma o `/swarm` numa software house orquestrada: spec-driven + TDD, tarefas atômicas, um commit por etapa, aprovação humana.

```
spec → [design no Claude Design, se frontend] → testes → validar testes → dev → revisões (spec + layout do swarmbay; stack, segurança etc. do ECC) → aprovação humana
```

**Frontend:** a tarefa gera um artefato no Claude Design (copiando antes a tela atual, se ainda não houver artefato) e você aprova o layout antes dos testes. O `layout-reviewer` compara a implementação com esse layout. No início, o swarm pergunta se a aplicação é mobile first (ou, se não for, se a usabilidade mobile importa para o app ou só para certos módulos); a resposta fica em `.swarm/config.md`.

## Layout

```
.claude-plugin/plugin.json   manifesto
commands/swarm.md            o orquestrador (/swarm)
agents/                      spec-writer, designer, tester, test-auditor, developer,
                             spec-reviewer, layout-reviewer, mapper
hooks/hooks.json             SessionStart: roda o porteiro
scripts/gatekeeper.sh        porteiro: diagnostica o repo (somente leitura)
scripts/init-swarm.sh        cria o esqueleto .swarm/ (idempotente)
scripts/capture-screens.sh   prints das telas (Chrome headless) para .swarm/references/capturas
templates/                   modelos de spec, tarefa, config, designs e .swarm/README
references/ecc-routing.md    qual agente/skill do ECC usar por stack e por etapa
```

## Custo e qualidade

- **Divisão com o ECC:** o ECC é o revisor principal (stack, segurança, falhas silenciosas, acessibilidade, banco, tipos). O swarmbay só cobre o que o ECC não conhece: aderência à spec e aos testes (`spec-reviewer`), fidelidade ao Claude Design (`layout-reviewer`), viés dos testes (`test-auditor`), spec, design, mapa e a implementação guiada por testes.
- **Triagem por risco:** o orquestrador escolhe os revisores pelo tamanho e pelo risco do diff, registra o que rodou e o que foi pulado (com o motivo), e a segurança é obrigatória em autenticação, pagamentos, segredos e dependências.
- **Modelo por agente** (cabeçalho de cada agente): `spec-writer` e `test-auditor` em Opus (decidem o que é certo e o erro é caro); `designer`, `tester`, `developer`, `mapper`, `spec-reviewer` e `layout-reviewer` em Sonnet.
- **Máximo de 5 skills do ECC por agente**, relatórios curtos e suíte de testes em modo silencioso.
- **Sem cold start:** o orquestrador guarda o id dos agentes e os retoma com `SendMessage` em novas rodadas (correção de testes, achados de revisão, mudança de layout), em vez de lançar um agente novo.
- **Higiene de sessão:** o estado fica em `.swarm/`; ao trocar de área, `/clear` e `/swarm resume`.

## Design de frontend

- **Referências visuais:** coloque imagens em `.swarm/references/` (ou o swarm tira prints das telas da aplicação existente, e se não conseguir, pergunta quais telas você quer usar como referência). O `designer` lê tudo isso antes de propor o layout e sobe as imagens como assets no canvas do Claude Design (artboard "Referências"). Imagens **coladas no chat** o Claude vê, mas não viram arquivo: salve o original na pasta.
- **Sem referências? O swarm pesquisa:** se você não disser nada, ele busca inspirações no Dribbble e outras plataformas, propõe até 3 direções (com link, o que aproveitar e o que não) e **pergunta se pode seguir por uma delas** antes de desenhar. Fica registrado em `.swarm/references/inspiracoes.md` (links e notas, sem baixar imagens). Diga "não pesquise" para pular.
- **Versionamento e dados sensíveis:** as referências são versionadas, mas antes de comitar imagens novas o swarm pede que você confirme que não têm dados sensíveis; sem a confirmação, elas não entram no commit.
- **Prints automáticos, só de telas públicas:** `bash scripts/capture-screens.sh --base-url http://localhost:3000 --routes "/,/pricing" --start "npm run dev"` (Chrome/Chromium headless; viewports mobile e desktop por padrão, só localhost). Ele nunca faz login: rotas que exigem login são puladas, e essas telas você adiciona à mão. Rode `--help` para as opções.
- **A pasta `.swarm/references/` é sua:** adicione o que quiser a qualquer momento; o swarm só cria arquivos novos (capturas em `capturas/`) e nunca apaga ou sobrescreve os seus.
- **Design system primeiro:** nenhuma tela é implementada antes de existir um design system aprovado (artefato do tipo Design System no Claude Design) e implementado no código (tokens, tema, componentes base). Todas as telas seguintes são desenhadas, implementadas e revisadas dentro dele; o `layout-reviewer` reprova valores fora do sistema.

## Dependência: ECC

O swarmbay depende do plugin **ECC** (`ecc@ecc`) para a especialização por stack. É uma dependência **obrigatória**: sem o ECC o swarmbay não carrega. Testado: instalar o swarmbay instala o ECC junto **somente se o marketplace do ECC já tiver sido adicionado**; senão o swarmbay instala mas fica com status "failed to load". Por isso, nesta ordem:

```
/plugin marketplace add affaan-m/ECC
/plugin marketplace add /home/richardy/projects/swarmbay     # ou <owner>/<repo> do GitHub
/plugin install swarmbay@swarmbay                            # instala o ecc@ecc junto
```

Com `claude --plugin-dir`, a dependência não é imposta: o fluxo roda e avisa se o ECC não estiver instalado.

O swarmbay cuida do processo (spec, design, testes, auditoria, commits, estado em `.swarm/`); o ECC entra com os revisores por linguagem/framework, segurança, acessibilidade, skills de padrões e de testes. O mapa de quem usa o quê está em [references/ecc-routing.md](references/ecc-routing.md). O mapper grava a stack do projeto em `stack:` no `.swarm/map.md`, e o orquestrador aciona os agentes ECC certos nas etapas de revisão, validação de testes, design e spec. Sem o ECC, o fluxo roda só com os agentes do swarmbay e avisa da limitação.

## Usar em um repositório novo ou existente

```
claude --plugin-dir /home/richardy/projects/swarmbay     # a partir do repositório alvo
```

Depois, no Claude Code: `/swarm <pedido>`. O porteiro roda primeiro:

| Estado | O que acontece |
|---|---|
| sem código | fluxo `init` |
| **com código, sem mapa** | bootstrap: cria `.swarm/`, aciona o `mapper` (em paralelo por área se o repo for grande), confere comandos de teste, gera tarefas para lacunas de cobertura, pede sua confirmação e comita |
| mapa defasado (≥ 50 commits) | oferece refazer o mapa (`SWARM_STALE_COMMITS` ajusta o limite) |
| mapeado | classifica o pedido e segue o fluxo |

Ao abrir a sessão, o hook avisa o Claude se o repositório não está mapeado ou se há tarefas em aberto. Para mapear explicitamente: `/swarm map`.

O porteiro também roda sozinho:

```
bash scripts/gatekeeper.sh [dir]
```

## Estado em `.swarm/` (versionado)

`map.md` (com `mapped_at_commit`), `map/`, `config.md` (perfil mobile), `designs.md` (tela ↔ artefato Claude Design), `specs/`, `tasks/T-NNN-*.md`, `templates/`. Qualquer agente retoma uma tarefa lendo o campo "Próximo passo".

## Status

Rascunho. Os scripts foram testados em repositórios descartáveis; o `/swarm` completo ainda não foi exercitado de ponta a ponta no Claude Code.
