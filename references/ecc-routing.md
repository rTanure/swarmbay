# Roteamento swarmbay → ECC

O swarmbay define **o processo** (etapas, portões, commits, estado). O ECC (`ecc@ecc`) fornece **a especialização por stack**: revisores, resolvedores de build e skills de padrões e testes. Este arquivo diz o que usar de cada um.

Como ler:
- A stack vem do campo `stack:` no cabeçalho de `.swarm/map.md` (tags na seção 7) ou, se ausente, do que o agente observar nos manifestos.
- `ecc:<nome>` é um **agente** (ferramenta Agent, `subagent_type: "ecc:<nome>"`) quando a linha diz *agente*, ou uma **skill** (ferramenta Skill) quando diz *skill*.
- Se o ECC não estiver instalado (`ecc=no` no porteiro) ou o nome não existir, siga sem ele e **diga isso no relatório**. Nunca invente um nome.
- Subagentes não criam subagentes: quem aciona os *agentes* do ECC é o orquestrador. Os agentes do swarmbay só carregam *skills*.
- **Limite de 5 skills por agente** por execução, na ordem de prioridade destas tabelas, só as que a tarefa exige.
- Quem decide **quais** revisores ECC rodam é a triagem por risco do `/swarm` (seção "Revisões: ECC primeiro"); esta página só diz qual agente/skill cobre cada lente.

## 1. Revisores por stack (agentes ECC, etapa "revisões")

O orquestrador acrescenta, em paralelo aos revisores do swarmbay, o revisor da stack tocada pelo diff. Escolha todos que se aplicam.

| Tag(s) em `stack:` | Agente ECC |
|---|---|
| python | `ecc:python-reviewer` |
| django | `ecc:django-reviewer` |
| fastapi | `ecc:fastapi-reviewer` |
| typescript, javascript, node, nestjs | `ecc:typescript-reviewer` |
| react, nextjs | `ecc:react-reviewer` |
| vue, nuxt | `ecc:vue-reviewer` |
| go | `ecc:go-reviewer` |
| rust | `ecc:rust-reviewer` |
| java, springboot, quarkus | `ecc:java-reviewer` |
| kotlin, android, compose | `ecc:kotlin-reviewer` |
| cpp | `ecc:cpp-reviewer` |
| csharp, dotnet | `ecc:csharp-reviewer` |
| fsharp | `ecc:fsharp-reviewer` |
| swift, ios | `ecc:swift-reviewer` |
| php, laravel | `ecc:php-reviewer` |
| ruby, rails | `ecc:ruby-reviewer` |
| flutter, dart | `ecc:flutter-reviewer` |
| sql, postgres, mysql (schema, queries, migrações) | `ecc:database-reviewer` |
| ml | `ecc:mle-reviewer` |
| rag | `ecc:rag-pipeline-reviewer` |

Sempre que há código novo, também: `ecc:silent-failure-hunter` (erros engolidos, fallbacks ruins) e, se o diff mexe em tipos/modelos, `ecc:type-design-analyzer`. Para comentários e docs no diff, `ecc:comment-analyzer`. Para gargalos, `ecc:performance-optimizer` (somente se a spec tem requisito de desempenho).

Resolução de build quebrado (etapa dev, quando o `developer` escala por erro de compilação): `ecc:build-error-resolver` (genérico) ou o específico: `ecc:go-build-resolver`, `ecc:rust-build-resolver`, `ecc:java-build-resolver`, `ecc:kotlin-build-resolver`, `ecc:cpp-build-resolver`, `ecc:dart-build-resolver`, `ecc:swift-build-resolver`, `ecc:react-build-resolver`, `ecc:django-build-resolver`.

## 2. Segurança (revisor ECC; o swarmbay não tem revisor de segurança próprio)

| Quando | Usar |
|---|---|
| sempre | agente `ecc:security-reviewer` + skill `ecc:security-review` |
| django | skill `ecc:django-security` |
| laravel | skill `ecc:laravel-security` |
| springboot | skill `ecc:springboot-security` |
| quarkus | skill `ecc:quarkus-security` |
| perl | skill `ecc:perl-security` |
| container/infra | skills `ecc:docker-patterns`, `ecc:kubernetes-patterns` |

## 3. Layout e acessibilidade (lente `layout-reviewer`, etapa `designer`)

- agente `ecc:a11y-architect` (WCAG 2.2, web e nativo)
- skills `ecc:frontend-a11y`, `ecc:accessibility`, `ecc:frontend-design-direction`, `ecc:design-system`
- por stack: `ecc:react-patterns`, `ecc:frontend-patterns`, `ecc:vue-patterns`, `ecc:nuxt4-patterns`, `ecc:swiftui-patterns`, `ecc:compose-multiplatform-patterns`, `ecc:dart-flutter-patterns`, `ecc:react-native-patterns`
- verificação no navegador: skill `ecc:browser-qa`; agente `ecc:e2e-runner` para fluxos ponta a ponta

## 4. Testes (agentes `tester` e `test-auditor`)

Skills de testes por stack, para o `tester` seguir o idioma certo e o `test-auditor` julgar com o mesmo critério:

| Tag(s) | Skill |
|---|---|
| (qualquer) | `ecc:tdd-workflow`, `ecc:ai-regression-testing` |
| python | `ecc:python-testing` |
| django | `ecc:django-tdd` |
| go | `ecc:golang-testing` |
| rust | `ecc:rust-testing` |
| react | `ecc:react-testing` |
| kotlin, android | `ecc:kotlin-testing` |
| cpp | `ecc:cpp-testing` |
| csharp, dotnet | `ecc:csharp-testing` |
| fsharp | `ecc:fsharp-testing` |
| springboot | `ecc:springboot-tdd` |
| quarkus | `ecc:quarkus-tdd` |
| laravel | `ecc:laravel-tdd` |
| perl | `ecc:perl-testing` |
| fluxos de usuário | `ecc:e2e-testing` |

Agentes ECC úteis: `ecc:tdd-guide` (disciplina red/green/refactor) e `ecc:pr-test-analyzer` (qualidade e lacunas de cobertura do conjunto de testes). O orquestrador aciona o `ecc:pr-test-analyzer` **em paralelo ao `test-auditor`**, e os achados dos dois entram no mesmo relatório.

## 5. Desenvolvimento (agente `developer`): skills de padrões da stack

| Tag(s) | Skills |
|---|---|
| python | `ecc:python-patterns` |
| django | `ecc:django-patterns` |
| fastapi | `ecc:fastapi-patterns` |
| go | `ecc:golang-patterns` |
| rust | `ecc:rust-patterns` |
| kotlin | `ecc:kotlin-patterns`, `ecc:kotlin-coroutines-flows` |
| android | `ecc:android-clean-architecture` |
| springboot | `ecc:springboot-patterns` |
| quarkus | `ecc:quarkus-patterns` |
| laravel | `ecc:laravel-patterns` |
| rails | `ecc:rails-patterns` |
| nestjs | `ecc:nestjs-patterns` |
| react, nextjs | `ecc:react-patterns`, `ecc:frontend-patterns` |
| vue | `ecc:vue-patterns` |
| node | `ecc:backend-patterns` |
| dotnet, csharp | `ecc:dotnet-patterns` |
| postgres | `ecc:postgres-patterns` |
| mysql | `ecc:mysql-patterns` |
| redis | `ecc:redis-patterns` |
| prisma | `ecc:prisma-patterns` |
| java (JPA) | `ecc:jpa-patterns` |
| (APIs) | `ecc:api-design` |
| (migrações de banco) | `ecc:database-migrations` |
| (erros) | `ecc:error-handling` |
| (arquitetura) | `ecc:hexagonal-architecture` |

Depois de verde, para limpar sem mudar comportamento: agentes `ecc:code-simplifier` e `ecc:refactor-cleaner` (só com a suíte completa verde e commit próprio).

## 6. Spec, planejamento e mapeamento

- `spec-writer`: agente `ecc:spec-miner` (extrai requisitos e invariantes de código existente, útil em `fix`, `refactor` e brownfield); skills `ecc:architecture-decision-records`, `ecc:api-design`, `ecc:contract-first`.
- Decomposição em tarefas: agentes `ecc:planner`, `ecc:architect`, `ecc:code-architect`.
- `mapper`: agente `ecc:code-explorer` (rastreia fluxos de execução); skills `ecc:codebase-onboarding`, `ecc:repo-scan`.

## 7. Tags de stack aceitas em `stack:` (vocabulário fechado)

python, django, fastapi, typescript, javascript, node, nestjs, react, nextjs, vue, nuxt, go, rust, java, springboot, quarkus, kotlin, android, compose, cpp, csharp, dotnet, fsharp, swift, ios, php, laravel, ruby, rails, dart, flutter, react-native, perl, sql, postgres, mysql, redis, prisma, docker, kubernetes, ml, rag
